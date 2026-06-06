use std::path::PathBuf;
use std::sync::{Arc, RwLock};

use comicrd_core as core;

static CORE: RwLock<Option<Arc<core::ComicRdCore>>> = RwLock::new(None);

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

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RawComic {
    pub title: String,
    pub source_path: String,
    pub source_type: String,
    pub date_modified: i64,
    pub chapter_count: i64,
    pub read_chapter_count: i64,
    pub in_progress_chapter_count: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Library {
    pub id: i64,
    pub path: String,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ScanSummary {
    pub comics: u32,
    pub chapters: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LibraryScanStatus {
    pub running: bool,
    pub started_at: Option<i64>,
    pub finished_at: Option<i64>,
    pub last_summary: Option<ScanSummary>,
    pub error: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RawChapter {
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

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PageInfo {
    pub index: u32,
    pub name: String,
    pub width: Option<u32>,
    pub height: Option<u32>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
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

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReadingProgress {
    pub chapter_id: i64,
    pub last_page: i64,
    pub total_pages: i64,
    pub is_read: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Bookmark {
    pub id: i64,
    pub chapter_id: i64,
    pub page: i64,
    pub created_at: i64,
    pub note: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ComicBookmark {
    pub id: i64,
    pub comic_source_path: String,
    pub comic_title: String,
    pub created_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
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

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OpenChapterPayload {
    pub comic_source_path: String,
    pub chapter_source_path: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SaveProgressPayload {
    pub chapter_id: i64,
    pub last_page: i64,
    pub total_pages: i64,
    pub is_read: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SaveBookmarkPayload {
    pub chapter_id: i64,
    pub page: i64,
    pub note: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RenderPagePayload {
    pub chapter_id: i64,
    pub page_index: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PrefetchPagesPayload {
    pub chapter_id: i64,
    pub page_indices: Vec<u32>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RenderedPage {
    pub bytes: Vec<u8>,
    pub mime: String,
    pub width: u32,
    pub height: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LibrarySourceStatus {
    pub configured: bool,
    pub path: String,
    pub exists: bool,
    pub is_dir: bool,
    pub readable: bool,
    pub error: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SettingEntry {
    pub key: String,
    pub value_json: String,
}

impl From<SortBy> for core::SortBy {
    fn from(value: SortBy) -> Self {
        match value {
            SortBy::Name => Self::Name,
            SortBy::FolderDate => Self::FolderDate,
        }
    }
}

impl From<SortDir> for core::SortDir {
    fn from(value: SortDir) -> Self {
        match value {
            SortDir::Asc => Self::Asc,
            SortDir::Desc => Self::Desc,
        }
    }
}

impl From<core::RawComic> for RawComic {
    fn from(value: core::RawComic) -> Self {
        Self {
            title: value.title,
            source_path: value.source_path,
            source_type: value.source_type,
            date_modified: value.date_modified,
            chapter_count: value.chapter_count,
            read_chapter_count: value.read_chapter_count,
            in_progress_chapter_count: value.in_progress_chapter_count,
        }
    }
}

impl From<core::Library> for Library {
    fn from(value: core::Library) -> Self {
        Self {
            id: value.id,
            path: value.path,
            created_at: value.created_at,
            updated_at: value.updated_at,
        }
    }
}

impl From<core::ScanSummary> for ScanSummary {
    fn from(value: core::ScanSummary) -> Self {
        Self {
            comics: value.comics as u32,
            chapters: value.chapters as u32,
        }
    }
}

impl From<core::LibraryScanStatus> for LibraryScanStatus {
    fn from(value: core::LibraryScanStatus) -> Self {
        Self {
            running: value.running,
            started_at: value.started_at,
            finished_at: value.finished_at,
            last_summary: value.last_summary.map(Into::into),
            error: value.error,
        }
    }
}

impl From<core::RawChapter> for RawChapter {
    fn from(value: core::RawChapter) -> Self {
        Self {
            title: value.title,
            chapter_index: value.chapter_index,
            source_path: value.source_path,
            source_type: value.source_type,
            date_modified: value.date_modified,
            page_count: value.page_count,
            is_read: value.is_read,
            last_page: value.last_page,
            total_pages: value.total_pages,
        }
    }
}

impl From<core::PageInfo> for PageInfo {
    fn from(value: core::PageInfo) -> Self {
        Self {
            index: value.index as u32,
            name: value.name,
            width: value.width,
            height: value.height,
        }
    }
}

impl From<core::ChapterContext> for ChapterContext {
    fn from(value: core::ChapterContext) -> Self {
        Self {
            chapter_id: value.chapter_id,
            comic_id: value.comic_id,
            comic_source_path: value.comic_source_path,
            chapter_source_path: value.chapter_source_path,
            comic_title: value.comic_title,
            title: value.title,
            chapter_index: value.chapter_index,
            chapter_position: value.chapter_position,
            chapter_total: value.chapter_total,
            prev_chapter_id: value.prev_chapter_id,
            prev_chapter_title: value.prev_chapter_title,
            next_chapter_id: value.next_chapter_id,
            next_chapter_title: value.next_chapter_title,
        }
    }
}

impl From<core::ReadingProgress> for ReadingProgress {
    fn from(value: core::ReadingProgress) -> Self {
        Self {
            chapter_id: value.chapter_id,
            last_page: value.last_page,
            total_pages: value.total_pages,
            is_read: value.is_read,
        }
    }
}

impl From<core::Bookmark> for Bookmark {
    fn from(value: core::Bookmark) -> Self {
        Self {
            id: value.id,
            chapter_id: value.chapter_id,
            page: value.page,
            created_at: value.created_at,
            note: value.note,
        }
    }
}

impl From<core::ComicBookmark> for ComicBookmark {
    fn from(value: core::ComicBookmark) -> Self {
        Self {
            id: value.id,
            comic_source_path: value.comic_source_path,
            comic_title: value.comic_title,
            created_at: value.created_at,
        }
    }
}

impl From<core::ReadingHistoryEntry> for ReadingHistoryEntry {
    fn from(value: core::ReadingHistoryEntry) -> Self {
        Self {
            comic_source_path: value.comic_source_path,
            comic_title: value.comic_title,
            chapter_title: value.chapter_title,
            chapter_source_path: value.chapter_source_path,
            chapter_id: value.chapter_id,
            last_page: value.last_page,
            total_pages: value.total_pages,
            is_read: value.is_read,
            updated_at: value.updated_at,
        }
    }
}

impl From<OpenChapterPayload> for core::OpenChapterPayload {
    fn from(value: OpenChapterPayload) -> Self {
        Self {
            comic_source_path: value.comic_source_path,
            chapter_source_path: value.chapter_source_path,
        }
    }
}

impl From<SaveProgressPayload> for core::SaveProgressPayload {
    fn from(value: SaveProgressPayload) -> Self {
        Self {
            chapter_id: value.chapter_id,
            last_page: value.last_page,
            total_pages: value.total_pages,
            is_read: value.is_read,
        }
    }
}

impl From<SaveBookmarkPayload> for core::SaveBookmarkPayload {
    fn from(value: SaveBookmarkPayload) -> Self {
        Self {
            chapter_id: value.chapter_id,
            page: value.page,
            note: value.note,
        }
    }
}

impl From<RenderPagePayload> for core::RenderPagePayload {
    fn from(value: RenderPagePayload) -> Self {
        Self {
            chapter_id: value.chapter_id,
            page_index: value.page_index as usize,
        }
    }
}

impl From<PrefetchPagesPayload> for core::PrefetchPagesPayload {
    fn from(value: PrefetchPagesPayload) -> Self {
        Self {
            chapter_id: value.chapter_id,
            page_indices: value
                .page_indices
                .into_iter()
                .map(|index| index as usize)
                .collect(),
        }
    }
}

impl From<core::RenderedPage> for RenderedPage {
    fn from(value: core::RenderedPage) -> Self {
        Self {
            bytes: (*value.bytes).clone(),
            mime: value.mime,
            width: value.width,
            height: value.height,
        }
    }
}

impl From<core::LibrarySourceStatus> for LibrarySourceStatus {
    fn from(value: core::LibrarySourceStatus) -> Self {
        Self {
            configured: value.configured,
            path: value.path,
            exists: value.exists,
            is_dir: value.is_dir,
            readable: value.readable,
            error: value.error,
        }
    }
}

impl From<core::SettingEntry> for SettingEntry {
    fn from(value: core::SettingEntry) -> Self {
        Self {
            key: value.key,
            value_json: value.value_json,
        }
    }
}

fn core() -> Result<Arc<core::ComicRdCore>, String> {
    CORE.read()
        .map_err(|_| "core lock poisoned".to_string())?
        .clone()
        .ok_or_else(|| "ComicRD core has not been initialized".to_string())
}

pub fn init_app(app_data_dir: String) -> Result<(), String> {
    let core = core::ComicRdCore::open(PathBuf::from(app_data_dir))?;
    *CORE.write().map_err(|_| "core lock poisoned".to_string())? = Some(Arc::new(core));
    Ok(())
}

pub fn shutdown_app() -> Result<(), String> {
    *CORE.write().map_err(|_| "core lock poisoned".to_string())? = None;
    Ok(())
}

pub fn check_library_source() -> Result<LibrarySourceStatus, String> {
    core()?.check_library_source().map(Into::into)
}

pub fn add_library(path: String) -> Result<i64, String> {
    core()?.add_library(&path)
}

pub fn list_libraries() -> Result<Vec<Library>, String> {
    Ok(core()?
        .list_libraries()?
        .into_iter()
        .map(Into::into)
        .collect())
}

pub fn scan_libraries() -> Result<ScanSummary, String> {
    core()?.scan_libraries().map(Into::into)
}

pub fn start_scan_libraries() -> Result<bool, String> {
    core()?.start_scan_libraries()
}

pub fn get_library_scan_status() -> Result<LibraryScanStatus, String> {
    Ok(core()?.get_library_scan_status().into())
}

pub fn list_library_comics_raw(
    sort_by: SortBy,
    sort_dir: SortDir,
) -> Result<Vec<RawComic>, String> {
    Ok(core()?
        .list_library_comics_raw(sort_by.into(), sort_dir.into())?
        .into_iter()
        .map(Into::into)
        .collect())
}

pub fn list_comics_with_progress() -> Result<Vec<String>, String> {
    core()?.list_comics_with_progress()
}

pub fn list_reading_history() -> Result<Vec<ReadingHistoryEntry>, String> {
    Ok(core()?
        .list_reading_history()?
        .into_iter()
        .map(Into::into)
        .collect())
}

pub fn list_comic_chapters_raw(comic_source_path: String) -> Result<Vec<RawChapter>, String> {
    Ok(core()?
        .list_comic_chapters_raw(&comic_source_path)?
        .into_iter()
        .map(Into::into)
        .collect())
}

pub fn open_chapter_for_reading(payload: OpenChapterPayload) -> Result<i64, String> {
    core()?.open_chapter_for_reading(payload.into())
}

pub fn get_chapter_context(chapter_id: i64) -> Result<Option<ChapterContext>, String> {
    Ok(core()?.get_chapter_context(chapter_id)?.map(Into::into))
}

pub fn get_chapter_pages(chapter_id: i64) -> Result<Vec<PageInfo>, String> {
    Ok(core()?
        .get_chapter_pages(chapter_id)?
        .into_iter()
        .map(Into::into)
        .collect())
}

pub fn render_page_variant(payload: RenderPagePayload) -> Result<RenderedPage, String> {
    core()?.render_page_variant(payload.into()).map(Into::into)
}

pub fn prefetch_pages(payload: PrefetchPagesPayload) -> Result<(), String> {
    core()?.prefetch_pages(payload.into())
}

pub fn evict_chapter_pages(chapter_id: i64, keep_pages: Vec<u32>) -> Result<(), String> {
    let keep: Vec<usize> = keep_pages.into_iter().map(|p| p as usize).collect();
    core()?.evict_chapter_pages(chapter_id, keep);
    Ok(())
}

pub fn save_progress(payload: SaveProgressPayload) -> Result<(), String> {
    core()?.save_progress(payload.into())
}

pub fn get_progress(chapter_id: i64) -> Result<Option<ReadingProgress>, String> {
    Ok(core()?.get_progress(chapter_id)?.map(Into::into))
}

pub fn list_bookmarks(chapter_id: i64) -> Result<Vec<Bookmark>, String> {
    Ok(core()?
        .list_bookmarks(chapter_id)?
        .into_iter()
        .map(Into::into)
        .collect())
}

pub fn add_bookmark(payload: SaveBookmarkPayload) -> Result<i64, String> {
    core()?.add_bookmark(payload.into())
}

pub fn remove_bookmark(bookmark_id: i64) -> Result<(), String> {
    core()?.remove_bookmark(bookmark_id)
}

pub fn list_all_bookmarks() -> Result<Vec<ComicBookmark>, String> {
    Ok(core()?
        .list_all_bookmarks()?
        .into_iter()
        .map(Into::into)
        .collect())
}

pub fn add_comic_bookmark(comic_source_path: String) -> Result<i64, String> {
    core()?.add_comic_bookmark(&comic_source_path)
}

pub fn remove_comic_bookmark(comic_source_path: String) -> Result<(), String> {
    core()?.remove_comic_bookmark(&comic_source_path)
}

pub fn is_comic_bookmarked(comic_source_path: String) -> Result<bool, String> {
    core()?.is_comic_bookmarked(&comic_source_path)
}

pub fn add_chapter_favorite(
    chapter_source_path: String,
    comic_source_path: String,
) -> Result<i64, String> {
    core()?.add_chapter_favorite(&chapter_source_path, &comic_source_path)
}

pub fn remove_chapter_favorite(chapter_source_path: String) -> Result<(), String> {
    core()?.remove_chapter_favorite(&chapter_source_path)
}

pub fn list_chapter_favorites(comic_source_path: String) -> Result<Vec<String>, String> {
    core()?.list_chapter_favorites(&comic_source_path)
}

pub fn list_settings() -> Result<Vec<SettingEntry>, String> {
    Ok(core()?
        .list_settings()?
        .into_iter()
        .map(Into::into)
        .collect())
}

pub fn get_setting(key: String) -> Result<Option<String>, String> {
    core()?.get_setting(&key)
}

pub fn set_setting(key: String, value_json: String) -> Result<(), String> {
    core()?.set_setting(&key, &value_json)
}

pub fn export_database_backup(output_path: String) -> Result<(), String> {
    core()?.export_database_backup(PathBuf::from(output_path))
}

pub fn import_database_backup(input_path: String) -> Result<(), String> {
    core()?.import_database_backup(PathBuf::from(input_path))
}

pub fn open_containing_folder(path: String) -> Result<(), String> {
    let path = PathBuf::from(path);
    let target = if path.is_dir() {
        path.as_path()
    } else {
        path.parent().unwrap_or(path.as_path())
    };
    open_path(target)
}

#[cfg(target_os = "windows")]
fn open_path(path: &std::path::Path) -> Result<(), String> {
    std::process::Command::new("explorer")
        .arg(path)
        .spawn()
        .map_err(|e| format!("failed opening folder: {e}"))?;
    Ok(())
}

#[cfg(target_os = "macos")]
fn open_path(path: &std::path::Path) -> Result<(), String> {
    std::process::Command::new("open")
        .arg(path)
        .spawn()
        .map_err(|e| format!("failed opening folder: {e}"))?;
    Ok(())
}

#[cfg(all(unix, not(target_os = "macos")))]
fn open_path(path: &std::path::Path) -> Result<(), String> {
    std::process::Command::new("xdg-open")
        .arg(path)
        .spawn()
        .map_err(|e| format!("failed opening folder: {e}"))?;
    Ok(())
}
