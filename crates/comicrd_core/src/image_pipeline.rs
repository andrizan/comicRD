use std::fs;
use std::io::{Cursor, Read};
use std::path::Path;

use rusqlite::Connection;
use zip::ZipArchive;

use crate::chapter::{archive_image_entries, chapter_source, image_entries_in_dir};
use crate::{ImageVariantProfile, RenderPagePayload, RenderedPage};

const MAX_VARIANT_WIDTH: u32 = 4096;
const MIN_VARIANT_WIDTH: u32 = 320;

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

pub(crate) fn read_page_bytes(
    source_path: &str,
    source_type: &str,
    page_index: usize,
) -> Result<(Vec<u8>, &'static str), String> {
    match source_type {
        "folder" => {
            let pages = image_entries_in_dir(Path::new(source_path));
            let page_path = pages
                .get(page_index)
                .ok_or_else(|| "page index out of range".to_string())?;
            let bytes =
                fs::read(page_path).map_err(|e| format!("failed reading image file: {e}"))?;
            Ok((bytes, mime_for_path(page_path)))
        }
        "zip" | "cbz" => {
            let archive_path = Path::new(source_path);
            let names = archive_image_entries(archive_path)?;
            let name = names
                .get(page_index)
                .ok_or_else(|| "page index out of range".to_string())?;
            let mime = mime_for_path(Path::new(name));
            let file =
                fs::File::open(archive_path).map_err(|e| format!("failed opening archive: {e}"))?;
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
        other => Err(format!("unsupported source type: {other}")),
    }
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
    payload: RenderPagePayload,
) -> Result<RenderedPage, String> {
    let (source_path, source_type) = chapter_source(conn, payload.chapter_id)?;
    let (source_bytes, source_mime) =
        read_page_bytes(&source_path, &source_type, payload.page_index)?;
    let target_width = payload.target_width.and_then(normalize_variant_width);
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
}
