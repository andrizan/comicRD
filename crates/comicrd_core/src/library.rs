use std::collections::HashMap;
use std::path::Path;

use rusqlite::{params, Connection};

use crate::chapter::{
    chapter_size_bytes, comic_title_for_path, discover_chapter_entries_from_comic_dir, is_archive,
    source_type_for_path, upsert_chapter, upsert_comic, ChapterUpsert,
};
use crate::database::{file_modified_ts, now_ts};
use crate::{Library, LibrarySourceStatus, RawComic};

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
    _library_path: &str,
    entries: &[std::path::PathBuf],
    comics: &mut Vec<RawComic>,
) -> Result<(), String> {
    comics.reserve(entries.len());

    let mut folder_paths = Vec::new();
    let mut archive_paths = Vec::new();
    let mut all_comic_paths = Vec::new();
    for entry in entries {
        if entry.is_dir() {
            let source_path = entry.to_string_lossy().to_string();
            folder_paths.push(source_path.clone());
            all_comic_paths.push(source_path);
        } else if entry.is_file() && is_archive(entry) {
            let source_path = entry.to_string_lossy().to_string();
            archive_paths.push(source_path.clone());
            all_comic_paths.push(source_path);
        }
    }

    let folder_counts = batch_comic_counts_from_db(conn, &folder_paths)?;
    let archive_progress = batch_progress_counts_for_chapter_paths(conn, &archive_paths)?;
    let comic_size_by_path = batch_comic_size_from_db(conn, &all_comic_paths)?;

    let mut folder_idx = 0usize;
    let mut archive_idx = 0usize;
    for entry in entries {
        if entry.is_dir() {
            let source_path = entry.to_string_lossy().to_string();
            let (chapter_count, read_chapter_count, in_progress_chapter_count) =
                folder_counts.get(folder_idx).copied().unwrap_or((0, 0, 0));
            folder_idx += 1;
            let size_bytes = comic_size_by_path.get(&source_path).copied().unwrap_or(0);
            comics.push(RawComic {
                title: comic_title_for_path(entry),
                source_path,
                source_type: "folder".to_string(),
                date_modified: file_modified_ts(entry),
                chapter_count,
                read_chapter_count,
                in_progress_chapter_count,
                size_bytes,
            });
        } else if entry.is_file() && is_archive(entry) {
            let source_path = entry.to_string_lossy().to_string();
            let source_type = source_type_for_path(entry);
            let (read_chapter_count, in_progress_chapter_count) =
                archive_progress.get(archive_idx).copied().unwrap_or((0, 0));
            archive_idx += 1;
            let size_bytes = comic_size_by_path
                .get(&source_path)
                .copied()
                .unwrap_or_else(|| chapter_size_bytes(entry, &source_type));
            comics.push(RawComic {
                title: comic_title_for_path(entry),
                source_path,
                source_type,
                date_modified: file_modified_ts(entry),
                chapter_count: 1,
                read_chapter_count,
                in_progress_chapter_count,
                size_bytes,
            });
        }
    }
    Ok(())
}

fn batch_comic_counts_from_db(
    conn: &Connection,
    comic_paths: &[String],
) -> Result<Vec<(i64, i64, i64)>, String> {
    if comic_paths.is_empty() {
        return Ok(Vec::new());
    }
    let mut result = vec![(0i64, 0i64, 0i64); comic_paths.len()];
    let placeholders: String = comic_paths
        .iter()
        .enumerate()
        .map(|(i, _)| format!("?{}", i + 1))
        .collect::<Vec<_>>()
        .join(", ");
    let query = format!(
        r#"
        SELECT
            c.source_path,
            COUNT(ch.id),
            COALESCE(SUM(CASE WHEN COALESCE(r.is_read, 0) = 1 THEN 1 ELSE 0 END), 0),
            COALESCE(SUM(CASE WHEN COALESCE(r.last_page, 0) > 0 AND COALESCE(r.is_read, 0) = 0 THEN 1 ELSE 0 END), 0)
        FROM comics c
        LEFT JOIN chapters ch ON ch.comic_id = c.id
        LEFT JOIN reading_progress r ON r.chapter_id = ch.id
        WHERE c.source_path IN ({placeholders})
        GROUP BY c.source_path
        "#
    );
    let mut stmt = conn
        .prepare(&query)
        .map_err(|e| format!("failed preparing batch comic counts query: {e}"))?;
    let params: Vec<&dyn rusqlite::types::ToSql> = comic_paths
        .iter()
        .map(|k| k as &dyn rusqlite::types::ToSql)
        .collect();
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
    let path_to_idx: std::collections::HashMap<String, usize> = comic_paths
        .iter()
        .enumerate()
        .map(|(i, p)| (p.clone(), i))
        .collect();
    for row in rows {
        let (path, chapter_count, read_count, in_progress_count) =
            row.map_err(|e| format!("failed reading batch comic count row: {e}"))?;
        if let Some(&idx) = path_to_idx.get(&path) {
            result[idx] = (chapter_count, read_count, in_progress_count);
        }
    }
    Ok(result)
}

fn batch_comic_size_from_db(
    conn: &Connection,
    comic_paths: &[String],
) -> Result<std::collections::HashMap<String, i64>, String> {
    let mut result = std::collections::HashMap::new();
    if comic_paths.is_empty() {
        return Ok(result);
    }
    let placeholders: String = comic_paths
        .iter()
        .enumerate()
        .map(|(i, _)| format!("?{}", i + 1))
        .collect::<Vec<_>>()
        .join(", ");
    let query = format!(
        "SELECT source_path, size_bytes FROM comics WHERE source_path IN ({placeholders})"
    );
    let mut stmt = conn
        .prepare(&query)
        .map_err(|e| format!("failed preparing batch comic size query: {e}"))?;
    let params: Vec<&dyn rusqlite::types::ToSql> = comic_paths
        .iter()
        .map(|k| k as &dyn rusqlite::types::ToSql)
        .collect();
    let rows = stmt
        .query_map(params.as_slice(), |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)?))
        })
        .map_err(|e| format!("failed querying batch comic size: {e}"))?;
    for row in rows {
        let (path, size) = row.map_err(|e| format!("failed reading batch comic size row: {e}"))?;
        result.insert(path, size);
    }
    Ok(result)
}

fn batch_progress_counts_for_chapter_paths(
    conn: &Connection,
    chapter_paths: &[String],
) -> Result<Vec<(i64, i64)>, String> {
    if chapter_paths.is_empty() {
        return Ok(Vec::new());
    }
    let mut result = vec![(0i64, 0i64); chapter_paths.len()];
    let placeholders: String = chapter_paths
        .iter()
        .enumerate()
        .map(|(i, _)| format!("?{}", i + 1))
        .collect::<Vec<_>>()
        .join(", ");
    let query = format!(
        r#"
        SELECT ch.source_path, COALESCE(r.is_read, 0), COALESCE(r.last_page, 0)
        FROM chapters ch
        LEFT JOIN reading_progress r ON r.chapter_id = ch.id
        WHERE ch.source_path IN ({placeholders})
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
                row.get::<_, bool>(1)?,
                row.get::<_, i64>(2)?,
            ))
        })
        .map_err(|e| format!("failed querying batch progress: {e}"))?;
    let path_to_idx: std::collections::HashMap<String, usize> = chapter_paths
        .iter()
        .enumerate()
        .map(|(i, p)| (p.clone(), i))
        .collect();
    for row in rows {
        let (path, is_read, last_page) =
            row.map_err(|e| format!("failed reading batch progress row: {e}"))?;
        if let Some(&idx) = path_to_idx.get(&path) {
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

/// Filesystem half of scanning one top-level library entry: everything that
/// touches disk, gathered before any DB lock is taken so a long scan never
/// blocks the UI's DB calls.
pub(crate) enum ScanEntryPlan {
    Folder {
        title: String,
        source_path: String,
        modified_at: i64,
        chapters: Vec<DiscoveredChapter>,
    },
    Archive {
        title: String,
        source_path: String,
        source_type: String,
        modified_at: i64,
        size_bytes: i64,
    },
}

pub(crate) struct DiscoveredChapter {
    pub(crate) title: String,
    pub(crate) source_path: String,
    pub(crate) source_type: String,
    pub(crate) index: i64,
    pub(crate) modified_at: i64,
}

/// `(page_count, date_modified, size_bytes, chapter_index)` as stored.
pub(crate) type ChapterSnapshot = (i64, i64, i64, i64);

/// Placeholders per `IN (...)` snapshot query (SQLite allows 32766).
const SNAPSHOT_QUERY_CHUNK: usize = 500;

impl ScanEntryPlan {
    /// None for entries that are neither a comic folder nor an archive.
    pub(crate) fn from_entry(entry: &Path) -> Option<Self> {
        if entry.is_dir() {
            let chapters = discover_chapter_entries_from_comic_dir(entry)
                .into_iter()
                .map(|(title, source_path, source_type, index)| DiscoveredChapter {
                    modified_at: file_modified_ts(Path::new(&source_path)),
                    title,
                    source_path,
                    source_type,
                    index,
                })
                .collect();
            return Some(Self::Folder {
                title: comic_title_for_path(entry),
                source_path: entry.to_string_lossy().to_string(),
                modified_at: file_modified_ts(entry),
                chapters,
            });
        }
        if entry.is_file() && is_archive(entry) {
            let source_type = source_type_for_path(entry);
            let size_bytes = chapter_size_bytes(entry, &source_type);
            return Some(Self::Archive {
                title: comic_title_for_path(entry),
                source_path: entry.to_string_lossy().to_string(),
                source_type,
                modified_at: file_modified_ts(entry),
                size_bytes,
            });
        }
        None
    }

    pub(crate) fn source_path(&self) -> &str {
        match self {
            Self::Folder { source_path, .. } | Self::Archive { source_path, .. } => source_path,
        }
    }

    /// Chapter paths whose stored snapshot decides what gets rewritten.
    pub(crate) fn chapter_paths(&self) -> Vec<String> {
        match self {
            Self::Folder { chapters, .. } => {
                chapters.iter().map(|c| c.source_path.clone()).collect()
            }
            Self::Archive { source_path, .. } => vec![source_path.clone()],
        }
    }

    /// Sizes that must be measured on disk: chapters with no snapshot or a
    /// changed one (unchanged chapters reuse the stored size). Lock-free.
    pub(crate) fn measure_changed_sizes(
        &self,
        snapshots: &HashMap<String, ChapterSnapshot>,
    ) -> HashMap<String, i64> {
        let Self::Folder { chapters, .. } = self else {
            return HashMap::new();
        };
        chapters
            .iter()
            .filter(|chapter| !chapter.snapshot_matches(snapshots))
            .map(|chapter| {
                (
                    chapter.source_path.clone(),
                    chapter_size_bytes(Path::new(&chapter.source_path), &chapter.source_type),
                )
            })
            .collect()
    }
}

impl DiscoveredChapter {
    /// Stored row still describes this chapter: same mtime and position.
    fn snapshot_matches(&self, snapshots: &HashMap<String, ChapterSnapshot>) -> bool {
        matches!(
            snapshots.get(&self.source_path),
            Some(&(_, cached_modified_at, _, cached_index))
                if cached_modified_at == self.modified_at && cached_index == self.index
        )
    }
}

/// Stored snapshots for many chapter paths in a few batched queries.
pub(crate) fn chapter_snapshots_by_source_paths(
    conn: &Connection,
    paths: &[String],
) -> Result<HashMap<String, ChapterSnapshot>, String> {
    let mut snapshots = HashMap::with_capacity(paths.len());
    for chunk in paths.chunks(SNAPSHOT_QUERY_CHUNK) {
        let placeholders: String = (1..=chunk.len())
            .map(|i| format!("?{i}"))
            .collect::<Vec<_>>()
            .join(", ");
        let query = format!(
            "SELECT source_path, page_count, date_modified, size_bytes, chapter_index FROM chapters WHERE source_path IN ({placeholders})"
        );
        let mut stmt = conn
            .prepare(&query)
            .map_err(|e| format!("failed preparing chapter snapshot query: {e}"))?;
        let params: Vec<&dyn rusqlite::types::ToSql> = chunk
            .iter()
            .map(|path| path as &dyn rusqlite::types::ToSql)
            .collect();
        let rows = stmt
            .query_map(params.as_slice(), |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    (
                        row.get::<_, i64>(1)?,
                        row.get::<_, i64>(2)?,
                        row.get::<_, i64>(3)?,
                        row.get::<_, i64>(4)?,
                    ),
                ))
            })
            .map_err(|e| format!("failed querying chapter snapshots: {e}"))?;
        for row in rows {
            let (path, snapshot) =
                row.map_err(|e| format!("failed reading chapter snapshot: {e}"))?;
            snapshots.insert(path, snapshot);
        }
    }
    Ok(snapshots)
}

/// DB half of one entry: upsert the comic and its changed chapters in one
/// short transaction. Returns `(comics, chapters)` counting every discovered
/// chapter, rewritten or not, like the previous scan.
pub(crate) fn apply_scan_entry(
    conn: &mut Connection,
    library_id: i64,
    plan: &ScanEntryPlan,
    snapshots: &HashMap<String, ChapterSnapshot>,
    measured_sizes: &HashMap<String, i64>,
) -> Result<(usize, usize), String> {
    let tx = conn
        .transaction()
        .map_err(|e| format!("failed opening scan transaction: {e}"))?;
    let counts = match plan {
        ScanEntryPlan::Folder {
            title,
            source_path,
            modified_at,
            chapters,
        } => {
            let comic_id =
                upsert_comic(&tx, library_id, title, source_path, "folder", *modified_at)?;
            let mut total_size_bytes: i64 = 0;
            for chapter in chapters {
                let snapshot = snapshots.get(&chapter.source_path);
                if chapter.snapshot_matches(snapshots) {
                    let (_, _, cached_size, _) = snapshot.expect("matching snapshot exists");
                    total_size_bytes = total_size_bytes.saturating_add(*cached_size);
                    continue;
                }
                let cached_page_count = snapshot
                    .map(|(page_count, _, _, _)| *page_count)
                    .unwrap_or(0);
                // Measured lock-free beforehand; the fallback only runs if
                // a caller skipped `measure_changed_sizes`.
                let chapter_size = measured_sizes
                    .get(&chapter.source_path)
                    .copied()
                    .unwrap_or_else(|| {
                        chapter_size_bytes(Path::new(&chapter.source_path), &chapter.source_type)
                    });
                total_size_bytes = total_size_bytes.saturating_add(chapter_size);
                upsert_chapter(
                    &tx,
                    ChapterUpsert {
                        comic_id,
                        title: &chapter.title,
                        chapter_index: chapter.index,
                        source_path: &chapter.source_path,
                        source_type: &chapter.source_type,
                        page_count: cached_page_count.max(0) as usize,
                        date_modified: chapter.modified_at,
                        size_bytes: chapter_size,
                    },
                )?;
            }
            tx.execute(
                "UPDATE comics SET size_bytes = ?1 WHERE id = ?2",
                params![total_size_bytes, comic_id],
            )
            .map_err(|e| format!("failed updating comic size_bytes: {e}"))?;
            (1, chapters.len())
        }
        ScanEntryPlan::Archive {
            title,
            source_path,
            source_type,
            modified_at,
            size_bytes,
        } => {
            let comic_id =
                upsert_comic(&tx, library_id, title, source_path, source_type, *modified_at)?;
            let snapshot = snapshots.get(source_path);
            let unchanged = matches!(
                snapshot,
                Some(&(_, cached_modified_at, _, cached_index))
                    if cached_modified_at == *modified_at && cached_index == 1
            );
            if !unchanged {
                let cached_page_count = snapshot
                    .map(|(page_count, _, _, _)| *page_count)
                    .unwrap_or(0);
                upsert_chapter(
                    &tx,
                    ChapterUpsert {
                        comic_id,
                        title: "Chapter 1",
                        chapter_index: 1,
                        source_path,
                        source_type,
                        page_count: cached_page_count.max(0) as usize,
                        date_modified: *modified_at,
                        size_bytes: *size_bytes,
                    },
                )?;
            }
            tx.execute(
                "UPDATE comics SET size_bytes = ?1 WHERE id = ?2",
                params![*size_bytes, comic_id],
            )
            .map_err(|e| format!("failed updating archive comic size_bytes: {e}"))?;
            (1, 1)
        }
    };
    tx.commit()
        .map_err(|e| format!("failed committing scan transaction: {e}"))?;
    Ok(counts)
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
