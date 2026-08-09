use std::collections::HashSet;
use std::fs;
use std::path::Path;

use rusqlite::{Connection, params_from_iter};
use walkdir::WalkDir;

use crate::chapter::is_archive;
use crate::thumbnail::purge_orphan_thumbnails;
use crate::OptimizeDatabaseResult;

pub(crate) fn database_size_bytes_on_disk(db_path: &Path) -> i64 {
    let mut total = fs::metadata(db_path)
        .map(|m| m.len() as i64)
        .unwrap_or(0);
    total += fs::metadata(db_path.with_extension("db-wal"))
        .map(|m| m.len() as i64)
        .unwrap_or(0);
    total += fs::metadata(db_path.with_extension("db-shm"))
        .map(|m| m.len() as i64)
        .unwrap_or(0);
    total
}

pub(crate) fn optimize_database_conn(
    conn: &mut Connection,
    db_path: &Path,
    thumbnail_dir: &Path,
) -> Result<OptimizeDatabaseResult, String> {
    let database_size_before = database_size_bytes_on_disk(db_path);

    let tx = conn
        .transaction()
        .map_err(|e| format!("failed opening optimize transaction: {e}"))?;

    let libraries: Vec<(i64, String)> = {
        let mut stmt = tx
            .prepare("SELECT id, path FROM libraries")
            .map_err(|e| format!("failed preparing libraries query: {e}"))?;
        let rows = stmt
            .query_map([], |row| Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?)))
            .map_err(|e| format!("failed querying libraries: {e}"))?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("failed collecting libraries: {e}"))?
    };
    let available_library_ids: Vec<i64> = libraries
        .iter()
        .filter(|(_, path)| Path::new(path).exists())
        .map(|(id, _)| *id)
        .collect();
    let skipped_library_count = (libraries.len() - available_library_ids.len()) as i64;

    let mut removed_comics = 0i64;
    let mut removed_chapters = 0i64;
    let mut removed_reading_progress = 0i64;
    let mut removed_page_bookmarks = 0i64;

    // 1. Stale comics: source_path no longer present on disk. Chapters and
    //    their progress rows are removed as part of the comic deletion.
    let comics: Vec<(i64, String, i64)> = {
        let mut stmt = tx
            .prepare("SELECT id, source_path, library_id FROM comics")
            .map_err(|e| format!("failed preparing comics query: {e}"))?;
        let rows = stmt
            .query_map([], |row| {
                Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?, row.get::<_, i64>(2)?))
            })
            .map_err(|e| format!("failed querying comics: {e}"))?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("failed collecting comics: {e}"))?
    };
    let missing_comic_ids: Vec<i64> = comics
        .iter()
        .filter(|(_, source_path, library_id)| {
            available_library_ids.contains(library_id) && !Path::new(source_path).exists()
        })
        .map(|(id, _, _)| *id)
        .collect();
    if !missing_comic_ids.is_empty() {
        let cascaded_chapter_ids =
            select_where_in(&tx, "chapters", "id", "comic_id", &missing_comic_ids)?;
        removed_chapters += cascaded_chapter_ids.len() as i64;
        removed_reading_progress +=
            count_where_in(&tx, "reading_progress", "chapter_id", &cascaded_chapter_ids)?;
        removed_page_bookmarks +=
            count_where_in(&tx, "page_bookmarks", "chapter_id", &cascaded_chapter_ids)?;
        removed_comics = missing_comic_ids.len() as i64;
        delete_where_in(&tx, "comics", "id", &missing_comic_ids)?;
    }

    // 2. Stale chapters: source_path no longer present on disk, for comics
    //    that still exist.
    let chapters: Vec<(i64, String, i64)> = {
        let mut stmt = tx
            .prepare("SELECT id, source_path, comic_id FROM chapters")
            .map_err(|e| format!("failed preparing chapters query: {e}"))?;
        let rows = stmt
            .query_map([], |row| {
                Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?, row.get::<_, i64>(2)?))
            })
            .map_err(|e| format!("failed querying chapters: {e}"))?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("failed collecting chapters: {e}"))?
    };
    let missing_chapter_ids: Vec<i64> = chapters
        .iter()
        .filter(|(_, source_path, comic_id)| {
            !missing_comic_ids.contains(comic_id) && !Path::new(source_path).exists()
        })
        .map(|(id, _, _)| *id)
        .collect();
    if !missing_chapter_ids.is_empty() {
        removed_chapters += missing_chapter_ids.len() as i64;
        removed_reading_progress +=
            count_where_in(&tx, "reading_progress", "chapter_id", &missing_chapter_ids)?;
        removed_page_bookmarks +=
            count_where_in(&tx, "page_bookmarks", "chapter_id", &missing_chapter_ids)?;
        delete_where_in(&tx, "chapters", "id", &missing_chapter_ids)?;
    }

    // 3. Belt and suspenders: progress rows and page bookmarks whose chapter
    //    no longer exists.
    removed_reading_progress += tx
        .execute(
            "DELETE FROM reading_progress WHERE chapter_id NOT IN (SELECT id FROM chapters)",
            [],
        )
        .map_err(|e| format!("failed purging orphan reading progress: {e}"))?
        as i64;
    removed_page_bookmarks += tx
        .execute(
            "DELETE FROM page_bookmarks WHERE chapter_id NOT IN (SELECT id FROM chapters)",
            [],
        )
        .map_err(|e| format!("failed purging orphan page bookmarks: {e}"))?
        as i64;

    // 4. Chapter bookmarks whose comic or chapter is gone.
    let removed_chapter_bookmarks = tx
        .execute(
            "DELETE FROM bookmarks WHERE chapter_source_path NOT IN (SELECT source_path FROM chapters)",
            [],
        )
        .map_err(|e| format!("failed purging orphan bookmarks: {e}"))?
        as i64;

    // 5. Favorites whose comic is gone.
    let removed_favorites = tx
        .execute(
            "DELETE FROM favorites WHERE comic_source_path NOT IN (SELECT source_path FROM comics)",
            [],
        )
        .map_err(|e| format!("failed purging orphan favorites: {e}"))?
        as i64;

    tx.commit()
        .map_err(|e| format!("failed committing optimize transaction: {e}"))?;

    // VACUUM physically shrinks the database file. It cannot run inside a
    // transaction, so it runs after the commit.
    conn.execute_batch("VACUUM")
        .map_err(|e| format!("failed vacuuming database: {e}"))?;
    let _ = conn.execute_batch("PRAGMA wal_checkpoint(TRUNCATE);");

    // Purge cached cover thumbnails for comics that no longer exist. Valid
    // sources are the comics still present on disk (surviving DB rows for
    // available libraries, plus top-level entries of every available library
    // root, since the raw library listing is filesystem-primary).
    let (removed_thumbnails, removed_thumbnail_bytes) =
        purge_orphan_thumbnails(thumbnail_dir, &valid_source_paths(conn)?)?;

    Ok(OptimizeDatabaseResult {
        database_size_before,
        database_size_after: database_size_bytes_on_disk(db_path),
        removed_comics,
        removed_chapters,
        removed_reading_progress,
        removed_page_bookmarks,
        removed_chapter_bookmarks,
        removed_favorites,
        removed_thumbnails: removed_thumbnails as i64,
        removed_thumbnail_bytes: removed_thumbnail_bytes as i64,
        skipped_library_count,
    })
}

/// Collect every comic source path that still exists, for thumbnail purge.
///
/// The raw library listing is filesystem-primary, so a comic on disk may not
/// be in the database yet (never scanned). Both sources are combined.
fn valid_source_paths(conn: &Connection) -> Result<HashSet<String>, String> {
    let mut valid = HashSet::new();

    let mut library_paths: Vec<String> = {
        let mut stmt = conn
            .prepare("SELECT path FROM libraries")
            .map_err(|e| format!("failed preparing libraries query: {e}"))?;
        let rows = stmt
            .query_map([], |row| row.get::<_, String>(0))
            .map_err(|e| format!("failed querying libraries: {e}"))?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("failed collecting libraries: {e}"))?
    };
    if let Ok(setting_path) = crate::database::get_library_source_setting(conn) {
        if !library_paths.iter().any(|p| p == &setting_path) {
            library_paths.push(setting_path);
        }
    }

    for library_path in &library_paths {
        let base = Path::new(library_path);
        if !base.exists() || !base.is_dir() {
            continue;
        }
        let entries = WalkDir::new(base)
            .min_depth(1)
            .max_depth(1)
            .into_iter()
            .filter_map(|e| e.ok())
            .map(|e| e.into_path())
            .collect::<Vec<_>>();
        for entry in entries {
            if entry.is_dir() || is_archive(&entry) {
                valid.insert(entry.to_string_lossy().to_string());
            }
        }
    }

    let mut stmt = conn
        .prepare("SELECT source_path FROM comics")
        .map_err(|e| format!("failed preparing comics query: {e}"))?;
    let rows = stmt
        .query_map([], |row| row.get::<_, String>(0))
        .map_err(|e| format!("failed querying comics: {e}"))?;
    for path in rows {
        let path = path.map_err(|e| format!("failed reading comic path: {e}"))?;
        if Path::new(&path).exists() {
            valid.insert(path);
        }
    }

    Ok(valid)
}

fn select_where_in(
    conn: &Connection,
    table: &str,
    id_column: &str,
    where_column: &str,
    ids: &[i64],
) -> Result<Vec<i64>, String> {
    if ids.is_empty() {
        return Ok(Vec::new());
    }
    let placeholders = ids.iter().map(|_| "?").collect::<Vec<_>>().join(",");
    let sql = format!("SELECT {id_column} FROM {table} WHERE {where_column} IN ({placeholders})");
    let mut stmt = conn
        .prepare(&sql)
        .map_err(|e| format!("failed preparing select in: {e}"))?;
    let rows = stmt
        .query_map(params_from_iter(ids.iter()), |row| row.get::<_, i64>(0))
        .map_err(|e| format!("failed querying select in: {e}"))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("failed collecting select in: {e}"))
}

fn count_where_in(
    conn: &Connection,
    table: &str,
    where_column: &str,
    ids: &[i64],
) -> Result<i64, String> {
    if ids.is_empty() {
        return Ok(0);
    }
    let placeholders = ids.iter().map(|_| "?").collect::<Vec<_>>().join(",");
    let sql = format!("SELECT COUNT(*) FROM {table} WHERE {where_column} IN ({placeholders})");
    conn.query_row(&sql, params_from_iter(ids.iter()), |row| row.get::<_, i64>(0))
        .map_err(|e| format!("failed counting rows in: {e}"))
}

fn delete_where_in(
    conn: &Connection,
    table: &str,
    id_column: &str,
    ids: &[i64],
) -> Result<(), String> {
    if ids.is_empty() {
        return Ok(());
    }
    let placeholders = ids.iter().map(|_| "?").collect::<Vec<_>>().join(",");
    let sql = format!("DELETE FROM {table} WHERE {id_column} IN ({placeholders})");
    conn.execute(&sql, params_from_iter(ids.iter()))
        .map_err(|e| format!("failed deleting rows from {table}: {e}"))?;
    Ok(())
}
