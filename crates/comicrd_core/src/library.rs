use std::path::Path;

use rusqlite::{params, Connection};
use walkdir::WalkDir;

use crate::chapter::{
    chapter_history_key, chapter_snapshot_by_history_key, comic_history_key, comic_title_for_path,
    discover_chapter_entries_from_comic_dir, is_archive, source_type_for_path, upsert_chapter,
    upsert_comic, ChapterUpsert,
};
use crate::database::{file_modified_ts, get_library_source_setting, now_ts};
use crate::{Comic, Library, LibrarySourceStatus, RawComic, ScanSummary, SortBy, SortDir};

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

pub(crate) fn list_library_comics_raw_conn(
    conn: &Connection,
    sort_by: SortBy,
    sort_dir: SortDir,
) -> Result<Vec<RawComic>, String> {
    let library_path = get_library_source_setting(conn)?;
    let base = Path::new(&library_path);
    if !base.exists() || !base.is_dir() {
        return Ok(Vec::new());
    }

    let mut comics = Vec::new();
    let mut entries = WalkDir::new(base)
        .min_depth(1)
        .max_depth(1)
        .into_iter()
        .filter_map(|e| e.ok())
        .map(|e| e.into_path())
        .collect::<Vec<_>>();
    entries.sort();

    for entry in entries {
        if entry.is_dir() {
            let source_path = entry.to_string_lossy().to_string();
            comics.push(RawComic {
                key: source_path.clone(),
                title: comic_title_for_path(&entry),
                source_path,
                source_type: "folder".to_string(),
                library_path: library_path.clone(),
                date_modified: file_modified_ts(&entry),
                chapter_count: 0,
                read_chapter_count: 0,
                in_progress_chapter_count: 0,
            });
        } else if entry.is_file() && is_archive(&entry) {
            let source_path = entry.to_string_lossy().to_string();
            comics.push(RawComic {
                key: source_path.clone(),
                title: comic_title_for_path(&entry),
                source_path,
                source_type: source_type_for_path(&entry),
                library_path: library_path.clone(),
                date_modified: file_modified_ts(&entry),
                chapter_count: 1,
                read_chapter_count: 0,
                in_progress_chapter_count: 0,
            });
        }
    }

    comics.sort_by(|a, b| {
        let ord = match sort_by {
            SortBy::FolderDate => a.date_modified.cmp(&b.date_modified),
            SortBy::Name => a.title.to_lowercase().cmp(&b.title.to_lowercase()),
        };
        match sort_dir {
            SortDir::Desc => ord.reverse(),
            SortDir::Asc => ord,
        }
    });
    Ok(comics)
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

        let tx = conn
            .transaction()
            .map_err(|e| format!("failed opening scan transaction: {e}"))?;
        let mut entries = WalkDir::new(base)
            .min_depth(1)
            .max_depth(1)
            .into_iter()
            .filter_map(|e| e.ok())
            .map(|e| e.into_path())
            .collect::<Vec<_>>();
        entries.sort();

        for entry in entries {
            if entry.is_dir() {
                let (c, ch) = scan_comic_dir(&tx, library_id, &library_path, &entry)?;
                comic_count += c;
                chapter_count += ch;
            } else if entry.is_file() && is_archive(&entry) {
                let title = comic_title_for_path(&entry);
                let source_type = source_type_for_path(&entry);
                let source_path = entry.to_string_lossy().to_string();
                let comic_key = comic_history_key(&library_path, &source_path);
                let modified_at = file_modified_ts(&entry);
                let comic_id = upsert_comic(
                    &tx,
                    library_id,
                    &title,
                    &comic_key,
                    &source_path,
                    &source_type,
                    modified_at,
                )?;
                let chapter_key = chapter_history_key(&library_path, &source_path, 1);
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
    }

    Ok(ScanSummary {
        comics: comic_count,
        chapters: chapter_count,
    })
}

pub(crate) fn list_comics_conn(
    conn: &Connection,
    sort_by: SortBy,
    sort_dir: SortDir,
) -> Result<Vec<Comic>, String> {
    let order_field = match sort_by {
        SortBy::FolderDate => "c.date_modified",
        SortBy::Name => "c.title COLLATE NOCASE",
    };
    let order_dir = match sort_dir {
        SortDir::Desc => "DESC",
        SortDir::Asc => "ASC",
    };
    let query = format!(
        r#"
    SELECT
      c.id,
      c.library_id,
      c.title,
      c.source_path,
      c.source_type,
      c.date_modified,
      c.updated_at,
      COUNT(ch.id) AS chapter_count,
      SUM(CASE WHEN COALESCE(r.is_read, 0) = 1 THEN 1 ELSE 0 END) AS read_chapter_count,
      SUM(CASE
            WHEN COALESCE(r.last_page, 0) > 0 AND COALESCE(r.is_read, 0) = 0 THEN 1
            ELSE 0
          END) AS in_progress_chapter_count
    FROM comics c
    LEFT JOIN chapters ch ON ch.comic_id = c.id
    LEFT JOIN reading_progress r ON r.chapter_id = ch.id
    GROUP BY c.id
    ORDER BY {order_field} {order_dir}
    "#
    );
    let mut stmt = conn
        .prepare(&query)
        .map_err(|e| format!("failed preparing comics query: {e}"))?;
    let rows = stmt
        .query_map([], |row| {
            Ok(Comic {
                id: row.get(0)?,
                library_id: row.get(1)?,
                title: row.get(2)?,
                source_path: row.get(3)?,
                source_type: row.get(4)?,
                date_modified: row.get(5)?,
                updated_at: row.get(6)?,
                chapter_count: row.get(7)?,
                read_chapter_count: row.get(8)?,
                in_progress_chapter_count: row.get(9)?,
            })
        })
        .map_err(|e| format!("failed querying comics: {e}"))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("failed collecting comics: {e}"))
}
