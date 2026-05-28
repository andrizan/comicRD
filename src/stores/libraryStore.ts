import { create } from "zustand";
import { getSetting, setSetting } from "../api/tauri";
import type { SortBy, SortDir } from "../types";

export type ViewMode = "history" | "library" | "bookmarks";

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
  inputPath: string;
  chapterSortDir: SortDir;
  preferencesReady: boolean;
  setSortBy: (sortBy: SortBy) => void;
  setSortDir: (sortDir: SortDir) => void;
  setViewMode: (viewMode: ViewMode) => void;
  setInputPath: (inputPath: string) => void;
  setChapterSortDir: (dir: SortDir) => void;
  loadPreferences: () => Promise<void>;
}

export const usePreferencesStore = create<PreferencesState>((set, get) => ({
  sortBy: "name",
  sortDir: "asc",
  viewMode: "library",
  inputPath: "",
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

  setInputPath: (inputPath) => {
    set({ inputPath });
    if (get().preferencesReady) void setSetting("library_source_input", inputPath);
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
    const savedChapterSortDir = parseStoredString(await getSetting("chapter_sort_dir"));

    const patch: Partial<PreferencesState> = { preferencesReady: true };
    if (savedPath.trim()) patch.inputPath = savedPath.trim();
    if (savedSortBy === "name" || savedSortBy === "folder_date") patch.sortBy = savedSortBy;
    if (savedSortDir === "asc" || savedSortDir === "desc") patch.sortDir = savedSortDir;
    if (isViewMode(savedViewMode)) patch.viewMode = savedViewMode;
    if (savedChapterSortDir === "asc" || savedChapterSortDir === "desc")
      patch.chapterSortDir = savedChapterSortDir;
    set(patch);
  },
}));
