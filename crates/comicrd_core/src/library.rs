use std::path::Path;

use rusqlite::{params, Connection, OptionalExtension};
use walkdir::WalkDir;

use crate::chapter::{
    chapter_history_key, chapter_snapshot_by_history_key, comic_history_key, comic_title_for_path,
    discover_chapter_entries_from_comic_dir, is_archive, source_type_for_path, upsert_chapter,
    upsert_comic, ChapterUpsert,
};
use crate::database::{file_modified_ts, now_ts};
use crate::{Library, LibrarySourceStatus, RawComic, ScanSummary};

pub(crate) fn library_source_status_for(path: &str) -> LibrarySourceStatus {
    if path.is_empty() {
        return LibrarySourceStatus {
            configured: false,
            path: String::new(),
            exists: false,
            is_dir: false,
            readable: false,
            error: None,
        };
    }
    let p = Path::new(path);
    let exists = p.exists();
    let is_dir = exists && p.is_dir();
    let readable = is_dir && p.read_dir().is_ok();
    let error = if !exists {
        Some(format!(
            "path '{path}' not found. On Linux, you may need to mount the partition first."
        ))
    } else if !is_dir {
        Some(format!("path '{path}' exists but is not a directory."))
    } else if !readable {
        Some(format!(
            "path '{path}' is not readable (permission denied)."
        ))
    } else {
        None
    };
    LibrarySourceStatus {
        configured: true,
        path: path.to_string(),
        exists,
        is_dir,
        readable,
        error,
    }
}

pub(crate) fn comics_from_fs_entries(
    conn: &Connection,
    library_path: &str,
    entries: &[std::path::PathBuf],
    comics: &mut Vec<RawComic>,
) -> Result<(), String> {
    comics.reserve(entries.len());

    let mut folder_keys = Vec::new();
    let mut archive_keys = Vec::new();
    for entry in entries {
        if entry.is_dir() {
            let source_path = entry.to_string_lossy().to_string();
            folder_keys.push(comic_history_key(library_path, &source_path));
        } else if entry.is_file() && is_archive(entry) {
            let source_path = entry.to_string_lossy().to_string();
            archive_keys.push(chapter_history_key(library_path, &source_path, 1));
        }
    }

    let folder_counts = batch_comic_counts_from_db(conn, &folder_keys)?;
    let archive_progress = batch_progress_counts_for_chapter_keys(conn, &archive_keys)?;

    let mut folder_idx = 0usize;
    let mut archive_idx = 0usize;
    for entry in entries {
        if entry.is_dir() {
            let source_path = entry.to_string_lossy().to_string();
            let (chapter_count, read_chapter_count, in_progress_chapter_count) =
                folder_counts.get(folder_idx).copied().unwrap_or((0, 0, 0));
            folder_idx += 1;
            comics.push(RawComic {
                key: source_path.clone(),
                title: comic_title_for_path(entry),
                source_path,
                source_type: "folder".to_string(),
                library_path: library_path.to_string(),
                date_modified: file_modified_ts(entry),
                chapter_count,
                read_chapter_count,
                in_progress_chapter_count,
            });
        } else if entry.is_file() && is_archive(entry) {
            let source_path = entry.to_string_lossy().to_string();
            let (read_chapter_count, in_progress_chapter_count) =
                archive_progress.get(archive_idx).copied().unwrap_or((0, 0));
            archive_idx += 1;
            comics.push(RawComic {
                key: source_path.clone(),
                title: comic_title_for_path(entry),
                source_path,
                source_type: source_type_for_path(entry),
                library_path: library_path.to_string(),
                date_modified: file_modified_ts(entry),
                chapter_count: 1,
                read_chapter_count,
                in_progress_chapter_count,
            });
        }
    }
    Ok(())
}

fn comic_counts_from_db(
    conn: &Connection,
    comic_history_key: &str,
) -> Result<(i64, i64, i64), String> {
    let result = conn
        .query_row(
            r#"
            SELECT
                COUNT(ch.id),
                COALESCE(SUM(CASE WHEN COALESCE(r.is_read, 0) = 1 THEN 1 ELSE 0 END), 0),
                COALESCE(SUM(CASE WHEN COALESCE(r.last_page, 0) > 0 AND COALESCE(r.is_read, 0) = 0 THEN 1 ELSE 0 END), 0)
            FROM comics c
            LEFT JOIN chapters ch ON ch.comic_id = c.id
            LEFT JOIN reading_progress r ON r.chapter_id = ch.id
            WHERE c.history_key = ?1
            "#,
            params![comic_history_key],
            |row| Ok((row.get::<_, i64>(0)?, row.get::<_, i64>(1)?, row.get::<_, i64>(2)?)),
        )
        .optional()
        .map_err(|e| format!("failed querying comic counts: {e}"))?;

    Ok(result.unwrap_or((0, 0, 0)))
}

fn progress_counts_for_chapter_keys(
    conn: &Connection,
    chapter_keys: &[String],
) -> Result<(i64, i64), String> {
    if chapter_keys.is_empty() {
        return Ok((0, 0));
    }

    let mut stmt = conn
        .prepare(
            r#"
            SELECT COALESCE(r.is_read, 0), COALESCE(r.last_page, 0)
            FROM chapters ch
            LEFT JOIN reading_progress r ON r.chapter_id = ch.id
            WHERE ch.history_key = ?1
            "#,
        )
        .map_err(|e| format!("failed preparing raw progress query: {e}"))?;

    let mut read_count = 0;
    let mut in_progress_count = 0;
    for chapter_key in chapter_keys {
        let progress = stmt
            .query_row(params![chapter_key], |row| {
                Ok((row.get::<_, bool>(0)?, row.get::<_, i64>(1)?))
            })
            .optional()
            .map_err(|e| format!("failed querying raw progress: {e}"))?;
        if let Some((is_read, last_page)) = progress {
            if is_read {
                read_count += 1;
            } else if last_page > 0 {
                in_progress_count += 1;
            }
        }
    }
    Ok((read_count, in_progress_count))
}

fn batch_comic_counts_from_db(
    conn: &Connection,
    comic_keys: &[String],
) -> Result<Vec<(i64, i64, i64)>, String> {
    if comic_keys.is_empty() {
        return Ok(Vec::new());
    }
    let mut result = vec![(0i64, 0i64, 0i64); comic_keys.len()];
    let placeholders: String = comic_keys
        .iter()
        .enumerate()
        .map(|(i, _)| format!("?{}", i + 1))
        .collect::<Vec<_>>()
        .join(", ");
    let query = format!(
        r#"
        SELECT
            c.history_key,
            COUNT(ch.id),
            COALESCE(SUM(CASE WHEN COALESCE(r.is_read, 0) = 1 THEN 1 ELSE 0 END), 0),
            COALESCE(SUM(CASE WHEN COALESCE(r.last_page, 0) > 0 AND COALESCE(r.is_read, 0) = 0 THEN 1 ELSE 0 END), 0)
        FROM comics c
        LEFT JOIN chapters ch ON ch.comic_id = c.id
        LEFT JOIN reading_progress r ON r.chapter_id = ch.id
        WHERE c.history_key IN ({placeholders})
        GROUP BY c.history_key
        "#
    );
    let mut stmt = conn
        .prepare(&query)
        .map_err(|e| format!("failed preparing batch comic counts query: {e}"))?;
    let params: Vec<&dyn rusqlite::types::ToSql> =
        comic_keys.iter().map(|k| k as &dyn rusqlite::types::ToSql).collect();
    let rows = stmt
        .query_map(params.as_slice(), |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, i64>(1)?,
                row.get::<_, i64>(2)?,
                row.get::<_, i64>(3)?,
            ))
        })
        .map_err(|e| format!("failed querying batch comic counts: {e}"))?;
    let key_to_idx: std::collections::HashMap<String, usize> =
        comic_keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect();
    for row in rows {
        let (key, chapter_count, read_count, in_progress_count) =
            row.map_err(|e| format!("failed reading batch comic count row: {e}"))?;
        if let Some(&idx) = key_to_idx.get(&key) {
            result[idx] = (chapter_count, read_count, in_progress_count);
        }
    }
    Ok(result)
}

fn batch_progress_counts_for_chapter_keys(
    conn: &Connection,
    chapter_keys: &[String],
) -> Result<Vec<(i64, i64)>, String> {
    if chapter_keys.is_empty() {
        return Ok(Vec::new());
    }
    let mut result = vec![(0i64, 0i64); chapter_keys.len()];
    let placeholders: String = chapter_keys
        .iter()
        .enumerate()
        .map(|(i, _)| format!("?{}", i + 1))
        .collect::<Vec<_>>()
        .join(", ");
    let query = format!(
        r#"
        SELECT ch.history_key, COALESCE(r.is_read, 0), COALESCE(r.last_page, 0)
        FROM chapters ch
        LEFT JOIN reading_progress r ON r.chapter_id = ch.id
        WHERE ch.history_key IN ({placeholders})
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
                row.get::<_, bool>(1)?,
                row.get::<_, i64>(2)?,
            ))
        })
        .map_err(|e| format!("failed querying batch progress: {e}"))?;
    let key_to_idx: std::collections::HashMap<String, usize> =
        chapter_keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect();
    for row in rows {
        let (key, is_read, last_page) =
            row.map_err(|e| format!("failed reading batch progress row: {e}"))?;
        if let Some(&idx) = key_to_idx.get(&key) {
            if is_read {
                result[idx] = (1, 0);
            } else if last_page > 0 {
                result[idx] = (0, 1);
            }
        }
    }
    Ok(result)
}

pub(crate) fn add_library_conn(conn: &Connection, path: &str) -> Result<i64, String> {
    let ts = now_ts();
    conn.execute(
        r#"
      INSERT INTO libraries (path, created_at, updated_at)
      VALUES (?1, ?2, ?3)
      ON CONFLICT(path) DO UPDATE SET updated_at=excluded.updated_at
      "#,
        params![path, ts, ts],
    )
    .map_err(|e| format!("failed upserting library: {e}"))?;
    conn.query_row(
        "SELECT id FROM libraries WHERE path = ?1",
        params![path],
        |row| row.get::<_, i64>(0),
    )
    .map_err(|e| format!("failed selecting library id: {e}"))
}

pub(crate) fn list_libraries_conn(conn: &Connection) -> Result<Vec<Library>, String> {
    let mut stmt = conn
        .prepare("SELECT id, path, created_at, updated_at FROM libraries ORDER BY updated_at DESC")
        .map_err(|e| format!("failed preparing query: {e}"))?;
    let rows = stmt
        .query_map([], |row| {
            Ok(Library {
                id: row.get(0)?,
                path: row.get(1)?,
                created_at: row.get(2)?,
                updated_at: row.get(3)?,
            })
        })
        .map_err(|e| format!("failed querying libraries: {e}"))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("failed collecting libraries: {e}"))
}

pub(crate) fn scan_comic_dir(
    conn: &Connection,
    library_id: i64,
    library_path: &str,
    comic_dir: &Path,
) -> Result<(usize, usize), String> {
    let title = comic_title_for_path(comic_dir);
    let source_path = comic_dir.to_string_lossy().to_string();
    let comic_key = comic_history_key(library_path, &source_path);
    let comic_id = upsert_comic(
        conn,
        library_id,
        &title,
        &comic_key,
        &source_path,
        "folder",
        file_modified_ts(comic_dir),
    )?;
    let chapter_entries = discover_chapter_entries_from_comic_dir(comic_dir);

    let mut chapter_count = 0usize;
    for (chapter_title, chapter_path, chapter_type, idx) in chapter_entries {
        let chapter_key = chapter_history_key(library_path, &chapter_path, idx);
        let modified_at = file_modified_ts(Path::new(&chapter_path));
        let mut cached_page_count = 0i64;
        if let Some((existing_page_count, cached_modified_at)) =
            chapter_snapshot_by_history_key(conn, &chapter_key)?
        {
            cached_page_count = existing_page_count;
            if cached_modified_at == modified_at {
                chapter_count += 1;
                continue;
            }
        }

        upsert_chapter(
            conn,
            ChapterUpsert {
                comic_id,
                title: &chapter_title,
                chapter_index: idx,
                history_key: &chapter_key,
                source_path: &chapter_path,
                source_type: &chapter_type,
                page_count: cached_page_count.max(0) as usize,
                date_modified: modified_at,
            },
        )?;
        chapter_count += 1;
    }

    Ok((1, chapter_count))
}

pub(crate) fn scan_libraries_conn(conn: &mut Connection) -> Result<ScanSummary, String> {
    let libraries: Vec<(i64, String)> = {
        let mut stmt = conn
            .prepare("SELECT id, path FROM libraries ORDER BY id")
            .map_err(|e| format!("failed preparing libraries query: {e}"))?;
        let rows = stmt
            .query_map([], |row| {
                Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?))
            })
            .map_err(|e| format!("failed querying libraries: {e}"))?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("invalid library row: {e}"))?
    };

    let mut comic_count = 0usize;
    let mut chapter_count = 0usize;

    for (library_id, library_path) in libraries {
        let base = Path::new(&library_path);
        if !base.exists() || !base.is_dir() {
            continue;
        }

        let mut entries = WalkDir::new(base)
            .min_depth(1)
            .max_depth(1)
            .into_iter()
            .filter_map(|e| e.ok())
            .map(|e| e.into_path())
            .collect::<Vec<_>>();
        entries.sort();

        let (c, ch) = scan_library_entries(conn, library_id, &library_path, &entries)?;
        comic_count += c;
        chapter_count += ch;
    }

    Ok(ScanSummary {
        comics: comic_count,
        chapters: chapter_count,
    })
}

pub(crate) fn scan_library_entries(
    conn: &mut Connection,
    library_id: i64,
    library_path: &str,
    entries: &[std::path::PathBuf],
) -> Result<(usize, usize), String> {
    let mut comic_count = 0usize;
    let mut chapter_count = 0usize;

    let tx = conn
        .transaction()
        .map_err(|e| format!("failed opening scan transaction: {e}"))?;

    for entry in entries {
        if entry.is_dir() {
            let (c, ch) = scan_comic_dir(&tx, library_id, library_path, entry)?;
            comic_count += c;
            chapter_count += ch;
        } else if entry.is_file() && is_archive(entry) {
            let title = comic_title_for_path(entry);
            let source_type = source_type_for_path(entry);
            let source_path = entry.to_string_lossy().to_string();
            let comic_key = comic_history_key(library_path, &source_path);
            let modified_at = file_modified_ts(entry);
            let comic_id = upsert_comic(
                &tx,
                library_id,
                &title,
                &comic_key,
                &source_path,
                &source_type,
                modified_at,
            )?;
            let chapter_key = chapter_history_key(library_path, &source_path, 1);
            let mut should_upsert_chapter = true;
            let page_count = if let Some((cached_page_count, cached_modified_at)) =
                chapter_snapshot_by_history_key(&tx, &chapter_key)?
            {
                if cached_modified_at == modified_at {
                    should_upsert_chapter = false;
                    cached_page_count as usize
                } else {
                    cached_page_count.max(0) as usize
                }
            } else {
                0
            };
            if should_upsert_chapter {
                upsert_chapter(
                    &tx,
                    ChapterUpsert {
                        comic_id,
                        title: "Chapter 1",
                        chapter_index: 1,
                        history_key: &chapter_key,
                        source_path: &source_path,
                        source_type: &source_type,
                        page_count,
                        date_modified: modified_at,
                    },
                )?;
            }
            comic_count += 1;
            chapter_count += 1;
        }
    }

    tx.commit()
        .map_err(|e| format!("failed committing scan transaction: {e}"))?;

    Ok((comic_count, chapter_count))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn library_source_status_for_empty_path_is_unconfigured() {
        let status = library_source_status_for("");
        assert!(!status.configured);
        assert_eq!(status.path, "");
        assert!(!status.exists);
        assert!(!status.is_dir);
        assert!(!status.readable);
        assert!(status.error.is_none());
    }

    #[test]
    fn library_source_status_for_missing_path_reports_error() {
        let status = library_source_status_for("/nonexistent/path/12345");
        assert!(status.configured);
        assert!(!status.exists);
        assert!(!status.is_dir);
        assert!(!status.readable);
        assert!(status.error.is_some());
        assert!(status.error.unwrap().contains("not found"));
    }

    #[test]
    fn library_source_status_for_file_reports_not_dir() {
        let temp = tempfile::tempdir().expect("tempdir");
        let file = temp.path().join("file.txt");
        std::fs::write(&file, "").expect("write");

        let status = library_source_status_for(&file.to_string_lossy());
        assert!(status.configured);
        assert!(status.exists);
        assert!(!status.is_dir);
        assert!(!status.readable);
        assert!(status.error.unwrap().contains("not a directory"));
    }

    #[test]
    fn library_source_status_for_valid_dir_is_readable() {
        let temp = tempfile::tempdir().expect("tempdir");
        let status = library_source_status_for(&temp.path().to_string_lossy());
        assert!(status.configured);
        assert!(status.exists);
        assert!(status.is_dir);
        assert!(status.readable);
        assert!(status.error.is_none());
    }
}
