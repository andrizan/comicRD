use std::fs;
use std::io::{Cursor, Read};
use std::path::{Path, PathBuf};

use rusqlite::{params, Connection};
use unrar::Archive;
use walkdir::WalkDir;
use zip::ZipArchive;

use crate::database::{file_modified_ts, get_library_source_setting, now_ts};
use crate::{ChapterContext, OpenChapterPayload, PageInfo, RawChapter};
use crate::image_pipeline::tile_layout_for_dimensions;

pub(crate) fn ext_eq(path: &Path, target: &str) -> bool {
    path.extension()
        .and_then(|v| v.to_str())
        .map(|e| e.eq_ignore_ascii_case(target))
        .unwrap_or(false)
}

pub(crate) fn is_archive(path: &Path) -> bool {
    is_zip_archive(path) || is_rar_archive(path)
}

pub(crate) fn is_zip_archive(path: &Path) -> bool {
    ext_eq(path, "zip") || ext_eq(path, "cbz")
}

pub(crate) fn is_rar_archive(path: &Path) -> bool {
    ext_eq(path, "cbr") || ext_eq(path, "rar")
}

pub(crate) fn source_type_for_path(path: &Path) -> String {
    if path.is_dir() {
        return "folder".to_string();
    }
    path.extension()
        .and_then(|v| v.to_str())
        .map(|v| v.to_ascii_lowercase())
        .unwrap_or_else(|| "zip".to_string())
}

pub(crate) fn normalize_slashes(value: &str) -> String {
    value.replace('\\', "/")
}

pub(crate) fn upsert_comic(
    conn: &Connection,
    library_id: i64,
    title: &str,
    source_path: &str,
    source_type: &str,
    date_modified: i64,
) -> Result<i64, String> {
    if let Ok(id) = conn.query_row(
        "SELECT id FROM comics WHERE source_path = ?1 LIMIT 1",
        params![source_path],
        |row| row.get::<_, i64>(0),
    ) {
        conn.execute(
            r#"
        UPDATE comics
        SET library_id = ?1, title = ?2, source_type = ?3, date_modified = ?4
        WHERE id = ?5
        "#,
            params![library_id, title, source_type, date_modified, id],
        )
        .map_err(|e| format!("failed updating comic by source path: {e}"))?;
        return Ok(id);
    }

    conn.execute(
        r#"
      INSERT INTO comics (library_id, title, source_path, source_type, date_modified)
      VALUES (?1, ?2, ?3, ?4, ?5)
      "#,
        params![library_id, title, source_path, source_type, date_modified],
    )
    .map_err(|e| format!("failed inserting comic: {e}"))?;
    Ok(conn.last_insert_rowid())
}

pub(crate) struct ChapterUpsert<'a> {
    pub(crate) comic_id: i64,
    pub(crate) title: &'a str,
    pub(crate) chapter_index: i64,
    pub(crate) source_path: &'a str,
    pub(crate) source_type: &'a str,
    pub(crate) page_count: usize,
    pub(crate) date_modified: i64,
    pub(crate) size_bytes: i64,
}

pub(crate) fn upsert_chapter(conn: &Connection, params: ChapterUpsert<'_>) -> Result<i64, String> {
    if let Ok(id) = conn.query_row(
        "SELECT id FROM chapters WHERE source_path = ?1 LIMIT 1",
        params![params.source_path],
        |row| row.get::<_, i64>(0),
    ) {
        conn.execute(
            r#"
        UPDATE chapters
        SET comic_id = ?1, title = ?2, chapter_index = ?3, source_path = ?4, source_type = ?5, page_count = ?6, date_modified = ?7, size_bytes = ?8
        WHERE id = ?9
        "#,
            params![
                params.comic_id,
                params.title,
                params.chapter_index,
                params.source_path,
                params.source_type,
                params.page_count as i64,
                params.date_modified,
                params.size_bytes,
                id
            ],
        )
        .map_err(|e| format!("failed updating chapter by source path: {e}"))?;
        return Ok(id);
    }

    conn.execute(
        r#"
      INSERT INTO chapters (comic_id, title, chapter_index, source_path, source_type, page_count, date_modified, size_bytes)
      VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
      ON CONFLICT(source_path) DO UPDATE SET
        comic_id = excluded.comic_id,
        title = excluded.title,
        chapter_index = excluded.chapter_index,
        source_type = excluded.source_type,
        page_count = excluded.page_count,
        date_modified = excluded.date_modified,
        size_bytes = excluded.size_bytes
      "#,
        params![
            params.comic_id,
            params.title,
            params.chapter_index,
            params.source_path,
            params.source_type,
            params.page_count as i64,
            params.date_modified,
            params.size_bytes
        ],
    )
    .map_err(|e| format!("failed inserting chapter: {e}"))?;
    Ok(conn.last_insert_rowid())
}

pub(crate) fn chapter_snapshot_by_source_path(
    conn: &Connection,
    source_path: &str,
) -> Result<Option<(i64, i64, i64, i64)>, String> {
    conn.query_row(
        "SELECT page_count, date_modified, size_bytes, chapter_index FROM chapters WHERE source_path = ?1",
        params![source_path],
        |row| {
            Ok((
                row.get::<_, i64>(0)?,
                row.get::<_, i64>(1)?,
                row.get::<_, i64>(2)?,
                row.get::<_, i64>(3)?,
            ))
        },
    )
    .map(Some)
    .or_else(|e| {
        if matches!(e, rusqlite::Error::QueryReturnedNoRows) {
            Ok(None)
        } else {
            Err(format!("failed loading chapter snapshot: {e}"))
        }
    })
}

pub(crate) fn comic_title_for_path(path: &Path) -> String {
    if path.is_dir() {
        return path
            .file_name()
            .and_then(|v| v.to_str())
            .unwrap_or("Untitled")
            .to_string();
    }
    path.file_stem()
        .and_then(|v| v.to_str())
        .unwrap_or("Untitled")
        .to_string()
}

pub(crate) fn is_image(path: &Path) -> bool {
    ext_eq(path, "jpg")
        || ext_eq(path, "jpeg")
        || ext_eq(path, "png")
        || ext_eq(path, "webp")
        || ext_eq(path, "gif")
        || ext_eq(path, "bmp")
        || ext_eq(path, "avif")
}

pub(crate) fn chapter_size_bytes(path: &Path, source_type: &str) -> i64 {
    if source_type == "folder" {
        let entries = image_entries_in_dir(path);
        let mut total: i64 = 0;
        for entry in entries {
            if let Ok(meta) = fs::metadata(&entry) {
                total = total.saturating_add(meta.len() as i64);
            }
        }
        total
    } else {
        fs::metadata(path)
            .map(|m| m.len() as i64)
            .unwrap_or(0)
    }
}

pub(crate) fn archive_image_entries(path: &Path) -> Result<Vec<String>, String> {
    if is_rar_archive(path) {
        return rar_image_entries(path);
    }
    zip_image_entries(path)
}

pub(crate) fn archive_image_bytes(path: &Path, name: &str) -> Result<Vec<u8>, String> {
    if is_rar_archive(path) {
        return rar_image_bytes(path, name);
    }
    zip_image_bytes(path, name)
}

fn open_zip(path: &Path) -> Result<ZipArchive<fs::File>, String> {
    let file = fs::File::open(path).map_err(|e| format!("failed opening archive: {e}"))?;
    ZipArchive::new(file).map_err(|e| format!("invalid zip/cbz: {e}"))
}

fn zip_image_entries(path: &Path) -> Result<Vec<String>, String> {
    zip_image_entry_names(&mut open_zip(path)?)
}

/// Natural-sorted image entry names of an already opened archive.
fn zip_image_entry_names(archive: &mut ZipArchive<fs::File>) -> Result<Vec<String>, String> {
    let mut names = Vec::new();
    for idx in 0..archive.len() {
        let file = archive
            .by_index(idx)
            .map_err(|e| format!("failed reading archive entry: {e}"))?;
        let Ok(name) = file.name() else {
            continue;
        };
        if !name.ends_with('/') && is_image(Path::new(name.as_ref())) {
            names.push(name.into_owned());
        }
    }
    names.sort_by(|a, b| natural_compare(a, b));
    Ok(names)
}

/// Image entries with their dimensions through ONE archive open: the
/// central directory is parsed once per chapter instead of once per page
/// (3x faster page lists on a 200-page cbz).
fn zip_image_entries_with_dimensions(
    path: &Path,
) -> Result<Vec<(String, Option<(u32, u32)>)>, String> {
    let mut archive = open_zip(path)?;
    let names = zip_image_entry_names(&mut archive)?;
    Ok(names
        .into_iter()
        .map(|name| {
            let dims = zip_entry_dimensions(&mut archive, &name);
            (name, dims)
        })
        .collect())
}

fn zip_image_bytes(path: &Path, name: &str) -> Result<Vec<u8>, String> {
    let mut archive = open_zip(path)?;
    let mut entry = archive
        .by_name(name)
        .map_err(|e| format!("failed reading archive entry: {e}"))?;
    let mut bytes = Vec::new();
    entry
        .read_to_end(&mut bytes)
        .map_err(|e| format!("failed extracting image: {e}"))?;
    Ok(bytes)
}

fn rar_image_entries(path: &Path) -> Result<Vec<String>, String> {
    let archive = Archive::new(path)
        .open_for_listing()
        .map_err(|e| format!("invalid rar/cbr: {e}"))?;
    let mut names = Vec::new();

    for entry in archive {
        let entry = entry.map_err(|e| format!("failed reading rar/cbr entry: {e}"))?;
        if entry.is_file() && is_image(&entry.filename) {
            names.push(normalize_slashes(entry.filename.to_string_lossy().as_ref()));
        }
    }

    names.sort_by(|a, b| natural_compare(a, b));
    Ok(names)
}

fn rar_image_bytes(path: &Path, name: &str) -> Result<Vec<u8>, String> {
    let mut archive = Archive::new(path)
        .open_for_processing()
        .map_err(|e| format!("invalid rar/cbr: {e}"))?;
    loop {
        let Some(entry_archive) = archive
            .read_header()
            .map_err(|e| format!("failed reading rar/cbr entry: {e}"))?
        else {
            return Err(format!("rar/cbr image entry not found: {name}"));
        };
        let entry_name =
            normalize_slashes(entry_archive.entry().filename.to_string_lossy().as_ref());
        if entry_archive.entry().is_file() && entry_name == name {
            let (bytes, _rest) = entry_archive
                .read()
                .map_err(|e| format!("failed extracting rar/cbr image: {e}"))?;
            return Ok(bytes);
        }
        archive = entry_archive
            .skip()
            .map_err(|e| format!("failed skipping rar/cbr entry: {e}"))?;
    }
}

/// Leading bytes read from a zip entry when probing dimensions.
/// Covers JPEG/PNG/GIF/BMP/WebP headers; falls back to a full read below.
const DIM_PROBE_BYTES: u64 = 64 * 1024;

/// Dimensions of one entry of an already opened archive: only the leading
/// bytes are decompressed for the header probe; a full read is the fallback
/// for headers beyond the probe window (e.g. giant metadata).
fn zip_entry_dimensions(archive: &mut ZipArchive<fs::File>, name: &str) -> Option<(u32, u32)> {
    let head = {
        let entry = archive.by_name(name).ok()?;
        let mut head = Vec::new();
        entry.take(DIM_PROBE_BYTES).read_to_end(&mut head).ok()?;
        head
    };
    if let Some(dims) = image_dimensions_from_bytes(&head) {
        return Some(dims);
    }
    let mut entry = archive.by_name(name).ok()?;
    let mut bytes = Vec::new();
    entry.read_to_end(&mut bytes).ok()?;
    image_dimensions_from_bytes(&bytes)
}

fn zip_image_dimensions(path: &Path, name: &str) -> Option<(u32, u32)> {
    zip_entry_dimensions(&mut open_zip(path).ok()?, name)
}

/// Dimensions of an archive entry without fully extracting it when possible.
///
/// Zip/cbz probe headers (see `zip_entry_dimensions`). unrar only extracts
/// whole entries, so cbr/rar keeps the full read.
pub(crate) fn archive_image_dimensions(path: &Path, name: &str) -> Option<(u32, u32)> {
    if !is_rar_archive(path) {
        return zip_image_dimensions(path, name);
    }
    rar_image_bytes(path, name)
        .ok()
        .and_then(|bytes| image_dimensions_from_bytes(&bytes))
}

fn ignored_fs_entry(path: &Path) -> bool {
    path.components().any(|component| {
        let Some(name) = component.as_os_str().to_str() else {
            return false;
        };
        name.starts_with('.')
            || name.eq_ignore_ascii_case("__MACOSX")
            || name.eq_ignore_ascii_case("thumbs.db")
            || name.eq_ignore_ascii_case("desktop.ini")
    })
}

fn image_entries_in_dir_with_depth(path: &Path, max_depth: usize) -> Vec<PathBuf> {
    let mut entries = WalkDir::new(path)
        .min_depth(1)
        .max_depth(max_depth)
        .into_iter()
        .filter_map(|e| e.ok())
        .map(|e| e.into_path())
        .filter(|p| {
            let relative = p.strip_prefix(path).unwrap_or(p);
            p.is_file() && !ignored_fs_entry(relative) && is_image(p)
        })
        .collect::<Vec<_>>();
    entries.sort_by(|a, b| {
        let a_name = a.to_string_lossy();
        let b_name = b.to_string_lossy();
        natural_compare(&a_name, &b_name)
    });
    entries
}

pub(crate) fn image_entries_in_dir(path: &Path) -> Vec<PathBuf> {
    image_entries_in_dir_with_depth(path, 3)
}

pub(crate) fn image_entries_in_dir_shallow(path: &Path) -> Vec<PathBuf> {
    image_entries_in_dir_with_depth(path, 1)
}

fn image_dimensions_from_path(path: &Path) -> Option<(u32, u32)> {
    image::ImageReader::open(path)
        .ok()?
        .with_guessed_format()
        .ok()?
        .into_dimensions()
        .ok()
}

fn image_dimensions_from_bytes(bytes: &[u8]) -> Option<(u32, u32)> {
    image::ImageReader::new(Cursor::new(bytes))
        .with_guessed_format()
        .ok()?
        .into_dimensions()
        .ok()
}

/// Name used for natural sorting of chapter entries. Archives sort by their
/// file stem so the `.cbz`/`.cbr` extension does not influence ordering
/// (e.g. "Chapter 06.5.cbz" must come after "Chapter 06.cbz").
fn sort_name(path: &Path) -> String {
    if path.is_dir() {
        return path
            .file_name()
            .and_then(|v| v.to_str())
            .unwrap_or("")
            .to_string();
    }
    path.file_stem()
        .and_then(|v| v.to_str())
        .unwrap_or("")
        .to_string()
}

/// Natural ("Chapter 2" < "Chapter 10"), case-insensitive ordering.
///
/// Allocation-free: digit runs are accumulated into a `u64` as they are
/// walked and other characters are compared through their lowercase
/// iterators, so sorting a large library no longer allocates two strings
/// per compared character.
pub(crate) fn natural_compare(a: &str, b: &str) -> std::cmp::Ordering {
    let mut a_chars = a.chars().peekable();
    let mut b_chars = b.chars().peekable();
    loop {
        match (a_chars.peek().copied(), b_chars.peek().copied()) {
            (None, None) => return std::cmp::Ordering::Equal,
            (None, Some(_)) => return std::cmp::Ordering::Less,
            (Some(_), None) => return std::cmp::Ordering::Greater,
            (Some(ac), Some(bc)) => {
                if ac.is_ascii_digit() && bc.is_ascii_digit() {
                    match take_digit_run(&mut a_chars).cmp(&take_digit_run(&mut b_chars)) {
                        std::cmp::Ordering::Equal => continue,
                        other => return other,
                    }
                } else {
                    // Lowercase expansions compared code point by code point:
                    // the same order as comparing the collected strings,
                    // without building them.
                    match ac.to_lowercase().cmp(bc.to_lowercase()) {
                        std::cmp::Ordering::Equal => {
                            a_chars.next();
                            b_chars.next();
                            continue;
                        }
                        other => return other,
                    }
                }
            }
        }
    }
}

/// Consume a run of ASCII digits as a number. A run that overflows `u64`
/// yields 0, matching the old `parse().unwrap_or(0)`.
fn take_digit_run(chars: &mut std::iter::Peekable<std::str::Chars<'_>>) -> u64 {
    let mut value = Some(0u64);
    while let Some(c) = chars.next_if(|c| c.is_ascii_digit()) {
        value = value
            .and_then(|v| v.checked_mul(10))
            .and_then(|v| v.checked_add(u64::from(c as u8 - b'0')));
    }
    value.unwrap_or(0)
}

/// Natural sort of paths by `sort_name`, computing each key once. The key
/// allocates and stats its path, so per-comparison keys would cost
/// O(n log n) syscalls.
fn sort_paths_naturally(paths: Vec<PathBuf>) -> Vec<PathBuf> {
    let mut keyed: Vec<(String, PathBuf)> = paths
        .into_iter()
        .map(|path| (sort_name(&path), path))
        .collect();
    keyed.sort_by(|a, b| natural_compare(&a.0, &b.0));
    keyed.into_iter().map(|(_, path)| path).collect()
}

pub(crate) fn discover_chapter_entries_from_comic_dir(
    comic_dir: &Path,
) -> Vec<(String, String, String, i64)> {
    let source_path = comic_dir.to_string_lossy().to_string();
    let mut chapter_entries = Vec::new();
    let mut chapter_index = 1i64;

    let root_images = image_entries_in_dir_shallow(comic_dir);
    if !root_images.is_empty() {
        chapter_entries.push((
            "Chapter 1".to_string(),
            source_path.clone(),
            "folder".to_string(),
            chapter_index,
        ));
        chapter_index += 1;
    }

    let children = sort_paths_naturally(
        WalkDir::new(comic_dir)
            .min_depth(1)
            .max_depth(1)
            .into_iter()
            .filter_map(|e| e.ok())
            .map(|e| e.into_path())
            .collect(),
    );

    for child in children {
        if child.is_dir() {
            let has_images = !image_entries_in_dir(&child).is_empty();
            let mut nested_archives = Vec::new();

            let child_entries = sort_paths_naturally(
                WalkDir::new(&child)
                    .min_depth(1)
                    .max_depth(1)
                    .into_iter()
                    .filter_map(|e| e.ok())
                    .map(|e| e.into_path())
                    .collect(),
            );

            for entry in child_entries {
                if entry.is_file() && is_archive(&entry) {
                    nested_archives.push(entry);
                }
            }

            if has_images {
                chapter_entries.push((
                    child
                        .file_name()
                        .and_then(|v| v.to_str())
                        .unwrap_or("Chapter")
                        .to_string(),
                    child.to_string_lossy().to_string(),
                    "folder".to_string(),
                    chapter_index,
                ));
                chapter_index += 1;
            }

            for archive in nested_archives {
                chapter_entries.push((
                    archive
                        .file_stem()
                        .and_then(|v| v.to_str())
                        .unwrap_or("Chapter")
                        .to_string(),
                    archive.to_string_lossy().to_string(),
                    source_type_for_path(&archive),
                    chapter_index,
                ));
                chapter_index += 1;
            }
        }

        if child.is_file() && is_archive(&child) {
            chapter_entries.push((
                child
                    .file_stem()
                    .and_then(|v| v.to_str())
                    .unwrap_or("Chapter")
                    .to_string(),
                child.to_string_lossy().to_string(),
                source_type_for_path(&child),
                chapter_index,
            ));
            chapter_index += 1;
        }
    }

    chapter_entries
}

pub(crate) fn discover_chapter_entries_for_comic(
    comic_source_path: &str,
) -> Result<Vec<(String, String, String, i64)>, String> {
    let comic_path = Path::new(comic_source_path);
    if comic_path.is_dir() {
        return Ok(discover_chapter_entries_from_comic_dir(comic_path));
    }
    if comic_path.is_file() && is_archive(comic_path) {
        return Ok(vec![(
            "Chapter 1".to_string(),
            comic_source_path.to_string(),
            source_type_for_path(comic_path),
            1,
        )]);
    }
    Err("invalid comic source".to_string())
}

pub(crate) fn list_comic_chapters_raw_conn_with_discovered(
    conn: &Connection,
    _comic_source_path: &str,
    discovered: &[(String, String, String, i64)],
) -> Result<Vec<RawChapter>, String> {
    let chapter_paths: Vec<String> = discovered
        .iter()
        .map(|(_, chapter_path, _, _)| chapter_path.clone())
        .collect();

    let mut progress_map = std::collections::HashMap::new();
    if !chapter_paths.is_empty() {
        let placeholders: String = chapter_paths
            .iter()
            .enumerate()
            .map(|(i, _)| format!("?{}", i + 1))
            .collect::<Vec<_>>()
            .join(", ");
        let query = format!(
            r#"
            SELECT c.source_path,
                   c.page_count,
                   COALESCE(r.is_read, 0),
                   COALESCE(r.last_page, 0),
                   COALESCE(r.total_pages, c.page_count),
                   c.date_modified,
                   c.size_bytes,
                   r.updated_at
            FROM chapters c
            LEFT JOIN reading_progress r ON r.chapter_id = c.id
            WHERE c.source_path IN ({placeholders})
            "#
        );
        let mut stmt = conn
            .prepare(&query)
            .map_err(|e| format!("failed preparing batch progress query: {e}"))?;
        let params: Vec<&dyn rusqlite::types::ToSql> = chapter_paths
            .iter()
            .map(|k| k as &dyn rusqlite::types::ToSql)
            .collect();
        let rows = stmt
            .query_map(params.as_slice(), |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, i64>(1)?,
                    row.get::<_, i64>(2)? == 1,
                    row.get::<_, i64>(3)?,
                    row.get::<_, i64>(4)?,
                    row.get::<_, i64>(5)?,
                    row.get::<_, i64>(6)?,
                    row.get::<_, Option<i64>>(7)?,
                ))
            })
            .map_err(|e| format!("failed querying batch progress: {e}"))?;
        for row in rows {
            let (path, page_count, is_read, last_page, total_pages, date_modified, size_bytes, progress_updated_at) =
                row.map_err(|e| format!("failed reading progress row: {e}"))?;
            progress_map.insert(
                path,
                (page_count, is_read, last_page, total_pages, date_modified, size_bytes, progress_updated_at),
            );
        }
    }

    let mut out = Vec::with_capacity(discovered.len());
    for (chapter_title, chapter_path, _chapter_type, chapter_index) in discovered.iter() {
        let modified_at = file_modified_ts(Path::new(chapter_path));
        let (page_count, is_read, last_page, total_pages, date_modified, size_bytes, progress_updated_at) = progress_map
            .get(chapter_path.as_str())
            .copied()
            .unwrap_or((0, false, 0, 0, modified_at, 0, None));
        out.push(RawChapter {
            title: chapter_title.clone(),
            chapter_index: *chapter_index,
            source_path: chapter_path.clone(),
            source_type: source_type_for_path(Path::new(chapter_path)),
            date_modified,
            page_count,
            is_read,
            last_page,
            total_pages,
            size_bytes,
            progress_updated_at: progress_updated_at.unwrap_or(0),
        });
    }
    Ok(out)
}

pub(crate) fn find_library_for_comic(
    conn: &Connection,
    comic_source_path: &str,
) -> Result<(i64, String), String> {
    let library_path = get_library_source_setting(conn)?;
    if !comic_source_path.starts_with(library_path.as_str()) {
        return Err("comic is not under the current library source".to_string());
    }
    let ts = now_ts();
    conn.execute(
        r#"
      INSERT INTO libraries (path, created_at, updated_at)
      VALUES (?1, ?2, ?3)
      ON CONFLICT(path) DO UPDATE SET updated_at=excluded.updated_at
      "#,
        params![library_path, ts, ts],
    )
    .map_err(|e| format!("failed upserting library from settings: {e}"))?;
    let library_id = conn
        .query_row(
            "SELECT id FROM libraries WHERE path = ?1",
            params![library_path],
            |row| row.get::<_, i64>(0),
        )
        .map_err(|e| format!("failed selecting library id from settings: {e}"))?;
    Ok((library_id, library_path))
}

pub(crate) fn open_chapter_for_reading_conn(
    conn: &mut Connection,
    payload: OpenChapterPayload,
) -> Result<i64, String> {
    let tx = conn
        .transaction()
        .map_err(|e| format!("failed opening chapter transaction: {e}"))?;
    let (library_id, _library_path) = find_library_for_comic(&tx, &payload.comic_source_path)?;
    let comic_source = Path::new(&payload.comic_source_path);
    let comic_source_type = source_type_for_path(comic_source);
    let comic_title = comic_title_for_path(comic_source);
    let comic_id = upsert_comic(
        &tx,
        library_id,
        &comic_title,
        &payload.comic_source_path,
        &comic_source_type,
        file_modified_ts(comic_source),
    )?;

    let chapter_entries = discover_chapter_entries_for_comic(&payload.comic_source_path)?;
    let mut selected_chapter_id = None;
    let mut total_size_bytes: i64 = 0;
    for (chapter_title, chapter_path, chapter_type, chapter_index) in chapter_entries {
        let modified_at = file_modified_ts(Path::new(&chapter_path));
        let cached_page_count = chapter_snapshot_by_source_path(&tx, &chapter_path)?
            .map(|(page_count, _, _, _)| page_count.max(0) as usize)
            .unwrap_or(0);
        let chapter_size = chapter_size_bytes(Path::new(&chapter_path), &chapter_type);
        total_size_bytes = total_size_bytes.saturating_add(chapter_size);
        let chapter_id = upsert_chapter(
            &tx,
            ChapterUpsert {
                comic_id,
                title: &chapter_title,
                chapter_index,
                source_path: &chapter_path,
                source_type: &chapter_type,
                page_count: cached_page_count,
                date_modified: modified_at,
                size_bytes: chapter_size,
            },
        )?;
        if chapter_path == payload.chapter_source_path {
            selected_chapter_id = Some(chapter_id);
        }
    }
    tx.execute(
        "UPDATE comics SET size_bytes = ?1 WHERE id = ?2",
        params![total_size_bytes, comic_id],
    )
    .map_err(|e| format!("failed updating comic size_bytes: {e}"))?;
    tx.commit()
        .map_err(|e| format!("failed committing chapter transaction: {e}"))?;
    selected_chapter_id.ok_or_else(|| "chapter not found".to_string())
}

pub(crate) fn chapter_source(
    conn: &Connection,
    chapter_id: i64,
) -> Result<(String, String), String> {
    conn.query_row(
        "SELECT source_path, source_type FROM chapters WHERE id = ?1",
        params![chapter_id],
        |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)),
    )
    .map_err(|e| format!("failed loading chapter source: {e}"))
}

/// Page list for a rar/cbr chapter from its extracted session: fast header
/// probes from disk instead of per-entry decompression. `entries`
/// (archive names, list order) and `files` (extracted paths) are parallel,
/// both coming from one `ensure_rar_session` call.
pub(crate) fn build_rar_session_page_list(
    entries: &[String],
    files: &[PathBuf],
) -> Vec<PageInfo> {
    entries
        .iter()
        .zip(files.iter())
        .enumerate()
        .map(|(index, (name, path))| {
            let dims = image_dimensions_from_path(path);
            let (width, height) = dims
                .map(|(width, height)| (Some(width), Some(height)))
                .unwrap_or((None, None));
            let tile_heights = match dims {
                Some((w, h)) => {
                    tile_layout_for_dimensions(w, h, ext_eq(Path::new(name), "gif")).1
                }
                None => vec![0],
            };
            PageInfo {
                index,
                name: name.clone(),
                width,
                height,
                tile_heights,
            }
        })
        .collect()
}

/// Page list without touching the DB: archive listing, dimension probing,
/// and tile layout. Must run WITHOUT holding the DB mutex (slow IO).
pub(crate) fn build_page_list(
    source_path: &str,
    source_type: &str,
) -> Result<Vec<PageInfo>, String> {
    let pages = match source_type {
        "folder" => image_entries_in_dir(Path::new(&source_path))
            .into_iter()
            .enumerate()
            .map(|(index, path)| {
                let dims = image_dimensions_from_path(&path);
                let (width, height) = dims
                    .map(|(width, height)| (Some(width), Some(height)))
                    .unwrap_or((None, None));
                let tile_heights = match dims {
                    Some((w, h)) => {
                        tile_layout_for_dimensions(w, h, ext_eq(&path, "gif")).1
                    }
                    None => vec![0],
                };
                PageInfo {
                    index,
                    name: path
                        .file_name()
                        .and_then(|v| v.to_str())
                        .unwrap_or_default()
                        .to_string(),
                    width,
                    height,
                    tile_heights,
                }
            })
            .collect::<Vec<_>>(),
        "zip" | "cbz" | "cbr" | "rar" => {
            let archive = Path::new(&source_path);
            // Zip probes every entry through one open. Rar keeps per-entry
            // extraction; its fast route is the session path in
            // `get_chapter_pages`, this arm is the fallback.
            let entries = if is_rar_archive(archive) {
                archive_image_entries(archive)?
                    .into_iter()
                    .map(|name| {
                        let dims = archive_image_dimensions(archive, &name);
                        (name, dims)
                    })
                    .collect::<Vec<_>>()
            } else {
                zip_image_entries_with_dimensions(archive)?
            };
            entries
                .into_iter()
                .enumerate()
                .map(|(index, (name, dims))| {
                    let (width, height) = dims
                        .map(|(width, height)| (Some(width), Some(height)))
                        .unwrap_or((None, None));
                    let tile_heights = match dims {
                        Some((w, h)) => {
                            tile_layout_for_dimensions(w, h, ext_eq(Path::new(&name), "gif")).1
                        }
                        None => vec![0],
                    };
                    PageInfo {
                        index,
                        name,
                        width,
                        height,
                        tile_heights,
                    }
                })
                .collect::<Vec<_>>()
        }
        other => return Err(format!("unsupported source type: {other}")),
    };
    Ok(pages)
}

/// Stats write after listing. Lenient by design: a failed stats write must
/// never fail the listing itself (mirrors the old inline `let _ =`).
pub(crate) fn update_chapter_page_count(
    conn: &Connection,
    chapter_id: i64,
    source_path: &str,
    page_count: i64,
) {
    let modified_at = file_modified_ts(Path::new(source_path));
    let _ = conn.execute(
        "UPDATE chapters SET page_count = ?1, date_modified = ?2 WHERE id = ?3",
        params![page_count, modified_at, chapter_id],
    );
}

pub(crate) fn get_chapter_context_conn(
    conn: &Connection,
    chapter_id: i64,
) -> Result<Option<ChapterContext>, String> {
    let mut stmt = conn
        .prepare(
            r#"
      SELECT ch.id, ch.comic_id, ch.title, ch.chapter_index, ch.source_path,
             c.title, c.source_path
      FROM chapters ch
      INNER JOIN comics c ON c.id = ch.comic_id
      WHERE ch.id = ?1
      "#,
        )
        .map_err(|e| format!("failed preparing chapter context query: {e}"))?;
    let mut rows = stmt
        .query(params![chapter_id])
        .map_err(|e| format!("failed querying chapter context: {e}"))?;
    let Some(row) = rows
        .next()
        .map_err(|e| format!("failed loading chapter row: {e}"))?
    else {
        return Ok(None);
    };

    let chapter_id = row
        .get::<_, i64>(0)
        .map_err(|e| format!("invalid chapter row: {e}"))?;
    let comic_id = row
        .get::<_, i64>(1)
        .map_err(|e| format!("invalid chapter row: {e}"))?;
    let title = row
        .get::<_, String>(2)
        .map_err(|e| format!("invalid chapter row: {e}"))?;
    let chapter_index = row
        .get::<_, i64>(3)
        .map_err(|e| format!("invalid chapter row: {e}"))?;
    let chapter_source_path = row
        .get::<_, String>(4)
        .map_err(|e| format!("invalid chapter row: {e}"))?;
    let comic_title = row
        .get::<_, String>(5)
        .map_err(|e| format!("invalid chapter row: {e}"))?;
    let comic_source_path = row
        .get::<_, String>(6)
        .map_err(|e| format!("invalid chapter row: {e}"))?;
    drop(rows);
    drop(stmt);

    let mut stmt = conn
        .prepare(
            r#"
      WITH ranked AS (
        SELECT id, title, chapter_index,
               COUNT(*) OVER () AS total,
               ROW_NUMBER() OVER (ORDER BY chapter_index ASC, id ASC) AS pos,
               LAG(id) OVER (ORDER BY chapter_index ASC, id ASC) AS prev_id,
               LAG(title) OVER (ORDER BY chapter_index ASC, id ASC) AS prev_title,
               LEAD(id) OVER (ORDER BY chapter_index ASC, id ASC) AS next_id,
               LEAD(title) OVER (ORDER BY chapter_index ASC, id ASC) AS next_title
        FROM chapters
        WHERE comic_id = ?1
      )
      SELECT pos, total, prev_id, prev_title, next_id, next_title
      FROM ranked
      WHERE id = ?2
      "#,
        )
        .map_err(|e| format!("failed preparing chapter neighbors query: {e}"))?;
    let row = stmt
        .query_row(params![comic_id, chapter_id], |row| {
            Ok((
                row.get::<_, i64>(0)?,
                row.get::<_, i64>(1)?,
                row.get::<_, Option<i64>>(2)?,
                row.get::<_, Option<String>>(3)?,
                row.get::<_, Option<i64>>(4)?,
                row.get::<_, Option<String>>(5)?,
            ))
        })
        .map_err(|e| format!("failed loading chapter neighbors: {e}"))?;
    let (
        chapter_position,
        chapter_total,
        prev_chapter_id,
        prev_chapter_title,
        next_chapter_id,
        next_chapter_title,
    ) = row;

    Ok(Some(ChapterContext {
        chapter_id,
        comic_id,
        comic_source_path,
        chapter_source_path,
        comic_title,
        title,
        chapter_index,
        chapter_position,
        chapter_total,
        prev_chapter_id,
        prev_chapter_title,
        next_chapter_id,
        next_chapter_title,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    const VERSION_RAR: &[u8] = &[
        0x52, 0x61, 0x72, 0x21, 0x1a, 0x07, 0x00, 0xcf, 0x90, 0x73, 0x00, 0x00, 0x0d, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x0f, 0x0c, 0x74, 0x20, 0x80, 0x27, 0x00, 0x15, 0x00, 0x00,
        0x00, 0x0b, 0x00, 0x00, 0x00, 0x03, 0x45, 0xf3, 0x7d, 0xc6, 0xa4, 0x8a, 0x07, 0x47, 0x1d,
        0x33, 0x07, 0x00, 0xa4, 0x81, 0x00, 0x00, 0x56, 0x45, 0x52, 0x53, 0x49, 0x4f, 0x4e, 0x0c,
        0x00, 0x8f, 0xec, 0x8a, 0x45, 0xcc, 0x23, 0xc8, 0x48, 0x08, 0x83, 0x62, 0xfe, 0x5f, 0xdd,
        0x5c, 0x53, 0x88, 0xf0, 0x72, 0xc4, 0x3d, 0x7b, 0x00, 0x40, 0x07, 0x00,
    ];

    #[test]
    fn rar_image_bytes_reads_named_entry_from_cbr_file() {
        let temp = tempfile::tempdir().expect("tempdir");
        let archive = temp.path().join("fixture.cbr");
        std::fs::write(&archive, VERSION_RAR).expect("write fixture");

        let bytes = rar_image_bytes(&archive, "VERSION").expect("read cbr entry");

        assert_eq!(bytes, b"unrar-0.4.0");
    }

    #[test]
    fn ext_eq_matches_case_insensitive() {
        assert!(ext_eq(Path::new("image.JPG"), "jpg"));
        assert!(ext_eq(Path::new("image.Jpeg"), "jpeg"));
        assert!(ext_eq(Path::new("image.png"), "png"));
        assert!(!ext_eq(Path::new("image.png"), "jpg"));
        assert!(!ext_eq(Path::new("noext"), "jpg"));
    }

    #[test]
    fn tile_layout_matches_branch_rules_for_gif_and_unknown_dims() {
        // Mirrors get_chapter_pages_conn: a gif extension forces a single
        // tile (animation), unknown dimensions yield a single empty tile.
        let (_, gif_tiles) =
            tile_layout_for_dimensions(1600, 20000, ext_eq(Path::new("p.GIF"), "gif"));
        assert_eq!(gif_tiles, vec![20000]);
        let (_, unknown) = tile_layout_for_dimensions(0, 0, false);
        assert_eq!(unknown, vec![0]);
    }

    #[test]
    fn is_archive_recognizes_extensions() {
        assert!(is_archive(Path::new("comic.cbz")));
        assert!(is_archive(Path::new("comic.cbr")));
        assert!(is_archive(Path::new("comic.zip")));
        assert!(is_archive(Path::new("comic.rar")));
        assert!(!is_archive(Path::new("comic.cb")));
        assert!(!is_archive(Path::new("image.png")));
        assert!(!is_archive(Path::new("folder")));
    }

    #[test]
    fn source_type_for_path_returns_extension() {
        assert_eq!(source_type_for_path(Path::new("comic.cbz")), "cbz");
        assert_eq!(source_type_for_path(Path::new("comic.cbr")), "cbr");
        assert_eq!(source_type_for_path(Path::new("comic.zip")), "zip");
        assert_eq!(source_type_for_path(Path::new("comic.rar")), "rar");
        assert_eq!(source_type_for_path(Path::new("noext")), "zip");
        assert_eq!(source_type_for_path(Path::new("noext")), "zip");
    }

    #[test]
    fn is_image_recognizes_extensions() {
        assert!(is_image(Path::new("page.jpg")));
        assert!(is_image(Path::new("page.jpeg")));
        assert!(is_image(Path::new("page.png")));
        assert!(is_image(Path::new("page.webp")));
        assert!(is_image(Path::new("page.gif")));
        assert!(is_image(Path::new("page.bmp")));
        assert!(is_image(Path::new("page.avif")));
        assert!(!is_image(Path::new("page.txt")));
        assert!(!is_image(Path::new("page.cbz")));
    }

    #[test]
    fn chapter_size_bytes_sums_image_files_in_folder() {
        let temp = tempfile::tempdir().expect("tempdir");
        let chapter_dir = temp.path().join("Chapter 1");
        fs::create_dir_all(&chapter_dir).expect("chapter");
        fs::write(chapter_dir.join("001.png"), vec![0u8; 1024]).expect("p1");
        fs::write(chapter_dir.join("002.png"), vec![0u8; 2048]).expect("p2");
        fs::write(chapter_dir.join("Thumbs.db"), b"junk").expect("thumbs");
        fs::write(chapter_dir.join("notes.txt"), b"junk").expect("notes");
        fs::create_dir_all(chapter_dir.join("__MACOSX")).expect("macosx");
        fs::write(chapter_dir.join("__MACOSX").join("._001.png"), b"junk")
            .expect("macosx file");

        let total = chapter_size_bytes(&chapter_dir, "folder");
        assert_eq!(total, 1024 + 2048);
    }

    #[test]
    fn chapter_size_bytes_uses_archive_file_size() {
        let temp = tempfile::tempdir().expect("tempdir");
        let archive = temp.path().join("comic.cbz");
        fs::write(&archive, vec![0u8; 4096]).expect("cbz");
        let total = chapter_size_bytes(&archive, "cbz");
        assert_eq!(total, 4096);
    }

    #[test]
    fn comic_title_for_path_uses_filename() {
        assert_eq!(
            comic_title_for_path(Path::new("/library/My Comic")),
            "My Comic"
        );
        assert_eq!(
            comic_title_for_path(Path::new("/library/Cool Manga.cbz")),
            "Cool Manga"
        );
        assert_eq!(
            comic_title_for_path(Path::new("/library/sub/folder")),
            "folder"
        );
    }

    #[test]
    fn natural_compare_orders_numbers_correctly() {
        assert_eq!(
            natural_compare("Chapter 2", "Chapter 10"),
            std::cmp::Ordering::Less
        );
        assert_eq!(
            natural_compare("Chapter 10", "Chapter 2"),
            std::cmp::Ordering::Greater
        );
        assert_eq!(
            natural_compare("Chapter 5", "Chapter 5"),
            std::cmp::Ordering::Equal
        );
        assert_eq!(
            natural_compare("Chapter 1a", "Chapter 1b"),
            std::cmp::Ordering::Less
        );
    }

    #[test]
    fn natural_compare_orders_decimal_chapters_after_whole_chapters() {
        assert_eq!(
            natural_compare("Chapter 06", "Chapter 06.5"),
            std::cmp::Ordering::Less
        );
        assert_eq!(
            natural_compare("Chapter 06.5", "Chapter 06"),
            std::cmp::Ordering::Greater
        );
        assert_eq!(
            natural_compare("Chapter 46", "Chapter 46.1"),
            std::cmp::Ordering::Less
        );
        assert_eq!(
            natural_compare("Chapter 46.1", "Chapter 46.2"),
            std::cmp::Ordering::Less
        );
        assert_eq!(
            natural_compare("Chapter 46.2", "Chapter 46.10"),
            std::cmp::Ordering::Less
        );
        assert_eq!(
            natural_compare("Chapter 06.5", "Chapter 07"),
            std::cmp::Ordering::Less
        );
    }

    #[test]
    fn natural_compare_is_case_insensitive_and_treats_overflowing_numbers_as_zero() {
        assert_eq!(natural_compare("Ä", "ä"), std::cmp::Ordering::Equal);
        assert_eq!(natural_compare("CHAPTER 2", "chapter 10"), std::cmp::Ordering::Less);
        assert_eq!(natural_compare("Chapter 010", "Chapter 10"), std::cmp::Ordering::Equal);
        // Runs past u64 parse as 0 (the old `parse().unwrap_or(0)`).
        assert_eq!(
            natural_compare("99999999999999999999999", "1"),
            std::cmp::Ordering::Less
        );
        assert_eq!(natural_compare("abc", "abcd"), std::cmp::Ordering::Less);
        assert_eq!(natural_compare("", ""), std::cmp::Ordering::Equal);
    }

    #[test]
    fn sort_paths_naturally_orders_dirs_and_archives_by_stem() {
        let temp = tempfile::tempdir().expect("tempdir");
        let names = ["Chapter 10", "Chapter 2", "Chapter 06.5.cbz", "Chapter 06"];
        let mut paths = Vec::new();
        for name in names {
            let path = temp.path().join(name);
            if name.ends_with(".cbz") {
                std::fs::write(&path, b"").expect("archive");
            } else {
                std::fs::create_dir_all(&path).expect("dir");
            }
            paths.push(path);
        }

        let sorted: Vec<String> = sort_paths_naturally(paths)
            .into_iter()
            .map(|p| p.file_name().unwrap().to_string_lossy().to_string())
            .collect();
        assert_eq!(
            sorted,
            ["Chapter 2", "Chapter 06", "Chapter 06.5.cbz", "Chapter 10"]
        );
    }

    #[test]
    fn sort_name_uses_stem_for_archives_and_name_for_dirs() {
        let temp = tempfile::tempdir().expect("tempdir");
        let archive = temp.path().join("Chapter 06.5.cbz");
        std::fs::write(&archive, b"").expect("archive");
        let dir = temp.path().join("Chapter 07");
        std::fs::create_dir_all(&dir).expect("dir");
        assert_eq!(sort_name(&archive), "Chapter 06.5");
        assert_eq!(sort_name(&dir), "Chapter 07");
    }

    #[test]
    fn archive_image_dimensions_probes_zip_entry_headers() {
        use std::io::Write;

        let temp = tempfile::tempdir().expect("tempdir");
        let archive = temp.path().join("pages.cbz");
        {
            let file = fs::File::create(&archive).expect("create zip");
            let mut zip = zip::ZipWriter::new(file);
            let options = zip::write::SimpleFileOptions::default();
            zip.start_file("001.png", options).expect("start png");
            zip.write_all(&test_png_bytes(200, 80)).expect("write png");
            zip.start_file("junk.png", options).expect("start junk");
            zip.write_all(b"not an image").expect("write junk");
            zip.finish().expect("finish zip");
        }

        assert_eq!(
            archive_image_dimensions(&archive, "001.png"),
            Some((200, 80))
        );
        assert_eq!(archive_image_dimensions(&archive, "junk.png"), None);
        assert_eq!(archive_image_dimensions(&archive, "missing.png"), None);
    }

    #[test]
    fn zip_image_entries_with_dimensions_probes_every_entry_through_one_open() {
        use std::io::Write;

        let temp = tempfile::tempdir().expect("tempdir");
        let archive = temp.path().join("pages.cbz");
        {
            let file = fs::File::create(&archive).expect("create zip");
            let mut zip = zip::ZipWriter::new(file);
            let options = zip::write::SimpleFileOptions::default();
            zip.add_directory("extras/", options).expect("dir entry");
            zip.start_file("notes.txt", options).expect("start txt");
            zip.write_all(b"not a page").expect("write txt");
            zip.start_file("10.png", options).expect("start 10");
            zip.write_all(&test_png_bytes(200, 80)).expect("write 10");
            zip.start_file("2.png", options).expect("start 2");
            zip.write_all(&test_png_bytes(100, 50)).expect("write 2");
            zip.start_file("5.png", options).expect("start 5");
            zip.write_all(b"not an image").expect("write 5");
            zip.finish().expect("finish zip");
        }

        let entries = zip_image_entries_with_dimensions(&archive).expect("entries");
        assert_eq!(
            entries,
            vec![
                ("2.png".to_string(), Some((100, 50))),
                ("5.png".to_string(), None),
                ("10.png".to_string(), Some((200, 80))),
            ]
        );
    }

    #[test]
    fn zip_entry_dimensions_falls_back_to_full_read_when_header_is_past_probe_window() {
        use std::io::{Read, Write};

        let temp = tempfile::tempdir().expect("tempdir");
        let archive = temp.path().join("pages.cbz");
        {
            let file = fs::File::create(&archive).expect("create zip");
            let mut zip = zip::ZipWriter::new(file);
            let options = zip::write::SimpleFileOptions::default();
            zip.start_file("001.jpg", options).expect("start jpg");
            zip.write_all(&jpeg_with_oversized_app_segment(64, 48))
                .expect("write jpg");
            zip.finish().expect("finish zip");
        }

        let mut opened = open_zip(&archive).expect("open");
        let head = {
            let entry = opened.by_name("001.jpg").expect("entry");
            let mut head = Vec::new();
            entry
                .take(DIM_PROBE_BYTES)
                .read_to_end(&mut head)
                .expect("probe");
            head
        };
        assert!(
            image_dimensions_from_bytes(&head).is_none(),
            "fixture must defeat the header probe"
        );
        assert_eq!(zip_entry_dimensions(&mut opened, "001.jpg"), Some((64, 48)));
        assert_eq!(
            archive_image_dimensions(&archive, "001.jpg"),
            Some((64, 48))
        );
    }

    /// A JPEG whose SOF sits past `DIM_PROBE_BYTES`: a maximal (65535-byte)
    /// APP1 segment is spliced in right after SOI.
    fn jpeg_with_oversized_app_segment(width: u32, height: u32) -> Vec<u8> {
        let image = image::ImageBuffer::from_pixel(width, height, image::Rgb([10u8, 20, 30]));
        let mut cursor = std::io::Cursor::new(Vec::new());
        image
            .write_to(&mut cursor, image::ImageFormat::Jpeg)
            .expect("encode jpeg");
        let jpeg = cursor.into_inner();
        assert_eq!(&jpeg[..2], &[0xFF, 0xD8], "SOI");
        let mut spliced = Vec::with_capacity(jpeg.len() + 65_537);
        spliced.extend_from_slice(&jpeg[..2]);
        spliced.extend_from_slice(&[0xFF, 0xE1, 0xFF, 0xFF]);
        spliced.extend(std::iter::repeat(0u8).take(65_533));
        spliced.extend_from_slice(&jpeg[2..]);
        assert!(spliced.len() as u64 > DIM_PROBE_BYTES);
        spliced
    }

    fn test_png_bytes(width: u32, height: u32) -> Vec<u8> {
        let image = image::ImageBuffer::from_pixel(width, height, image::Rgba([10u8, 20, 30, 255]));
        let mut cursor = std::io::Cursor::new(Vec::new());
        image
            .write_to(&mut cursor, image::ImageFormat::Png)
            .expect("encode png");
        cursor.into_inner()
    }
}
