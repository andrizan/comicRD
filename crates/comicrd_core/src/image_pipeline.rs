use std::collections::{HashMap, VecDeque};
use std::fs;
use std::io::Cursor;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, MutexGuard};

use image::codecs::jpeg::JpegEncoder;
use image::imageops::FilterType;

use crate::chapter::{
    archive_image_bytes, archive_image_entries, image_entries_in_dir,
};
use crate::{RenderPageTilePayload, RenderedPage};

const PAGE_SOURCE_CACHE_CAP: usize = 2;
// Tiles are small (<=2048x2048 decoded); the cap counts tile entries.
const PAGE_BYTES_CACHE_CAP: usize = 16;
/// Maximum tile height in pixels. Safe on 8192-limited GPUs
/// (2048x2048x4 = 16MB decoded per tile max).

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
    bytes: HashMap<(i64, usize, usize), CachedPageBytes>,
    bytes_order: VecDeque<(i64, usize, usize)>,
    pub(crate) stats: CacheStats,
}

impl PageCacheState {
    fn touch_source(&mut self, chapter_id: i64) {
        self.source_order.retain(|key| *key != chapter_id);
        self.source_order.push_back(chapter_id);
    }

    fn touch_bytes(&mut self, key: (i64, usize, usize)) {
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

    fn remember_bytes(&mut self, key: (i64, usize, usize), bytes: CachedPageBytes) {
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

    /// Drop cached raw bytes for all pages except `keep_pages`.
    /// The key is (chapter, page, tile); every tile of an evicted page goes.
    pub(crate) fn evict_except(&self, chapter_id: i64, keep_pages: &[usize]) {
        if let Ok(mut state) = self.state.lock() {
            let keys_to_remove: Vec<(i64, usize, usize)> = state
                .bytes
                .keys()
                .filter(|(cid, idx, _)| *cid == chapter_id && !keep_pages.contains(idx))
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

/// Resolve a page source without holding the DB mutex: the caller reads
/// `(source_path, source_type)` under a short scoped lock first. Archive
/// listing and directory walks must never run under the DB lock.
fn get_or_load_page_source(
    cache: &PageCache,
    chapter_id: i64,
    source_path: &str,
    source_type: &str,
) -> Result<PageSource, String> {
    {
        let mut state = cache.lock_state()?;
        if let Some(source) = state.sources.get(&chapter_id).cloned() {
            state.stats.page_source_cache_hits += 1;
            state.touch_source(chapter_id);
            return Ok(source);
        }
    }
    let source = compute_page_source(source_path, source_type)?;
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
const TILE_MAX_HEIGHT: u32 = 2048;

/// Tile layout for a page: (fitted width, fitted tile heights top-to-bottom).
///
/// Sole source of truth for tiling; the layout is shipped to Flutter in
/// `PageInfo.tile_heights` so Dart never recomputes splits (Rust uses `f32`
/// rounding that Dart `double` math could disagree on by a row).
/// GIFs and zero-size inputs always yield a single tile.
pub(crate) fn tile_layout_for_dimensions(
    width: u32,
    height: u32,
    is_gif: bool,
) -> (u32, Vec<u32>) {
    let fitted_width = width.min(MAX_VARIANT_WIDTH);
    let fitted_height = if width > MAX_VARIANT_WIDTH {
        let scale = MAX_VARIANT_WIDTH as f32 / width as f32;
        ((height as f32 * scale).round() as u32).max(1)
    } else {
        height
    };
    if is_gif || fitted_height == 0 {
        return (fitted_width, vec![fitted_height]);
    }
    let mut tiles = Vec::new();
    let mut remaining = fitted_height;
    while remaining > 0 {
        let tile = remaining.min(TILE_MAX_HEIGHT);
        tiles.push(tile);
        remaining -= tile;
    }
    (fitted_width, tiles)
}

/// Width-fit; None when already within cap (caller passes bytes through).
fn resize_to_width(img: &image::DynamicImage) -> Option<image::DynamicImage> {
    let (width, height) = (img.width(), img.height());
    if width <= MAX_VARIANT_WIDTH || width == 0 {
        return None;
    }
    let scale = MAX_VARIANT_WIDTH as f32 / width as f32;
    let new_height = ((height as f32 * scale).round() as u32).max(1);
    Some(img.resize(MAX_VARIANT_WIDTH, new_height, FilterType::CatmullRom))
}

/// Encode with the variant rule shared by whole-page and tile paths:
/// lossless PNG for PNG inputs, JPEG q92 otherwise.
fn encode_variant_image(
    img: &image::DynamicImage,
    mime: &'static str,
) -> Option<(Vec<u8>, &'static str)> {
    if mime == "image/png" {
        let mut output = Vec::new();
        let encoder = image::codecs::png::PngEncoder::new(&mut output);
        img.write_with_encoder(encoder).ok()?;
        return Some((output, "image/png"));
    }
    let rgb = img.to_rgb8();
    let mut output = Vec::new();
    JpegEncoder::new_with_quality(&mut output, VARIANT_JPEG_QUALITY)
        .encode(
            rgb.as_raw(),
            rgb.width(),
            rgb.height(),
            image::ColorType::Rgb8.into(),
        )
        .ok()?;
    Some((output, "image/jpeg"))
}

/// Downscale an over-wide page to the variant cap, returning
/// (bytes, mime, width, height).
///
/// Cost/quality balance: CatmullRom resampling (sharper than Triangle, far
/// cheaper than Lanczos3) and lossless PNG output for PNG inputs so line
/// art and text gain no encoding artifacts beyond the resolution change.
/// Other formats are re-encoded as JPEG q92. Images that already fit and
/// GIFs (animation) are returned untouched.
/// Decoded page with width-fit applied at most once. Decoded once per
/// page-miss no matter how many tiles are served from it.
struct DecodedPage {
    /// Pixels after width-fit (original pixels when already fitting).
    image: image::DynamicImage,
    /// Whether the width cap was applied.
    resized: bool,
}

/// Decode + width-fit in one step. `Err` for GIFs (animation) and
/// undecodable bytes; callers pass those through untouched.
fn decode_and_fit(bytes: &[u8], mime: &'static str) -> Result<DecodedPage, ()> {
    if mime == "image/gif" {
        return Err(());
    }
    let img = image::load_from_memory(bytes).map_err(|_| ())?;
    match resize_to_width(&img) {
        Some(resized) => Ok(DecodedPage {
            image: resized,
            resized: true,
        }),
        None => Ok(DecodedPage {
            image: img,
            resized: false,
        }),
    }
}

fn get_or_load_tile_bytes(
    cache: &PageCache,
    source_path: &str,
    source_type: &str,
    chapter_id: i64,
    page_index: usize,
    tile_index: usize,
) -> Result<(Arc<Vec<u8>>, &'static str), String> {
    let key = (chapter_id, page_index, tile_index);
    {
        let mut state = cache.lock_state()?;
        if let Some(cached) = state.bytes.get(&key) {
            let result = (Arc::clone(&cached.bytes), cached.mime);
            state.stats.page_bytes_cache_hits += 1;
            state.touch_bytes(key);
            return Ok(result);
        }
    }
    let source = get_or_load_page_source(cache, chapter_id, source_path, source_type)?;
    let (bytes, mime) = read_page_bytes(&source, page_index)?;
    // Single decode per page-miss: GIFs and corrupt files fall through to
    // the whole-file single tile (matching list-time layout).
    let Ok(page) = decode_and_fit(&bytes, mime) else {
        if tile_index != 0 {
            return Err("tile index out of range".to_string());
        }
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
        return Ok((shared, mime));
    };
    let (fitted_width, fitted_height) = (page.image.width(), page.image.height());
    let (_, tiles) = tile_layout_for_dimensions(fitted_width, fitted_height, false);
    if tile_index >= tiles.len() {
        return Err("tile index out of range".to_string());
    }
    if tiles.len() == 1 {
        // Byte-identical to `fit_page_variant` output without decoding
        // twice: untouched originals pass through, resized pages encode the
        // one decoded image.
        if !page.resized {
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
            return Ok((shared, mime));
        }
        let (new_width, new_height) = (page.image.width(), page.image.height());
        let (out, out_mime) = encode_variant_image(&page.image, mime)
            .ok_or_else(|| "failed encoding page tile".to_string())?;
        debug_assert_eq!(
            (new_width, new_height),
            (fitted_width, fitted_height)
        );
        let shared = Arc::new(out);
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
                mime: out_mime,
            },
        );
        return Ok((shared, out_mime));
    }
    // Multi-tile: crop every tile from the one decoded image and cache
    // them all, so sibling tiles never pay another full decode. Counts as
    // ONE page-miss in stats regardless of tile count.
    let mut encoded: Vec<(Vec<u8>, &'static str)> = Vec::with_capacity(tiles.len());
    for (t, tile_height) in tiles.iter().enumerate() {
        let y = t as u32 * TILE_MAX_HEIGHT;
        let crop = page.image.crop_imm(0, y, fitted_width, *tile_height);
        let (out, out_mime) = encode_variant_image(&crop, mime)
            .ok_or_else(|| "failed encoding page tile".to_string())?;
        encoded.push((out, out_mime));
    }
    let mut state = cache.lock_state()?;
    if let Some(cached) = state.bytes.get(&key) {
        let result = (Arc::clone(&cached.bytes), cached.mime);
        state.stats.page_bytes_cache_hits += 1;
        state.touch_bytes(key);
        return Ok(result);
    }
    state.stats.page_bytes_loads += 1;
    let mut requested: Option<(Arc<Vec<u8>>, &'static str)> = None;
    for (t, (out, out_mime)) in encoded.into_iter().enumerate() {
        let shared = Arc::new(out);
        if t == tile_index {
            requested = Some((Arc::clone(&shared), out_mime));
        }
        state.remember_bytes(
            (chapter_id, page_index, t),
            CachedPageBytes {
                bytes: Arc::clone(&shared),
                mime: out_mime,
            },
        );
    }
    Ok(requested.expect("requested tile was just encoded"))
}

pub(crate) fn render_page_tile_conn(
    cache: &PageCache,
    source_path: &str,
    source_type: &str,
    payload: RenderPageTilePayload,
) -> Result<RenderedPage, String> {
    let (bytes, mime) = get_or_load_tile_bytes(
        cache,
        source_path,
        source_type,
        payload.chapter_id,
        payload.page_index,
        payload.tile_index,
    )?;
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
    fn decode_and_fit_passes_through_small_images() {
        let bytes = png_bytes(800, 400);
        let page = decode_and_fit(&bytes, "image/png").expect("decode");
        assert!(!page.resized);
        assert_eq!((page.image.width(), page.image.height()), (800, 400));
    }

    #[test]
    fn decode_and_fit_downscales_oversized_pages() {
        let bytes = jpeg_bytes(3000, 4000);
        let page = decode_and_fit(&bytes, "image/jpeg").expect("decode");
        assert!(page.resized);
        assert_eq!((page.image.width(), page.image.height()), (2048, 2731));
        let png = png_bytes(3000, 4000);
        let page = decode_and_fit(&png, "image/png").expect("decode");
        assert!(page.resized);
        assert_eq!((page.image.width(), page.image.height()), (2048, 2731));
    }

    #[test]
    fn decode_and_fit_keeps_tall_strips_at_full_width() {
        // A webtoon strip whose width already fits the display must not be
        // shrunk: capping the long side would crush it into a sliver.
        let bytes = png_bytes(1600, 8000);
        let page = decode_and_fit(&bytes, "image/png").expect("decode");
        assert!(!page.resized);
        assert_eq!((page.image.width(), page.image.height()), (1600, 8000));
    }

    #[test]
    fn tile_layout_keeps_short_pages_whole() {
        assert_eq!(tile_layout_for_dimensions(800, 400, false), (800, vec![400]));
        assert_eq!(
            tile_layout_for_dimensions(1600, 2048, false),
            (1600, vec![2048])
        );
        assert_eq!(
            tile_layout_for_dimensions(3000, 4000, false),
            (2048, vec![2048, 683])
        );
    }

    #[test]
    fn tile_layout_splits_tall_strips_on_exact_boundaries() {
        let (w, tiles) = tile_layout_for_dimensions(1600, 20000, false);
        assert_eq!(w, 1600);
        assert_eq!(tiles.len(), 10);
        assert!(tiles[..9].iter().all(|&t| t == 2048));
        assert_eq!(tiles[9], 20000 - 9 * 2048);
        assert_eq!(tiles.iter().sum::<u32>(), 20000);
    }

    #[test]
    fn tile_layout_splits_fitted_wide_pages() {
        // 3000x4000 JPEG -> fitted 2048x2731 -> tiles [2048, 683].
        // (Crop/encode interplay for fitted pages shares the loop proven
        // pixel-exact by the strip reassembly test.)
        assert_eq!(
            tile_layout_for_dimensions(3000, 4000, false),
            (2048, vec![2048, 683])
        );
    }

    #[test]
    fn tile_layout_splits_exact_multiples_without_empty_trailing_tile() {
        assert_eq!(
            tile_layout_for_dimensions(100, 4096, false),
            (100, vec![2048, 2048])
        );
        assert_eq!(
            tile_layout_for_dimensions(100, 2049, false),
            (100, vec![2048, 1])
        );
    }

    #[test]
    fn tile_layout_never_tiles_gifs_or_empty_pages() {
        assert_eq!(
            tile_layout_for_dimensions(1600, 20000, true),
            (1600, vec![20000])
        );
        assert_eq!(tile_layout_for_dimensions(0, 0, false), (0, vec![0]));
    }

    #[test]
    fn decode_and_fit_rejects_gifs_and_garbage() {
        // Minimal 1x1 transparent GIF.
        let bytes = vec![
            0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00, 0x00,
            0x00, 0x00, 0xFF, 0xFF, 0xFF, 0x21, 0xF9, 0x04, 0x01, 0x00, 0x00, 0x00, 0x00, 0x2C,
            0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x02, 0x02, 0x44, 0x01, 0x00,
            0x3B,
        ];
        assert!(decode_and_fit(&bytes, "image/gif").is_err());
        assert!(decode_and_fit(&[0x00, 0x01, 0x02, 0x03], "image/png").is_err());
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
