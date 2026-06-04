use std::fs;
use std::io::{Cursor, Read};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use walkdir::WalkDir;
use zip::ZipArchive;

const MAX_VARIANT_WIDTH: u32 = 4096;
const MIN_VARIANT_WIDTH: u32 = 320;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SortBy {
    Name,
    FolderDate,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SortDir {
    Asc,
    Desc,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RawComic {
    pub key: String,
    pub title: String,
    pub source_path: String,
    pub source_type: String,
    pub library_path: String,
    pub date_modified: i64,
    pub chapter_count: i64,
    pub read_chapter_count: i64,
    pub in_progress_chapter_count: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RawChapter {
    pub key: String,
    pub title: String,
    pub chapter_index: i64,
    pub source_path: String,
    pub source_type: String,
    pub page_count: i64,
    pub is_read: bool,
    pub last_page: i64,
    pub total_pages: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PageInfo {
    pub index: usize,
    pub name: String,
    pub width: Option<u32>,
    pub height: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ChapterContext {
    pub chapter_id: i64,
    pub comic_id: i64,
    pub comic_source_path: String,
    pub chapter_source_path: String,
    pub comic_title: String,
    pub title: String,
    pub chapter_index: i64,
    pub chapter_position: i64,
    pub chapter_total: i64,
    pub prev_chapter_id: Option<i64>,
    pub prev_chapter_title: Option<String>,
    pub next_chapter_id: Option<i64>,
    pub next_chapter_title: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ReadingProgress {
    pub chapter_id: i64,
    pub last_page: i64,
    pub total_pages: i64,
    pub mode: String,
    pub is_read: bool,
    pub updated_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct OpenChapterPayload {
    pub comic_source_path: String,
    pub chapter_source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SaveProgressPayload {
    pub chapter_id: i64,
    pub last_page: i64,
    pub total_pages: i64,
    pub mode: String,
    pub is_read: bool,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum ImageVariantProfile {
    Performance,
    Balanced,
    Quality,
}

impl ImageVariantProfile {
    fn jpeg_quality(self) -> u8 {
        match self {
            Self::Performance => 78,
            Self::Balanced => 82,
            Self::Quality => 88,
        }
    }

    fn filter(self) -> image::imageops::FilterType {
        match self {
            Self::Performance => image::imageops::FilterType::Nearest,
            Self::Balanced => image::imageops::FilterType::Triangle,
            Self::Quality => image::imageops::FilterType::CatmullRom,
        }
    }

    fn resize_threshold(self, source_mime: &'static str) -> (u32, u32) {
        if source_mime == "image/jpeg" || source_mime == "image/webp" {
            return match self {
                Self::Performance => (3, 2),
                Self::Balanced => (4, 3),
                Self::Quality => (6, 5),
            };
        }
        match self {
            Self::Performance => (6, 5),
            Self::Balanced => (6, 5),
            Self::Quality => (11, 10),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RenderPagePayload {
    pub chapter_id: i64,
    pub page_index: usize,
    pub target_width: Option<u32>,
    pub profile: ImageVariantProfile,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RenderedPage {
    pub bytes: Vec<u8>,
    pub mime: String,
    pub width: u32,
    pub height: u32,
    pub cache_key: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct LibrarySourceStatus {
    pub configured: bool,
    pub path: String,
    pub exists: bool,
    pub is_dir: bool,
    pub readable: bool,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SettingEntry {
    pub key: String,
    pub value_json: String,
    pub updated_at: i64,
}

pub struct ComicRdCore {
    db_path: PathBuf,
    conn: Mutex<Connection>,
}

impl ComicRdCore {
    pub fn open(app_data_dir: impl AsRef<Path>) -> Result<Self, String> {
        let app_data_dir = app_data_dir.as_ref();
        fs::create_dir_all(app_data_dir)
            .map_err(|e| format!("failed creating app data dir: {e}"))?;
        let db_path = app_data_dir.join("comicrd.db");
        let conn = Connection::open(&db_path).map_err(|e| format!("failed opening db: {e}"))?;
        conn.execute_batch(
            "PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON; PRAGMA synchronous = NORMAL;",
        )
        .map_err(|e| format!("failed enabling pragmas: {e}"))?;
        run_migrations(&conn)?;

        Ok(Self {
            db_path,
            conn: Mutex::new(conn),
        })
    }

    pub fn db_path(&self) -> &Path {
        &self.db_path
    }

    pub fn list_settings(&self) -> Result<Vec<SettingEntry>, String> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        list_settings_conn(&conn)
    }

    pub fn get_setting(&self, key: &str) -> Result<Option<String>, String> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        get_setting_conn(&conn, key)
    }

    pub fn set_setting(&self, key: &str, value_json: &str) -> Result<(), String> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        set_setting_conn(&conn, key, value_json)
    }

    pub fn check_library_source(&self) -> Result<LibrarySourceStatus, String> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        let path = get_library_source_setting(&conn).unwrap_or_default();
        Ok(library_source_status_for(&path))
    }

    pub fn list_library_comics_raw(
        &self,
        sort_by: SortBy,
        sort_dir: SortDir,
    ) -> Result<Vec<RawComic>, String> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        list_library_comics_raw_conn(&conn, sort_by, sort_dir)
    }

    pub fn list_comic_chapters_raw(
        &self,
        comic_source_path: &str,
    ) -> Result<Vec<RawChapter>, String> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        list_comic_chapters_raw_conn(&conn, comic_source_path)
    }

    pub fn open_chapter_for_reading(&self, payload: OpenChapterPayload) -> Result<i64, String> {
        let mut conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        open_chapter_for_reading_conn(&mut conn, payload)
    }

    pub fn get_chapter_pages(&self, chapter_id: i64) -> Result<Vec<PageInfo>, String> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        get_chapter_pages_conn(&conn, chapter_id)
    }

    pub fn get_chapter_context(&self, chapter_id: i64) -> Result<Option<ChapterContext>, String> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        get_chapter_context_conn(&conn, chapter_id)
    }

    pub fn save_progress(&self, payload: SaveProgressPayload) -> Result<(), String> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        save_progress_conn(&conn, &payload)
    }

    pub fn get_progress(&self, chapter_id: i64) -> Result<Option<ReadingProgress>, String> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        get_progress_conn(&conn, chapter_id)
    }

    pub fn render_page_variant(&self, payload: RenderPagePayload) -> Result<RenderedPage, String> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        render_page_variant_conn(&conn, payload)
    }
}

fn now_ts() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

fn file_modified_ts(path: &Path) -> i64 {
    fs::metadata(path)
        .ok()
        .and_then(|m| m.modified().ok())
        .and_then(|ts| ts.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_secs() as i64)
        .unwrap_or_else(now_ts)
}

fn run_migrations(conn: &Connection) -> Result<(), String> {
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
        mode TEXT NOT NULL,
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
      "#,
    )
    .map_err(|e| format!("failed creating indexes: {e}"))?;

    let ts = now_ts();
    let defaults = [
        ("default_mode", "\"webtoon\""),
        ("arrow_navigation_enabled", "false"),
        ("default_zoom", "1"),
        ("page_gap", "10"),
        ("library_sort_by", "\"name\""),
        ("library_sort_dir", "\"asc\""),
        ("library_view_mode", "\"library\""),
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

fn list_settings_conn(conn: &Connection) -> Result<Vec<SettingEntry>, String> {
    let mut stmt = conn
        .prepare("SELECT key, value_json, updated_at FROM app_settings ORDER BY key")
        .map_err(|e| format!("failed preparing settings query: {e}"))?;
    let rows = stmt
        .query_map([], |row| {
            Ok(SettingEntry {
                key: row.get(0)?,
                value_json: row.get(1)?,
                updated_at: row.get(2)?,
            })
        })
        .map_err(|e| format!("failed querying settings: {e}"))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("failed collecting settings: {e}"))
}

fn get_setting_conn(conn: &Connection, key: &str) -> Result<Option<String>, String> {
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

fn set_setting_conn(conn: &Connection, key: &str, value_json: &str) -> Result<(), String> {
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

fn get_library_source_setting(conn: &Connection) -> Result<String, String> {
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

fn library_source_status_for(path: &str) -> LibrarySourceStatus {
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

fn ext_eq(path: &Path, target: &str) -> bool {
    path.extension()
        .and_then(|v| v.to_str())
        .map(|e| e.eq_ignore_ascii_case(target))
        .unwrap_or(false)
}

fn is_archive(path: &Path) -> bool {
    ext_eq(path, "zip") || ext_eq(path, "cbz")
}

fn source_type_for_path(path: &Path) -> String {
    if path.is_dir() {
        return "folder".to_string();
    }
    path.extension()
        .and_then(|v| v.to_str())
        .map(|v| v.to_ascii_lowercase())
        .unwrap_or_else(|| "zip".to_string())
}

fn normalize_slashes(value: &str) -> String {
    value.replace('\\', "/")
}

fn relative_history_path(library_path: &str, target_path: &str) -> String {
    let base = Path::new(library_path);
    let target = Path::new(target_path);
    if let Ok(rel) = target.strip_prefix(base) {
        return normalize_slashes(rel.to_string_lossy().as_ref());
    }
    normalize_slashes(target_path)
}

fn comic_history_key(library_path: &str, comic_source_path: &str) -> String {
    format!(
        "comic/{}",
        relative_history_path(library_path, comic_source_path)
    )
}

fn chapter_history_key(
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

fn upsert_comic(
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

struct ChapterUpsert<'a> {
    comic_id: i64,
    title: &'a str,
    chapter_index: i64,
    history_key: &'a str,
    source_path: &'a str,
    source_type: &'a str,
    page_count: usize,
    date_modified: i64,
}

fn upsert_chapter(conn: &Connection, params: ChapterUpsert<'_>) -> Result<i64, String> {
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

fn chapter_snapshot_by_history_key(
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

fn comic_title_for_path(path: &Path) -> String {
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

fn is_image(path: &Path) -> bool {
    ext_eq(path, "jpg")
        || ext_eq(path, "jpeg")
        || ext_eq(path, "png")
        || ext_eq(path, "webp")
        || ext_eq(path, "gif")
        || ext_eq(path, "bmp")
        || ext_eq(path, "avif")
}

fn archive_image_entries(path: &Path) -> Result<Vec<String>, String> {
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

fn image_entries_in_dir(path: &Path) -> Vec<PathBuf> {
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

fn natural_compare(a: &str, b: &str) -> std::cmp::Ordering {
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

fn discover_chapter_entries_from_comic_dir(comic_dir: &Path) -> Vec<(String, String, String, i64)> {
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
            let images = image_entries_in_dir(&child);
            if !images.is_empty() {
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

            let mut nested_archives = WalkDir::new(&child)
                .min_depth(1)
                .max_depth(1)
                .into_iter()
                .filter_map(|e| e.ok())
                .map(|e| e.into_path())
                .filter(|p| p.is_file() && is_archive(p))
                .collect::<Vec<_>>();
            nested_archives.sort();
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

fn discover_chapter_entries_for_comic(
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

fn list_library_comics_raw_conn(
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

fn list_comic_chapters_raw_conn(
    conn: &Connection,
    comic_source_path: &str,
) -> Result<Vec<RawChapter>, String> {
    let library_path = get_library_source_setting(conn)?;
    let discovered = discover_chapter_entries_for_comic(comic_source_path)?;
    let mut out = Vec::with_capacity(discovered.len());

    for (chapter_title, chapter_path, _chapter_type, chapter_index) in discovered {
        let chapter_key = chapter_history_key(&library_path, &chapter_path, chapter_index);
        let progress = conn
            .query_row(
                r#"
        SELECT c.page_count,
               COALESCE(r.is_read, 0),
               COALESCE(r.last_page, 0),
               COALESCE(r.total_pages, c.page_count)
        FROM chapters c
        LEFT JOIN reading_progress r ON r.chapter_id = c.id
        WHERE c.history_key = ?1
        LIMIT 1
        "#,
                params![chapter_key],
                |row| {
                    Ok((
                        row.get::<_, i64>(0)?,
                        row.get::<_, i64>(1)? == 1,
                        row.get::<_, i64>(2)?,
                        row.get::<_, i64>(3)?,
                    ))
                },
            )
            .ok();
        let (page_count, is_read, last_page, total_pages) = progress.unwrap_or((0, false, 0, 0));
        out.push(RawChapter {
            key: chapter_path.clone(),
            title: chapter_title,
            chapter_index,
            source_path: chapter_path.clone(),
            source_type: source_type_for_path(Path::new(&chapter_path)),
            page_count,
            is_read,
            last_page,
            total_pages,
        });
    }
    Ok(out)
}

fn find_library_for_comic(
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

fn open_chapter_for_reading_conn(
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

fn chapter_source(conn: &Connection, chapter_id: i64) -> Result<(String, String), String> {
    conn.query_row(
        "SELECT source_path, source_type FROM chapters WHERE id = ?1",
        params![chapter_id],
        |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)),
    )
    .map_err(|e| format!("failed loading chapter source: {e}"))
}

fn get_chapter_pages_conn(conn: &Connection, chapter_id: i64) -> Result<Vec<PageInfo>, String> {
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
        "zip" | "cbz" => archive_image_entries(Path::new(&source_path))?,
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

fn normalize_variant_width(width: u32) -> Option<u32> {
    if width == 0 {
        return None;
    }
    let clamped = width.clamp(MIN_VARIANT_WIDTH, MAX_VARIANT_WIDTH);
    Some(((clamped + 31) / 64) * 64)
}

fn mime_for_path(path: &Path) -> &'static str {
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

fn read_page_bytes(
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

fn page_dimensions_from_bytes(bytes: &[u8]) -> Option<(u32, u32)> {
    image::ImageReader::new(Cursor::new(bytes))
        .with_guessed_format()
        .ok()?
        .into_dimensions()
        .ok()
}

fn should_resize_page(
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

fn resize_page_bytes(
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

fn render_page_variant_conn(
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

fn get_chapter_context_conn(
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

fn save_progress_conn(conn: &Connection, payload: &SaveProgressPayload) -> Result<(), String> {
    let ts = now_ts();
    conn.execute(
        r#"
      INSERT INTO reading_progress (chapter_id, last_page, total_pages, mode, is_read, updated_at)
      VALUES (?1, ?2, ?3, ?4, ?5, ?6)
      ON CONFLICT(chapter_id) DO UPDATE SET
        last_page=excluded.last_page,
        total_pages=excluded.total_pages,
        mode=excluded.mode,
        is_read=excluded.is_read,
        updated_at=excluded.updated_at
      "#,
        params![
            payload.chapter_id,
            payload.last_page,
            payload.total_pages,
            &payload.mode,
            if payload.is_read { 1 } else { 0 },
            ts
        ],
    )
    .map_err(|e| format!("failed saving progress: {e}"))?;
    Ok(())
}

fn get_progress_conn(
    conn: &Connection,
    chapter_id: i64,
) -> Result<Option<ReadingProgress>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT chapter_id, last_page, total_pages, mode, is_read, updated_at FROM reading_progress WHERE chapter_id = ?1",
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
            mode: row
                .get(3)
                .map_err(|e| format!("invalid progress row: {e}"))?,
            is_read: row
                .get::<_, i64>(4)
                .map_err(|e| format!("invalid progress row: {e}"))?
                == 1,
            updated_at: row
                .get(5)
                .map_err(|e| format!("invalid progress row: {e}"))?,
        }));
    }
    Ok(None)
}
