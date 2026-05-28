export type SortBy = "name" | "folder_date";
export type SortDir = "asc" | "desc";
export type ReaderMode = "webtoon";

export type Library = {
  id: number;
  path: string;
  created_at: number;
  updated_at: number;
};

export type Comic = {
  id: number;
  library_id: number;
  title: string;
  source_path: string;
  source_type: string;
  date_modified: number;
  updated_at: number;
  chapter_count: number;
  read_chapter_count: number;
  in_progress_chapter_count: number;
};

export type RawComic = {
  key: string;
  title: string;
  source_path: string;
  source_type: string;
  library_path: string;
  date_modified: number;
  chapter_count: number;
  read_chapter_count: number;
  in_progress_chapter_count: number;
};

export type Chapter = {
  id: number;
  comic_id: number;
  title: string;
  chapter_index: number;
  page_count: number;
  source_path: string;
  source_type: string;
  is_read: boolean;
  last_page: number;
  total_pages: number;
};

export type RawChapter = {
  key: string;
  title: string;
  chapter_index: number;
  source_path: string;
  source_type: string;
  page_count: number;
  is_read: boolean;
  last_page: number;
  total_pages: number;
};

export type PageInfo = {
  index: number;
  name: string;
};

export type Bookmark = {
  id: number;
  chapter_id: number;
  page: number;
  created_at: number;
  note: string;
};

export type ComicBookmark = {
  id: number;
  comic_source_path: string;
  comic_title: string;
  created_at: number;
};

export type ReadingHistoryEntry = {
  comic_source_path: string;
  comic_title: string;
  chapter_title: string;
  chapter_source_path: string;
  chapter_id: number;
  last_page: number;
  total_pages: number;
  is_read: boolean;
  updated_at: number;
};

export type ReadingProgress = {
  chapter_id: number;
  last_page: number;
  total_pages: number;
  mode: ReaderMode;
  is_read: boolean;
  updated_at: number;
};

export type SettingEntry = {
  key: string;
  value_json: string;
  updated_at: number;
};

export type ScanSummary = {
  comics: number;
  chapters: number;
};

export type LibraryScanStatus = {
  running: boolean;
  started_at: number | null;
  finished_at: number | null;
  last_summary: ScanSummary | null;
  error: string | null;
};

export type ChapterContext = {
  chapter_id: number;
  comic_id: number;
  comic_source_path: string;
  chapter_source_path: string;
  comic_title: string;
  title: string;
  chapter_index: number;
  chapter_position: number;
  chapter_total: number;
  prev_chapter_id: number | null;
  prev_chapter_title: string | null;
  next_chapter_id: number | null;
  next_chapter_title: string | null;
};
