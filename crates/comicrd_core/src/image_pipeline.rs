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
    /// Rar/cbr chapter extracted once into a session dir (see below).
    /// Reads and dimension probes serve from disk; no per-request unrar
    /// scan. Zip/cbz keep the `Archive` variant (cheap header probes).
    RarSession {
        files: Arc<Vec<PathBuf>>,
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
    rar_session_base: PathBuf,
}

/// One extracted rar/cbr chapter: `entries` (archive names, list order)
/// and `files` (extracted paths) are parallel. Served from disk until the
/// page source is evicted or the reader closes.
#[derive(Clone)]
pub(crate) struct RarSession {
    dir: PathBuf,
    pub(crate) entries: Arc<Vec<String>>,
    pub(crate) files: Arc<Vec<PathBuf>>,
}

#[derive(Default)]
struct PageCacheState {
    sources: HashMap<i64, PageSource>,
    source_order: VecDeque<i64>,
    bytes: HashMap<(i64, usize, usize), CachedPageBytes>,
    bytes_order: VecDeque<(i64, usize, usize)>,
    /// Live rar sessions by chapter. Bounded by the page-source LRU
    /// below: a session dies with its source (plus reader-close evict
    /// and the startup sweep in `ComicRdCore::open`).
    rar_sessions: HashMap<i64, std::sync::Arc<RarSession>>,
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

    fn remember_source(&mut self, chapter_id: i64, source: PageSource) -> Vec<PathBuf> {
        self.sources.insert(chapter_id, source);
        self.touch_source(chapter_id);
        let mut evicted_sessions = Vec::new();
        while self.source_order.len() > PAGE_SOURCE_CACHE_CAP {
            let Some(old_key) = self.source_order.pop_front() else {
                break;
            };
            self.sources.remove(&old_key);
            // Sessions follow their source through the same LRU: at most
            // PAGE_SOURCE_CACHE_CAP live session dirs. The caller deletes
            // the dirs after dropping this lock (no IO under the mutex).
            if let Some(session) = self.rar_sessions.remove(&old_key) {
                evicted_sessions.push(session.dir.clone());
            }
        }
        evicted_sessions
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
    pub(crate) fn with_rar_session_base(base: PathBuf) -> Self {
        Self {
            state: Mutex::new(PageCacheState::default()),
            rar_session_base: base,
        }
    }

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
    /// An empty keep list also drops the page source and its rar session
    /// dir (reader close/switch path).
    pub(crate) fn evict_except(&self, chapter_id: i64, keep_pages: &[usize]) {
        let session_dir = if let Ok(mut state) = self.state.lock() {
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
                state
                    .rar_sessions
                    .remove(&chapter_id)
                    .map(|session| session.dir.clone())
            } else {
                None
            }
        } else {
            None
        };
        if let Some(dir) = session_dir {
            let _ = fs::remove_dir_all(dir);
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

/// Disk file name for one extracted session entry. The index prefix keeps
/// entries unique (archives may repeat bare names across folders) and
/// preserves list order under natural sort; the original extension is kept
/// so mime probing agrees with the archive entry.
fn session_file_name(index: usize, entry: &str) -> String {
    let base = Path::new(entry)
        .file_name()
        .and_then(|v| v.to_str())
        .unwrap_or("");
    let base = if base.is_empty() {
        "page".to_string()
    } else {
        base.replace(
            ['/', '\\', ':', '*', '?', '"', '<', '>', '|'],
            "_",
        )
    };
    format!("{index:05}-{base}")
}

/// Extract every entry into `dir`, returning paths in entry order.
/// A failed entry removes the half-written dir so retries start clean.
/// `extract_one` is a parameter (not hardcoded to unrar) so the lifecycle
/// is unit-testable with a fake extractor; production passes
/// `archive_image_bytes`.
fn extract_rar_session(
    entries: &[String],
    extract_one: impl Fn(&str) -> Result<Vec<u8>, String>,
    dir: &Path,
) -> Result<Vec<PathBuf>, String> {
    if let Err(e) = fs::create_dir_all(dir) {
        return Err(format!("failed creating rar session dir: {e}"));
    }
    let mut files = Vec::with_capacity(entries.len());
    for (index, entry) in entries.iter().enumerate() {
        let bytes = extract_one(entry).map_err(|e| {
            let _ = fs::remove_dir_all(dir);
            e
        })?;
        let path = dir.join(session_file_name(index, entry));
        if let Err(e) = fs::write(&path, &bytes) {
            let _ = fs::remove_dir_all(dir);
            return Err(format!("failed writing rar session file: {e}"));
        }
        files.push(path);
    }
    Ok(files)
}

/// Session for one rar/cbr chapter, extracted once and served from disk.
/// Slow work (listing, decompress, file writes) runs lock-free; the cache
/// lock only guards the map check/insert. Never call under the DB mutex.
pub(crate) fn ensure_rar_session(
    cache: &PageCache,
    chapter_id: i64,
    source_path: &str,
) -> Result<Arc<RarSession>, String> {
    {
        let state = cache.lock_state()?;
        if let Some(session) = state.rar_sessions.get(&chapter_id) {
            return Ok(Arc::clone(session));
        }
    }
    let base = cache.rar_session_base.clone();
    let _ = fs::create_dir_all(&base);
    let dir = base.join(format!("chapter-{chapter_id}"));
    // Stale leftovers (crash between extract and evict, or an evicted
    // session re-opened) must not mix with fresh files.
    let _ = fs::remove_dir_all(&dir);
    let entries = archive_image_entries(Path::new(source_path))?;
    let files = extract_rar_session(
        &entries,
        |name| archive_image_bytes(Path::new(source_path), name),
        &dir,
    )?;
    {
        let mut state = cache.lock_state()?;
        if let Some(existing) = state.rar_sessions.get(&chapter_id) {
            // Lost a race: keep the winner, drop the dir we just made.
            let existing = Arc::clone(existing);
            drop(state);
            let _ = fs::remove_dir_all(&dir);
            return Ok(existing);
        }
        let session = Arc::new(RarSession {
            dir,
            entries: Arc::new(entries),
            files: Arc::new(files),
        });
        state.rar_sessions.insert(chapter_id, Arc::clone(&session));
        Ok(session)
    }
}

fn compute_page_source(
    cache: &PageCache,
    chapter_id: i64,
    source_path: &str,
    source_type: &str,
) -> Result<PageSource, String> {
    match source_type {
        "folder" => Ok(PageSource::Folder(Arc::new(image_entries_in_dir(
            Path::new(source_path),
        )))),
        "zip" | "cbz" => Ok(PageSource::Archive {
            source_path: PathBuf::from(source_path),
            pages: Arc::new(archive_image_entries(Path::new(source_path))?),
        }),
        // Rar/cbr cannot probe headers without full extraction, so the
        // first access extracts once into a session dir; reads and
        // dimension probes serve from disk afterwards.
        "cbr" | "rar" => {
            let session = ensure_rar_session(cache, chapter_id, source_path)?;
            Ok(PageSource::RarSession {
                files: Arc::clone(&session.files),
            })
        }
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
    let source = compute_page_source(cache, chapter_id, source_path, source_type)?;
    let mut state = cache.lock_state()?;
    if let Some(source) = state.sources.get(&chapter_id).cloned() {
        state.stats.page_source_cache_hits += 1;
        state.touch_source(chapter_id);
        return Ok(source);
    }
    state.stats.page_source_loads += 1;
    let evicted_sessions = state.remember_source(chapter_id, source.clone());
    drop(state);
    // Session dirs die outside the cache lock (plain IO, best effort).
    for dir in evicted_sessions {
        let _ = fs::remove_dir_all(dir);
    }
    Ok(source)
}

pub(crate) fn read_page_bytes(
    source: &PageSource,
    page_index: usize,
) -> Result<(Vec<u8>, &'static str), String> {
    match source {
        PageSource::Folder(pages) | PageSource::RarSession { files: pages } => {
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
    // SIMD fast path; exotic pixel types fall back to the image crate.
    if let Some(resized) = fir_resize_to_width(img, new_height) {
        return Some(resized);
    }
    Some(img.resize(MAX_VARIANT_WIDTH, new_height, FilterType::CatmullRom))
}

/// SIMD downscale via fast_image_resize (CatmullRom, same kernel family as
/// before; `use_alpha` keeps straight-alpha correctness for RGBA PNGs).
/// Returns None for non-8-bit pixel types (caller falls back) or on any
/// internal error (dimensions are pre-validated, so errors are unreachable
/// in practice but must never panic the reader).
fn fir_resize_to_width(img: &image::DynamicImage, new_height: u32) -> Option<image::DynamicImage> {
    use fast_image_resize::images::Image as FirImage;
    use fast_image_resize::{
        FilterType as FirFilter, PixelType, ResizeAlg, ResizeOptions, Resizer,
    };
    // 8-bit only; 16-bit sources keep the image-crate fallback below.
    // (`img` serves as the source view directly: zero-copy, no alignment
    // pitfalls from borrowed slices.)
    let pixel_type = match img.color() {
        image::ColorType::L8 => PixelType::U8,
        image::ColorType::La8 => PixelType::U8x2,
        image::ColorType::Rgb8 => PixelType::U8x3,
        image::ColorType::Rgba8 => PixelType::U8x4,
        _ => return None,
    };
    let mut dst = FirImage::new(MAX_VARIANT_WIDTH, new_height, pixel_type);
    let mut resizer = Resizer::new();
    let options = ResizeOptions::new()
        .resize_alg(ResizeAlg::Convolution(FirFilter::CatmullRom))
        .use_alpha(true);
    resizer.resize(img, &mut dst, &options).ok()?;
    let buffer = dst.buffer().to_vec();
    match pixel_type {
        PixelType::U8 => image::ImageBuffer::from_raw(MAX_VARIANT_WIDTH, new_height, buffer)
            .map(image::DynamicImage::ImageLuma8),
        PixelType::U8x2 => image::ImageBuffer::from_raw(MAX_VARIANT_WIDTH, new_height, buffer)
            .map(image::DynamicImage::ImageLumaA8),
        PixelType::U8x3 => image::ImageBuffer::from_raw(MAX_VARIANT_WIDTH, new_height, buffer)
            .map(image::DynamicImage::ImageRgb8),
        _ => image::ImageBuffer::from_raw(MAX_VARIANT_WIDTH, new_height, buffer)
            .map(image::DynamicImage::ImageRgba8),
    }
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

/// Cache-hit-or-insert for a single tile: concurrent duplicate work
/// collapses into a hit instead of double-counting a load.
fn remember_tile_bytes(
    cache: &PageCache,
    key: (i64, usize, usize),
    bytes: Vec<u8>,
    mime: &'static str,
) -> Result<(Arc<Vec<u8>>, &'static str), String> {
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

/// Tile work plan for one page, shared by the single render and the
/// batched prefetch so both agree on layout and output bytes.
enum PageBody {
    /// Serve the original file bytes untouched: fits without resize or
    /// tiling (fast header path), GIF animation, or undecodable file.
    /// No full decode is performed (or needed).
    Raw,
    /// One decoded image to crop/encode tiles from.
    Decoded(image::DynamicImage),
}

struct PagePlan {
    body: PageBody,
    /// Fitted width + tile heights (from headers for the Raw fast path,
    /// from pixels for Decoded; a single whole-file tile otherwise).
    fitted_width: u32,
    tiles: Vec<u32>,
    /// For single-tile Decoded pages: whether the width cap was applied
    /// (false serves the original bytes, byte-identical to the old output).
    resized: bool,
}

fn plan_page_tiles(bytes: &[u8], mime: &'static str) -> PagePlan {
    // Fast path: the header probe is ~1000x cheaper than a full decode.
    // When the headers already prove the page needs neither resize nor
    // tiling, the original bytes serve as-is (byte-identical to the old
    // decode-then-discard pass-through). GIFs and undecodable files keep
    // the slow path: GIFs preserve the animation rule and corrupt files
    // must survive as whole-file single tiles (matching list-time layout).
    if mime != "image/gif" {
        if let Some((width, height)) = page_dimensions_from_bytes(bytes) {
            let (fitted_width, tiles) = tile_layout_for_dimensions(width, height, false);
            if fitted_width == width && tiles.len() == 1 {
                return PagePlan {
                    body: PageBody::Raw,
                    fitted_width,
                    tiles,
                    resized: false,
                };
            }
        }
    }
    match decode_and_fit(bytes, mime) {
        Err(()) => PagePlan {
            body: PageBody::Raw,
            fitted_width: 0,
            tiles: vec![0],
            resized: false,
        },
        Ok(page) => {
            let (fitted_width, fitted_height) = (page.image.width(), page.image.height());
            let (_, tiles) = tile_layout_for_dimensions(fitted_width, fitted_height, false);
            if page.resized {
                debug_assert_eq!(fitted_width, MAX_VARIANT_WIDTH);
            }
            PagePlan {
                body: PageBody::Decoded(page.image),
                fitted_width,
                tiles,
                resized: page.resized,
            }
        }
    }
}

/// Encode one tile from a plan. Callers validate `tile_index` first.
fn encode_planned_tile(
    plan: &PagePlan,
    bytes: &[u8],
    mime: &'static str,
    tile_index: usize,
) -> Result<(Vec<u8>, &'static str), String> {
    match &plan.body {
        PageBody::Raw => Ok((bytes.to_vec(), mime)),
        PageBody::Decoded(image) => {
            if plan.tiles.len() == 1 {
                if !plan.resized {
                    return Ok((bytes.to_vec(), mime));
                }
                return encode_variant_image(image, mime)
                    .ok_or_else(|| "failed encoding page tile".to_string());
            }
            let y = tile_index as u32 * TILE_MAX_HEIGHT;
            let crop = image.crop_imm(0, y, plan.fitted_width, plan.tiles[tile_index]);
            encode_variant_image(&crop, mime)
                .ok_or_else(|| "failed encoding page tile".to_string())
        }
    }
}

/// Batched prefetch for one page: hit-filter under a short lock, then a
/// single decode serves every missed tile of the page. Tiles are handled
/// in payload order and fail fast on the first out-of-range tile, like
/// the old per-tile loop. Stats: +1 `page_bytes_loads` per decoded page,
/// per-tile hits as usual.
pub(crate) fn prefetch_page_tiles_conn(
    cache: &PageCache,
    source_path: &str,
    source_type: &str,
    chapter_id: i64,
    page_index: usize,
    tile_indices: &[usize],
) -> Result<(), String> {
    let mut need = Vec::new();
    {
        let state = cache.lock_state()?;
        for &tile_index in tile_indices {
            if !state.bytes.contains_key(&(chapter_id, page_index, tile_index))
                && !need.contains(&tile_index)
            {
                need.push(tile_index);
            }
        }
    }
    if need.is_empty() {
        return Ok(());
    }
    let source = get_or_load_page_source(cache, chapter_id, source_path, source_type)?;
    let (bytes, mime) = read_page_bytes(&source, page_index)?;
    let plan = plan_page_tiles(&bytes, mime);
    let mut encoded = Vec::with_capacity(need.len());
    for tile_index in need {
        if tile_index >= plan.tiles.len() {
            return Err("tile index out of range".to_string());
        }
        let (out, out_mime) = encode_planned_tile(&plan, &bytes, mime, tile_index)?;
        encoded.push((tile_index, out, out_mime));
    }
    // One decode served the whole batch: +1 load no matter how many tiles
    // were encoded (a lost race counts as a hit instead).
    {
        let mut state = cache.lock_state()?;
        let mut fresh = 0;
        for (tile_index, out, out_mime) in encoded {
            let key = (chapter_id, page_index, tile_index);
            if state.bytes.contains_key(&key) {
                state.stats.page_bytes_cache_hits += 1;
                state.touch_bytes(key);
            } else {
                state.remember_bytes(
                    key,
                    CachedPageBytes {
                        bytes: Arc::new(out),
                        mime: out_mime,
                    },
                );
                fresh += 1;
            }
        }
        if fresh > 0 {
            state.stats.page_bytes_loads += 1;
        }
    }
    Ok(())
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
    // Shared layout/output plan: the fast header path, GIF/corrupt
    // whole-file fallback, and decode+tile math agree here so the single
    // render and the batched prefetch below serve identical bytes.
    let plan = plan_page_tiles(&bytes, mime);
    if tile_index >= plan.tiles.len() {
        return Err("tile index out of range".to_string());
    }
    // Lazy siblings: only the requested tile is encoded here, so first
    // paint pays one decode + one encode. The batched prefetch above
    // decodes once per page for its whole window (no per-tile re-decode).
    let (out, out_mime) = encode_planned_tile(&plan, &bytes, mime, tile_index)?;
    remember_tile_bytes(cache, key, out, out_mime)
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
    fn fir_resize_matches_image_crate_within_tolerance() {
        // Small-but-wide patterned fixtures: FIR CatmullRom must agree with
        // the image crate's CatmullRom reference (encoders differ, so no
        // exact-bytes assert — only perceptual closeness + exact dims).
        // 2600x100 RGB -> 2048x79.
        let rgb = image::ImageBuffer::from_fn(2600, 100, |x, y| {
            image::Rgb([(x % 256) as u8, (y % 256) as u8, ((x * y) % 256) as u8])
        });
        let src = image::DynamicImage::ImageRgb8(rgb);
        let fir = fir_resize_to_width(&src, 79).expect("fir resize");
        assert_eq!((fir.width(), fir.height()), (2048, 79));
        let reference = src.resize(2048, 79, FilterType::CatmullRom);
        let (mean, max) = mean_max_abs_diff(fir.to_rgb8().as_raw(), reference.to_rgb8().as_raw());
        assert!(mean < 2.0, "mean abs diff too large: {mean}");
        assert!(max < 30, "max abs diff too large: {max}");

        // Fully-opaque RGBA (the common comic case) must match tightly:
        // with alpha == 255 everywhere, premultiplied and straight-alpha
        // convolution are the same math up to float rounding.
        let rgba = image::ImageBuffer::from_fn(2600, 100, |x, y| {
            image::Rgba([
                (x % 256) as u8,
                (y % 256) as u8,
                ((x + y) % 256) as u8,
                255,
            ])
        });
        let src = image::DynamicImage::ImageRgba8(rgba);
        let fir = fir_resize_to_width(&src, 79).expect("fir resize rgba");
        assert_eq!((fir.width(), fir.height()), (2048, 79));
        let reference = src.resize(2048, 79, FilterType::CatmullRom);
        let (mean, max) = mean_max_abs_diff(
            fir.to_rgba8().as_raw(),
            reference.to_rgba8().as_raw(),
        );
        assert!(mean < 2.0, "rgba mean abs diff too large: {mean}");
        assert!(max < 30, "rgba max abs diff too large: {max}");

        // Varying alpha exercises the use_alpha path. FIR premultiplies
        // before convolution (the compositing-correct choice; the image
        // crate convolves straight alpha), so color channels may differ
        // where the alpha gradient is steep while alpha itself stays
        // close. This pins "sane", not "identical".
        let rgba = image::ImageBuffer::from_fn(2600, 100, |x, y| {
            image::Rgba([
                (x % 256) as u8,
                (y % 256) as u8,
                ((x + y) % 256) as u8,
                (x % 200 + 55) as u8,
            ])
        });
        let src = image::DynamicImage::ImageRgba8(rgba);
        let fir = fir_resize_to_width(&src, 79).expect("fir varying alpha");
        assert_eq!((fir.width(), fir.height()), (2048, 79));
        let reference = src.resize(2048, 79, FilterType::CatmullRom);
        let (color_mean, color_max, alpha_mean, alpha_max) =
            rgba_channel_diffs(&fir.to_rgba8(), &reference.to_rgba8());
        assert!(alpha_mean < 5.0, "alpha mean diff too large: {alpha_mean}");
        assert!(alpha_max < 16, "alpha max diff too large: {alpha_max}");
        assert!(color_mean < 10.0, "color mean diff too large: {color_mean}");
        assert!(color_max < 90, "color max diff too large: {color_max}");
    }

    #[test]
    fn fir_resize_falls_back_for_non_8bit_pixels() {
        let rgb16 = image::ImageBuffer::from_pixel(2600, 100, image::Rgb([1000u16, 2000, 3000]));
        let src = image::DynamicImage::ImageRgb16(rgb16);
        assert!(fir_resize_to_width(&src, 79).is_none());
        // The public path still serves 16-bit PNGs via the image fallback.
        let page = decode_and_fit_png16(&src);
        assert_eq!((page.0, page.1), (2048, 79));
    }

    fn mean_max_abs_diff(a: &[u8], b: &[u8]) -> (f64, u8) {
        assert_eq!(a.len(), b.len());
        let mut sum: u64 = 0;
        let mut max: u8 = 0;
        for (&x, &y) in a.iter().zip(b.iter()) {
            let d = x.abs_diff(y);
            sum += d as u64;
            max = max.max(d);
        }
        (sum as f64 / a.len() as f64, max)
    }

    fn rgba_channel_diffs(
        a: &image::RgbaImage,
        b: &image::RgbaImage,
    ) -> (f64, u8, f64, u8) {
        assert_eq!(a.dimensions(), b.dimensions());
        let (mut color_sum, mut alpha_sum): (u64, u64) = (0, 0);
        let (mut color_max, mut alpha_max): (u8, u8) = (0, 0);
        for (x, y) in a.pixels().zip(b.pixels()) {
            for c in 0..3 {
                let d = x[c].abs_diff(y[c]);
                color_sum += d as u64;
                color_max = color_max.max(d);
            }
            let d = x[3].abs_diff(y[3]);
            alpha_sum += d as u64;
            alpha_max = alpha_max.max(d);
        }
        let n = a.pixels().len() as f64;
        (
            color_sum as f64 / (3.0 * n),
            color_max,
            alpha_sum as f64 / n,
            alpha_max,
        )
    }

    fn decode_and_fit_png16(src: &image::DynamicImage) -> (u32, u32) {
        let resized = resize_to_width(src).expect("fallback resize");
        (resized.width(), resized.height())
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

    #[test]
    fn session_file_name_is_indexed_and_safe() {
        // Index prefix keeps entries unique and list-ordered; extension
        // survives for mime probing; separators and Windows-illegal chars
        // are neutralized.
        assert_eq!(session_file_name(0, "2.png"), "00000-2.png");
        assert_eq!(session_file_name(12, "sub/dir/10.JPG"), "00012-10.JPG");
        assert_eq!(session_file_name(3, "a:b*c?.png"), "00003-a_b_c_.png");
        assert_eq!(session_file_name(0, ""), "00000-page");
    }

    #[test]
    fn extract_rar_session_writes_entries_in_order() {
        let temp = tempfile::tempdir().expect("tempdir");
        let dir = temp.path().join("session");
        let entries = vec![
            "sub/2.png".to_string(),
            "10.png".to_string(),
            "anim.gif".to_string(),
        ];
        let files = extract_rar_session(
            &entries,
            |name| Ok(format!("bytes-of-{name}").into_bytes()),
            &dir,
        )
        .expect("extract");
        assert_eq!(files.len(), 3);
        // Order follows the entry list (archive order), not the sort.
        assert_eq!(files[0].file_name().unwrap(), "00000-2.png");
        assert_eq!(files[1].file_name().unwrap(), "00001-10.png");
        assert_eq!(files[2].file_name().unwrap(), "00002-anim.gif");
        for (entry, path) in entries.iter().zip(files.iter()) {
            assert_eq!(
                std::fs::read(path).expect("read session file"),
                format!("bytes-of-{entry}").into_bytes()
            );
        }
    }

    #[test]
    fn extract_rar_session_failure_removes_half_written_dir() {
        let temp = tempfile::tempdir().expect("tempdir");
        let dir = temp.path().join("session");
        let entries = vec!["ok.png".to_string(), "bad.png".to_string()];
        let result = extract_rar_session(
            &entries,
            |name| {
                if name == "bad.png" {
                    Err("boom".to_string())
                } else {
                    Ok(vec![1, 2, 3])
                }
            },
            &dir,
        );
        assert!(result.is_err());
        assert!(!dir.exists(), "half-written session dir must be gone");
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
