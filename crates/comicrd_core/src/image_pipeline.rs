use std::collections::{HashMap, HashSet, VecDeque};
use std::fs;
use std::io::{Cursor, Read};
use std::path::{Path, PathBuf};
use std::sync::{Condvar, Mutex, MutexGuard};

use rusqlite::Connection;
use zip::ZipArchive;

use crate::chapter::{archive_image_entries, chapter_source, image_entries_in_dir};
use crate::{ImageVariantProfile, RenderPagePayload, RenderedPage};

const MAX_VARIANT_WIDTH: u32 = 4096;
const MIN_VARIANT_WIDTH: u32 = 320;
const PAGE_SOURCE_CACHE_CAP: usize = 32;
const PAGE_BYTES_CACHE_CAP: usize = 32;
const PAGE_VARIANT_CACHE_CAP: usize = 128;
const PAGE_VARIANT_CACHE_BYTE_BUDGET: usize = 192 * 1024 * 1024;

#[derive(Clone)]
pub(crate) enum PageSource {
    Folder(Vec<PathBuf>),
    Archive {
        source_path: PathBuf,
        pages: Vec<String>,
    },
}

#[derive(Clone)]
struct CachedPageBytes {
    bytes: Vec<u8>,
    mime: &'static str,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CacheStats {
    pub page_source_loads: usize,
    pub page_bytes_loads: usize,
    pub variant_renders: usize,
    pub page_source_cache_hits: usize,
    pub page_bytes_cache_hits: usize,
    pub variant_cache_hits: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
struct VariantKey {
    chapter_id: i64,
    page_index: usize,
    target_width: u32,
    profile: ImageVariantProfile,
}

#[derive(Default)]
pub(crate) struct PageCache {
    state: Mutex<PageCacheState>,
    variant_ready: Condvar,
}

struct PageCacheState {
    sources: HashMap<i64, PageSource>,
    source_order: VecDeque<i64>,
    bytes: HashMap<(i64, usize), CachedPageBytes>,
    bytes_order: VecDeque<(i64, usize)>,
    variants: HashMap<VariantKey, RenderedPage>,
    variant_order: VecDeque<VariantKey>,
    variant_total_bytes: usize,
    in_flight_variants: HashSet<VariantKey>,
    pub(crate) stats: CacheStats,
}

impl Default for PageCacheState {
    fn default() -> Self {
        Self {
            sources: HashMap::new(),
            source_order: VecDeque::new(),
            bytes: HashMap::new(),
            bytes_order: VecDeque::new(),
            variants: HashMap::new(),
            variant_order: VecDeque::new(),
            variant_total_bytes: 0,
            in_flight_variants: HashSet::new(),
            stats: CacheStats::default(),
        }
    }
}

impl PageCacheState {
    fn touch_source(&mut self, chapter_id: i64) {
        self.source_order.retain(|key| *key != chapter_id);
        self.source_order.push_back(chapter_id);
    }

    fn touch_bytes(&mut self, key: (i64, usize)) {
        self.bytes_order.retain(|existing| *existing != key);
        self.bytes_order.push_back(key);
    }

    fn touch_variant(&mut self, key: VariantKey) {
        self.variant_order.retain(|existing| *existing != key);
        self.variant_order.push_back(key);
    }

    fn remember_source(&mut self, chapter_id: i64, source: PageSource) {
        self.sources.insert(chapter_id, source);
        self.touch_source(chapter_id);
        while self.source_order.len() > PAGE_SOURCE_CACHE_CAP {
            let Some(old_key) = self.source_order.pop_front() else {
                break;
            };
            self.sources.remove(&old_key);
        }
    }

    fn remember_bytes(&mut self, key: (i64, usize), bytes: CachedPageBytes) {
        self.bytes.insert(key, bytes);
        self.touch_bytes(key);
        while self.bytes_order.len() > PAGE_BYTES_CACHE_CAP {
            let Some(old_key) = self.bytes_order.pop_front() else {
                break;
            };
            self.bytes.remove(&old_key);
        }
    }

    fn remember_variant(&mut self, key: VariantKey, rendered: RenderedPage) -> RenderedPage {
        if let Some(old) = self.variants.insert(key, rendered.clone()) {
            self.variant_total_bytes = self.variant_total_bytes.saturating_sub(old.bytes.len());
        }
        self.touch_variant(key);
        self.variant_total_bytes = self
            .variant_total_bytes
            .saturating_add(rendered.bytes.len());
        while self.variant_order.len() > PAGE_VARIANT_CACHE_CAP
            || self.variant_total_bytes > PAGE_VARIANT_CACHE_BYTE_BUDGET
        {
            let Some(old_key) = self.variant_order.pop_front() else {
                break;
            };
            if let Some(old) = self.variants.remove(&old_key) {
                self.variant_total_bytes = self.variant_total_bytes.saturating_sub(old.bytes.len());
            }
        }
        rendered
    }
}

impl PageCache {
    fn lock_state(&self) -> Result<MutexGuard<'_, PageCacheState>, String> {
        self.state
            .lock()
            .map_err(|_| "page cache lock poisoned".to_string())
    }

    pub(crate) fn stats(&self) -> CacheStats {
        self.state
            .lock()
            .map(|state| state.stats)
            .unwrap_or_default()
    }

    fn begin_variant_render(&self, key: VariantKey) -> Result<Option<RenderedPage>, String> {
        let mut state = self.lock_state()?;
        loop {
            if let Some(rendered) = state.variants.get(&key).cloned() {
                state.stats.variant_cache_hits += 1;
                state.touch_variant(key);
                return Ok(Some(rendered));
            }
            if state.in_flight_variants.insert(key) {
                return Ok(None);
            }
            state = self
                .variant_ready
                .wait(state)
                .map_err(|_| "page cache lock poisoned".to_string())?;
        }
    }

    fn finish_variant_render(
        &self,
        key: VariantKey,
        rendered: RenderedPage,
    ) -> Result<RenderedPage, String> {
        let mut state = self.lock_state()?;
        state.in_flight_variants.remove(&key);
        state.stats.variant_renders += 1;
        let rendered = state.remember_variant(key, rendered);
        self.variant_ready.notify_all();
        Ok(rendered)
    }

    fn cancel_variant_render(&self, key: VariantKey) {
        if let Ok(mut state) = self.state.lock() {
            state.in_flight_variants.remove(&key);
            self.variant_ready.notify_all();
        }
    }
}

pub(crate) fn normalize_variant_width(width: u32) -> Option<u32> {
    if width == 0 {
        return None;
    }
    let clamped = width.clamp(MIN_VARIANT_WIDTH, MAX_VARIANT_WIDTH);
    Some(((clamped + 31) / 64) * 64)
}

pub(crate) fn mime_for_path(path: &Path) -> &'static str {
    let Some(ext) = path.extension().and_then(|v| v.to_str()) else {
        return "application/octet-stream";
    };
    if ext.eq_ignore_ascii_case("jpg") || ext.eq_ignore_ascii_case("jpeg") {
        "image/jpeg"
    } else if ext.eq_ignore_ascii_case("png") {
        "image/png"
    } else if ext.eq_ignore_ascii_case("webp") {
        "image/webp"
    } else if ext.eq_ignore_ascii_case("gif") {
        "image/gif"
    } else if ext.eq_ignore_ascii_case("bmp") {
        "image/bmp"
    } else if ext.eq_ignore_ascii_case("avif") {
        "image/avif"
    } else {
        "application/octet-stream"
    }
}

fn compute_page_source(source_path: &str, source_type: &str) -> Result<PageSource, String> {
    match source_type {
        "folder" => Ok(PageSource::Folder(image_entries_in_dir(Path::new(
            source_path,
        )))),
        "zip" | "cbz" => Ok(PageSource::Archive {
            source_path: PathBuf::from(source_path),
            pages: archive_image_entries(Path::new(source_path))?,
        }),
        other => Err(format!("unsupported source type: {other}")),
    }
}

fn get_or_load_page_source(
    conn: &Connection,
    cache: &PageCache,
    chapter_id: i64,
) -> Result<PageSource, String> {
    {
        let mut state = cache.lock_state()?;
        if let Some(source) = state.sources.get(&chapter_id).cloned() {
            state.stats.page_source_cache_hits += 1;
            state.touch_source(chapter_id);
            return Ok(source);
        }
    }
    let (source_path, source_type) = chapter_source(conn, chapter_id)?;
    let source = compute_page_source(&source_path, &source_type)?;
    let mut state = cache.lock_state()?;
    if let Some(source) = state.sources.get(&chapter_id).cloned() {
        state.stats.page_source_cache_hits += 1;
        state.touch_source(chapter_id);
        return Ok(source);
    }
    state.stats.page_source_loads += 1;
    state.remember_source(chapter_id, source.clone());
    Ok(source)
}

pub(crate) fn read_page_bytes(
    source: &PageSource,
    page_index: usize,
) -> Result<(Vec<u8>, &'static str), String> {
    match source {
        PageSource::Folder(pages) => {
            let page_path = pages
                .get(page_index)
                .ok_or_else(|| "page index out of range".to_string())?;
            let bytes =
                fs::read(page_path).map_err(|e| format!("failed reading image file: {e}"))?;
            Ok((bytes, mime_for_path(page_path)))
        }
        PageSource::Archive { source_path, pages } => {
            let name = pages
                .get(page_index)
                .ok_or_else(|| "page index out of range".to_string())?;
            let mime = mime_for_path(Path::new(name));
            let file =
                fs::File::open(source_path).map_err(|e| format!("failed opening archive: {e}"))?;
            let mut archive = ZipArchive::new(file).map_err(|e| format!("invalid zip/cbz: {e}"))?;
            let mut entry = archive
                .by_name(name)
                .map_err(|e| format!("failed reading archive entry: {e}"))?;
            let mut bytes = Vec::new();
            entry
                .read_to_end(&mut bytes)
                .map_err(|e| format!("failed extracting image: {e}"))?;
            Ok((bytes, mime))
        }
    }
}

fn get_or_load_page_bytes(
    conn: &Connection,
    cache: &PageCache,
    chapter_id: i64,
    page_index: usize,
) -> Result<(Vec<u8>, &'static str), String> {
    let key = (chapter_id, page_index);
    {
        let mut state = cache.lock_state()?;
        if let Some(cached) = state.bytes.get(&key).cloned() {
            state.stats.page_bytes_cache_hits += 1;
            state.touch_bytes(key);
            return Ok((cached.bytes, cached.mime));
        }
    }
    let source = get_or_load_page_source(conn, cache, chapter_id)?;
    let (bytes, mime) = read_page_bytes(&source, page_index)?;
    let mut state = cache.lock_state()?;
    if let Some(cached) = state.bytes.get(&key).cloned() {
        state.stats.page_bytes_cache_hits += 1;
        state.touch_bytes(key);
        return Ok((cached.bytes, cached.mime));
    }
    state.stats.page_bytes_loads += 1;
    state.remember_bytes(
        key,
        CachedPageBytes {
            bytes: bytes.clone(),
            mime,
        },
    );
    Ok((bytes, mime))
}

pub(crate) fn page_dimensions_from_bytes(bytes: &[u8]) -> Option<(u32, u32)> {
    image::ImageReader::new(Cursor::new(bytes))
        .with_guessed_format()
        .ok()?
        .into_dimensions()
        .ok()
}

pub(crate) fn should_resize_page(
    source_width: u32,
    source_height: u32,
    target_width: u32,
    source_mime: &'static str,
    profile: ImageVariantProfile,
) -> bool {
    if source_width == 0 || source_height == 0 {
        return false;
    }
    let (num, den) = profile.resize_threshold(source_mime);
    source_width.saturating_mul(den) > target_width.saturating_mul(num)
}

pub(crate) fn resize_page_bytes(
    bytes: &[u8],
    target_width: u32,
    source_mime: &'static str,
    profile: ImageVariantProfile,
) -> Option<(Vec<u8>, &'static str)> {
    let (source_width, source_height) = page_dimensions_from_bytes(bytes)?;
    if !should_resize_page(
        source_width,
        source_height,
        target_width,
        source_mime,
        profile,
    ) {
        return None;
    }

    let image = image::load_from_memory(bytes).ok()?;
    let target_height =
        ((source_height as f64) * (target_width as f64 / source_width as f64)).round() as u32;
    let resized = image.resize_exact(target_width, target_height.max(1), profile.filter());

    let mut out = Vec::new();
    let rgb = resized.to_rgb8();
    let mut encoder =
        image::codecs::jpeg::JpegEncoder::new_with_quality(&mut out, profile.jpeg_quality());
    encoder.encode_image(&rgb).ok()?;
    Some((out, "image/jpeg"))
}

pub(crate) fn render_page_variant_conn(
    conn: &Connection,
    cache: &PageCache,
    payload: RenderPagePayload,
) -> Result<RenderedPage, String> {
    let target_width = payload.target_width.and_then(normalize_variant_width);
    let variant_key = target_width.map(|width| VariantKey {
        chapter_id: payload.chapter_id,
        page_index: payload.page_index,
        target_width: width,
        profile: payload.profile,
    });
    if let Some(key) = variant_key {
        if let Some(rendered) = cache.begin_variant_render(key)? {
            return Ok(rendered);
        }
    }

    let render_result = (|| {
        let (source_bytes, source_mime) =
            get_or_load_page_bytes(conn, cache, payload.chapter_id, payload.page_index)?;
        let (bytes, mime) = if source_mime == "image/gif" {
            (source_bytes, source_mime)
        } else if let Some(target_width) = target_width {
            resize_page_bytes(&source_bytes, target_width, source_mime, payload.profile)
                .unwrap_or((source_bytes, source_mime))
        } else {
            (source_bytes, source_mime)
        };
        let (width, height) = page_dimensions_from_bytes(&bytes).unwrap_or((0, 0));
        let cache_key = format!(
            "{}:{}:{}:{:?}",
            payload.chapter_id,
            payload.page_index,
            target_width.unwrap_or(0),
            payload.profile
        );
        Ok(RenderedPage {
            bytes,
            mime: mime.to_string(),
            width,
            height,
            cache_key,
        })
    })();

    if let Some(key) = variant_key {
        return match render_result {
            Ok(rendered) => cache.finish_variant_render(key, rendered),
            Err(error) => {
                cache.cancel_variant_render(key);
                Err(error)
            }
        };
    }
    render_result
}
