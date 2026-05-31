import { create } from "zustand";
import { useShallow } from "zustand/react/shallow";
import { getSetting, setSetting } from "@/api/tauri";
import type { SortBy, SortDir } from "@/types";

export type ViewMode = "history" | "library" | "bookmarks";
export type DisplayMode = "grid" | "list";

function parseStoredString(value: string | null): string {
  if (!value) return "";
  try {
    const parsed = JSON.parse(value);
    return typeof parsed === "string" ? parsed : "";
  } catch {
    return "";
  }
}

function isViewMode(value: string): value is ViewMode {
  return value === "history" || value === "library" || value === "bookmarks";
}

interface PreferencesState {
  sortBy: SortBy;
  sortDir: SortDir;
  viewMode: ViewMode;
  displayMode: DisplayMode;
  inputPath: string;
  chapterSortBy: SortBy;
  chapterSortDir: SortDir;
  preferencesReady: boolean;
  setSortBy: (sortBy: SortBy) => void;
  setSortDir: (sortDir: SortDir) => void;
  setViewMode: (viewMode: ViewMode) => void;
  setDisplayMode: (mode: DisplayMode) => void;
  setInputPath: (inputPath: string) => void;
  setChapterSortBy: (sortBy: SortBy) => void;
  setChapterSortDir: (dir: SortDir) => void;
  loadPreferences: () => Promise<void>;
}

export const usePreferencesStore = create<PreferencesState>((set, get) => ({
  sortBy: "name",
  sortDir: "asc",
  viewMode: "library",
  displayMode: "grid",
  inputPath: "",
  chapterSortBy: "name",
  chapterSortDir: "asc",
  preferencesReady: false,

  setSortBy: (sortBy) => {
    set({ sortBy });
    if (get().preferencesReady) void setSetting("library_sort_by", sortBy);
  },

  setSortDir: (sortDir) => {
    set({ sortDir });
    if (get().preferencesReady) void setSetting("library_sort_dir", sortDir);
  },

  setViewMode: (viewMode) => {
    set({ viewMode });
    if (get().preferencesReady) void setSetting("library_view_mode", viewMode);
  },

  setDisplayMode: (displayMode) => {
    set({ displayMode });
    if (get().preferencesReady) void setSetting("library_display_mode", displayMode);
  },

  setInputPath: (inputPath) => {
    set({ inputPath });
    if (get().preferencesReady) void setSetting("library_source_input", inputPath);
  },

  setChapterSortBy: (chapterSortBy) => {
    set({ chapterSortBy });
    if (get().preferencesReady) void setSetting("chapter_sort_by", chapterSortBy);
  },

  setChapterSortDir: (chapterSortDir) => {
    set({ chapterSortDir });
    if (get().preferencesReady) void setSetting("chapter_sort_dir", chapterSortDir);
  },

  loadPreferences: async () => {
    const savedPath = parseStoredString(await getSetting("library_source_input"));
    const savedSortBy = parseStoredString(await getSetting("library_sort_by"));
    const savedSortDir = parseStoredString(await getSetting("library_sort_dir"));
    const savedViewMode = parseStoredString(await getSetting("library_view_mode"));
    const savedDisplayMode = parseStoredString(await getSetting("library_display_mode"));
    const savedChapterSortDir = parseStoredString(await getSetting("chapter_sort_dir"));
    const savedChapterSortBy = parseStoredString(await getSetting("chapter_sort_by"));

    const patch: Partial<PreferencesState> = { preferencesReady: true };
    if (savedPath.trim()) patch.inputPath = savedPath.trim();
    if (savedSortBy === "name" || savedSortBy === "folder_date") patch.sortBy = savedSortBy;
    if (savedSortDir === "asc" || savedSortDir === "desc") patch.sortDir = savedSortDir;
    if (isViewMode(savedViewMode)) patch.viewMode = savedViewMode;
    if (savedDisplayMode === "grid" || savedDisplayMode === "list")
      patch.displayMode = savedDisplayMode;
    if (savedChapterSortDir === "asc" || savedChapterSortDir === "desc")
      patch.chapterSortDir = savedChapterSortDir;
    if (savedChapterSortBy === "name" || savedChapterSortBy === "folder_date")
      patch.chapterSortBy = savedChapterSortBy;
    set(patch);
  },
}));

const selectorLibraryView = (s: PreferencesState) => ({
  sortBy: s.sortBy,
  sortDir: s.sortDir,
  viewMode: s.viewMode,
  displayMode: s.displayMode,
  inputPath: s.inputPath,
  setSortBy: s.setSortBy,
  setSortDir: s.setSortDir,
  setViewMode: s.setViewMode,
  setDisplayMode: s.setDisplayMode,
  loadPreferences: s.loadPreferences,
});

const selectorChapterSort = (s: PreferencesState) => ({
  chapterSortBy: s.chapterSortBy,
  chapterSortDir: s.chapterSortDir,
  setChapterSortBy: s.setChapterSortBy,
  setChapterSortDir: s.setChapterSortDir,
});

export const useLibraryPreferences = () => usePreferencesStore(useShallow(selectorLibraryView));

export const useChapterSort = () => usePreferencesStore(useShallow(selectorChapterSort));
