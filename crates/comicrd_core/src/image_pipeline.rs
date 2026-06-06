use std::collections::{HashMap, VecDeque};
use std::fs;
use std::io::Cursor;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, MutexGuard};

use rusqlite::Connection;

use crate::chapter::{
    archive_image_bytes, archive_image_entries, chapter_source, image_entries_in_dir,
};
use crate::{RenderPagePayload, RenderedPage};

const PAGE_SOURCE_CACHE_CAP: usize = 2;
const PAGE_BYTES_CACHE_CAP: usize = 6;

#[derive(Clone)]
pub(crate) enum PageSource {
    Folder(Arc<Vec<PathBuf>>),
    Archive {
        source_path: PathBuf,
        pages: Arc<Vec<String>>,
    },
}

#[derive(Clone)]
struct CachedPageBytes {
    bytes: Arc<Vec<u8>>,
    mime: &'static str,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CacheStats {
    pub page_source_loads: usize,
    pub page_bytes_loads: usize,
    pub page_source_cache_hits: usize,
    pub page_bytes_cache_hits: usize,
}

#[derive(Default)]
pub(crate) struct PageCache {
    state: Mutex<PageCacheState>,
}

struct PageCacheState {
    sources: HashMap<i64, PageSource>,
    source_order: VecDeque<i64>,
    bytes: HashMap<(i64, usize), CachedPageBytes>,
    bytes_order: VecDeque<(i64, usize)>,
    pub(crate) stats: CacheStats,
}

impl Default for PageCacheState {
    fn default() -> Self {
        Self {
            sources: HashMap::new(),
            source_order: VecDeque::new(),
            bytes: HashMap::new(),
            bytes_order: VecDeque::new(),
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

    pub(crate) fn evict_except(&self, chapter_id: i64, keep_pages: &[usize]) {
        if let Ok(mut state) = self.state.lock() {
            let keys_to_remove: Vec<(i64, usize)> = state
                .bytes
                .keys()
                .filter(|(cid, idx)| *cid == chapter_id && !keep_pages.contains(idx))
                .copied()
                .collect();
            for key in keys_to_remove {
                state.bytes.remove(&key);
                state.bytes_order.retain(|k| *k != key);
            }
        }
    }
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
        "folder" => Ok(PageSource::Folder(Arc::new(image_entries_in_dir(Path::new(
            source_path,
        ))))),
        "zip" | "cbz" | "cbr" | "rar" => Ok(PageSource::Archive {
            source_path: PathBuf::from(source_path),
            pages: Arc::new(archive_image_entries(Path::new(source_path))?),
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
            let bytes = archive_image_bytes(source_path, name)?;
            Ok((bytes, mime))
        }
    }
}

fn get_or_load_page_bytes(
    conn: &Connection,
    cache: &PageCache,
    chapter_id: i64,
    page_index: usize,
) -> Result<(Arc<Vec<u8>>, &'static str), String> {
    let key = (chapter_id, page_index);
    {
        let mut state = cache.lock_state()?;
        if let Some(cached) = state.bytes.get(&key) {
            let result = (Arc::clone(&cached.bytes), cached.mime);
            state.stats.page_bytes_cache_hits += 1;
            state.touch_bytes(key);
            return Ok(result);
        }
    }
    let source = get_or_load_page_source(conn, cache, chapter_id)?;
    let (bytes, mime) = read_page_bytes(&source, page_index)?;
    let shared = Arc::new(bytes);
    let mut state = cache.lock_state()?;
    if let Some(cached) = state.bytes.get(&key) {
        let result = (Arc::clone(&cached.bytes), cached.mime);
        state.stats.page_bytes_cache_hits += 1;
        state.touch_bytes(key);
        return Ok(result);
    }
    state.stats.page_bytes_loads += 1;
    state.remember_bytes(
        key,
        CachedPageBytes {
            bytes: Arc::clone(&shared),
            mime,
        },
    );
    Ok((shared, mime))
}

pub(crate) fn page_dimensions_from_bytes(bytes: &[u8]) -> Option<(u32, u32)> {
    image::ImageReader::new(Cursor::new(bytes))
        .with_guessed_format()
        .ok()?
        .into_dimensions()
        .ok()
}

pub(crate) fn render_page_variant_conn(
    conn: &Connection,
    cache: &PageCache,
    payload: RenderPagePayload,
) -> Result<RenderedPage, String> {
    let (bytes, mime) =
        get_or_load_page_bytes(conn, cache, payload.chapter_id, payload.page_index)?;
    let (width, height) = page_dimensions_from_bytes(&bytes).unwrap_or((0, 0));
    let cache_key = format!("{}:{}", payload.chapter_id, payload.page_index);
    Ok(RenderedPage {
        bytes: (*bytes).clone(),
        mime: mime.to_string(),
        width,
        height,
        cache_key,
    })
}
