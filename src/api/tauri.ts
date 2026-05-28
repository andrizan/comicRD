import { invoke } from "@tauri-apps/api/core";
import type {
  Bookmark,
  Chapter,
  ChapterContext,
  Comic,
  ComicBookmark,
  RawChapter,
  RawComic,
  LibraryScanStatus,
  Library,
  PageInfo,
  ReadingHistoryEntry,
  ReadingProgress,
  ReaderMode,
  ScanSummary,
  SettingEntry,
  SortBy,
  SortDir,
} from "../types";

export async function initDb() {
  await invoke("init_db");
}

export async function addLibrary(path: string) {
  return invoke<number>("add_library", { path });
}

export async function listLibraries() {
  return invoke<Library[]>("list_libraries");
}

export async function scanLibraries() {
  return invoke<ScanSummary>("scan_libraries");
}

export async function startScanLibraries() {
  return invoke<boolean>("start_scan_libraries");
}

export async function getLibraryScanStatus() {
  return invoke<LibraryScanStatus>("get_library_scan_status");
}

export async function listComics(sortBy: SortBy, sortDir: SortDir) {
  return invoke<Comic[]>("list_comics", { sortBy, sortDir });
}

export async function listChapters(comicId: number) {
  return invoke<Chapter[]>("list_chapters", { comicId });
}

export async function listLibraryComicsRaw(sortBy: SortBy, sortDir: SortDir) {
  return invoke<RawComic[]>("list_library_comics_raw", {
    sortBy,
    sortDir,
  });
}

export async function listComicChaptersRaw(comicSourcePath: string) {
  return invoke<RawChapter[]>("list_comic_chapters_raw", { comicSourcePath });
}

export async function openChapterForReading(payload: {
  comic_source_path: string;
  chapter_source_path: string;
}) {
  return invoke<number>("open_chapter_for_reading", { payload });
}

export async function getChapterContext(chapterId: number) {
  return invoke<ChapterContext | null>("get_chapter_context", { chapterId });
}

export async function getChapterPages(chapterId: number) {
  return invoke<PageInfo[]>("get_chapter_pages", { chapterId });
}

export async function saveProgress(payload: {
  chapter_id: number;
  last_page: number;
  total_pages: number;
  mode: ReaderMode;
  is_read: boolean;
}) {
  return invoke("save_progress", { payload });
}

export async function getProgress(chapterId: number) {
  return invoke<ReadingProgress | null>("get_progress", { chapterId });
}

export async function listBookmarks(chapterId: number) {
  return invoke<Bookmark[]>("list_bookmarks", { chapterId });
}

export async function addBookmark(payload: { chapter_id: number; page: number; note?: string }) {
  return invoke<number>("add_bookmark", { payload });
}

export async function removeBookmark(bookmarkId: number) {
  return invoke("remove_bookmark", { bookmarkId });
}

export async function listSettings() {
  return invoke<SettingEntry[]>("list_settings");
}

export async function getSetting(key: string) {
  return invoke<string | null>("get_setting", { key });
}

export async function setSetting(key: string, value: unknown) {
  return invoke("set_setting", {
    key,
    valueJson: JSON.stringify(value),
  });
}

export async function exportDatabaseBackup(outputPath: string) {
  return invoke("export_database_backup", { outputPath });
}

export async function importDatabaseBackup(inputPath: string) {
  return invoke("import_database_backup", { inputPath });
}

export async function listAllBookmarks() {
  return invoke<ComicBookmark[]>("list_all_bookmarks");
}

export async function addComicBookmark(comicSourcePath: string) {
  return invoke<number>("add_comic_bookmark", { comicSourcePath });
}

export async function removeComicBookmark(comicSourcePath: string) {
  return invoke("remove_comic_bookmark", { comicSourcePath });
}

export async function isComicBookmarked(comicSourcePath: string) {
  return invoke<boolean>("is_comic_bookmarked", { comicSourcePath });
}

export async function listReadingHistory() {
  return invoke<ReadingHistoryEntry[]>("list_reading_history");
}

export async function openContainingFolder(path: string) {
  return invoke("open_containing_folder", { path });
}
