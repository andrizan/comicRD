use std::collections::{HashMap, VecDeque};
use std::fs;
use std::io::Cursor;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, MutexGuard};

use image::codecs::jpeg::JpegEncoder;
use image::imageops::FilterType;
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

#[derive(Default)]
struct PageCacheState {
    sources: HashMap<i64, PageSource>,
    source_order: VecDeque<i64>,
    bytes: HashMap<(i64, usize), CachedPageBytes>,
    bytes_order: VecDeque<(i64, usize)>,
    pub(crate) stats: CacheStats,
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
            if keep_pages.is_empty() {
                state.sources.remove(&chapter_id);
                state.source_order.retain(|key| *key != chapter_id);
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
        "folder" => Ok(PageSource::Folder(Arc::new(image_entries_in_dir(
            Path::new(source_path),
        )))),
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
    // Cache the fitted variant so oversized pages are decoded/resized once.
    let (bytes, mime, _, _) = fit_page_variant(bytes, mime);
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

/// Width cap for reader page variants, in pixels.
///
/// Width is what maps to screen pixels in the vertical reader, so it alone
/// decides on-screen sharpness. A long-side cap would crush tall webtoon
/// strips (e.g. 1600x20000, whose width already fits the display) into
/// unreadable slivers, so height is deliberately left untouched.
/// Display targets are 1000px (portrait) / 1500px (landscape) wide at up to
/// 1.5x zoom; 2048px keeps full sharpness there while cutting width
/// monsters (3000px+) down to a fraction of the decoded GPU texture size
/// (decoded RGBA costs width x height x 4 bytes per page).
const MAX_VARIANT_WIDTH: u32 = 2048;
const VARIANT_JPEG_QUALITY: u8 = 92;

/// Downscale an over-wide page to the variant cap, returning
/// (bytes, mime, width, height).
///
/// Cost/quality balance: CatmullRom resampling (sharper than Triangle, far
/// cheaper than Lanczos3) and lossless PNG output for PNG inputs so line
/// art and text gain no encoding artifacts beyond the resolution change.
/// Other formats are re-encoded as JPEG q92. Images that already fit and
/// GIFs (animation) are returned untouched.
fn fit_page_variant(bytes: Vec<u8>, mime: &'static str) -> (Vec<u8>, &'static str, u32, u32) {
    if mime == "image/gif" {
        let (width, height) = page_dimensions_from_bytes(&bytes).unwrap_or((0, 0));
        return (bytes, mime, width, height);
    }
    let Ok(img) = image::load_from_memory(&bytes) else {
        let (width, height) = page_dimensions_from_bytes(&bytes).unwrap_or((0, 0));
        return (bytes, mime, width, height);
    };
    let (width, height) = (img.width(), img.height());
    if width <= MAX_VARIANT_WIDTH {
        return (bytes, mime, width, height);
    }
    let scale = MAX_VARIANT_WIDTH as f32 / width as f32;
    let new_width = MAX_VARIANT_WIDTH;
    let new_height = ((height as f32 * scale).round() as u32).max(1);
    let resized = img.resize(new_width, new_height, FilterType::CatmullRom);
    if mime == "image/png" {
        let mut output = Vec::new();
        let encoder = image::codecs::png::PngEncoder::new(&mut output);
        if resized.write_with_encoder(encoder).is_err() {
            return (bytes, mime, width, height);
        }
        return (output, "image/png", new_width, new_height);
    }
    let rgb = resized.to_rgb8();
    let mut output = Vec::new();
    if JpegEncoder::new_with_quality(&mut output, VARIANT_JPEG_QUALITY)
        .encode(
            rgb.as_raw(),
            rgb.width(),
            rgb.height(),
            image::ColorType::Rgb8.into(),
        )
        .is_err()
    {
        return (bytes, mime, width, height);
    }
    (output, "image/jpeg", new_width, new_height)
}

pub(crate) fn render_page_variant_conn(
    conn: &Connection,
    cache: &PageCache,
    payload: RenderPagePayload,
) -> Result<RenderedPage, String> {
    let (bytes, mime) =
        get_or_load_page_bytes(conn, cache, payload.chapter_id, payload.page_index)?;
    let (width, height) = page_dimensions_from_bytes(&bytes).unwrap_or((0, 0));
    Ok(RenderedPage {
        bytes: Arc::clone(&bytes),
        mime: mime.to_string(),
        width,
        height,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    #[test]
    fn mime_for_path_recognizes_extensions() {
        assert_eq!(mime_for_path(Path::new("image.jpg")), "image/jpeg");
        assert_eq!(mime_for_path(Path::new("image.jpeg")), "image/jpeg");
        assert_eq!(mime_for_path(Path::new("image.JPG")), "image/jpeg");
        assert_eq!(mime_for_path(Path::new("image.png")), "image/png");
        assert_eq!(mime_for_path(Path::new("image.PNG")), "image/png");
        assert_eq!(mime_for_path(Path::new("image.webp")), "image/webp");
        assert_eq!(mime_for_path(Path::new("image.gif")), "image/gif");
        assert_eq!(mime_for_path(Path::new("image.bmp")), "image/bmp");
        assert_eq!(mime_for_path(Path::new("image.avif")), "image/avif");
        assert_eq!(
            mime_for_path(Path::new("file.txt")),
            "application/octet-stream"
        );
        assert_eq!(
            mime_for_path(Path::new("noext")),
            "application/octet-stream"
        );
    }

    #[test]
    fn page_dimensions_returns_none_for_invalid_bytes() {
        assert!(page_dimensions_from_bytes(&[]).is_none());
        assert!(page_dimensions_from_bytes(&[0x00, 0x01, 0x02]).is_none());
    }

    #[test]
    fn fit_page_variant_passes_through_small_images_untouched() {
        let bytes = png_bytes(800, 400);
        let (out, mime, width, height) = fit_page_variant(bytes.clone(), "image/png");
        assert_eq!(out, bytes);
        assert_eq!(mime, "image/png");
        assert_eq!((width, height), (800, 400));
    }

    #[test]
    fn fit_page_variant_downscales_oversized_pages_to_jpeg() {
        let bytes = jpeg_bytes(3000, 4000);
        let (out, mime, width, height) = fit_page_variant(bytes, "image/jpeg");
        assert_eq!(mime, "image/jpeg");
        assert_eq!((width, height), (2048, 2731));
        let (probe_w, probe_h) = page_dimensions_from_bytes(&out).expect("dims");
        assert_eq!((probe_w, probe_h), (2048, 2731));
    }

    #[test]
    fn fit_page_variant_downscales_oversized_png_losslessly() {
        let bytes = png_bytes(3000, 4000);
        let (out, mime, width, height) = fit_page_variant(bytes, "image/png");
        assert_eq!(mime, "image/png");
        assert_eq!((width, height), (2048, 2731));
        let (probe_w, probe_h) = page_dimensions_from_bytes(&out).expect("dims");
        assert_eq!((probe_w, probe_h), (2048, 2731));
    }

    #[test]
    fn fit_page_variant_leaves_tall_strips_untouched() {
        // A webtoon strip whose width already fits the display must not be
        // shrunk: capping the long side would crush it into a sliver.
        let bytes = png_bytes(1600, 8000);
        let (out, mime, width, height) = fit_page_variant(bytes.clone(), "image/png");
        assert_eq!(out, bytes);
        assert_eq!(mime, "image/png");
        assert_eq!((width, height), (1600, 8000));
    }

    #[test]
    fn fit_page_variant_passes_through_gifs_to_preserve_animation() {
        // Minimal 1x1 transparent GIF.
        let bytes = vec![
            0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00, 0x00,
            0x00, 0x00, 0xFF, 0xFF, 0xFF, 0x21, 0xF9, 0x04, 0x01, 0x00, 0x00, 0x00, 0x00, 0x2C,
            0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x02, 0x02, 0x44, 0x01, 0x00,
            0x3B,
        ];
        let (out, mime, width, height) = fit_page_variant(bytes.clone(), "image/gif");
        assert_eq!(out, bytes);
        assert_eq!(mime, "image/gif");
        assert_eq!((width, height), (1, 1));
    }

    #[test]
    fn fit_page_variant_passes_through_undecodable_bytes() {
        let bytes = vec![0x00, 0x01, 0x02, 0x03];
        let (out, mime, width, height) = fit_page_variant(bytes.clone(), "image/png");
        assert_eq!(out, bytes);
        assert_eq!(mime, "image/png");
        assert_eq!((width, height), (0, 0));
    }

    fn png_bytes(width: u32, height: u32) -> Vec<u8> {
        let image = image::ImageBuffer::from_pixel(width, height, image::Rgba([10u8, 20, 30, 255]));
        let mut cursor = std::io::Cursor::new(Vec::new());
        image
            .write_to(&mut cursor, image::ImageFormat::Png)
            .expect("encode png");
        cursor.into_inner()
    }

    fn jpeg_bytes(width: u32, height: u32) -> Vec<u8> {
        let image = image::ImageBuffer::from_pixel(width, height, image::Rgb([10u8, 20, 30]));
        let mut cursor = std::io::Cursor::new(Vec::new());
        image
            .write_to(&mut cursor, image::ImageFormat::Jpeg)
            .expect("encode jpeg");
        cursor.into_inner()
    }
}
