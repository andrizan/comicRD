use std::path::Path;

use rusqlite::{params, Connection};

use crate::chapter::comic_title_for_path;
use crate::database::now_ts;
use crate::{
    PageBookmark, Favorite, ReadingHistoryEntry, ReadingProgress, SavePageBookmarkPayload,
    SaveProgressPayload,
};

pub(crate) fn save_progress_conn(
    conn: &Connection,
    payload: &SaveProgressPayload,
) -> Result<(), String> {
    let ts = now_ts();
    conn.execute(
        r#"
      INSERT INTO reading_progress (chapter_id, last_page, total_pages, is_read, updated_at)
      VALUES (?1, ?2, ?3, ?4, ?5)
      ON CONFLICT(chapter_id) DO UPDATE SET
        last_page=excluded.last_page,
        total_pages=excluded.total_pages,
        is_read=excluded.is_read,
        updated_at=excluded.updated_at
      "#,
        params![
            payload.chapter_id,
            payload.last_page,
            payload.total_pages,
            if payload.is_read { 1 } else { 0 },
            ts
        ],
    )
    .map_err(|e| format!("failed saving progress: {e}"))?;
    Ok(())
}

pub(crate) fn get_progress_conn(
    conn: &Connection,
    chapter_id: i64,
) -> Result<Option<ReadingProgress>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT chapter_id, last_page, total_pages, is_read FROM reading_progress WHERE chapter_id = ?1",
        )
        .map_err(|e| format!("failed preparing progress query: {e}"))?;
    let mut rows = stmt
        .query(params![chapter_id])
        .map_err(|e| format!("failed querying progress: {e}"))?;
    if let Some(row) = rows
        .next()
        .map_err(|e| format!("failed loading row: {e}"))?
    {
        return Ok(Some(ReadingProgress {
            chapter_id: row
                .get(0)
                .map_err(|e| format!("invalid progress row: {e}"))?,
            last_page: row
                .get(1)
                .map_err(|e| format!("invalid progress row: {e}"))?,
            total_pages: row
                .get(2)
                .map_err(|e| format!("invalid progress row: {e}"))?,
            is_read: row
                .get::<_, i64>(3)
                .map_err(|e| format!("invalid progress row: {e}"))?
                == 1,
        }));
    }
    Ok(None)
}

pub(crate) fn add_page_bookmark_conn(
    conn: &Connection,
    payload: SavePageBookmarkPayload,
) -> Result<i64, String> {
    conn.execute(
        "INSERT INTO page_bookmarks (chapter_id, page, created_at, note) VALUES (?1, ?2, ?3, ?4)",
        params![
            payload.chapter_id,
            payload.page,
            now_ts(),
            payload.note.unwrap_or_default()
        ],
    )
    .map_err(|e| format!("failed creating bookmark: {e}"))?;
    Ok(conn.last_insert_rowid())
}

pub(crate) fn remove_page_bookmark_conn(conn: &Connection, bookmark_id: i64) -> Result<(), String> {
    conn.execute("DELETE FROM page_bookmarks WHERE id = ?1", params![bookmark_id])
        .map_err(|e| format!("failed deleting bookmark: {e}"))?;
    Ok(())
}

pub(crate) fn list_page_bookmarks_conn(
    conn: &Connection,
    chapter_id: i64,
) -> Result<Vec<PageBookmark>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT id, chapter_id, page, created_at, note FROM page_bookmarks WHERE chapter_id = ?1 ORDER BY page ASC, created_at DESC",
        )
        .map_err(|e| format!("failed preparing bookmarks query: {e}"))?;
    let rows = stmt
        .query_map(params![chapter_id], |row| {
            Ok(PageBookmark {
                id: row.get(0)?,
                chapter_id: row.get(1)?,
                page: row.get(2)?,
                created_at: row.get(3)?,
                note: row.get(4)?,
            })
        })
        .map_err(|e| format!("failed querying bookmarks: {e}"))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("failed collecting bookmarks: {e}"))
}

pub(crate) fn list_favorites_conn(conn: &Connection) -> Result<Vec<Favorite>, String> {
    let mut stmt = conn
        .prepare(
            r#"
      SELECT cb.id, cb.comic_source_path, COALESCE(c.title, ''), cb.created_at
      FROM favorites cb
      LEFT JOIN comics c ON c.source_path = cb.comic_source_path
      ORDER BY cb.created_at DESC
      "#,
        )
        .map_err(|e| format!("failed preparing favorites query: {e}"))?;
    let rows = stmt
        .query_map([], |row| {
            Ok(Favorite {
                id: row.get(0)?,
                comic_source_path: row.get(1)?,
                comic_title: row.get(2)?,
                created_at: row.get(3)?,
            })
        })
        .map_err(|e| format!("failed querying favorites: {e}"))?;
    let mut favorites = rows
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("failed collecting favorites: {e}"))?;
    for favorite in &mut favorites {
        if favorite.comic_title.trim().is_empty() {
            favorite.comic_title =
                comic_title_for_path(Path::new(&favorite.comic_source_path));
        }
    }
    Ok(favorites)
}

pub(crate) fn add_favorite_conn(
    conn: &Connection,
    comic_source_path: &str,
) -> Result<i64, String> {
    conn.execute(
        "INSERT OR IGNORE INTO favorites (comic_source_path, created_at) VALUES (?1, ?2)",
        params![comic_source_path, now_ts()],
    )
    .map_err(|e| format!("failed adding favorite: {e}"))?;
    Ok(conn.last_insert_rowid())
}

pub(crate) fn remove_favorite_conn(
    conn: &Connection,
    comic_source_path: &str,
) -> Result<(), String> {
    conn.execute(
        "DELETE FROM favorites WHERE comic_source_path = ?1",
        params![comic_source_path],
    )
    .map_err(|e| format!("failed removing favorite: {e}"))?;
    Ok(())
}

pub(crate) fn is_favorited_conn(
    conn: &Connection,
    comic_source_path: &str,
) -> Result<bool, String> {
    conn.query_row(
        "SELECT EXISTS(SELECT 1 FROM favorites WHERE comic_source_path = ?1)",
        params![comic_source_path],
        |row| row.get(0),
    )
    .map_err(|e| format!("failed checking favorite: {e}"))
}

pub(crate) fn add_bookmark_conn(
    conn: &Connection,
    chapter_source_path: &str,
    comic_source_path: &str,
) -> Result<i64, String> {
    conn.execute(
        "INSERT OR IGNORE INTO bookmarks (chapter_source_path, comic_source_path, created_at) VALUES (?1, ?2, ?3)",
        params![chapter_source_path, comic_source_path, now_ts()],
    )
    .map_err(|e| format!("failed adding bookmark: {e}"))?;
    Ok(conn.last_insert_rowid())
}

pub(crate) fn remove_bookmark_conn(
    conn: &Connection,
    chapter_source_path: &str,
) -> Result<(), String> {
    conn.execute(
        "DELETE FROM bookmarks WHERE chapter_source_path = ?1",
        params![chapter_source_path],
    )
    .map_err(|e| format!("failed removing bookmark: {e}"))?;
    Ok(())
}

pub(crate) fn list_bookmarks_conn(
    conn: &Connection,
    comic_source_path: &str,
) -> Result<Vec<String>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT chapter_source_path FROM bookmarks WHERE comic_source_path = ?1 ORDER BY created_at DESC",
        )
        .map_err(|e| format!("failed preparing list bookmarks: {e}"))?;
    let rows = stmt
        .query_map(params![comic_source_path], |row| row.get(0))
        .map_err(|e| format!("failed listing bookmarks: {e}"))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("failed reading bookmark row: {e}"))
}

pub(crate) fn list_reading_history_conn(
    conn: &Connection,
) -> Result<Vec<ReadingHistoryEntry>, String> {
    let mut stmt = conn
        .prepare(
            r#"
          SELECT
            c.source_path,
            c.title,
            ch.title,
            ch.source_path,
            ch.id,
            r.last_page,
            r.total_pages,
            r.is_read,
            r.updated_at
          FROM reading_progress r
          INNER JOIN chapters ch ON ch.id = r.chapter_id
          INNER JOIN comics c ON c.id = ch.comic_id
          INNER JOIN (
            SELECT ch2.comic_id, MAX(r2.updated_at) AS max_updated
            FROM reading_progress r2
            INNER JOIN chapters ch2 ON ch2.id = r2.chapter_id
            GROUP BY ch2.comic_id
          ) latest ON latest.comic_id = c.id AND latest.max_updated = r.updated_at
          ORDER BY r.updated_at DESC
          "#,
        )
        .map_err(|e| format!("failed preparing reading history query: {e}"))?;
    let rows = stmt
        .query_map([], |row| {
            Ok(ReadingHistoryEntry {
                comic_source_path: row.get(0)?,
                comic_title: row.get(1)?,
                chapter_title: row.get(2)?,
                chapter_source_path: row.get(3)?,
                chapter_id: row.get(4)?,
                last_page: row.get(5)?,
                total_pages: row.get(6)?,
                is_read: row.get::<_, i64>(7)? == 1,
                updated_at: row.get(8)?,
            })
        })
        .map_err(|e| format!("failed querying reading history: {e}"))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("failed collecting reading history: {e}"))
}

pub(crate) fn list_comics_with_progress_conn(conn: &Connection) -> Result<Vec<String>, String> {
    let mut stmt = conn
        .prepare(
            r#"
            SELECT DISTINCT c.source_path
            FROM reading_progress r
            INNER JOIN chapters ch ON ch.id = r.chapter_id
            INNER JOIN comics c ON c.id = ch.comic_id
            "#,
        )
        .map_err(|e| format!("failed preparing comics-with-progress query: {e}"))?;
    let rows = stmt
        .query_map([], |row| row.get::<_, String>(0))
        .map_err(|e| format!("failed querying comics with progress: {e}"))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("failed collecting comics with progress: {e}"))
}
