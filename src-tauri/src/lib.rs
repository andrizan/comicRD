use std::collections::{HashMap, VecDeque};
use std::fs;
use std::io::Cursor;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::{LazyLock, Mutex};
use std::thread;
use std::time::{SystemTime, UNIX_EPOCH};

use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use image::imageops::FilterType;
use image::RgbaImage;
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
struct ChapterContext {
  chapter_id: i64,
  comic_id: i64,
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
struct PageRenderOptions {
  target_width: Option<u32>,
  target_height: Option<u32>,
  interpolation: Option<String>,
}

const THUMBNAIL_CACHE_BUDGET_BYTES: usize = 48 * 1024 * 1024;
const PREVIEW_CACHE_BUDGET_BYTES: usize = 192 * 1024 * 1024;

struct CacheEntry {
  value: String,
  size_bytes: usize,
}

struct RenderCache {
  budget_bytes: usize,
  used_bytes: usize,
  order: VecDeque<String>,
  values: HashMap<String, CacheEntry>,
}

#[derive(Clone, Copy)]
enum RenderCacheKind {
  Thumbnail,
  Preview,
}

impl RenderCache {
  fn new(budget_bytes: usize) -> Self {
    Self {
      budget_bytes,
      used_bytes: 0,
      order: VecDeque::new(),
      values: HashMap::new(),
    }
  }

  fn get(&mut self, key: &str) -> Option<String> {
    if self.values.contains_key(key) {
      let value = self.values.get(key).map(|entry| entry.value.clone());
      self.touch(key);
      return value;
    }
    None
  }

  fn insert(&mut self, key: String, value: String) {
    let new_size = value.len();
    if new_size > self.budget_bytes {
      return;
    }

    if let Some(old) = self.values.remove(&key) {
      self.used_bytes = self.used_bytes.saturating_sub(old.size_bytes);
      self.values.insert(
        key.clone(),
        CacheEntry {
          value,
          size_bytes: new_size,
        },
      );
      self.used_bytes += new_size;
      self.touch(&key);
      self.enforce_budget();
      return;
    }

    self.values.insert(
      key.clone(),
      CacheEntry {
        value,
        size_bytes: new_size,
      },
    );
    self.used_bytes += new_size;
    self.order.push_back(key);
    self.enforce_budget();
  }

  fn touch(&mut self, key: &str) {
    if let Some(pos) = self.order.iter().position(|x| x == key) {
      let _ = self.order.remove(pos);
    }
    self.order.push_back(key.to_string());
  }

  fn enforce_budget(&mut self) {
    while self.used_bytes > self.budget_bytes {
      if let Some(oldest) = self.order.pop_front() {
        if let Some(removed) = self.values.remove(&oldest) {
          self.used_bytes = self.used_bytes.saturating_sub(removed.size_bytes);
        }
      } else {
        break;
      }
    }
  }
}

static THUMBNAIL_RENDER_CACHE: LazyLock<Mutex<RenderCache>> =
  LazyLock::new(|| Mutex::new(RenderCache::new(THUMBNAIL_CACHE_BUDGET_BYTES)));
static PREVIEW_RENDER_CACHE: LazyLock<Mutex<RenderCache>> =
  LazyLock::new(|| Mutex::new(RenderCache::new(PREVIEW_CACHE_BUDGET_BYTES)));
static LIBRARY_SCAN_STATE: LazyLock<Mutex<LibraryScanState>> =
  LazyLock::new(|| Mutex::new(LibraryScanState::default()));

fn cache_kind_for_render_options(options: &PageRenderOptions) -> RenderCacheKind {
  let max_edge = options
    .target_width
    .unwrap_or(0)
    .max(options.target_height.unwrap_or(0));
  if max_edge > 0 && max_edge <= 480 {
    RenderCacheKind::Thumbnail
  } else {
    RenderCacheKind::Preview
  }
}

fn cache_get(kind: RenderCacheKind, key: &str) -> Option<String> {
  match kind {
    RenderCacheKind::Thumbnail => THUMBNAIL_RENDER_CACHE.lock().ok()?.get(key),
    RenderCacheKind::Preview => PREVIEW_RENDER_CACHE.lock().ok()?.get(key),
  }
}

fn cache_insert(kind: RenderCacheKind, key: String, value: String) {
  match kind {
    RenderCacheKind::Thumbnail => {
      if let Ok(mut cache) = THUMBNAIL_RENDER_CACHE.lock() {
        cache.insert(key, value);
      }
    }
    RenderCacheKind::Preview => {
      if let Ok(mut cache) = PREVIEW_RENDER_CACHE.lock() {
        cache.insert(key, value);
      }
    }
  }
}

fn chapter_date_modified(conn: &Connection, chapter_id: i64) -> Result<i64, String> {
  conn
    .query_row(
      "SELECT date_modified FROM chapters WHERE id = ?1",
      params![chapter_id],
      |row| row.get::<_, i64>(0),
    )
    .map_err(|e| format!("failed loading chapter date_modified: {e}"))
}

fn disk_cache_dir(app: &AppHandle, kind: RenderCacheKind) -> Result<PathBuf, String> {
  let app_dir = app
    .path()
    .app_data_dir()
    .map_err(|e| format!("failed resolving app data dir for cache: {e}"))?;
  let dir = match kind {
    RenderCacheKind::Thumbnail => app_dir.join("render-cache").join("thumbnail"),
    RenderCacheKind::Preview => app_dir.join("render-cache").join("preview"),
  };
  fs::create_dir_all(&dir).map_err(|e| format!("failed creating render cache dir: {e}"))?;
  Ok(dir)
}

fn cache_key_file_name(key: &str) -> String {
  let mut out = String::with_capacity(key.len() + 4);
  for ch in key.chars() {
    if ch.is_ascii_alphanumeric() || ch == '-' || ch == '_' {
      out.push(ch);
    } else {
      out.push('_');
    }
  }
  out.push_str(".b64");
  out
}

fn disk_cache_get(app: &AppHandle, kind: RenderCacheKind, key: &str) -> Option<String> {
  let dir = disk_cache_dir(app, kind).ok()?;
  let path = dir.join(cache_key_file_name(key));
  fs::read_to_string(path).ok()
}

fn disk_cache_set(app: &AppHandle, kind: RenderCacheKind, key: &str, value: &str) {
  if let Ok(dir) = disk_cache_dir(app, kind) {
    let path = dir.join(cache_key_file_name(key));
    let _ = fs::write(path, value);
  }
}

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

fn open_conn(app: &AppHandle) -> Result<Connection, String> {
  let conn = Connection::open(db_path(app)?).map_err(|e| format!("failed opening db: {e}"))?;
  conn
    .execute_batch("PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;")
    .map_err(|e| format!("failed enabling pragmas: {e}"))?;
  run_migrations(&conn)?;
  Ok(conn)
}

fn run_migrations(conn: &Connection) -> Result<(), String> {
  conn
    .execute_batch(
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

      DROP TABLE IF EXISTS settings;
      "#,
    )
    .map_err(|e| format!("failed running migrations: {e}"))?;

  let ts = now_ts();
  let defaults = [
    ("default_mode", "\"webtoon\""),
    ("arrow_navigation_enabled", "false"),
    ("smooth_scroll_speed", "1"),
    ("default_zoom", "1"),
    ("page_gap", "8"),
    ("interpolation_method", "\"off\""),
  ];
  for (key, value_json) in defaults {
    conn
      .execute(
        "INSERT OR IGNORE INTO app_settings (key, value_json, updated_at) VALUES (?1, ?2, ?3)",
        params![key, value_json, ts],
      )
      .map_err(|e| format!("failed seeding default setting {key}: {e}"))?;
  }
  Ok(())
}

fn is_archive(path: &Path) -> bool {
  path
    .extension()
    .and_then(|v| v.to_str())
    .map(|e| matches!(e.to_ascii_lowercase().as_str(), "zip" | "cbz"))
    .unwrap_or(false)
}

fn is_image(path: &Path) -> bool {
  path
    .extension()
    .and_then(|v| v.to_str())
    .map(|e| {
      matches!(
        e.to_ascii_lowercase().as_str(),
        "jpg" | "jpeg" | "png" | "webp" | "gif" | "bmp" | "avif"
      )
    })
    .unwrap_or(false)
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

fn image_names_in_archive(path: &Path) -> Result<Vec<String>, String> {
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

fn page_count_for_source(source_path: &str, source_type: &str) -> Result<usize, String> {
  let path = Path::new(source_path);
  match source_type {
    "folder" => Ok(image_entries_in_dir(path).len()),
    "zip" | "cbz" => Ok(image_names_in_archive(path)?.len()),
    other => Err(format!("unsupported source type: {other}")),
  }
}

fn upsert_comic(
  conn: &Connection,
  library_id: i64,
  title: &str,
  source_path: &str,
  source_type: &str,
  date_modified: i64,
) -> Result<i64, String> {
  let ts = now_ts();
  conn
    .execute(
      r#"
      INSERT INTO comics (library_id, title, source_path, source_type, created_at, updated_at, date_modified)
      VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
      ON CONFLICT(source_path) DO UPDATE SET
        library_id=excluded.library_id,
        title=excluded.title,
        source_type=excluded.source_type,
        updated_at=excluded.updated_at,
        date_modified=excluded.date_modified
      "#,
      params![library_id, title, source_path, source_type, ts, ts, date_modified],
    )
    .map_err(|e| format!("failed upserting comic: {e}"))?;

  conn
    .query_row(
      "SELECT id FROM comics WHERE source_path = ?1",
      params![source_path],
      |row| row.get::<_, i64>(0),
    )
    .map_err(|e| format!("failed selecting comic id: {e}"))
}

fn upsert_chapter(
  conn: &Connection,
  comic_id: i64,
  title: &str,
  chapter_index: i64,
  source_path: &str,
  source_type: &str,
  page_count: usize,
  date_modified: i64,
) -> Result<i64, String> {
  let ts = now_ts();
  conn
    .execute(
      r#"
      INSERT INTO chapters (comic_id, title, chapter_index, source_path, source_type, page_count, created_at, updated_at, date_modified)
      VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
      ON CONFLICT(source_path) DO UPDATE SET
        comic_id=excluded.comic_id,
        title=excluded.title,
        chapter_index=excluded.chapter_index,
        source_type=excluded.source_type,
        page_count=excluded.page_count,
        updated_at=excluded.updated_at,
        date_modified=excluded.date_modified
      "#,
      params![
        comic_id,
        title,
        chapter_index,
        source_path,
        source_type,
        page_count as i64,
        ts,
        ts,
        date_modified
      ],
    )
    .map_err(|e| format!("failed upserting chapter: {e}"))?;

  conn
    .query_row(
      "SELECT id FROM chapters WHERE source_path = ?1",
      params![source_path],
      |row| row.get::<_, i64>(0),
    )
    .map_err(|e| format!("failed selecting chapter id: {e}"))
}

fn scan_comic_dir(conn: &Connection, library_id: i64, comic_dir: &Path) -> Result<(usize, usize), String> {
  let title = comic_dir
    .file_name()
    .and_then(|v| v.to_str())
    .unwrap_or("Untitled")
    .to_string();
  let source_path = comic_dir.to_string_lossy().to_string();
  let comic_id = upsert_comic(
    conn,
    library_id,
    &title,
    &source_path,
    "folder",
    file_modified_ts(comic_dir),
  )?;

  let mut chapter_entries: Vec<(String, String, String, i64)> = Vec::new();
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

  let mut dirs = WalkDir::new(comic_dir)
    .min_depth(1)
    .max_depth(1)
    .into_iter()
    .filter_map(|e| e.ok())
    .map(|e| e.into_path())
    .collect::<Vec<_>>();
  dirs.sort();

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
        let stype = archive
          .extension()
          .and_then(|v| v.to_str())
          .map(|v| v.to_ascii_lowercase())
          .unwrap_or_else(|| "zip".to_string());
        chapter_entries.push((
          archive
            .file_stem()
            .and_then(|v| v.to_str())
            .unwrap_or("Chapter")
            .to_string(),
          archive.to_string_lossy().to_string(),
          stype,
          chapter_index,
        ));
        chapter_index += 1;
      }
    }

    if child.is_file() && is_archive(&child) {
      let stype = child
        .extension()
        .and_then(|v| v.to_str())
        .map(|v| v.to_ascii_lowercase())
        .unwrap_or_else(|| "zip".to_string());
      chapter_entries.push((
        child
          .file_stem()
          .and_then(|v| v.to_str())
          .unwrap_or("Chapter")
          .to_string(),
        child.to_string_lossy().to_string(),
        stype,
        chapter_index,
      ));
      chapter_index += 1;
    }
  }

  let mut chapter_count = 0usize;
  for (chapter_title, chapter_path, chapter_type, idx) in chapter_entries {
    let page_count = page_count_for_source(&chapter_path, &chapter_type)?;
    if page_count == 0 {
      continue;
    }
    upsert_chapter(
      conn,
      comic_id,
      &chapter_title,
      idx,
      &chapter_path,
      &chapter_type,
      page_count,
      file_modified_ts(Path::new(&chapter_path)),
    )?;
    chapter_count += 1;
  }

  Ok((1, chapter_count))
}

#[tauri::command]
fn init_db(app: AppHandle) -> Result<(), String> {
  let _ = open_conn(&app)?;
  Ok(())
}

#[tauri::command]
fn add_library(app: AppHandle, path: String) -> Result<i64, String> {
  let conn = open_conn(&app)?;
  let ts = now_ts();
  conn
    .execute(
      r#"
      INSERT INTO libraries (path, created_at, updated_at)
      VALUES (?1, ?2, ?3)
      ON CONFLICT(path) DO UPDATE SET updated_at=excluded.updated_at
      "#,
      params![path, ts, ts],
    )
    .map_err(|e| format!("failed upserting library: {e}"))?;
  conn
    .query_row("SELECT id FROM libraries WHERE path = ?1", params![path], |row| {
      row.get::<_, i64>(0)
    })
    .map_err(|e| format!("failed selecting library id: {e}"))
}

#[tauri::command]
fn list_libraries(app: AppHandle) -> Result<Vec<Library>, String> {
  let conn = open_conn(&app)?;
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
  rows
    .collect::<Result<Vec<_>, _>>()
    .map_err(|e| format!("failed collecting libraries: {e}"))
}

#[tauri::command]
fn scan_libraries(app: AppHandle) -> Result<ScanSummary, String> {
  let conn = open_conn(&app)?;
  scan_libraries_conn(&conn)
}

fn scan_libraries_conn(conn: &Connection) -> Result<ScanSummary, String> {
  let mut stmt = conn
    .prepare("SELECT id, path FROM libraries ORDER BY id")
    .map_err(|e| format!("failed preparing libraries query: {e}"))?;
  let rows = stmt
    .query_map([], |row| Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?)))
    .map_err(|e| format!("failed querying libraries: {e}"))?;

  let mut comic_count = 0usize;
  let mut chapter_count = 0usize;

  for row in rows {
    let (library_id, library_path) = row.map_err(|e| format!("invalid library row: {e}"))?;
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

    for entry in entries {
      if entry.is_dir() {
        let (c, ch) = scan_comic_dir(&conn, library_id, &entry)?;
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
        let comic_id = upsert_comic(
          &conn,
          library_id,
          &title,
          &source_path,
          &source_type,
          file_modified_ts(&entry),
        )?;
        let page_count = page_count_for_source(&source_path, &source_type)?;
        if page_count > 0 {
          upsert_chapter(
            &conn,
            comic_id,
            "Chapter 1",
            1,
            &source_path,
            &source_type,
            page_count,
            file_modified_ts(&entry),
          )?;
          comic_count += 1;
          chapter_count += 1;
        }
      }
    }
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
    let result = open_conn(&app_handle).and_then(|conn| scan_libraries_conn(&conn));
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
  let conn = open_conn(&app)?;
  let order_field = match sort_by.unwrap_or_else(|| "name".to_string()).as_str() {
    "folder_date" => "c.date_modified",
    _ => "c.title COLLATE NOCASE",
  };
  let order_dir = match sort_dir.unwrap_or_else(|| "asc".to_string()).to_lowercase().as_str() {
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
  rows
    .collect::<Result<Vec<_>, _>>()
    .map_err(|e| format!("failed collecting comics: {e}"))
}

#[tauri::command]
fn list_chapters(app: AppHandle, comic_id: i64) -> Result<Vec<Chapter>, String> {
  let conn = open_conn(&app)?;
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
  rows
    .collect::<Result<Vec<_>, _>>()
    .map_err(|e| format!("failed collecting chapters: {e}"))
}

#[tauri::command]
fn get_chapter_context(app: AppHandle, chapter_id: i64) -> Result<Option<ChapterContext>, String> {
  let conn = open_conn(&app)?;
  let mut stmt = conn
    .prepare(
      r#"
      SELECT ch.id, ch.comic_id, ch.title, ch.chapter_index, c.title
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

  let chapter_id = row.get::<_, i64>(0).map_err(|e| format!("invalid chapter row: {e}"))?;
  let comic_id = row.get::<_, i64>(1).map_err(|e| format!("invalid chapter row: {e}"))?;
  let title = row
    .get::<_, String>(2)
    .map_err(|e| format!("invalid chapter row: {e}"))?;
  let chapter_index = row
    .get::<_, i64>(3)
    .map_err(|e| format!("invalid chapter row: {e}"))?;
  let comic_title = row
    .get::<_, String>(4)
    .map_err(|e| format!("invalid chapter row: {e}"))?;

  let chapter_total = conn
    .query_row(
      "SELECT COUNT(*) FROM chapters WHERE comic_id = ?1",
      params![comic_id],
      |r| r.get::<_, i64>(0),
    )
    .map_err(|e| format!("failed counting chapters: {e}"))?;

  let chapter_position = conn
    .query_row(
      r#"
      SELECT COUNT(*) + 1
      FROM chapters
      WHERE comic_id = ?1 AND (chapter_index < ?2 OR (chapter_index = ?2 AND id < ?3))
      "#,
      params![comic_id, chapter_index, chapter_id],
      |r| r.get::<_, i64>(0),
    )
    .map_err(|e| format!("failed computing chapter position: {e}"))?;

  let prev = conn
    .query_row(
      r#"
      SELECT id, title
      FROM chapters
      WHERE comic_id = ?1 AND (chapter_index < ?2 OR (chapter_index = ?2 AND id < ?3))
      ORDER BY chapter_index DESC, id DESC
      LIMIT 1
      "#,
      params![comic_id, chapter_index, chapter_id],
      |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?)),
    )
    .ok();

  let next = conn
    .query_row(
      r#"
      SELECT id, title
      FROM chapters
      WHERE comic_id = ?1 AND (chapter_index > ?2 OR (chapter_index = ?2 AND id > ?3))
      ORDER BY chapter_index ASC, id ASC
      LIMIT 1
      "#,
      params![comic_id, chapter_index, chapter_id],
      |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?)),
    )
    .ok();

  Ok(Some(ChapterContext {
    chapter_id,
    comic_id,
    comic_title,
    title,
    chapter_index,
    chapter_position,
    chapter_total,
    prev_chapter_id: prev.as_ref().map(|v| v.0),
    prev_chapter_title: prev.as_ref().map(|v| v.1.clone()),
    next_chapter_id: next.as_ref().map(|v| v.0),
    next_chapter_title: next.as_ref().map(|v| v.1.clone()),
  }))
}

fn chapter_source(conn: &Connection, chapter_id: i64) -> Result<(String, String), String> {
  conn
    .query_row(
      "SELECT source_path, source_type FROM chapters WHERE id = ?1",
      params![chapter_id],
      |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)),
    )
    .map_err(|e| format!("failed loading chapter source: {e}"))
}

fn extract_page_bytes(
  source_path: &str,
  source_type: &str,
  page_index: usize,
) -> Result<(Vec<u8>, String), String> {
  match source_type {
    "folder" => {
      let pages = image_entries_in_dir(Path::new(source_path));
      let page_path = pages
        .get(page_index)
        .ok_or_else(|| "page index out of range".to_string())?;
      let bytes = fs::read(page_path).map_err(|e| format!("failed reading image file: {e}"))?;
      Ok((bytes, page_path.to_string_lossy().to_string()))
    }
    "zip" | "cbz" => {
      let file = fs::File::open(source_path).map_err(|e| format!("failed opening archive: {e}"))?;
      let mut archive = ZipArchive::new(file).map_err(|e| format!("invalid archive: {e}"))?;
      let names = image_names_in_archive(Path::new(source_path))?;
      let name = names
        .get(page_index)
        .ok_or_else(|| "page index out of range".to_string())?;
      let mut entry = archive
        .by_name(name)
        .map_err(|e| format!("failed reading archive entry: {e}"))?;
      let mut bytes = Vec::new();
      entry
        .read_to_end(&mut bytes)
        .map_err(|e| format!("failed extracting image: {e}"))?;
      Ok((bytes, name.clone()))
    }
    other => Err(format!("unsupported source type: {other}")),
  }
}

#[tauri::command]
async fn get_chapter_pages(app: AppHandle, chapter_id: i64) -> Result<Vec<PageInfo>, String> {
  tauri::async_runtime::spawn_blocking(move || get_chapter_pages_sync(app, chapter_id))
    .await
    .map_err(|e| format!("chapter page task join error: {e}"))?
}

fn get_chapter_pages_sync(app: AppHandle, chapter_id: i64) -> Result<Vec<PageInfo>, String> {
  let conn = open_conn(&app)?;
  let (source_path, source_type) = chapter_source(&conn, chapter_id)?;
  let names = match source_type.as_str() {
    "folder" => image_entries_in_dir(Path::new(&source_path))
      .iter()
      .map(|p| {
        p.file_name()
          .and_then(|v| v.to_str())
          .unwrap_or_default()
          .to_string()
      })
      .collect::<Vec<_>>(),
    "zip" | "cbz" => image_names_in_archive(Path::new(&source_path))?,
    other => return Err(format!("unsupported source type: {other}")),
  };
  Ok(
    names
      .into_iter()
      .enumerate()
      .map(|(index, name)| PageInfo { index, name })
      .collect(),
  )
}

fn mime_for_path(path: &Path) -> &'static str {
  match path
    .extension()
    .and_then(|v| v.to_str())
    .map(|v| v.to_ascii_lowercase())
    .as_deref()
  {
    Some("jpg") | Some("jpeg") => "image/jpeg",
    Some("png") => "image/png",
    Some("webp") => "image/webp",
    Some("gif") => "image/gif",
    Some("bmp") => "image/bmp",
    Some("avif") => "image/avif",
    _ => "application/octet-stream",
  }
}

enum InterpolationKind {
  BuiltIn(FilterType),
  Mitchell,
  Lanczos2,
  Spline36,
}

fn interpolation_kind(method: &str) -> InterpolationKind {
  match method {
    "nearest" => InterpolationKind::BuiltIn(FilterType::Nearest),
    "linear" => InterpolationKind::BuiltIn(FilterType::Triangle),
    "cubic" => InterpolationKind::BuiltIn(FilterType::CatmullRom),
    "lanczos3" => InterpolationKind::BuiltIn(FilterType::Lanczos3),
    "gaussian" => InterpolationKind::BuiltIn(FilterType::Gaussian),
    "mitchell" => InterpolationKind::Mitchell,
    "lanczos2" => InterpolationKind::Lanczos2,
    "spline36" => InterpolationKind::Spline36,
    _ => InterpolationKind::BuiltIn(FilterType::Triangle),
  }
}

fn preview_filter(method: &str) -> FilterType {
  match method {
    "nearest" => FilterType::Nearest,
    "linear" => FilterType::Triangle,
    "cubic" | "mitchell" => FilterType::CatmullRom,
    "lanczos2" | "lanczos3" | "spline36" => FilterType::Lanczos3,
    "gaussian" => FilterType::Gaussian,
    _ => FilterType::Triangle,
  }
}

fn clamp_to_bounds(v: i32, max: u32) -> u32 {
  v.max(0).min(max as i32 - 1) as u32
}

fn sinc(x: f32) -> f32 {
  if x == 0.0 {
    return 1.0;
  }
  let pix = std::f32::consts::PI * x;
  pix.sin() / pix
}

fn lanczos_weight(x: f32, taps: f32) -> f32 {
  let ax = x.abs();
  if ax >= taps {
    0.0
  } else {
    sinc(ax) * sinc(ax / taps)
  }
}

fn mitchell_weight(x: f32) -> f32 {
  let b = 1.0 / 3.0;
  let c = 1.0 / 3.0;
  let ax = x.abs();
  if ax < 1.0 {
    ((12.0 - 9.0 * b - 6.0 * c) * ax * ax * ax
      + (-18.0 + 12.0 * b + 6.0 * c) * ax * ax
      + (6.0 - 2.0 * b))
      / 6.0
  } else if ax < 2.0 {
    ((-b - 6.0 * c) * ax * ax * ax
      + (6.0 * b + 30.0 * c) * ax * ax
      + (-12.0 * b - 48.0 * c) * ax
      + (8.0 * b + 24.0 * c))
      / 6.0
  } else {
    0.0
  }
}

fn spline36_weight(x: f32) -> f32 {
  let d = x.abs();
  if d < 1.0 {
    (((247.0 * d - 453.0) * d - 3.0) * d + 209.0) / 209.0
  } else if d < 2.0 {
    (((-114.0 * d + 612.0) * d - 1038.0) * d + 540.0) / 209.0
  } else if d < 3.0 {
    (((19.0 * d - 159.0) * d + 434.0) * d - 384.0) / 209.0
  } else {
    0.0
  }
}

fn render_cache_key(
  chapter_id: i64,
  chapter_modified_at: i64,
  page_index: usize,
  target_width: u32,
  target_height: u32,
  interpolation: &str,
) -> String {
  format!(
    "{chapter_id}:{chapter_modified_at}:{page_index}:{target_width}:{target_height}:{}",
    interpolation.to_ascii_lowercase()
  )
}

fn resample_custom_rgba(
  src: &RgbaImage,
  dst_w: u32,
  dst_h: u32,
  support: i32,
  weight: fn(f32) -> f32,
) -> RgbaImage {
  let src_w = src.width();
  let src_h = src.height();
  let mut out = RgbaImage::new(dst_w, dst_h);
  let sx = src_w as f32 / dst_w as f32;
  let sy = src_h as f32 / dst_h as f32;
  let offset = -support + 1;
  for y in 0..dst_h {
    let src_y = (y as f32 + 0.5) * sy - 0.5;
    let y_floor = src_y.floor() as i32;
    for x in 0..dst_w {
      let src_x = (x as f32 + 0.5) * sx - 0.5;
      let x_floor = src_x.floor() as i32;
      let mut acc = [0.0f32; 4];
      let mut wsum = 0.0f32;
      for ky in offset..=support {
        let py = y_floor + ky;
        let wy = weight(src_y - py as f32);
        if wy == 0.0 {
          continue;
        }
        let syi = clamp_to_bounds(py, src_h);
        for kx in offset..=support {
          let px = x_floor + kx;
          let wx = weight(src_x - px as f32);
          if wx == 0.0 {
            continue;
          }
          let w = wx * wy;
          if w == 0.0 {
            continue;
          }
          let sxi = clamp_to_bounds(px, src_w);
          let p = src.get_pixel(sxi, syi).0;
          acc[0] += p[0] as f32 * w;
          acc[1] += p[1] as f32 * w;
          acc[2] += p[2] as f32 * w;
          acc[3] += p[3] as f32 * w;
          wsum += w;
        }
      }
      let inv = if wsum.abs() > f32::EPSILON {
        1.0 / wsum
      } else {
        1.0
      };
      out.get_pixel_mut(x, y).0 = [
        (acc[0] * inv).round().clamp(0.0, 255.0) as u8,
        (acc[1] * inv).round().clamp(0.0, 255.0) as u8,
        (acc[2] * inv).round().clamp(0.0, 255.0) as u8,
        (acc[3] * inv).round().clamp(0.0, 255.0) as u8,
      ];
    }
  }
  out
}

#[tauri::command]
async fn get_page_data(
  app: AppHandle,
  chapter_id: i64,
  page_index: usize,
  options: Option<PageRenderOptions>,
) -> Result<String, String> {
  tauri::async_runtime::spawn_blocking(move || {
    get_page_data_sync(app, chapter_id, page_index, options)
  })
  .await
  .map_err(|e| format!("page render task join error: {e}"))?
}

fn get_page_data_sync(
  app: AppHandle,
  chapter_id: i64,
  page_index: usize,
  options: Option<PageRenderOptions>,
) -> Result<String, String> {
  let conn = open_conn(&app)?;
  let chapter_modified_at = chapter_date_modified(&conn, chapter_id)?;
  let (source_path, source_type) = chapter_source(&conn, chapter_id)?;
  let (bytes, name_or_path) = extract_page_bytes(&source_path, &source_type, page_index)?;
  let options = options.unwrap_or(PageRenderOptions {
    target_width: None,
    target_height: None,
    interpolation: None,
  });
  let cache_kind = cache_kind_for_render_options(&options);
  let interpolation = options
    .interpolation
    .as_deref()
    .unwrap_or("linear")
    .to_ascii_lowercase();
  let cache_key = render_cache_key(
    chapter_id,
    chapter_modified_at,
    page_index,
    options.target_width.unwrap_or(0),
    options.target_height.unwrap_or(0),
    interpolation.as_str(),
  );
  if let Some(cached) = cache_get(cache_kind, cache_key.as_str()) {
    return Ok(cached);
  }
  if let Some(cached) = disk_cache_get(&app, cache_kind, cache_key.as_str()) {
    cache_insert(cache_kind, cache_key.clone(), cached.clone());
    return Ok(cached);
  }

  let needs_resize = options.target_width.is_some() || options.target_height.is_some();
  if !needs_resize {
    let mime = mime_for_path(Path::new(&name_or_path));
    let encoded = format!("data:{mime};base64,{}", STANDARD.encode(bytes));
    cache_insert(cache_kind, cache_key.clone(), encoded.clone());
    disk_cache_set(&app, cache_kind, cache_key.as_str(), encoded.as_str());
    return Ok(encoded);
  }

  let source_img =
    image::load_from_memory(&bytes).map_err(|e| format!("failed decoding image: {e}"))?;
  let src_w = source_img.width();
  let src_h = source_img.height();

  let target_width = options.target_width.unwrap_or(0);
  let target_height = options.target_height.unwrap_or(0);
  let (dst_w, dst_h) = if target_width > 0 && target_height > 0 {
    (target_width, target_height)
  } else if target_width > 0 {
    let ratio = target_width as f32 / src_w as f32;
    (target_width, ((src_h as f32 * ratio).round() as u32).max(1))
  } else if target_height > 0 {
    let ratio = target_height as f32 / src_h as f32;
    (((src_w as f32 * ratio).round() as u32).max(1), target_height)
  } else {
    (src_w, src_h)
  };

  let max_edge = dst_w.max(dst_h);
  let use_fast_preview = max_edge > 480;

  let rendered = if dst_w == src_w && dst_h == src_h {
    source_img
  } else if use_fast_preview {
    source_img.resize_exact(dst_w, dst_h, preview_filter(interpolation.as_str()))
  } else {
    match interpolation_kind(interpolation.as_str()) {
      InterpolationKind::BuiltIn(filter) => source_img.resize_exact(dst_w, dst_h, filter),
      InterpolationKind::Mitchell => image::DynamicImage::ImageRgba8(resample_custom_rgba(
        &source_img.to_rgba8(),
        dst_w,
        dst_h,
        2,
        mitchell_weight,
      )),
      InterpolationKind::Lanczos2 => image::DynamicImage::ImageRgba8(resample_custom_rgba(
        &source_img.to_rgba8(),
        dst_w,
        dst_h,
        2,
        |x| lanczos_weight(x, 2.0),
      )),
      InterpolationKind::Spline36 => image::DynamicImage::ImageRgba8(resample_custom_rgba(
        &source_img.to_rgba8(),
        dst_w,
        dst_h,
        3,
        spline36_weight,
      )),
    }
  };

  let mut out = Cursor::new(Vec::new());
  rendered
    .write_to(&mut out, image::ImageFormat::Jpeg)
    .map_err(|e| format!("failed encoding resized image: {e}"))?;
  let encoded = format!("data:image/jpeg;base64,{}", STANDARD.encode(out.into_inner()));
  cache_insert(cache_kind, cache_key.clone(), encoded.clone());
  disk_cache_set(&app, cache_kind, cache_key.as_str(), encoded.as_str());
  Ok(encoded)
}

#[tauri::command]
fn save_progress(app: AppHandle, payload: SaveProgressPayload) -> Result<(), String> {
  let conn = open_conn(&app)?;
  save_progress_conn(&conn, &payload)
}

fn save_progress_conn(conn: &Connection, payload: &SaveProgressPayload) -> Result<(), String> {
  let ts = now_ts();
  conn
    .execute(
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
  let conn = open_conn(&app)?;
  get_progress_conn(&conn, chapter_id)
}

fn get_progress_conn(conn: &Connection, chapter_id: i64) -> Result<Option<ReadingProgress>, String> {
  let mut stmt = conn
    .prepare(
      "SELECT chapter_id, last_page, total_pages, mode, is_read, updated_at FROM reading_progress WHERE chapter_id = ?1",
    )
    .map_err(|e| format!("failed preparing progress query: {e}"))?;
  let mut rows = stmt
    .query(params![chapter_id])
    .map_err(|e| format!("failed querying progress: {e}"))?;
  if let Some(row) = rows.next().map_err(|e| format!("failed loading row: {e}"))? {
    return Ok(Some(ReadingProgress {
      chapter_id: row.get(0).map_err(|e| format!("invalid progress row: {e}"))?,
      last_page: row.get(1).map_err(|e| format!("invalid progress row: {e}"))?,
      total_pages: row.get(2).map_err(|e| format!("invalid progress row: {e}"))?,
      mode: row.get(3).map_err(|e| format!("invalid progress row: {e}"))?,
      is_read: row
        .get::<_, i64>(4)
        .map_err(|e| format!("invalid progress row: {e}"))?
        == 1,
      updated_at: row.get(5).map_err(|e| format!("invalid progress row: {e}"))?,
    }));
  }
  Ok(None)
}

#[tauri::command]
fn add_bookmark(app: AppHandle, payload: SaveBookmarkPayload) -> Result<i64, String> {
  let conn = open_conn(&app)?;
  let ts = now_ts();
  conn
    .execute(
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
  let conn = open_conn(&app)?;
  conn
    .execute("DELETE FROM bookmarks WHERE id = ?1", params![bookmark_id])
    .map_err(|e| format!("failed deleting bookmark: {e}"))?;
  Ok(())
}

#[tauri::command]
fn list_bookmarks(app: AppHandle, chapter_id: i64) -> Result<Vec<Bookmark>, String> {
  let conn = open_conn(&app)?;
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
  rows
    .collect::<Result<Vec<_>, _>>()
    .map_err(|e| format!("failed collecting bookmarks: {e}"))
}

#[tauri::command]
fn set_setting(app: AppHandle, key: String, value_json: String) -> Result<(), String> {
  let conn = open_conn(&app)?;
  conn
    .execute(
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
  let conn = open_conn(&app)?;
  let mut stmt = conn
    .prepare("SELECT value_json FROM app_settings WHERE key = ?1")
    .map_err(|e| format!("failed preparing setting query: {e}"))?;
  let mut rows = stmt
    .query(params![key])
    .map_err(|e| format!("failed querying setting: {e}"))?;
  if let Some(row) = rows.next().map_err(|e| format!("failed loading setting row: {e}"))? {
    return row
      .get::<_, String>(0)
      .map(Some)
      .map_err(|e| format!("invalid setting value: {e}"));
  }
  Ok(None)
}

#[tauri::command]
fn list_settings(app: AppHandle) -> Result<Vec<SettingEntry>, String> {
  let conn = open_conn(&app)?;
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
  rows
    .collect::<Result<Vec<_>, _>>()
    .map_err(|e| format!("failed collecting settings: {e}"))
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
  tauri::Builder::default()
    .plugin(tauri_plugin_dialog::init())
    .setup(|app| {
      if cfg!(debug_assertions) {
        app.handle().plugin(
          tauri_plugin_log::Builder::default()
            .level(log::LevelFilter::Info)
            .build(),
        )?;
      }
      let _ = open_conn(app.handle());
      Ok(())
    })
    .invoke_handler(tauri::generate_handler![
      init_db,
      add_library,
      list_libraries,
      scan_libraries,
      start_scan_libraries,
      get_library_scan_status,
      list_comics,
      list_chapters,
      get_chapter_context,
      get_chapter_pages,
      get_page_data,
      save_progress,
      get_progress,
      add_bookmark,
      remove_bookmark,
      list_bookmarks,
      set_setting,
      get_setting,
      list_settings
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
  fn render_cache_evicts_oldest_entry_by_budget() {
    let mut cache = RenderCache::new(8);
    cache.insert("a".to_string(), "1111".to_string());
    cache.insert("b".to_string(), "2222".to_string());
    cache.insert("c".to_string(), "3333".to_string());

    assert!(cache.get("a").is_none());
    assert_eq!(cache.get("b").as_deref(), Some("2222"));
    assert_eq!(cache.get("c").as_deref(), Some("3333"));
    assert!(cache.used_bytes <= 8);
  }

  #[test]
  fn render_cache_promotes_recently_used_key() {
    let mut cache = RenderCache::new(8);
    cache.insert("a".to_string(), "1111".to_string());
    cache.insert("b".to_string(), "2222".to_string());
    let _ = cache.get("a");
    cache.insert("c".to_string(), "3333".to_string());

    assert_eq!(cache.get("a").as_deref(), Some("1111"));
    assert!(cache.get("b").is_none());
    assert_eq!(cache.get("c").as_deref(), Some("3333"));
  }

  #[test]
  fn render_cache_skips_item_larger_than_budget() {
    let mut cache = RenderCache::new(4);
    cache.insert("a".to_string(), "12345".to_string());
    assert!(cache.get("a").is_none());
    assert_eq!(cache.used_bytes, 0);
  }

  #[test]
  fn spline36_weight_is_zero_outside_support() {
    assert_eq!(spline36_weight(3.0), 0.0);
    assert_eq!(spline36_weight(4.0), 0.0);
    assert!(spline36_weight(0.0) > 0.99);
  }

  #[test]
  fn mitchell_weight_is_zero_outside_support() {
    assert_eq!(mitchell_weight(2.0), 0.0);
    assert_eq!(mitchell_weight(3.0), 0.0);
    assert!(mitchell_weight(0.0) > 0.7);
  }

  #[test]
  fn render_cache_key_is_stable_lowercase() {
    let a = render_cache_key(1, 123, 2, 800, 0, "Spline36");
    let b = render_cache_key(1, 123, 2, 800, 0, "spline36");
    assert_eq!(a, b);
  }

  #[test]
  fn smoke_scan_progress_and_continue_flow() {
    let conn = Connection::open_in_memory().expect("open in memory db");
    run_migrations(&conn).expect("migrations");

    let tmp = tempdir().expect("tempdir");
    let library_path = tmp.path().join("library");
    let comic_path = library_path.join("Comic A");
    let chapter_a = comic_path.join("Chapter 001");
    let chapter_b = comic_path.join("Chapter 002");
    fs::create_dir_all(&chapter_a).expect("create chapter a");
    fs::create_dir_all(&chapter_b).expect("create chapter b");

    create_test_png(chapter_a.join("001.png"));
    create_test_png(chapter_a.join("002.png"));
    create_test_png(chapter_b.join("001.png"));

    let ts = now_ts();
    conn
      .execute(
        "INSERT INTO libraries (path, created_at, updated_at) VALUES (?1, ?2, ?3)",
        params![library_path.to_string_lossy().to_string(), ts, ts],
      )
      .expect("insert library");
    let library_id = conn.last_insert_rowid();

    let (comic_count, chapter_count) = scan_comic_dir(&conn, library_id, &comic_path).expect("scan comic");
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
    assert_eq!(page_count, 2);

    save_progress_conn(
      &conn,
      &SaveProgressPayload {
        chapter_id,
        last_page: 1,
        total_pages: 2,
        mode: "manga".to_string(),
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
        mode: "manga".to_string(),
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
}
