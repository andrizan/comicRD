use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};

use rusqlite::{params, Connection};
use unrar::Archive;
use walkdir::WalkDir;
use zip::ZipArchive;

use crate::database::{file_modified_ts, get_library_source_setting, now_ts};
use crate::{ChapterContext, OpenChapterPayload, PageInfo, RawChapter};

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

pub(crate) fn relative_history_path(library_path: &str, target_path: &str) -> String {
    let base = Path::new(library_path);
    let target = Path::new(target_path);
    if let Ok(rel) = target.strip_prefix(base) {
        return normalize_slashes(rel.to_string_lossy().as_ref());
    }
    normalize_slashes(target_path)
}

pub(crate) fn comic_history_key(library_path: &str, comic_source_path: &str) -> String {
    format!(
        "comic/{}",
        relative_history_path(library_path, comic_source_path)
    )
}

pub(crate) fn chapter_history_key(
    library_path: &str,
    chapter_source_path: &str,
    chapter_index: i64,
) -> String {
    format!(
        "chapter/{}#{}",
        relative_history_path(library_path, chapter_source_path),
        chapter_index
    )
}

pub(crate) fn upsert_comic(
    conn: &Connection,
    library_id: i64,
    title: &str,
    history_key: &str,
    source_path: &str,
    source_type: &str,
    date_modified: i64,
) -> Result<i64, String> {
    let ts = now_ts();
    if let Ok(id) = conn.query_row(
        "SELECT id FROM comics WHERE history_key = ?1 LIMIT 1",
        params![history_key],
        |row| row.get::<_, i64>(0),
    ) {
        conn.execute(
            r#"
        UPDATE comics
        SET library_id = ?1, title = ?2, source_path = ?3, source_type = ?4, updated_at = ?5, date_modified = ?6
        WHERE id = ?7
        "#,
            params![library_id, title, source_path, source_type, ts, date_modified, id],
        )
        .map_err(|e| format!("failed updating comic by history key: {e}"))?;
        return Ok(id);
    }

    conn.execute(
        r#"
      INSERT INTO comics (library_id, title, history_key, source_path, source_type, created_at, updated_at, date_modified)
      VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
      "#,
        params![library_id, title, history_key, source_path, source_type, ts, ts, date_modified],
    )
    .map_err(|e| format!("failed inserting comic: {e}"))?;
    Ok(conn.last_insert_rowid())
}

pub(crate) struct ChapterUpsert<'a> {
    pub(crate) comic_id: i64,
    pub(crate) title: &'a str,
    pub(crate) chapter_index: i64,
    pub(crate) history_key: &'a str,
    pub(crate) source_path: &'a str,
    pub(crate) source_type: &'a str,
    pub(crate) page_count: usize,
    pub(crate) date_modified: i64,
}

pub(crate) fn upsert_chapter(conn: &Connection, params: ChapterUpsert<'_>) -> Result<i64, String> {
    let ts = now_ts();
    if let Ok(id) = conn.query_row(
        "SELECT id FROM chapters WHERE history_key = ?1 LIMIT 1",
        params![params.history_key],
        |row| row.get::<_, i64>(0),
    ) {
        conn.execute(
            r#"
        UPDATE chapters
        SET comic_id = ?1, title = ?2, chapter_index = ?3, source_path = ?4, source_type = ?5, page_count = ?6, updated_at = ?7, date_modified = ?8
        WHERE id = ?9
        "#,
            params![
                params.comic_id,
                params.title,
                params.chapter_index,
                params.source_path,
                params.source_type,
                params.page_count as i64,
                ts,
                params.date_modified,
                id
            ],
        )
        .map_err(|e| format!("failed updating chapter by history key: {e}"))?;
        return Ok(id);
    }

    conn.execute(
        r#"
      INSERT INTO chapters (comic_id, title, chapter_index, history_key, source_path, source_type, page_count, created_at, updated_at, date_modified)
      VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
      ON CONFLICT(source_path) DO UPDATE SET
        comic_id = excluded.comic_id,
        title = excluded.title,
        chapter_index = excluded.chapter_index,
        history_key = excluded.history_key,
        source_type = excluded.source_type,
        page_count = excluded.page_count,
        updated_at = excluded.updated_at,
        date_modified = excluded.date_modified
      "#,
        params![
            params.comic_id,
            params.title,
            params.chapter_index,
            params.history_key,
            params.source_path,
            params.source_type,
            params.page_count as i64,
            ts,
            ts,
            params.date_modified
        ],
    )
    .map_err(|e| format!("failed inserting chapter: {e}"))?;
    Ok(conn.last_insert_rowid())
}

pub(crate) fn chapter_snapshot_by_history_key(
    conn: &Connection,
    history_key: &str,
) -> Result<Option<(i64, i64)>, String> {
    conn.query_row(
        "SELECT page_count, date_modified FROM chapters WHERE history_key = ?1",
        params![history_key],
        |row| Ok((row.get::<_, i64>(0)?, row.get::<_, i64>(1)?)),
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

fn zip_image_entries(path: &Path) -> Result<Vec<String>, String> {
    let file = fs::File::open(path).map_err(|e| format!("failed opening archive: {e}"))?;
    let mut archive = ZipArchive::new(file).map_err(|e| format!("invalid zip/cbz: {e}"))?;
    let mut names = Vec::new();
    for idx in 0..archive.len() {
        let file = archive
            .by_index(idx)
            .map_err(|e| format!("failed reading archive entry: {e}"))?;
        if !file.name().ends_with('/') {
            let p = Path::new(file.name());
            if is_image(p) {
                names.push(file.name().to_string());
            }
        }
    }
    names.sort();
    Ok(names)
}

fn zip_image_bytes(path: &Path, name: &str) -> Result<Vec<u8>, String> {
    let file = fs::File::open(path).map_err(|e| format!("failed opening archive: {e}"))?;
    let mut archive = ZipArchive::new(file).map_err(|e| format!("invalid zip/cbz: {e}"))?;
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

    names.sort();
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

pub(crate) fn image_entries_in_dir(path: &Path) -> Vec<PathBuf> {
    let mut entries = WalkDir::new(path)
        .min_depth(1)
        .max_depth(1)
        .into_iter()
        .filter_map(|e| e.ok())
        .map(|e| e.into_path())
        .filter(|p| p.is_file() && is_image(p))
        .collect::<Vec<_>>();
    entries.sort();
    entries
}

pub(crate) fn natural_compare(a: &str, b: &str) -> std::cmp::Ordering {
    let mut a_chars = a.chars().peekable();
    let mut b_chars = b.chars().peekable();
    loop {
        match (a_chars.peek(), b_chars.peek()) {
            (None, None) => return std::cmp::Ordering::Equal,
            (None, Some(_)) => return std::cmp::Ordering::Less,
            (Some(_), None) => return std::cmp::Ordering::Greater,
            (Some(&ac), Some(&bc)) => {
                if ac.is_ascii_digit() && bc.is_ascii_digit() {
                    let mut a_num = String::new();
                    let mut b_num = String::new();
                    while a_chars.peek().is_some_and(|c| c.is_ascii_digit()) {
                        a_num.push(a_chars.next().expect("peeked digit"));
                    }
                    while b_chars.peek().is_some_and(|c| c.is_ascii_digit()) {
                        b_num.push(b_chars.next().expect("peeked digit"));
                    }
                    let a_val: u64 = a_num.parse().unwrap_or(0);
                    let b_val: u64 = b_num.parse().unwrap_or(0);
                    match a_val.cmp(&b_val) {
                        std::cmp::Ordering::Equal => continue,
                        other => return other,
                    }
                } else {
                    let ac_lower: String = ac.to_lowercase().collect();
                    let bc_lower: String = bc.to_lowercase().collect();
                    match ac_lower.cmp(&bc_lower) {
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

pub(crate) fn discover_chapter_entries_from_comic_dir(
    comic_dir: &Path,
) -> Vec<(String, String, String, i64)> {
    let source_path = comic_dir.to_string_lossy().to_string();
    let mut chapter_entries = Vec::new();
    let mut chapter_index = 1i64;

    let root_images = image_entries_in_dir(comic_dir);
    if !root_images.is_empty() {
        chapter_entries.push((
            "Chapter 1".to_string(),
            source_path.clone(),
            "folder".to_string(),
            chapter_index,
        ));
        chapter_index += 1;
    }

    let mut children = WalkDir::new(comic_dir)
        .min_depth(1)
        .max_depth(1)
        .into_iter()
        .filter_map(|e| e.ok())
        .map(|e| e.into_path())
        .collect::<Vec<_>>();
    children.sort_by(|a, b| {
        let a_name = a.file_name().and_then(|v| v.to_str()).unwrap_or("");
        let b_name = b.file_name().and_then(|v| v.to_str()).unwrap_or("");
        natural_compare(a_name, b_name)
    });

    for child in children {
        if child.is_dir() {
            let mut has_images = false;
            let mut nested_archives = Vec::new();

            let mut child_entries = WalkDir::new(&child)
                .min_depth(1)
                .max_depth(1)
                .into_iter()
                .filter_map(|e| e.ok())
                .map(|e| e.into_path())
                .collect::<Vec<_>>();
            child_entries.sort();

            for entry in child_entries {
                if entry.is_file() {
                    if is_image(&entry) {
                        has_images = true;
                    } else if is_archive(&entry) {
                        nested_archives.push(entry);
                    }
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
    Err("comic source tidak valid".to_string())
}

pub(crate) fn list_comic_chapters_raw_conn(
    conn: &Connection,
    comic_source_path: &str,
) -> Result<Vec<RawChapter>, String> {
    let discovered = discover_chapter_entries_for_comic(comic_source_path)?;
    list_comic_chapters_raw_conn_with_discovered(conn, comic_source_path, &discovered)
}

pub(crate) fn list_comic_chapters_raw_conn_with_discovered(
    conn: &Connection,
    _comic_source_path: &str,
    discovered: &[(String, String, String, i64)],
) -> Result<Vec<RawChapter>, String> {
    let library_path = get_library_source_setting(conn)?;

    let chapter_keys: Vec<String> = discovered
        .iter()
        .map(|(_, chapter_path, _, chapter_index)| {
            chapter_history_key(&library_path, chapter_path, *chapter_index)
        })
        .collect();

    let mut progress_map = std::collections::HashMap::new();
    if !chapter_keys.is_empty() {
        let placeholders: String = chapter_keys
            .iter()
            .enumerate()
            .map(|(i, _)| format!("?{}", i + 1))
            .collect::<Vec<_>>()
            .join(", ");
        let query = format!(
            r#"
            SELECT c.history_key,
                   c.page_count,
                   COALESCE(r.is_read, 0),
                   COALESCE(r.last_page, 0),
                   COALESCE(r.total_pages, c.page_count),
                   c.date_modified
            FROM chapters c
            LEFT JOIN reading_progress r ON r.chapter_id = c.id
            WHERE c.history_key IN ({placeholders})
            "#
        );
        let mut stmt = conn
            .prepare(&query)
            .map_err(|e| format!("failed preparing batch progress query: {e}"))?;
        let params: Vec<&dyn rusqlite::types::ToSql> =
            chapter_keys.iter().map(|k| k as &dyn rusqlite::types::ToSql).collect();
        let rows = stmt
            .query_map(params.as_slice(), |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, i64>(1)?,
                    row.get::<_, i64>(2)? == 1,
                    row.get::<_, i64>(3)?,
                    row.get::<_, i64>(4)?,
                    row.get::<_, i64>(5)?,
                ))
            })
            .map_err(|e| format!("failed querying batch progress: {e}"))?;
        for row in rows {
            let (key, page_count, is_read, last_page, total_pages, date_modified) =
                row.map_err(|e| format!("failed reading progress row: {e}"))?;
            progress_map.insert(key, (page_count, is_read, last_page, total_pages, date_modified));
        }
    }

    let mut out = Vec::with_capacity(discovered.len());
    for (i, (chapter_title, chapter_path, _chapter_type, chapter_index)) in
        discovered.iter().enumerate()
    {
        let chapter_key = &chapter_keys[i];
        let modified_at = file_modified_ts(Path::new(chapter_path));
        let (page_count, is_read, last_page, total_pages, date_modified) =
            progress_map
                .get(chapter_key.as_str())
                .copied()
                .unwrap_or((0, false, 0, 0, modified_at));
        out.push(RawChapter {
            key: chapter_path.clone(),
            title: chapter_title.clone(),
            chapter_index: *chapter_index,
            source_path: chapter_path.clone(),
            source_type: source_type_for_path(Path::new(chapter_path)),
            date_modified,
            page_count,
            is_read,
            last_page,
            total_pages,
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
        return Err("comic bukan bagian dari library_source_input saat ini".to_string());
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
    let (library_id, library_path) = find_library_for_comic(&tx, &payload.comic_source_path)?;
    let comic_source = Path::new(&payload.comic_source_path);
    let comic_source_type = source_type_for_path(comic_source);
    let comic_title = comic_title_for_path(comic_source);
    let comic_key = comic_history_key(&library_path, &payload.comic_source_path);
    let comic_id = upsert_comic(
        &tx,
        library_id,
        &comic_title,
        &comic_key,
        &payload.comic_source_path,
        &comic_source_type,
        file_modified_ts(comic_source),
    )?;

    let chapter_entries = discover_chapter_entries_for_comic(&payload.comic_source_path)?;
    let mut selected_chapter_id = None;
    for (chapter_title, chapter_path, chapter_type, chapter_index) in chapter_entries {
        let chapter_key = chapter_history_key(&library_path, &chapter_path, chapter_index);
        let modified_at = file_modified_ts(Path::new(&chapter_path));
        let cached_page_count = chapter_snapshot_by_history_key(&tx, &chapter_key)?
            .map(|(pc, _)| pc.max(0) as usize)
            .unwrap_or(0);
        let chapter_id = upsert_chapter(
            &tx,
            ChapterUpsert {
                comic_id,
                title: &chapter_title,
                chapter_index,
                history_key: &chapter_key,
                source_path: &chapter_path,
                source_type: &chapter_type,
                page_count: cached_page_count,
                date_modified: modified_at,
            },
        )?;
        if chapter_path == payload.chapter_source_path {
            selected_chapter_id = Some(chapter_id);
        }
    }
    tx.commit()
        .map_err(|e| format!("failed committing chapter transaction: {e}"))?;
    selected_chapter_id.ok_or_else(|| "chapter tidak ditemukan".to_string())
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

pub(crate) fn get_chapter_pages_conn(
    conn: &Connection,
    chapter_id: i64,
) -> Result<Vec<PageInfo>, String> {
    let (source_path, source_type) = chapter_source(conn, chapter_id)?;
    let names = match source_type.as_str() {
        "folder" => image_entries_in_dir(Path::new(&source_path))
            .into_iter()
            .map(|p| {
                p.file_name()
                    .and_then(|v| v.to_str())
                    .unwrap_or_default()
                    .to_string()
            })
            .collect::<Vec<_>>(),
        "zip" | "cbz" | "cbr" | "rar" => archive_image_entries(Path::new(&source_path))?,
        other => return Err(format!("unsupported source type: {other}")),
    };
    let page_count = names.len() as i64;
    let modified_at = file_modified_ts(Path::new(&source_path));
    let _ = conn.execute(
        "UPDATE chapters SET page_count = ?1, date_modified = ?2, updated_at = ?3 WHERE id = ?4",
        params![page_count, modified_at, now_ts(), chapter_id],
    );
    Ok(names
        .into_iter()
        .enumerate()
        .map(|(index, name)| PageInfo {
            index,
            name,
            width: None,
            height: None,
        })
        .collect())
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
    use std::path::PathBuf;

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
}
