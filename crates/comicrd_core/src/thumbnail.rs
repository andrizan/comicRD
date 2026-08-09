use std::collections::{HashMap, HashSet, VecDeque};
use std::fs;
use std::path::Path;
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::SystemTime;

use image::codecs::jpeg::JpegEncoder;
use image::{imageops::FilterType, ColorType, DynamicImage};

use crate::chapter::{
    archive_image_bytes, archive_image_entries, discover_chapter_entries_for_comic,
    image_entries_in_dir, image_entries_in_dir_shallow,
};

const THUMBNAIL_CACHE_CAP: usize = 64;
const DEFAULT_THUMBNAIL_QUALITY: u8 = 85;

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
struct ThumbnailKey {
    source_path: String,
    max_width: u32,
    max_height: u32,
}

#[derive(Default)]
pub(crate) struct ThumbnailCache {
    state: Mutex<ThumbnailCacheState>,
}

#[derive(Default)]
struct ThumbnailCacheState {
    entries: HashMap<ThumbnailKey, Arc<Vec<u8>>>,
    order: VecDeque<ThumbnailKey>,
}

impl ThumbnailCacheState {
    fn touch(&mut self, key: &ThumbnailKey) {
        self.order.retain(|k| k != key);
        self.order.push_back(key.clone());
    }

    fn remember(&mut self, key: ThumbnailKey, bytes: Arc<Vec<u8>>) {
        self.entries.insert(key.clone(), bytes);
        self.touch(&key);
        while self.order.len() > THUMBNAIL_CACHE_CAP {
            let Some(old_key) = self.order.pop_front() else {
                break;
            };
            self.entries.remove(&old_key);
        }
    }
}

impl ThumbnailCache {
    fn lock_state(&self) -> Result<MutexGuard<'_, ThumbnailCacheState>, String> {
        self.state
            .lock()
            .map_err(|_| "thumbnail cache lock poisoned".to_string())
    }

    pub(crate) fn get(
        &self,
        source_path: &str,
        max_width: u32,
        max_height: u32,
    ) -> Option<Arc<Vec<u8>>> {
        let key = ThumbnailKey {
            source_path: source_path.to_string(),
            max_width,
            max_height,
        };
        let mut state = self.lock_state().ok()?;
        let bytes = state.entries.get(&key).cloned()?;
        state.touch(&key);
        Some(bytes)
    }

    pub(crate) fn insert(
        &self,
        source_path: &str,
        max_width: u32,
        max_height: u32,
        bytes: Arc<Vec<u8>>,
    ) -> Result<(), String> {
        let key = ThumbnailKey {
            source_path: source_path.to_string(),
            max_width,
            max_height,
        };
        let mut state = self.lock_state()?;
        state.remember(key, bytes);
        Ok(())
    }
}

/// Load the first suitable image bytes for a comic source.
///
/// For folder comics this first tries root-level images. If the folder has no
/// cover image, it falls back to the first page of the earliest chapter that
/// contains images.
/// For archive comics this reads the first image entry in natural order.
///
/// Returns an empty `Vec` when the source has no usable images at all (empty
/// folder, no chapter with images, or empty archive). This lets callers treat
/// "no content" as a silent fallback rather than an error.
pub(crate) fn load_cover_image_bytes(source_path: &str) -> Result<Vec<u8>, String> {
    let path = Path::new(source_path);
    if !path.exists() {
        // The comic source was moved or deleted after the library was listed.
        // Treat this as a silent fallback so the UI can show a placeholder
        // thumbnail instead of bubbling an error up through the bridge.
        return Ok(Vec::new());
    }
    if path.is_dir() {
        // Prefer a root-level cover image.
        let root_images = image_entries_in_dir_shallow(path);
        if let Some(first) = root_images.first() {
            return std::fs::read(first)
                .map_err(|e| format!("failed reading cover image: {e}"));
        }

        // Fall back to the first readable page of chapter 1 (or the first
        // chapter that actually contains images).
        let chapters = discover_chapter_entries_for_comic(source_path)?;
        for (_, chapter_path, chapter_source_type, _) in chapters {
            if let Ok(bytes) = first_page_bytes(&chapter_path, &chapter_source_type) {
                return Ok(bytes);
            }
        }
        Ok(Vec::new())
    } else {
        let entries = archive_image_entries(path)?;
        let Some(first) = entries.first() else {
            return Ok(Vec::new());
        };
        archive_image_bytes(path, first)
    }
}

/// Read the first image page from a chapter source (folder or archive).
fn first_page_bytes(source_path: &str, source_type: &str) -> Result<Vec<u8>, String> {
    match source_type {
        "folder" => {
            let path = Path::new(source_path);
            let entries = image_entries_in_dir(path);
            let Some(first) = entries.first() else {
                return Err("no images found in chapter folder".to_string());
            };
            std::fs::read(first).map_err(|e| format!("failed reading chapter page: {e}"))
        }
        _ => {
            let path = Path::new(source_path);
            let entries = archive_image_entries(path)?;
            let Some(first) = entries.first() else {
                return Err("no images found in chapter archive".to_string());
            };
            archive_image_bytes(path, first)
        }
    }
}

/// Resize a decoded image so it fits inside `max_width` x `max_height` while
/// preserving aspect ratio. If the image is already smaller than both bounds,
/// it is returned without upscaling.
fn fit_thumbnail(img: &DynamicImage, max_width: u32, max_height: u32) -> DynamicImage {
    let (orig_w, orig_h) = (img.width(), img.height());
    let scale_x = max_width as f32 / orig_w as f32;
    let scale_y = max_height as f32 / orig_h as f32;
    let scale = scale_x.min(scale_y).min(1.0);

    if scale >= 1.0 {
        return img.clone();
    }

    let new_w = (orig_w as f32 * scale).round() as u32;
    let new_h = (orig_h as f32 * scale).round() as u32;
    img.resize(new_w, new_h, FilterType::Triangle)
}

/// Generate a JPEG thumbnail for a comic source.
///
/// Returns an empty `Arc<Vec<u8>>` when the source has no usable cover image
/// (empty folder, no chapter with images, or empty archive). Callers should
/// treat this as a silent fallback and skip cache writes.
pub(crate) fn generate_thumbnail_bytes(
    source_path: &str,
    max_width: u32,
    max_height: u32,
) -> Result<Arc<Vec<u8>>, String> {
    let cover_bytes = load_cover_image_bytes(source_path)?;
    if cover_bytes.is_empty() {
        return Ok(Arc::new(Vec::new()));
    }
    let img = image::load_from_memory(&cover_bytes)
        .map_err(|e| format!("failed decoding cover image: {e}"))?;
    let thumbnail = fit_thumbnail(&img, max_width, max_height);

    let rgb = thumbnail.to_rgb8();
    let mut output = Vec::new();
    JpegEncoder::new_with_quality(&mut output, DEFAULT_THUMBNAIL_QUALITY)
        .encode(rgb.as_raw(), rgb.width(), rgb.height(), ColorType::Rgb8.into())
        .map_err(|e| format!("failed encoding thumbnail: {e}"))?;

    Ok(Arc::new(output))
}

const MAX_DISK_CACHE_BYTES: u64 = 200 * 1024 * 1024;

fn fnv1a_64(data: &str) -> u64 {
    const FNV_OFFSET: u64 = 0xcbf29ce484222325;
    const FNV_PRIME: u64 = 0x100000001b3;
    let mut hash = FNV_OFFSET;
    for b in data.bytes() {
        hash ^= b as u64;
        hash = hash.wrapping_mul(FNV_PRIME);
    }
    hash
}

fn disk_cache_filename(source_path: &str, max_width: u32, max_height: u32) -> String {
    format!(
        "{}x{}-{:016x}.jpg",
        max_width,
        max_height,
        fnv1a_64(source_path)
    )
}

pub(crate) fn read_disk_thumbnail(
    thumbnail_dir: &Path,
    source_path: &str,
    max_width: u32,
    max_height: u32,
) -> Option<Vec<u8>> {
    let path = thumbnail_dir.join(disk_cache_filename(source_path, max_width, max_height));
    if !path.is_file() {
        return None;
    }
    fs::read(&path).ok()
}

pub(crate) fn write_disk_thumbnail(
    thumbnail_dir: &Path,
    source_path: &str,
    max_width: u32,
    max_height: u32,
    bytes: &[u8],
) -> Result<(), String> {
    fs::create_dir_all(thumbnail_dir)
        .map_err(|e| format!("failed creating thumbnail dir: {e}"))?;
    let path = thumbnail_dir.join(disk_cache_filename(source_path, max_width, max_height));
    fs::write(&path, bytes).map_err(|e| format!("failed writing thumbnail: {e}"))?;
    trim_disk_cache(thumbnail_dir, MAX_DISK_CACHE_BYTES)?;
    Ok(())
}

fn trim_disk_cache(thumbnail_dir: &Path, max_bytes: u64) -> Result<(), String> {
    let mut entries: Vec<(std::path::PathBuf, u64, SystemTime)> = Vec::new();
    for entry in fs::read_dir(thumbnail_dir)
        .map_err(|e| format!("failed reading thumbnail dir: {e}"))?
    {
        let entry = entry.map_err(|e| format!("failed reading dir entry: {e}"))?;
        let meta = entry
            .metadata()
            .map_err(|e| format!("failed reading metadata: {e}"))?;
        if meta.is_file() {
            let modified = meta.modified().unwrap_or(SystemTime::UNIX_EPOCH);
            entries.push((entry.path(), meta.len(), modified));
        }
    }

    let total: u64 = entries.iter().map(|(_, size, _)| *size).sum();
    if total <= max_bytes {
        return Ok(());
    }

    entries.sort_by(|a, b| a.2.cmp(&b.2));
    let mut to_free = total - max_bytes;
    for (path, size, _) in entries {
        if to_free == 0 {
            break;
        }
        if fs::remove_file(&path).is_ok() {
            to_free = to_free.saturating_sub(size);
        }
    }
    Ok(())
}

/// Delete cached thumbnail files whose source path is not in
/// `valid_source_paths`. Returns the number of files removed and the bytes
/// freed. Used by database optimization so deleted comics do not leave junk
/// cover images behind.
pub(crate) fn purge_orphan_thumbnails(
    thumbnail_dir: &Path,
    valid_source_paths: &HashSet<String>,
) -> Result<(usize, u64), String> {
    let valid_hashes: HashSet<u64> = valid_source_paths
        .iter()
        .map(|path| fnv1a_64(path))
        .collect();

    let mut removed = 0usize;
    let mut freed_bytes = 0u64;
    for entry in fs::read_dir(thumbnail_dir)
        .map_err(|e| format!("failed reading thumbnail dir: {e}"))?
    {
        let entry = entry.map_err(|e| format!("failed reading dir entry: {e}"))?;
        let name = entry.file_name();
        let Some(name) = name.to_str() else {
            continue;
        };
        let Some((dimensions, hash_hex)) = name.split_once('-') else {
            continue;
        };
        if !dimensions.contains('x') || !hash_hex.ends_with(".jpg") {
            continue;
        }
        let Some(hash_hex) = hash_hex.strip_suffix(".jpg") else {
            continue;
        };
        let Ok(hash) = u64::from_str_radix(hash_hex, 16) else {
            continue;
        };
        if valid_hashes.contains(&hash) {
            continue;
        }
        let meta = entry.metadata().ok();
        let size = meta.as_ref().map(|m| m.len()).unwrap_or(0);
        if fs::remove_file(entry.path()).is_ok() {
            removed += 1;
            freed_bytes += size;
        }
    }
    Ok((removed, freed_bytes))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn thumbnail_cache_stores_and_evicts() {
        let cache = ThumbnailCache::default();
        let key = "comic/one";
        let bytes = Arc::new(vec![1, 2, 3]);
        cache.insert(key, 200, 300, Arc::clone(&bytes)).unwrap();
        assert_eq!(cache.get(key, 200, 300), Some(bytes));
        assert!(cache.get(key, 100, 100).is_none());
    }

    #[test]
    fn fit_thumbnail_preserves_aspect_ratio() {
        let img = DynamicImage::new_rgb8(400, 200);
        let thumb = fit_thumbnail(&img, 100, 100);
        assert_eq!(thumb.width(), 100);
        assert_eq!(thumb.height(), 50);
    }

    #[test]
    fn fit_thumbnail_does_not_upscale() {
        let img = DynamicImage::new_rgb8(50, 50);
        let thumb = fit_thumbnail(&img, 100, 100);
        assert_eq!(thumb.width(), 50);
        assert_eq!(thumb.height(), 50);
    }

    #[test]
    fn load_cover_returns_empty_for_empty_folder() {
        let dir = tempdir();
        let result = load_cover_image_bytes(dir.to_str().unwrap()).unwrap();
        assert!(result.is_empty(), "expected empty bytes for empty folder");
    }

    #[test]
    fn load_cover_returns_empty_for_missing_path() {
        let dir = tempdir();
        let missing = dir.join("does-not-exist");
        let result = load_cover_image_bytes(missing.to_str().unwrap()).unwrap();
        assert!(
            result.is_empty(),
            "expected empty bytes for missing source path"
        );
    }

    #[test]
    fn load_cover_returns_empty_for_folder_with_empty_chapter() {
        let dir = tempdir();
        std::fs::create_dir(dir.join("Chapter 1")).unwrap();
        let result = load_cover_image_bytes(dir.to_str().unwrap()).unwrap();
        assert!(
            result.is_empty(),
            "expected empty bytes when chapters have no images"
        );
    }

    #[test]
    fn generate_thumbnail_returns_empty_for_empty_folder() {
        let dir = tempdir();
        let result =
            generate_thumbnail_bytes(dir.to_str().unwrap(), 200, 300).unwrap();
        assert!(result.is_empty(), "expected empty thumbnail for empty folder");
    }

    #[test]
    fn purge_orphan_thumbnails_removes_only_stale_cover_files() {
        let dir = tempdir();
        let dir = Path::new(&dir);
        let keep_path = "/library/Comic Keep";
        let stale_path = "/library/Comic Deleted";
        let valid: HashSet<String> = [keep_path.to_string()].into();

        write_disk_thumbnail(dir, keep_path, 200, 300, b"keep-cover").unwrap();
        write_disk_thumbnail(dir, stale_path, 200, 300, b"stale-cover").unwrap();
        write_disk_thumbnail(dir, stale_path, 400, 600, b"stale-cover-2").unwrap();

        let (removed, freed) = purge_orphan_thumbnails(dir, &valid).unwrap();
        assert_eq!(removed, 2, "stale covers must be removed");
        assert!(
            freed > 0,
            "freed bytes must count removed cover files"
        );
        assert!(
            read_disk_thumbnail(dir, keep_path, 200, 300).is_some(),
            "valid cover must be kept"
        );
        assert!(
            read_disk_thumbnail(dir, stale_path, 200, 300).is_none(),
            "stale cover must be gone"
        );
        assert!(
            read_disk_thumbnail(dir, stale_path, 400, 600).is_none(),
            "second stale cover must be gone"
        );
    }

    #[test]
    fn purge_orphan_thumbnails_ignores_non_thumbnail_files() {
        let dir = tempdir();
        let dir = Path::new(&dir);
        let junk = dir.join("readme.txt");
        std::fs::write(&junk, b"junk").unwrap();
        let valid: HashSet<String> = HashSet::new();

        let (removed, _freed) = purge_orphan_thumbnails(dir, &valid).unwrap();
        assert_eq!(removed, 0);
        assert!(junk.exists(), "non-thumbnail files must be untouched");
    }

    fn tempdir() -> std::path::PathBuf {
        let base = std::env::temp_dir().join(format!(
            "comicrd_thumb_test_{}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&base).unwrap();
        base
    }
}
