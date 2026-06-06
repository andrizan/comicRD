use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use rusqlite::{params, Connection};

use crate::SettingEntry;

pub(crate) fn now_ts() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

pub(crate) fn open_database_file(path: &Path) -> Result<Connection, String> {
    let conn = Connection::open(path).map_err(|e| format!("failed opening db: {e}"))?;
    conn.execute_batch(
        "PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON; PRAGMA synchronous = NORMAL;",
    )
    .map_err(|e| format!("failed enabling pragmas: {e}"))?;
    Ok(conn)
}

pub(crate) fn copy_legacy_database_if_missing(
    app_data_dir: &Path,
    db_path: &Path,
) -> Result<(), String> {
    if db_path.exists() {
        return Ok(());
    }

    let Some(legacy_db) = legacy_database_candidates(app_data_dir)
        .into_iter()
        .find(|path| path.exists() && path.is_file())
    else {
        return Ok(());
    };

    if let Some(parent) = db_path.parent() {
        fs::create_dir_all(parent)
            .map_err(|e| format!("failed creating migrated database directory: {e}"))?;
    }
    remove_sqlite_sidecars(db_path);
    fs::copy(&legacy_db, db_path).map_err(|e| {
        format!(
            "failed copying legacy database from {}: {e}",
            legacy_db.display()
        )
    })?;
    Ok(())
}

fn legacy_database_candidates(app_data_dir: &Path) -> Vec<PathBuf> {
    let mut candidates = Vec::new();
    if !is_flutter_app_data_dir(app_data_dir) {
        return candidates;
    }
    if let Some(parent) = app_data_dir.parent() {
        candidates.push(parent.join("com.andrizan.comicrd").join("comicrd.db"));
        candidates.push(parent.join("com.andrizan.ComicRD").join("comicrd.db"));
    }
    if let Ok(home) = env::var("HOME") {
        let home = PathBuf::from(home);
        candidates.push(
            home.join(".local")
                .join("share")
                .join("com.andrizan.comicrd")
                .join("comicrd.db"),
        );
        candidates.push(
            home.join("Library")
                .join("Application Support")
                .join("com.andrizan.comicrd")
                .join("comicrd.db"),
        );
    }
    if let Ok(app_data) = env::var("APPDATA") {
        candidates.push(
            PathBuf::from(app_data)
                .join("com.andrizan.comicrd")
                .join("comicrd.db"),
        );
    }

    let mut deduped = Vec::new();
    for candidate in candidates {
        if !deduped.iter().any(|existing| existing == &candidate) {
            deduped.push(candidate);
        }
    }
    deduped
}

fn is_flutter_app_data_dir(app_data_dir: &Path) -> bool {
    let Some(name) = app_data_dir.file_name().and_then(|value| value.to_str()) else {
        return false;
    };
    matches!(
        name.to_lowercase().as_str(),
        "comicrd_flutter" | "comicrd" | "comicrd-flutter"
    )
}

pub(crate) fn remove_sqlite_sidecars(db_path: &Path) {
    let wal_path = PathBuf::from(format!("{}-wal", db_path.to_string_lossy()));
    let shm_path = PathBuf::from(format!("{}-shm", db_path.to_string_lossy()));
    if wal_path.exists() {
        let _ = fs::remove_file(wal_path);
    }
    if shm_path.exists() {
        let _ = fs::remove_file(shm_path);
    }
}

pub(crate) fn file_modified_ts(path: &Path) -> i64 {
    fs::metadata(path)
        .ok()
        .and_then(|m| m.modified().ok())
        .and_then(|ts| ts.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_secs() as i64)
        .unwrap_or_else(now_ts)
}

pub(crate) fn run_migrations(conn: &Connection) -> Result<(), String> {
    conn.execute_batch(
        r#"
      CREATE TABLE IF NOT EXISTS libraries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        path TEXT NOT NULL UNIQUE,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );

      CREATE TABLE IF NOT EXISTS comics (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        library_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        history_key TEXT NOT NULL,
        source_path TEXT NOT NULL UNIQUE,
        source_type TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        date_modified INTEGER NOT NULL,
        FOREIGN KEY(library_id) REFERENCES libraries(id) ON DELETE CASCADE
      );

      CREATE TABLE IF NOT EXISTS chapters (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        comic_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        chapter_index INTEGER NOT NULL,
        history_key TEXT NOT NULL,
        source_path TEXT NOT NULL UNIQUE,
        source_type TEXT NOT NULL,
        page_count INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        date_modified INTEGER NOT NULL,
        FOREIGN KEY(comic_id) REFERENCES comics(id) ON DELETE CASCADE
      );

      CREATE TABLE IF NOT EXISTS reading_progress (
        chapter_id INTEGER PRIMARY KEY,
        last_page INTEGER NOT NULL,
        total_pages INTEGER NOT NULL,
        is_read INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(chapter_id) REFERENCES chapters(id) ON DELETE CASCADE
      );

      CREATE TABLE IF NOT EXISTS bookmarks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chapter_id INTEGER NOT NULL,
        page INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        FOREIGN KEY(chapter_id) REFERENCES chapters(id) ON DELETE CASCADE
      );

      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value_json TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      );

      CREATE TABLE IF NOT EXISTS comic_bookmarks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        comic_source_path TEXT NOT NULL UNIQUE,
        created_at INTEGER NOT NULL
      );

      CREATE TABLE IF NOT EXISTS chapter_favorites (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chapter_source_path TEXT NOT NULL UNIQUE,
        comic_source_path TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );

      DROP TABLE IF EXISTS settings;
      "#,
    )
    .map_err(|e| format!("failed running migrations: {e}"))?;

    conn.execute_batch(
        r#"
      CREATE INDEX IF NOT EXISTS idx_chapters_comic_id ON chapters(comic_id);
      CREATE INDEX IF NOT EXISTS idx_chapters_chapter_index ON chapters(chapter_index);
      CREATE INDEX IF NOT EXISTS idx_bookmarks_chapter_id ON bookmarks(chapter_id);
      CREATE INDEX IF NOT EXISTS idx_chapter_favorites_comic ON chapter_favorites(comic_source_path);
      CREATE INDEX IF NOT EXISTS idx_reading_progress_updated_at ON reading_progress(updated_at);
      CREATE INDEX IF NOT EXISTS idx_comics_date_modified ON comics(date_modified);
      CREATE INDEX IF NOT EXISTS idx_libraries_updated_at ON libraries(updated_at);
      CREATE INDEX IF NOT EXISTS idx_comics_history_key ON comics(history_key);
      CREATE INDEX IF NOT EXISTS idx_chapters_history_key ON chapters(history_key);
      "#,
    )
    .map_err(|e| format!("failed creating indexes: {e}"))?;

    let ts = now_ts();
    let defaults = [
        ("arrow_navigation_enabled", "false"),
        ("default_zoom", "1"),
        ("page_gap", "10"),
        ("library_sort_by", "\"name\""),
        ("library_sort_dir", "\"asc\""),
        ("library_view_mode", "\"library\""),
        ("library_display_mode", "\"grid\""),
        ("chapter_sort_by", "\"chapter_index\""),
        ("chapter_sort_dir", "\"asc\""),
        ("image_pipeline_profile", "\"balanced\""),
        ("library_source_input", "\"\""),
        ("app_theme", "\"light\""),
        ("app_locale", "\"en\""),
    ];
    for (key, value_json) in defaults {
        conn.execute(
            "INSERT OR IGNORE INTO app_settings (key, value_json, updated_at) VALUES (?1, ?2, ?3)",
            params![key, value_json, ts],
        )
        .map_err(|e| format!("failed seeding default setting {key}: {e}"))?;
    }
    Ok(())
}

pub(crate) fn list_settings_conn(conn: &Connection) -> Result<Vec<SettingEntry>, String> {
    let mut stmt = conn
        .prepare("SELECT key, value_json FROM app_settings ORDER BY key")
        .map_err(|e| format!("failed preparing settings query: {e}"))?;
    let rows = stmt
        .query_map([], |row| {
            Ok(SettingEntry {
                key: row.get(0)?,
                value_json: row.get(1)?,
            })
        })
        .map_err(|e| format!("failed querying settings: {e}"))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("failed collecting settings: {e}"))
}

pub(crate) fn get_setting_conn(conn: &Connection, key: &str) -> Result<Option<String>, String> {
    let mut stmt = conn
        .prepare("SELECT value_json FROM app_settings WHERE key = ?1")
        .map_err(|e| format!("failed preparing setting query: {e}"))?;
    let mut rows = stmt
        .query(params![key])
        .map_err(|e| format!("failed querying setting: {e}"))?;
    if let Some(row) = rows
        .next()
        .map_err(|e| format!("failed loading setting row: {e}"))?
    {
        return row
            .get::<_, String>(0)
            .map(Some)
            .map_err(|e| format!("invalid setting value: {e}"));
    }
    Ok(None)
}

pub(crate) fn set_setting_conn(
    conn: &Connection,
    key: &str,
    value_json: &str,
) -> Result<(), String> {
    conn.execute(
        r#"
      INSERT INTO app_settings (key, value_json, updated_at)
      VALUES (?1, ?2, ?3)
      ON CONFLICT(key) DO UPDATE SET value_json=excluded.value_json, updated_at=excluded.updated_at
      "#,
        params![key, value_json, now_ts()],
    )
    .map_err(|e| format!("failed upserting setting: {e}"))?;
    Ok(())
}

pub(crate) fn get_library_source_setting(conn: &Connection) -> Result<String, String> {
    let raw = get_setting_conn(conn, "library_source_input")?;
    let Some(raw_value) = raw else {
        return Err("library_source_input belum diset".to_string());
    };
    serde_json::from_str::<String>(&raw_value)
        .map(|v| v.trim().to_string())
        .map_err(|e| format!("library_source_input invalid: {e}"))
        .and_then(|v| {
            if v.is_empty() {
                Err("library_source_input kosong".to_string())
            } else {
                Ok(v)
            }
        })
}
