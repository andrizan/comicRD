mod chapter;
mod database;
mod image_pipeline;
mod library;
mod reader;

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

use walkdir::WalkDir;

use rusqlite::Connection;
use serde::{Deserialize, Serialize};

use crate::chapter::*;
use crate::database::*;
use crate::image_pipeline::*;
use crate::library::*;
use crate::reader::*;

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
    pub size_bytes: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Library {
    pub id: i64,
    pub path: String,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ScanSummary {
    pub comics: usize,
    pub chapters: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct LibraryScanStatus {
    pub running: bool,
    pub started_at: Option<i64>,
    pub finished_at: Option<i64>,
    pub last_summary: Option<ScanSummary>,
    pub error: Option<String>,
}

#[derive(Debug, Default)]
struct LibraryScanState {
    running: bool,
    started_at: Option<i64>,
    finished_at: Option<i64>,
    last_summary: Option<ScanSummary>,
    error: Option<String>,
}

impl LibraryScanState {
    fn status(&self) -> LibraryScanStatus {
        LibraryScanStatus {
            running: self.running,
            started_at: self.started_at,
            finished_at: self.finished_at,
            last_summary: self.last_summary.clone(),
            error: self.error.clone(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RawChapter {
    pub key: String,
    pub title: String,
    pub chapter_index: i64,
    pub source_path: String,
    pub source_type: String,
    pub date_modified: i64,
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
    pub is_read: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Bookmark {
    pub id: i64,
    pub chapter_id: i64,
    pub page: i64,
    pub created_at: i64,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ComicBookmark {
    pub id: i64,
    pub comic_source_path: String,
    pub comic_title: String,
    pub created_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ReadingHistoryEntry {
    pub comic_source_path: String,
    pub comic_title: String,
    pub chapter_title: String,
    pub chapter_source_path: String,
    pub chapter_id: i64,
    pub last_page: i64,
    pub total_pages: i64,
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
    pub is_read: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SaveBookmarkPayload {
    pub chapter_id: i64,
    pub page: i64,
    pub note: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RenderPagePayload {
    pub chapter_id: i64,
    pub page_index: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PrefetchPagesPayload {
    pub chapter_id: i64,
    pub page_indices: Vec<usize>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RenderedPage {
    pub bytes: Arc<Vec<u8>>,
    pub mime: String,
    pub width: u32,
    pub height: u32,
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

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
pub struct LibraryStorageStats {
    pub total_size_bytes: i64,
    pub comic_count: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SettingEntry {
    pub key: String,
    pub value_json: String,
}

struct LibraryListCache {
    library_path: String,
    entries: Arc<Vec<PathBuf>>,
    total_size_bytes: i64,
    comic_count: i64,
    updated_at: Instant,
}

struct ChapterDiscoveryCache {
    discovered: Vec<(String, String, String, i64)>,
    updated_at: Instant,
}

pub struct ComicRdCore {
    db_path: PathBuf,
    conn: Mutex<Connection>,
    page_cache: PageCache,
    scan_state: Mutex<LibraryScanState>,
    library_list_cache: Mutex<Option<LibraryListCache>>,
    chapter_discovery_cache: Mutex<HashMap<String, ChapterDiscoveryCache>>,
}

impl ComicRdCore {
    pub fn open(app_data_dir: impl AsRef<Path>) -> Result<Self, String> {
        let app_data_dir = app_data_dir.as_ref();
        fs::create_dir_all(app_data_dir)
            .map_err(|e| format!("failed creating app data dir: {e}"))?;
        let db_path = app_data_dir.join("comicrd.db");
        copy_legacy_database_if_missing(app_data_dir, &db_path)?;
        let conn = open_database_file(&db_path)?;
        run_migrations(&conn)?;

        Ok(Self {
            db_path,
            conn: Mutex::new(conn),
            page_cache: PageCache::default(),
            scan_state: Mutex::new(LibraryScanState::default()),
            library_list_cache: Mutex::new(None),
            chapter_discovery_cache: Mutex::new(HashMap::new()),
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
        let library_path = {
            let conn = self
                .conn
                .lock()
                .map_err(|_| "db lock poisoned".to_string())?;
            get_library_source_setting(&conn)?
        };
        let base = Path::new(&library_path);
        if library_path.is_empty() || !base.exists() || !base.is_dir() {
            return Ok(Vec::new());
        }

        let entries = {
            let mut cache_guard = self
                .library_list_cache
                .lock()
                .map_err(|_| "library list cache lock poisoned".to_string())?;
            let needs_refresh = match &*cache_guard {
                Some(cached) => {
                    cached.library_path != library_path
                        || cached.updated_at.elapsed() > Duration::from_secs(30)
                }
                None => true,
            };
            if needs_refresh {
                let mut entries = WalkDir::new(base)
                    .min_depth(1)
                    .max_depth(1)
                    .into_iter()
                    .filter_map(|e| e.ok())
                    .map(|e| e.into_path())
                    .collect::<Vec<_>>();
                entries.sort();
                let shared = Arc::new(entries);
                *cache_guard = Some(LibraryListCache {
                    library_path: library_path.clone(),
                    entries: Arc::clone(&shared),
                    total_size_bytes: 0,
                    comic_count: 0,
                    updated_at: Instant::now(),
                });
                shared
            } else {
                Arc::clone(&cache_guard.as_ref().unwrap().entries)
            }
        };

        let mut comics = {
            let conn = self
                .conn
                .lock()
                .map_err(|_| "db lock poisoned".to_string())?;
            let mut comics = Vec::new();
            comics_from_fs_entries(&conn, &library_path, &entries, &mut comics)?;
            comics
        };
        let total_size_bytes: i64 = comics.iter().map(|c| c.size_bytes).sum();
        let comic_count = comics.len() as i64;
        {
            let mut cache_guard = self
                .library_list_cache
                .lock()
                .map_err(|_| "library list cache lock poisoned".to_string())?;
            if let Some(cached) = cache_guard.as_mut() {
                if cached.library_path == library_path {
                    cached.total_size_bytes = total_size_bytes;
                    cached.comic_count = comic_count;
                }
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

    pub fn get_library_storage_stats(&self) -> Result<LibraryStorageStats, String> {
        {
            let cache_guard = self
                .library_list_cache
                .lock()
                .map_err(|_| "library list cache lock poisoned".to_string())?;
            if let Some(cached) = cache_guard.as_ref() {
                if cached.updated_at.elapsed() <= Duration::from_secs(30) {
                    return Ok(LibraryStorageStats {
                        total_size_bytes: cached.total_size_bytes,
                        comic_count: cached.comic_count,
                    });
                }
            }
        }
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        conn.query_row(
            "SELECT COALESCE(SUM(size_bytes), 0), COUNT(*) FROM comics",
            [],
            |row| {
                Ok(LibraryStorageStats {
                    total_size_bytes: row.get(0)?,
                    comic_count: row.get(1)?,
                })
            },
        )
        .map_err(|e| format!("failed querying library storage stats: {e}"))
    }

    pub fn add_library(&self, path: &str) -> Result<i64, String> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        add_library_conn(&conn, path)
    }

    pub fn list_libraries(&self) -> Result<Vec<Library>, String> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        list_libraries_conn(&conn)
    }

    pub fn scan_libraries(&self) -> Result<ScanSummary, String> {
        self.mark_scan_started()?;
        let result = self.scan_libraries_now();
        self.mark_scan_finished(&result);
        self.clear_library_list_cache();
        self.clear_chapter_discovery_cache();
        result
    }

    fn scan_libraries_now(&self) -> Result<ScanSummary, String> {
        let libraries = {
            let conn = self
                .conn
                .lock()
                .map_err(|_| "db lock poisoned".to_string())?;
            list_libraries_conn(&conn)?
        };

        let mut comic_count = 0usize;
        let mut chapter_count = 0usize;

        for lib in libraries {
            let base = Path::new(&lib.path);
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

            let mut conn = self
                .conn
                .lock()
                .map_err(|_| "db lock poisoned".to_string())?;
            let (c, ch) = scan_library_entries(&mut conn, lib.id, &lib.path, &entries)?;
            drop(conn);

            comic_count += c;
            chapter_count += ch;
        }

        Ok(ScanSummary {
            comics: comic_count,
            chapters: chapter_count,
        })
    }

    pub fn start_scan_libraries(self: &Arc<Self>) -> Result<bool, String> {
        {
            let mut state = self
                .scan_state
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

        let core = Arc::clone(self);
        thread::spawn(move || {
            let result = core.scan_libraries_now();
            core.mark_scan_finished(&result);
            core.clear_library_list_cache();
            core.clear_chapter_discovery_cache();
        });

        Ok(true)
    }

    pub fn get_library_scan_status(&self) -> LibraryScanStatus {
        match self.scan_state.lock() {
            Ok(state) => state.status(),
            Err(_) => LibraryScanStatus {
                running: false,
                started_at: None,
                finished_at: None,
                last_summary: None,
                error: Some("scan state lock poisoned".to_string()),
            },
        }
    }

    fn mark_scan_started(&self) -> Result<(), String> {
        let mut state = self
            .scan_state
            .lock()
            .map_err(|_| "failed locking scan state".to_string())?;
        state.running = true;
        state.started_at = Some(now_ts());
        state.finished_at = None;
        state.error = None;
        Ok(())
    }

    fn mark_scan_finished(&self, result: &Result<ScanSummary, String>) {
        if let Ok(mut state) = self.scan_state.lock() {
            state.running = false;
            state.finished_at = Some(now_ts());
            match result {
                Ok(summary) => {
                    state.last_summary = Some(summary.clone());
                    state.error = None;
                }
                Err(error) => {
                    state.error = Some(error.clone());
                }
            }
        }
    }

    pub fn list_comic_chapters_raw(
        &self,
        comic_source_path: &str,
    ) -> Result<Vec<RawChapter>, String> {
        let discovered = match self.get_cached_chapter_discovery(comic_source_path) {
            Some(cached) => cached,
            None => {
                let discovered = discover_chapter_entries_for_comic(comic_source_path)?;
                self.set_cached_chapter_discovery(comic_source_path, discovered.clone());
                discovered
            }
        };
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        list_comic_chapters_raw_conn_with_discovered(&conn, comic_source_path, &discovered)
    }

    pub fn open_chapter_for_reading(&self, payload: OpenChapterPayload) -> Result<i64, String> {
        let mut conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        let result = open_chapter_for_reading_conn(&mut conn, payload);
        drop(conn);
        if result.is_ok() {
            self.clear_library_list_cache();
            self.clear_chapter_discovery_cache();
        }
        result
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
        save_progress_conn(&conn, &payload)?;
        self.clear_library_list_cache();
        Ok(())
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
        render_page_variant_conn(&conn, &self.page_cache, payload)
    }

    pub fn prefetch_pages(&self, payload: PrefetchPagesPayload) -> Result<(), String> {
        for page_index in payload.page_indices {
            let conn = self
                .conn
                .lock()
                .map_err(|_| "db lock poisoned".to_string())?;
            render_page_variant_conn(
                &conn,
                &self.page_cache,
                RenderPagePayload {
                    chapter_id: payload.chapter_id,
                    page_index,
                },
            )?;
        }
        Ok(())
    }

    pub fn evict_chapter_pages(&self, chapter_id: i64, keep_pages: Vec<usize>) {
        self.page_cache.evict_except(chapter_id, &keep_pages);
    }

    #[doc(hidden)]
    pub fn cache_stats_for_test(&self) -> CacheStats {
        self.page_cache.stats()
    }

    fn clear_library_list_cache(&self) {
        if let Ok(mut cache) = self.library_list_cache.lock() {
            *cache = None;
        }
    }

    fn get_cached_chapter_discovery(
        &self,
        comic_source_path: &str,
    ) -> Option<Vec<(String, String, String, i64)>> {
        let cache = self.chapter_discovery_cache.lock().ok()?;
        let cached = cache.get(comic_source_path)?;
        if cached.updated_at.elapsed() > Duration::from_secs(60) {
            return None;
        }
        Some(cached.discovered.clone())
    }

    fn set_cached_chapter_discovery(
        &self,
        comic_source_path: &str,
        discovered: Vec<(String, String, String, i64)>,
    ) {
        if let Ok(mut cache) = self.chapter_discovery_cache.lock() {
            cache.insert(
                comic_source_path.to_string(),
                ChapterDiscoveryCache {
                    discovered,
                    updated_at: Instant::now(),
                },
            );
        }
    }

    fn clear_chapter_discovery_cache(&self) {
        if let Ok(mut cache) = self.chapter_discovery_cache.lock() {
            cache.clear();
        }
    }

    pub fn add_bookmark(&self, payload: SaveBookmarkPayload) -> Result<i64, String> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        let id = add_bookmark_conn(&conn, payload)?;
        Ok(id)
    }

    pub fn remove_bookmark(&self, bookmark_id: i64) -> Result<(), String> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        remove_bookmark_conn(&conn, bookmark_id)?;
        Ok(())
    }

    pub fn list_bookmarks(&self, chapter_id: i64) -> Result<Vec<Bookmark>, String> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        list_bookmarks_conn(&conn, chapter_id)
    }

    pub fn list_all_bookmarks(&self) -> Result<Vec<ComicBookmark>, String> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        list_all_bookmarks_conn(&conn)
    }

    pub fn add_comic_bookmark(&self, comic_source_path: &str) -> Result<i64, String> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        let id = add_comic_bookmark_conn(&conn, comic_source_path)?;
        Ok(id)
    }

    pub fn remove_comic_bookmark(&self, comic_source_path: &str) -> Result<(), String> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        remove_comic_bookmark_conn(&conn, comic_source_path)?;
        Ok(())
    }

    pub fn is_comic_bookmarked(&self, comic_source_path: &str) -> Result<bool, String> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        is_comic_bookmarked_conn(&conn, comic_source_path)
    }

    pub fn add_chapter_favorite(
        &self,
        chapter_source_path: &str,
        comic_source_path: &str,
    ) -> Result<i64, String> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        add_chapter_favorite_conn(&conn, chapter_source_path, comic_source_path)
    }

    pub fn remove_chapter_favorite(&self, chapter_source_path: &str) -> Result<(), String> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        remove_chapter_favorite_conn(&conn, chapter_source_path)
    }

    pub fn list_chapter_favorites(&self, comic_source_path: &str) -> Result<Vec<String>, String> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        list_chapter_favorites_conn(&conn, comic_source_path)
    }

    pub fn list_reading_history(&self) -> Result<Vec<ReadingHistoryEntry>, String> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        list_reading_history_conn(&conn)
    }

    pub fn list_comics_with_progress(&self) -> Result<Vec<String>, String> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        list_comics_with_progress_conn(&conn)
    }

    pub fn export_database_backup(&self, output_path: impl AsRef<Path>) -> Result<(), String> {
        let output_path = output_path.as_ref();
        if output_path.as_os_str().is_empty() {
            return Err("output path kosong".to_string());
        }

        {
            let conn = self
                .conn
                .lock()
                .map_err(|_| "db lock poisoned".to_string())?;
            let _ = conn.execute_batch("PRAGMA wal_checkpoint(FULL);");
        }

        if let Some(parent) = output_path.parent() {
            fs::create_dir_all(parent)
                .map_err(|e| format!("failed creating backup directory: {e}"))?;
        }
        if output_path.exists() {
            fs::remove_file(output_path)
                .map_err(|e| format!("failed replacing existing backup file: {e}"))?;
        }

        let db_bytes =
            fs::read(&self.db_path).map_err(|e| format!("failed reading database file: {e}"))?;
        let zip_file =
            fs::File::create(output_path).map_err(|e| format!("failed creating zip file: {e}"))?;
        let mut zip = zip::ZipWriter::new(zip_file);
        let options = zip::write::SimpleFileOptions::default()
            .compression_method(zip::CompressionMethod::Deflated);
        zip.start_file("comicrd.db", options)
            .map_err(|e| format!("failed starting zip entry: {e}"))?;
        use std::io::Write;
        zip.write_all(&db_bytes)
            .map_err(|e| format!("failed writing db to zip: {e}"))?;
        zip.finish()
            .map_err(|e| format!("failed finishing zip: {e}"))?;
        Ok(())
    }

    pub fn import_database_backup(&self, input_path: impl AsRef<Path>) -> Result<(), String> {
        let input_path = input_path.as_ref();
        if input_path.as_os_str().is_empty() {
            return Err("input path kosong".to_string());
        }
        if !input_path.exists() || !input_path.is_file() {
            return Err("file backup tidak ditemukan".to_string());
        }

        let temp_dir = std::env::temp_dir().join(format!("comicrd-import-{}", now_ts()));
        fs::create_dir_all(&temp_dir).map_err(|e| format!("failed creating temp dir: {e}"))?;
        let db_bytes = if is_zip_file(input_path) {
            extract_db_from_zip(input_path)?
        } else {
            fs::read(input_path).map_err(|e| format!("failed reading backup file: {e}"))?
        };
        let temp_db_path = temp_dir.join("comicrd.db");
        fs::write(&temp_db_path, &db_bytes).map_err(|e| format!("failed writing temp db: {e}"))?;

        let mut conn_guard = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        let backup_path = self
            .db_path
            .with_extension(format!("db.pre-import-{}", now_ts()));
        if self.db_path.exists() {
            let _ = conn_guard.execute_batch("PRAGMA wal_checkpoint(FULL);");
            fs::copy(&self.db_path, &backup_path)
                .map_err(|e| format!("failed creating pre-import backup: {e}"))?;
        }

        let replacement_conn = Connection::open_in_memory()
            .map_err(|e| format!("failed opening temporary db: {e}"))?;
        let old_conn = std::mem::replace(&mut *conn_guard, replacement_conn);
        drop(old_conn);

        if self.db_path.exists() {
            fs::remove_file(&self.db_path)
                .map_err(|e| format!("failed replacing database file: {e}"))?;
        }
        remove_sqlite_sidecars(&self.db_path);

        fs::copy(&temp_db_path, &self.db_path)
            .map_err(|e| format!("failed importing backup file: {e}"))?;
        let imported_conn = open_database_file(&self.db_path)
            .map_err(|e| format!("failed opening imported db: {e}"))?;
        run_migrations(&imported_conn)?;
        *conn_guard = imported_conn;
        self.clear_library_list_cache();
        self.clear_chapter_discovery_cache();
        let _ = fs::remove_dir_all(&temp_dir);
        Ok(())
    }
}

fn is_zip_file(path: &Path) -> bool {
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    ext == "zip"
}

fn extract_db_from_zip(zip_path: &Path) -> Result<Vec<u8>, String> {
    let file = fs::File::open(zip_path).map_err(|e| format!("failed opening zip file: {e}"))?;
    let mut archive =
        zip::ZipArchive::new(file).map_err(|e| format!("failed reading zip archive: {e}"))?;
    let mut entry = archive
        .by_name("comicrd.db")
        .map_err(|_| "comicrd.db not found in zip archive".to_string())?;
    let mut bytes = Vec::new();
    use std::io::Read;
    entry
        .read_to_end(&mut bytes)
        .map_err(|e| format!("failed reading db from zip: {e}"))?;
    Ok(bytes)
}
