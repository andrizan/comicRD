use ahash::AHashMap;
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::{Arc, LazyLock, Mutex, OnceLock, RwLock};
use std::thread;
use std::time::{SystemTime, UNIX_EPOCH};

use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use tauri::AppHandle;
use tauri::Manager;
use walkdir::WalkDir;
use zip::ZipArchive;

#[derive(Debug, Serialize)]
struct Library {
    id: i64,
    path: String,
    created_at: i64,
    updated_at: i64,
}

#[derive(Debug, Serialize)]
struct Comic {
    id: i64,
    library_id: i64,
    title: String,
    source_path: String,
    source_type: String,
    date_modified: i64,
    updated_at: i64,
    chapter_count: i64,
    read_chapter_count: i64,
    in_progress_chapter_count: i64,
}

#[derive(Debug, Serialize)]
struct RawComic {
    key: String,
    title: String,
    source_path: String,
    source_type: String,
    library_path: String,
    date_modified: i64,
    chapter_count: i64,
    read_chapter_count: i64,
    in_progress_chapter_count: i64,
}

#[derive(Debug, Serialize)]
struct Chapter {
    id: i64,
    comic_id: i64,
    title: String,
    chapter_index: i64,
    page_count: i64,
    source_path: String,
    source_type: String,
    is_read: bool,
    last_page: i64,
    total_pages: i64,
}

#[derive(Debug, Serialize)]
struct RawChapter {
    key: String,
    title: String,
    chapter_index: i64,
    source_path: String,
    source_type: String,
    page_count: i64,
    is_read: bool,
    last_page: i64,
    total_pages: i64,
}

#[derive(Debug, Serialize)]
struct ChapterContext {
    chapter_id: i64,
    comic_id: i64,
    comic_source_path: String,
    chapter_source_path: String,
    comic_title: String,
    title: String,
    chapter_index: i64,
    chapter_position: i64,
    chapter_total: i64,
    prev_chapter_id: Option<i64>,
    prev_chapter_title: Option<String>,
    next_chapter_id: Option<i64>,
    next_chapter_title: Option<String>,
}

#[derive(Debug, Serialize)]
struct PageInfo {
    index: usize,
    name: String,
}

#[derive(Debug, Serialize)]
struct ReadingProgress {
    chapter_id: i64,
    last_page: i64,
    total_pages: i64,
    mode: String,
    is_read: bool,
    updated_at: i64,
}

#[derive(Debug, Serialize)]
struct Bookmark {
    id: i64,
    chapter_id: i64,
    page: i64,
    created_at: i64,
    note: String,
}

#[derive(Debug, Serialize)]
struct ComicBookmark {
    id: i64,
    comic_source_path: String,
    comic_title: String,
    created_at: i64,
}

#[derive(Debug, Serialize)]
struct ReadingHistoryEntry {
    comic_source_path: String,
    comic_title: String,
    chapter_title: String,
    chapter_source_path: String,
    chapter_id: i64,
    last_page: i64,
    total_pages: i64,
    is_read: bool,
    updated_at: i64,
}

#[derive(Debug, Serialize)]
struct SettingEntry {
    key: String,
    value_json: String,
    updated_at: i64,
}

#[derive(Debug, Serialize, Clone)]
struct ScanSummary {
    comics: usize,
    chapters: usize,
}

#[derive(Debug, Serialize, Clone)]
struct LibrarySourceStatus {
    configured: bool,
    path: String,
    exists: bool,
    is_dir: bool,
    readable: bool,
    error: Option<String>,
}

#[derive(Debug, Serialize, Clone)]
struct LibraryScanStatus {
    running: bool,
    started_at: Option<i64>,
    finished_at: Option<i64>,
    last_summary: Option<ScanSummary>,
    error: Option<String>,
}

#[derive(Debug, Default)]
struct LibraryScanState {
    running: bool,
    started_at: Option<i64>,
    finished_at: Option<i64>,
    last_summary: Option<ScanSummary>,
    error: Option<String>,
}

#[derive(Clone)]
enum ChapterSource {
    Folder(Arc<Vec<PathBuf>>),
    Archive(Arc<ChapterArchive>),
}

struct ChapterArchive {
    #[allow(dead_code)]
    source_path: PathBuf,
    pages: Arc<Vec<String>>,
    archive: Mutex<ZipArchive<std::fs::File>>,
}

const PAGE_BYTES_CACHE_CAP: usize = 512;

type CachedPageBytes = (Arc<Vec<u8>>, &'static str);

struct PageCache {
    by_chapter: AHashMap<i64, ChapterSource>,
    bytes: Mutex<lru::LruCache<(i64, usize), CachedPageBytes>>,
}

impl Default for PageCache {
    fn default() -> Self {
        Self {
            by_chapter: AHashMap::new(),
            bytes: Mutex::new(lru::LruCache::new(
                std::num::NonZeroUsize::new(PAGE_BYTES_CACHE_CAP).expect("cap > 0"),
            )),
        }
    }
}

static DB_CONN: OnceLock<Mutex<Connection>> = OnceLock::new();
static PAGE_CACHE: OnceLock<RwLock<PageCache>> = OnceLock::new();

#[derive(Debug, Deserialize)]
struct SaveProgressPayload {
    chapter_id: i64,
    last_page: i64,
    total_pages: i64,
    mode: String,
    is_read: bool,
}

#[derive(Debug, Deserialize)]
struct SaveBookmarkPayload {
    chapter_id: i64,
    page: i64,
    note: Option<String>,
}

#[derive(Debug, Deserialize)]
struct OpenChapterPayload {
    comic_source_path: String,
    chapter_source_path: String,
}

static LIBRARY_SCAN_STATE: LazyLock<Mutex<LibraryScanState>> =
    LazyLock::new(|| Mutex::new(LibraryScanState::default()));

fn current_scan_status() -> LibraryScanStatus {
    match LIBRARY_SCAN_STATE.lock() {
        Ok(state) => LibraryScanStatus {
            running: state.running,
            started_at: state.started_at,
            finished_at: state.finished_at,
            last_summary: state.last_summary.clone(),
            error: state.error.clone(),
        },
        Err(_) => LibraryScanStatus {
            running: false,
            started_at: None,
            finished_at: None,
            last_summary: None,
            error: Some("scan state lock poisoned".to_string()),
        },
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

fn db_path(app: &AppHandle) -> Result<PathBuf, String> {
    let app_dir = app
        .path()
        .app_data_dir()
        .map_err(|e| format!("failed resolving app data dir: {e}"))?;
    fs::create_dir_all(&app_dir).map_err(|e| format!("failed creating app data dir: {e}"))?;
    Ok(app_dir.join("comicrd.db"))
}

fn initialize_db(app: &AppHandle) -> Result<(), String> {
    let conn = Connection::open(db_path(app)?).map_err(|e| format!("failed opening db: {e}"))?;
    conn.execute_batch(
        "PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON; PRAGMA synchronous = NORMAL;",
    )
    .map_err(|e| format!("failed enabling pragmas: {e}"))?;
    run_migrations(&conn)?;
    DB_CONN
        .set(Mutex::new(conn))
        .map_err(|_| "db already initialized".to_string())?;
    PAGE_CACHE
        .set(RwLock::new(PageCache::default()))
        .map_err(|_| "page cache already initialized".to_string())?;
    Ok(())
}

fn get_conn<'a>(
    _app: &'a AppHandle,
) -> Result<std::sync::MutexGuard<'a, Connection>, String> {
    DB_CONN
        .get()
        .ok_or_else(|| "db not initialized".to_string())?
        .lock()
        .map_err(|_| "db lock poisoned".to_string())
}

fn page_cache_read<'a>(
    _app: &'a AppHandle,
) -> Result<std::sync::RwLockReadGuard<'a, PageCache>, String> {
    PAGE_CACHE
        .get()
        .ok_or_else(|| "page cache not initialized".to_string())?
        .read()
        .map_err(|_| "page cache lock poisoned".to_string())
}

fn page_cache_write<'a>(
    _app: &'a AppHandle,
) -> Result<std::sync::RwLockWriteGuard<'a, PageCache>, String> {
    PAGE_CACHE
        .get()
        .ok_or_else(|| "page cache not initialized".to_string())?
        .write()
        .map_err(|_| "page cache write lock poisoned".to_string())
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
        ("library_view_mode", "\"all\""),
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

fn ext_eq(path: &Path, target: &str) -> bool {
    path.extension()
        .and_then(|v| v.to_str())
        .map(|e| e.eq_ignore_ascii_case(target))
        .unwrap_or(false)
}

fn is_archive(path: &Path) -> bool {
    ext_eq(path, "zip") || ext_eq(path, "cbz")
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

fn open_chapter_archive(path: &Path) -> Result<ChapterArchive, String> {
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
    Ok(ChapterArchive {
        source_path: path.to_path_buf(),
        pages: Arc::new(names),
        archive: Mutex::new(archive),
    })
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
    if let Ok(id) = conn
        .query_row(
            "SELECT id FROM comics WHERE history_key = ?1 LIMIT 1",
            params![history_key],
            |row| row.get::<_, i64>(0),
        )
    {
        conn
      .execute(
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

    conn
    .execute(
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
    if let Ok(id) = conn
        .query_row(
            "SELECT id FROM chapters WHERE history_key = ?1 LIMIT 1",
            params![params.history_key],
            |row| row.get::<_, i64>(0),
        )
    {
        conn
      .execute(
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

    conn
    .execute(
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

fn get_library_source_setting(conn: &Connection) -> Result<String, String> {
    let raw: Option<String> = conn
        .query_row(
            "SELECT value_json FROM app_settings WHERE key = 'library_source_input' LIMIT 1",
            [],
            |row| row.get::<_, String>(0),
        )
        .ok();
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
        Some(format!("path '{path}' is not readable (permission denied)."))
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

#[tauri::command]
fn check_library_source(app: AppHandle) -> Result<LibrarySourceStatus, String> {
    let conn = get_conn(&app)?;
    let path = get_library_source_setting(&conn).unwrap_or_default();
    Ok(library_source_status_for(&path))
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
                        a_num.push(a_chars.next().unwrap());
                    }
                    while b_chars.peek().is_some_and(|c| c.is_ascii_digit()) {
                        b_num.push(b_chars.next().unwrap());
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
    let mut chapter_entries: Vec<(String, String, String, i64)> = Vec::new();
    let mut chapter_index = 1i64;

    let root_images = image_entries_in_dir(comic_dir);
    if !root_images.is_empty() {
        chapter_entries.push((
            "Chapter 1".to_string(),
            source_path,
            "folder".to_string(),
            chapter_index,
        ));
        chapter_index += 1;
    }

    let mut dirs = WalkDir::new(comic_dir)
        .min_depth(1)
        .max_depth(1)
        .into_iter()
        .filter_map(|e| e.ok())
        .map(|e| e.into_path())
        .collect::<Vec<_>>();
    dirs.sort_by(|a, b| {
        let a_name = a.file_name().and_then(|v| v.to_str()).unwrap_or("");
        let b_name = b.file_name().and_then(|v| v.to_str()).unwrap_or("");
        natural_compare(a_name, b_name)
    });

    for child in dirs {
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

fn scan_comic_dir(
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

#[tauri::command]
fn init_db(app: AppHandle) -> Result<(), String> {
    let _conn = get_conn(&app)?;
    Ok(())
}

#[tauri::command]
fn add_library(app: AppHandle, path: String) -> Result<i64, String> {
    let conn = get_conn(&app)?;
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

#[tauri::command]
fn list_libraries(app: AppHandle) -> Result<Vec<Library>, String> {
    let conn = get_conn(&app)?;
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

#[tauri::command]
fn scan_libraries(app: AppHandle) -> Result<ScanSummary, String> {
    let mut conn = get_conn(&app)?;
    scan_libraries_conn(&mut conn)
}

fn scan_libraries_conn(conn: &mut Connection) -> Result<ScanSummary, String> {
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
                let title = entry
                    .file_stem()
                    .and_then(|v| v.to_str())
                    .unwrap_or("Untitled")
                    .to_string();
                let source_type = entry
                    .extension()
                    .and_then(|v| v.to_str())
                    .map(|v| v.to_ascii_lowercase())
                    .unwrap_or_else(|| "zip".to_string());
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

#[tauri::command]
fn start_scan_libraries(app: AppHandle) -> Result<bool, String> {
    {
        let mut state = LIBRARY_SCAN_STATE
            .lock()
            .map_err(|_| "failed locking scan state".to_string())?;
        if state.running {
            return Ok(false);
        }
        state.running = true;
        state.started_at = Some(now_ts());
        state.finished_at = None;
        state.error = None;
    }

    let app_handle = app.clone();
    thread::spawn(move || {
        let result = get_conn(&app_handle).and_then(|mut conn| scan_libraries_conn(&mut conn));
        if let Ok(mut state) = LIBRARY_SCAN_STATE.lock() {
            state.running = false;
            state.finished_at = Some(now_ts());
            match result {
                Ok(summary) => {
                    state.last_summary = Some(summary);
                    state.error = None;
                }
                Err(err) => {
                    state.error = Some(err);
                }
            }
        }
    });

    Ok(true)
}

#[tauri::command]
fn get_library_scan_status() -> LibraryScanStatus {
    current_scan_status()
}

#[tauri::command]
fn list_comics(
    app: AppHandle,
    sort_by: Option<String>,
    sort_dir: Option<String>,
) -> Result<Vec<Comic>, String> {
    let conn = get_conn(&app)?;
    let order_field = match sort_by.unwrap_or_else(|| "name".to_string()).as_str() {
        "folder_date" => "c.date_modified",
        _ => "c.title COLLATE NOCASE",
    };
    let order_dir = match sort_dir
        .unwrap_or_else(|| "asc".to_string())
        .to_lowercase()
        .as_str()
    {
        "desc" => "DESC",
        _ => "ASC",
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

fn list_library_comics_raw_sync(
    app: AppHandle,
    sort_by: Option<String>,
    sort_dir: Option<String>,
) -> Result<Vec<RawComic>, String> {
    let conn = get_conn(&app)?;
    let library_path = get_library_source_setting(&conn)?;
    let base = Path::new(&library_path);
    if !base.exists() || !base.is_dir() {
        return Ok(Vec::new());
    }

    let mut comics: Vec<RawComic> = Vec::new();
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

    let order_by = sort_by.unwrap_or_else(|| "name".to_string());
    let desc = sort_dir
        .unwrap_or_else(|| "asc".to_string())
        .eq_ignore_ascii_case("desc");
    comics.sort_by(|a, b| {
        let ord = if order_by == "folder_date" {
            a.date_modified.cmp(&b.date_modified)
        } else {
            a.title.to_lowercase().cmp(&b.title.to_lowercase())
        };
        if desc {
            ord.reverse()
        } else {
            ord
        }
    });
    Ok(comics)
}

#[tauri::command]
async fn list_library_comics_raw(
    app: AppHandle,
    sort_by: Option<String>,
    sort_dir: Option<String>,
) -> Result<Vec<RawComic>, String> {
    tauri::async_runtime::spawn_blocking(move || {
        list_library_comics_raw_sync(app, sort_by, sort_dir)
    })
    .await
    .map_err(|e| format!("list raw comics task join error: {e}"))?
}

fn list_comic_chapters_raw_sync(
    app: AppHandle,
    comic_source_path: String,
) -> Result<Vec<RawChapter>, String> {
    let conn = get_conn(&app)?;
    let library_path = get_library_source_setting(&conn)?;
    let discovered = discover_chapter_entries_for_comic(&comic_source_path)?;
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

#[tauri::command]
async fn list_comic_chapters_raw(
    app: AppHandle,
    comic_source_path: String,
) -> Result<Vec<RawChapter>, String> {
    tauri::async_runtime::spawn_blocking(move || {
        list_comic_chapters_raw_sync(app, comic_source_path)
    })
    .await
    .map_err(|e| format!("list raw chapters task join error: {e}"))?
}

fn open_chapter_for_reading_sync(
    app: AppHandle,
    payload: OpenChapterPayload,
) -> Result<i64, String> {
    let mut conn = get_conn(&app)?;
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
    let mut selected_chapter_id: Option<i64> = None;
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

#[tauri::command]
async fn open_chapter_for_reading(
    app: AppHandle,
    payload: OpenChapterPayload,
) -> Result<i64, String> {
    tauri::async_runtime::spawn_blocking(move || open_chapter_for_reading_sync(app, payload))
        .await
        .map_err(|e| format!("open chapter task join error: {e}"))?
}

#[tauri::command]
fn list_chapters(app: AppHandle, comic_id: i64) -> Result<Vec<Chapter>, String> {
    let conn = get_conn(&app)?;
    let mut stmt = conn
        .prepare(
            r#"
      SELECT c.id, c.comic_id, c.title, c.chapter_index, c.page_count, c.source_path, c.source_type,
             COALESCE(r.is_read, 0), COALESCE(r.last_page, 0), COALESCE(r.total_pages, c.page_count)
      FROM chapters c
      LEFT JOIN reading_progress r ON r.chapter_id = c.id
      WHERE c.comic_id = ?1
      ORDER BY c.chapter_index ASC, c.title COLLATE NOCASE ASC
      "#,
        )
        .map_err(|e| format!("failed preparing chapters query: {e}"))?;
    let rows = stmt
        .query_map(params![comic_id], |row| {
            Ok(Chapter {
                id: row.get(0)?,
                comic_id: row.get(1)?,
                title: row.get(2)?,
                chapter_index: row.get(3)?,
                page_count: row.get(4)?,
                source_path: row.get(5)?,
                source_type: row.get(6)?,
                is_read: row.get::<_, i64>(7)? == 1,
                last_page: row.get(8)?,
                total_pages: row.get(9)?,
            })
        })
        .map_err(|e| format!("failed querying chapters: {e}"))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("failed collecting chapters: {e}"))
}

#[tauri::command]
fn get_chapter_context(app: AppHandle, chapter_id: i64) -> Result<Option<ChapterContext>, String> {
    let conn = get_conn(&app)?;
    get_chapter_context_conn(&conn, chapter_id)
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
    let (chapter_position, chapter_total, prev_chapter_id, prev_chapter_title, next_chapter_id, next_chapter_title) =
        row;

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

fn chapter_source(conn: &Connection, chapter_id: i64) -> Result<(String, String), String> {
    conn.query_row(
        "SELECT source_path, source_type FROM chapters WHERE id = ?1",
        params![chapter_id],
        |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)),
    )
    .map_err(|e| format!("failed loading chapter source: {e}"))
}

fn compute_chapter_source(
    source_path: &str,
    source_type: &str,
) -> Result<ChapterSource, String> {
    match source_type {
        "folder" => Ok(ChapterSource::Folder(Arc::new(image_entries_in_dir(
            Path::new(source_path),
        )))),
        "zip" | "cbz" => Ok(ChapterSource::Archive(Arc::new(open_chapter_archive(
            Path::new(source_path),
        )?))),
        other => Err(format!("unsupported source type: {other}")),
    }
}

fn get_or_load_page_list(
    app: &AppHandle,
    chapter_id: i64,
) -> Result<ChapterSource, String> {
    if let Some(source) = page_cache_read(app)?.by_chapter.get(&chapter_id).cloned() {
        return Ok(source);
    }

    let (source_path, source_type) = {
        let conn = get_conn(app)?;
        chapter_source(&conn, chapter_id)?
    };
    let source = compute_chapter_source(&source_path, &source_type)?;
    page_cache_write(app)?
        .by_chapter
        .insert(chapter_id, source.clone());
    Ok(source)
}

fn read_page_bytes(
    source: &ChapterSource,
    page_index: usize,
) -> Result<(Vec<u8>, &'static str), String> {
    match source {
        ChapterSource::Folder(pages) => {
            let page_path = pages
                .get(page_index)
                .ok_or_else(|| "page index out of range".to_string())?;
            let bytes = fs::read(page_path)
                .map_err(|e| format!("failed reading image file: {e}"))?;
            Ok((bytes, mime_for_path(page_path)))
        }
        ChapterSource::Archive(arc) => {
            let name = arc
                .pages
                .get(page_index)
                .ok_or_else(|| "page index out of range".to_string())?;
            let mime = mime_for_path(Path::new(name));
            let mut archive = arc
                .archive
                .lock()
                .map_err(|_| "archive lock poisoned".to_string())?;
            let mut entry = archive
                .by_name(name)
                .map_err(|e| format!("failed reading archive entry: {e}"))?;
            let mut bytes = Vec::new();
            entry
                .read_to_end(&mut bytes)
                .map_err(|e| format!("failed extracting image: {e}"))?;
            Ok((bytes, mime))
        }
    }
}

fn load_chapter_page_bytes(
    app: &AppHandle,
    chapter_id: i64,
    page_index: usize,
) -> Result<(Vec<u8>, &'static str), String> {
    if let Some((bytes, mime)) = page_cache_read(app)?
        .bytes
        .lock()
        .map_err(|_| "bytes cache lock poisoned".to_string())?
        .get(&(chapter_id, page_index))
        .cloned()
    {
        return Ok((bytes.as_ref().clone(), mime));
    }
    let source = get_or_load_page_list(app, chapter_id)?;
    let (bytes, mime) = read_page_bytes(&source, page_index)?;
    {
        let cache = page_cache_read(app)?;
        let mut bytes_cache = cache
            .bytes
            .lock()
            .map_err(|_| "bytes cache lock poisoned".to_string())?;
        bytes_cache.put((chapter_id, page_index), (Arc::new(bytes.clone()), mime));
    }
    Ok((bytes, mime))
}

fn simple_text_response(
    status: tauri::http::StatusCode,
    message: &str,
) -> tauri::http::Response<Vec<u8>> {
    tauri::http::Response::builder()
        .status(status)
        .header(
            tauri::http::header::CONTENT_TYPE,
            "text/plain; charset=utf-8",
        )
        .body(message.as_bytes().to_vec())
        .unwrap_or_else(|_| tauri::http::Response::new(Vec::new()))
}

fn comicrd_protocol_response(
    app: &AppHandle,
    request: tauri::http::Request<Vec<u8>>,
) -> tauri::http::Response<Vec<u8>> {
    let path = request.uri().path().trim_start_matches('/');
    let mut parts = path.split('/');
    let Some(resource) = parts.next() else {
        return simple_text_response(tauri::http::StatusCode::BAD_REQUEST, "invalid path");
    };
    if resource != "page" {
        return simple_text_response(tauri::http::StatusCode::NOT_FOUND, "not found");
    }

    let Some(chapter_id_raw) = parts.next() else {
        return simple_text_response(tauri::http::StatusCode::BAD_REQUEST, "missing chapter id");
    };
    let Some(page_index_raw) = parts.next() else {
        return simple_text_response(tauri::http::StatusCode::BAD_REQUEST, "missing page index");
    };

    let Ok(chapter_id) = chapter_id_raw.parse::<i64>() else {
        return simple_text_response(tauri::http::StatusCode::BAD_REQUEST, "invalid chapter id");
    };
    let Ok(page_index) = page_index_raw.parse::<usize>() else {
        return simple_text_response(tauri::http::StatusCode::BAD_REQUEST, "invalid page index");
    };

    match load_chapter_page_bytes(app, chapter_id, page_index) {
        Ok((bytes, mime)) => tauri::http::Response::builder()
            .status(tauri::http::StatusCode::OK)
            .header(tauri::http::header::CONTENT_TYPE, mime)
            .header(tauri::http::header::CACHE_CONTROL, "public, max-age=86400")
            .body(bytes)
            .unwrap_or_else(|_| tauri::http::Response::new(Vec::new())),
        Err(err) => simple_text_response(tauri::http::StatusCode::BAD_REQUEST, err.as_str()),
    }
}

#[tauri::command]
async fn get_chapter_pages(app: AppHandle, chapter_id: i64) -> Result<Vec<PageInfo>, String> {
    tauri::async_runtime::spawn_blocking(move || get_chapter_pages_sync(app, chapter_id))
        .await
        .map_err(|e| format!("chapter page task join error: {e}"))?
}

fn get_chapter_pages_sync(app: AppHandle, chapter_id: i64) -> Result<Vec<PageInfo>, String> {
    let (source_path, source_type) = {
        let conn = get_conn(&app)?;
        chapter_source(&conn, chapter_id)?
    };
    let source = compute_chapter_source(&source_path, &source_type)?;
    let names: Vec<String> = match &source {
        ChapterSource::Folder(paths) => paths
            .iter()
            .map(|p| {
                p.file_name()
                    .and_then(|v| v.to_str())
                    .unwrap_or_default()
                    .to_string()
            })
            .collect(),
        ChapterSource::Archive(arc) => arc.pages.iter().cloned().collect(),
    };
    let page_count = names.len() as i64;
    let modified_at = file_modified_ts(Path::new(&source_path));
    {
        let conn = get_conn(&app)?;
        let _ = conn.execute(
            "UPDATE chapters SET page_count = ?1, date_modified = ?2, updated_at = ?3 WHERE id = ?4",
            params![page_count, modified_at, now_ts(), chapter_id],
        );
    }
    page_cache_write(&app)?
        .by_chapter
        .insert(chapter_id, source);
    Ok(names
        .into_iter()
        .enumerate()
        .map(|(index, name)| PageInfo { index, name })
        .collect())
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

#[tauri::command]
fn save_progress(app: AppHandle, payload: SaveProgressPayload) -> Result<(), String> {
    let conn = get_conn(&app)?;
    save_progress_conn(&conn, &payload)
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

#[tauri::command]
fn get_progress(app: AppHandle, chapter_id: i64) -> Result<Option<ReadingProgress>, String> {
    let conn = get_conn(&app)?;
    get_progress_conn(&conn, chapter_id)
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

#[tauri::command]
fn add_bookmark(app: AppHandle, payload: SaveBookmarkPayload) -> Result<i64, String> {
    let conn = get_conn(&app)?;
    let ts = now_ts();
    conn.execute(
        "INSERT INTO bookmarks (chapter_id, page, created_at, note) VALUES (?1, ?2, ?3, ?4)",
        params![
            payload.chapter_id,
            payload.page,
            ts,
            payload.note.unwrap_or_default()
        ],
    )
    .map_err(|e| format!("failed creating bookmark: {e}"))?;
    Ok(conn.last_insert_rowid())
}

#[tauri::command]
fn remove_bookmark(app: AppHandle, bookmark_id: i64) -> Result<(), String> {
    let conn = get_conn(&app)?;
    conn.execute("DELETE FROM bookmarks WHERE id = ?1", params![bookmark_id])
        .map_err(|e| format!("failed deleting bookmark: {e}"))?;
    Ok(())
}

#[tauri::command]
fn list_bookmarks(app: AppHandle, chapter_id: i64) -> Result<Vec<Bookmark>, String> {
    let conn = get_conn(&app)?;
    let mut stmt = conn
    .prepare(
      "SELECT id, chapter_id, page, created_at, note FROM bookmarks WHERE chapter_id = ?1 ORDER BY page ASC, created_at DESC",
    )
    .map_err(|e| format!("failed preparing bookmarks query: {e}"))?;
    let rows = stmt
        .query_map(params![chapter_id], |row| {
            Ok(Bookmark {
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

#[tauri::command]
fn list_all_bookmarks(app: AppHandle) -> Result<Vec<ComicBookmark>, String> {
    let conn = get_conn(&app)?;
    let mut stmt = conn
    .prepare(
      r#"
      SELECT cb.id, cb.comic_source_path, COALESCE(c.title, ''), cb.created_at
      FROM comic_bookmarks cb
      LEFT JOIN comics c ON c.source_path = cb.comic_source_path
      ORDER BY cb.created_at DESC
      "#,
    )
    .map_err(|e| format!("failed preparing comic bookmarks query: {e}"))?;
    let rows = stmt
        .query_map([], |row| {
            Ok(ComicBookmark {
                id: row.get(0)?,
                comic_source_path: row.get(1)?,
                comic_title: row.get(2)?,
                created_at: row.get(3)?,
            })
        })
        .map_err(|e| format!("failed querying comic bookmarks: {e}"))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("failed collecting comic bookmarks: {e}"))
}

#[tauri::command]
fn add_comic_bookmark(app: AppHandle, comic_source_path: String) -> Result<i64, String> {
    let conn = get_conn(&app)?;
    let ts = now_ts();
    conn.execute(
        "INSERT OR IGNORE INTO comic_bookmarks (comic_source_path, created_at) VALUES (?1, ?2)",
        params![comic_source_path, ts],
    )
    .map_err(|e| format!("failed adding comic bookmark: {e}"))?;
    Ok(conn.last_insert_rowid())
}

#[tauri::command]
fn remove_comic_bookmark(app: AppHandle, comic_source_path: String) -> Result<(), String> {
    let conn = get_conn(&app)?;
    conn.execute(
        "DELETE FROM comic_bookmarks WHERE comic_source_path = ?1",
        params![comic_source_path],
    )
    .map_err(|e| format!("failed removing comic bookmark: {e}"))?;
    Ok(())
}

#[tauri::command]
fn is_comic_bookmarked(app: AppHandle, comic_source_path: String) -> Result<bool, String> {
    let conn = get_conn(&app)?;
    let exists: bool = conn
        .query_row(
            "SELECT EXISTS(SELECT 1 FROM comic_bookmarks WHERE comic_source_path = ?1)",
            params![comic_source_path],
            |row| row.get(0),
        )
        .map_err(|e| format!("failed checking comic bookmark: {e}"))?;
    Ok(exists)
}

#[tauri::command]
fn add_chapter_favorite(
    app: AppHandle,
    chapter_source_path: String,
    comic_source_path: String,
) -> Result<i64, String> {
    let conn = get_conn(&app)?;
    let ts = now_ts();
    conn.execute(
        "INSERT OR IGNORE INTO chapter_favorites (chapter_source_path, comic_source_path, created_at) VALUES (?1, ?2, ?3)",
        params![chapter_source_path, comic_source_path, ts],
    )
    .map_err(|e| format!("failed adding chapter favorite: {e}"))?;
    Ok(conn.last_insert_rowid())
}

#[tauri::command]
fn remove_chapter_favorite(app: AppHandle, chapter_source_path: String) -> Result<(), String> {
    let conn = get_conn(&app)?;
    conn.execute(
        "DELETE FROM chapter_favorites WHERE chapter_source_path = ?1",
        params![chapter_source_path],
    )
    .map_err(|e| format!("failed removing chapter favorite: {e}"))?;
    Ok(())
}

#[tauri::command]
fn list_chapter_favorites(
    app: AppHandle,
    comic_source_path: String,
) -> Result<Vec<String>, String> {
    let conn = get_conn(&app)?;
    let mut stmt = conn
        .prepare(
            "SELECT chapter_source_path FROM chapter_favorites WHERE comic_source_path = ?1 ORDER BY created_at DESC",
        )
        .map_err(|e| format!("failed preparing list chapter favorites: {e}"))?;
    let rows = stmt
        .query_map(params![comic_source_path], |row| row.get(0))
        .map_err(|e| format!("failed listing chapter favorites: {e}"))?;
    let mut result = Vec::new();
    for row in rows {
        result.push(row.map_err(|e| format!("failed reading chapter favorite row: {e}"))?);
    }
    Ok(result)
}

#[tauri::command]
fn list_reading_history(app: AppHandle) -> Result<Vec<ReadingHistoryEntry>, String> {
    let conn = get_conn(&app)?;
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

#[tauri::command]
fn list_comics_with_progress(app: AppHandle) -> Result<Vec<String>, String> {
    let conn = get_conn(&app)?;
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

#[tauri::command]
fn set_setting(app: AppHandle, key: String, value_json: String) -> Result<(), String> {
    let conn = get_conn(&app)?;
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

#[tauri::command]
fn get_setting(app: AppHandle, key: String) -> Result<Option<String>, String> {
    let conn = get_conn(&app)?;
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

#[tauri::command]
fn list_settings(app: AppHandle) -> Result<Vec<SettingEntry>, String> {
    let conn = get_conn(&app)?;
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

#[tauri::command]
fn export_database_backup(app: AppHandle, output_path: String) -> Result<(), String> {
    let path = output_path.trim();
    if path.is_empty() {
        return Err("output path kosong".to_string());
    }

    let conn = get_conn(&app)?;
    let _ = conn.execute_batch("PRAGMA wal_checkpoint(FULL);");
    drop(conn);

    let source = db_path(&app)?;
    let target = Path::new(path);
    if let Some(parent) = target.parent() {
        fs::create_dir_all(parent).map_err(|e| format!("failed creating backup directory: {e}"))?;
    }
    if target.exists() {
        fs::remove_file(target)
            .map_err(|e| format!("failed replacing existing backup file: {e}"))?;
    }
    fs::copy(&source, target).map_err(|e| format!("failed exporting database backup: {e}"))?;
    Ok(())
}

#[tauri::command]
fn import_database_backup(app: AppHandle, input_path: String) -> Result<(), String> {
    let path = input_path.trim();
    if path.is_empty() {
        return Err("input path kosong".to_string());
    }
    let source = Path::new(path);
    if !source.exists() || !source.is_file() {
        return Err("file backup tidak ditemukan".to_string());
    }

    let target = db_path(&app)?;
    if target.exists() {
        let backup_path = target.with_extension(format!("db.pre-import-{}", now_ts()));
        fs::copy(&target, &backup_path)
            .map_err(|e| format!("failed creating pre-import backup: {e}"))?;
    }

    if target.exists() {
        fs::remove_file(&target).map_err(|e| format!("failed replacing database file: {e}"))?;
    }
    let wal_path = PathBuf::from(format!("{}-wal", target.to_string_lossy()));
    let shm_path = PathBuf::from(format!("{}-shm", target.to_string_lossy()));
    if wal_path.exists() {
        let _ = fs::remove_file(wal_path);
    }
    if shm_path.exists() {
        let _ = fs::remove_file(shm_path);
    }

    fs::copy(source, &target).map_err(|e| format!("failed importing backup file: {e}"))?;
    let verify_conn =
        Connection::open(&target).map_err(|e| format!("failed opening imported db: {e}"))?;
    verify_conn
        .execute_batch("PRAGMA foreign_keys = ON;")
        .map_err(|e| format!("failed validating imported db: {e}"))?;
    run_migrations(&verify_conn)?;
    Ok(())
}

#[tauri::command]
fn open_containing_folder(path: String) -> Result<(), String> {
    let p = std::path::Path::new(&path);
    let dir = if p.is_dir() {
        p.to_path_buf()
    } else {
        p.parent()
            .map(|d| d.to_path_buf())
            .unwrap_or_else(|| std::path::PathBuf::from("."))
    };
    #[cfg(target_os = "linux")]
    {
        std::process::Command::new("xdg-open")
            .arg(&dir)
            .spawn()
            .map_err(|e| format!("failed to open folder: {e}"))?;
    }
    #[cfg(target_os = "macos")]
    {
        std::process::Command::new("open")
            .arg(&dir)
            .spawn()
            .map_err(|e| format!("failed to open folder: {e}"))?;
    }
    #[cfg(target_os = "windows")]
    {
        std::process::Command::new("explorer")
            .arg(&dir)
            .spawn()
            .map_err(|e| format!("failed to open folder: {e}"))?;
    }
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .register_uri_scheme_protocol("comicrd", |ctx, request| {
            comicrd_protocol_response(ctx.app_handle(), request)
        })
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            if cfg!(debug_assertions) {
                app.handle().plugin(
                    tauri_plugin_log::Builder::default()
                        .level(log::LevelFilter::Info)
                        .build(),
                )?;
            }
            initialize_db(app.handle())?;
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            init_db,
            add_library,
            list_libraries,
            scan_libraries,
            start_scan_libraries,
            get_library_scan_status,
            check_library_source,
            list_comics,
            list_library_comics_raw,
            list_chapters,
            list_comic_chapters_raw,
            open_chapter_for_reading,
            get_chapter_context,
            get_chapter_pages,
            save_progress,
            get_progress,
            add_bookmark,
            remove_bookmark,
            list_bookmarks,
            list_all_bookmarks,
            add_comic_bookmark,
            remove_comic_bookmark,
            is_comic_bookmarked,
            add_chapter_favorite,
            remove_chapter_favorite,
            list_chapter_favorites,
            list_reading_history,
            list_comics_with_progress,
            set_setting,
            get_setting,
            list_settings,
            export_database_backup,
            import_database_backup,
            open_containing_folder
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    #[test]
    fn smoke_scan_progress_and_continue_flow() {
        let conn = Connection::open_in_memory().expect("open in memory db");
        run_migrations(&conn).expect("migrations");
        let default_locale: String = conn
            .query_row(
                "SELECT value_json FROM app_settings WHERE key = 'app_locale'",
                [],
                |row| row.get(0),
            )
            .expect("default locale setting");
        assert_eq!(default_locale, "\"en\"");

        let tmp = tempdir().expect("tempdir");
        let library_path = tmp.path().join("library");
        let library_path_str = library_path.to_string_lossy().to_string();
        let comic_path = library_path.join("Comic A");
        let chapter_a = comic_path.join("Chapter 001");
        let chapter_b = comic_path.join("Chapter 002");
        fs::create_dir_all(&chapter_a).expect("create chapter a");
        fs::create_dir_all(&chapter_b).expect("create chapter b");

        create_test_png(chapter_a.join("001.png"));
        create_test_png(chapter_a.join("002.png"));
        create_test_png(chapter_b.join("001.png"));

        let ts = now_ts();
        conn.execute(
            "INSERT INTO libraries (path, created_at, updated_at) VALUES (?1, ?2, ?3)",
            params![library_path_str, ts, ts],
        )
        .expect("insert library");
        let library_id = conn.last_insert_rowid();

        let (comic_count, chapter_count) =
            scan_comic_dir(&conn, library_id, &library_path_str, &comic_path).expect("scan comic");
        assert_eq!(comic_count, 1);
        assert_eq!(chapter_count, 2);

        let chapter_id: i64 = conn
            .query_row(
                "SELECT id FROM chapters ORDER BY chapter_index ASC LIMIT 1",
                [],
                |row| row.get(0),
            )
            .expect("find chapter");
        let page_count: i64 = conn
            .query_row(
                "SELECT page_count FROM chapters WHERE id = ?1",
                params![chapter_id],
                |row| row.get(0),
            )
            .expect("find page count");
        assert_eq!(page_count, 0);

        save_progress_conn(
            &conn,
            &SaveProgressPayload {
                chapter_id,
                last_page: 1,
                total_pages: 2,
                mode: "webtoon".to_string(),
                is_read: false,
            },
        )
        .expect("save progress");
        let progress = get_progress_conn(&conn, chapter_id)
            .expect("load progress")
            .expect("progress exists");
        assert_eq!(progress.last_page, 1);
        assert!(!progress.is_read);

        save_progress_conn(
            &conn,
            &SaveProgressPayload {
                chapter_id,
                last_page: 1,
                total_pages: 2,
                mode: "webtoon".to_string(),
                is_read: true,
            },
        )
        .expect("save final progress");
        let final_progress = get_progress_conn(&conn, chapter_id)
            .expect("load final progress")
            .expect("final progress exists");
        assert!(final_progress.is_read);
        assert_eq!(final_progress.total_pages, 2);
    }

    fn create_test_png(path: std::path::PathBuf) {
        let mut img = image::RgbaImage::new(8, 8);
        for y in 0..8 {
            for x in 0..8 {
                img.put_pixel(x, y, image::Rgba([((x + y) * 8) as u8, 120, 200, 255]));
            }
        }
        img.save(path).expect("save test png");
    }

    #[test]
    fn page_bytes_reader_serves_sorted_folder_images() {
        let tmp = tempdir().expect("tempdir");
        create_test_png(tmp.path().join("002.png"));
        create_test_png(tmp.path().join("001.png"));

        let entries = image_entries_in_dir(tmp.path());
        let names = entries
            .iter()
            .map(|path| path.file_name().unwrap().to_string_lossy().to_string())
            .collect::<Vec<_>>();
        assert_eq!(names, vec!["001.png", "002.png"]);

        let source = ChapterSource::Folder(Arc::new(entries));
        let (bytes, mime) = read_page_bytes(&source, 0).expect("read first page");
        assert_eq!(mime, "image/png");
        assert!(!bytes.is_empty());
        assert!(read_page_bytes(&source, 2).is_err());
    }

    #[test]
    fn smoke_chapter_context_window_sql() {
        let conn = Connection::open_in_memory().expect("open");
        run_migrations(&conn).expect("migrations");
        let ts = now_ts();
        conn.execute(
            "INSERT INTO libraries (path, created_at, updated_at) VALUES (?1, ?2, ?3)",
            params!["/lib", ts, ts],
        )
        .expect("lib");
        let lib_id = conn.last_insert_rowid();
        conn.execute(
            "INSERT INTO comics (library_id, title, history_key, source_path, source_type, created_at, updated_at, date_modified)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            params![lib_id, "Comic", "hk", "/comic", "folder", ts, ts, ts],
        )
        .expect("comic");
        let comic_id = conn.last_insert_rowid();
        for i in 1..=5 {
            conn.execute(
                "INSERT INTO chapters (comic_id, title, chapter_index, history_key, source_path, source_type, page_count, created_at, updated_at, date_modified)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
                params![comic_id, format!("Ch{}", i), i, format!("hk{}", i), format!("/ch{}", i), "folder", 10, ts, ts, ts],
            )
            .expect("chapter");
        }
        let chapter_id: i64 = conn
            .query_row("SELECT id FROM chapters WHERE chapter_index = 3", [], |r| r.get(0))
            .expect("find chapter 3");
        let ctx = get_chapter_context_conn(&conn, chapter_id).expect("get ctx").expect("ctx exists");
        assert_eq!(ctx.chapter_total, 5);
        assert_eq!(ctx.chapter_position, 3);
        assert!(ctx.prev_chapter_id.is_some());
        assert!(ctx.next_chapter_id.is_some());
    }

    #[test]
    fn library_source_status_unconfigured() {
        let status = library_source_status_for("");
        assert!(!status.configured);
        assert_eq!(status.path, "");
        assert!(!status.exists);
        assert!(!status.is_dir);
        assert!(!status.readable);
        assert!(status.error.is_none());
    }

    #[test]
    fn library_source_status_valid_dir() {
        let dir = tempdir().expect("tempdir");
        let status = library_source_status_for(dir.path().to_str().unwrap());
        assert!(status.configured);
        assert!(status.exists);
        assert!(status.is_dir);
        assert!(status.readable);
        assert!(status.error.is_none());
    }

    #[test]
    fn library_source_status_nonexistent() {
        let dir = tempdir().expect("tempdir");
        let bogus = dir.path().join("definitely-not-mounted");
        let status = library_source_status_for(bogus.to_str().unwrap());
        assert!(status.configured);
        assert!(!status.exists);
        assert!(!status.is_dir);
        assert!(!status.readable);
        let err = status.error.expect("error must be set");
        assert!(err.contains("not found"), "got: {err}");
        assert!(err.contains("mount"), "got: {err}");
    }

    #[test]
    fn library_source_status_path_is_file() {
        let dir = tempdir().expect("tempdir");
        let file = dir.path().join("not-a-dir.txt");
        fs::write(&file, b"x").expect("write");
        let status = library_source_status_for(file.to_str().unwrap());
        assert!(status.configured);
        assert!(status.exists);
        assert!(!status.is_dir);
        assert!(!status.readable);
        let err = status.error.expect("error must be set");
        assert!(err.contains("not a directory"), "got: {err}");
    }
}
