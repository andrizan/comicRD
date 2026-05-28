import { useEffect, useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Link } from "@tanstack/react-router";
import { Bookmark, BookmarkCheck, RefreshCw, Search } from "lucide-react";
import {
  addComicBookmark,
  getSetting,
  initDb,
  listAllBookmarks,
  listLibraryComicsRaw,
  removeComicBookmark,
  setSetting,
} from "../api/tauri";
import { EmptyState, ErrorState, SkeletonList } from "../components/feedback/states";
import { Button } from "../components/ui/button";
import { useAppI18n } from "../i18n";
import { unixToLocale } from "../lib/utils";
import type { ComicBookmark, RawComic, SortBy, SortDir } from "../types";

function parseStoredString(value: string | null): string {
  if (!value) return "";
  try {
    const parsed = JSON.parse(value);
    return typeof parsed === "string" ? parsed : "";
  } catch {
    return "";
  }
}

function isViewMode(value: string): value is "all" | "by_folder" | "bookmarks" {
  return value === "all" || value === "by_folder" || value === "bookmarks";
}

export function LibraryPage() {
  const { t } = useAppI18n();
  const queryClient = useQueryClient();
  const [inputPath, setInputPath] = useState("");
  const [sortBy, setSortBy] = useState<SortBy>("name");
  const [sortDir, setSortDir] = useState<SortDir>("asc");
  const [viewMode, setViewMode] = useState<"all" | "by_folder" | "bookmarks">("all");
  const [searchText, setSearchText] = useState("");
  const [preferencesReady, setPreferencesReady] = useState(false);
  const activeLibraryPath = inputPath.trim();

  useEffect(() => {
    initDb().catch(console.error);
  }, []);

  useEffect(() => {
    let active = true;
    void (async () => {
      const savedPath = parseStoredString(await getSetting("library_source_input"));
      const savedSortBy = parseStoredString(await getSetting("library_sort_by"));
      const savedSortDir = parseStoredString(await getSetting("library_sort_dir"));
      const savedViewMode = parseStoredString(await getSetting("library_view_mode"));
      if (!active) return;
      if (savedPath.trim()) setInputPath(savedPath.trim());
      if (savedSortBy === "name" || savedSortBy === "folder_date") {
        setSortBy(savedSortBy);
      }
      if (savedSortDir === "asc" || savedSortDir === "desc") {
        setSortDir(savedSortDir);
      }
      if (isViewMode(savedViewMode)) {
        setViewMode(savedViewMode);
      }
      setPreferencesReady(true);
    })();
    return () => {
      active = false;
    };
  }, []);

  useEffect(() => {
    if (!preferencesReady) return;
    void setSetting("library_sort_by", sortBy);
  }, [preferencesReady, sortBy]);

  useEffect(() => {
    if (!preferencesReady) return;
    void setSetting("library_sort_dir", sortDir);
  }, [preferencesReady, sortDir]);

  useEffect(() => {
    if (!preferencesReady) return;
    void setSetting("library_view_mode", viewMode);
  }, [preferencesReady, viewMode]);

  const comicsQuery = useQuery({
    queryKey: ["raw-comics", sortBy, sortDir, activeLibraryPath],
    enabled: activeLibraryPath.length > 0,
    queryFn: () => listLibraryComicsRaw(sortBy, sortDir),
  });

  const bookmarksQuery = useQuery({
    queryKey: ["comic-bookmarks"],
    queryFn: listAllBookmarks,
  });

  const bookmarkSet = useMemo(() => {
    const set = new Set<string>();
    for (const b of bookmarksQuery.data ?? []) {
      set.add(b.comic_source_path);
    }
    return set;
  }, [bookmarksQuery.data]);

  const addBookmarkMutation = useMutation({
    mutationFn: (comicSourcePath: string) => addComicBookmark(comicSourcePath),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: ["comic-bookmarks"] }),
  });

  const removeBookmarkMutation = useMutation({
    mutationFn: (comicSourcePath: string) => removeComicBookmark(comicSourcePath),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: ["comic-bookmarks"] }),
  });

  function toggleBookmark(comicSourcePath: string) {
    if (bookmarkSet.has(comicSourcePath)) {
      removeBookmarkMutation.mutate(comicSourcePath);
    } else {
      addBookmarkMutation.mutate(comicSourcePath);
    }
  }

  const filteredComics = useMemo(
    () =>
      (comicsQuery.data ?? []).filter((comic) => {
        const q = searchText.trim().toLowerCase();
        if (!q) return true;
        return comic.title.toLowerCase().includes(q) || comic.source_path.toLowerCase().includes(q);
      }),
    [comicsQuery.data, searchText],
  );

  const groupedComics = useMemo(() => {
    const groups = new Map<string, RawComic[]>();
    for (const comic of filteredComics) {
      const current = groups.get(comic.library_path) ?? [];
      current.push(comic);
      groups.set(comic.library_path, current);
    }
    return groups;
  }, [filteredComics]);

  const bookmarkedComics = useMemo(() => {
    const bookmarks = bookmarksQuery.data ?? [];
    const q = searchText.trim().toLowerCase();
    const filtered = bookmarks.filter((b) => {
      if (!q) return true;
      return b.comic_title.toLowerCase().includes(q) || b.comic_source_path.toLowerCase().includes(q);
    });
    filtered.sort((a, b) => {
      let cmp: number;
      if (sortBy === "folder_date") {
        cmp = a.created_at - b.created_at;
      } else {
        cmp = a.comic_title.localeCompare(b.comic_title, undefined, {
          numeric: true,
          sensitivity: "base",
        });
      }
      return sortDir === "desc" ? -cmp : cmp;
    });
    return filtered;
  }, [bookmarksQuery.data, searchText, sortBy, sortDir]);

  const libraryStats = useMemo(() => {
    const allComics = comicsQuery.data ?? [];
    return {
      totalComics: allComics.length,
      visibleComics: viewMode === "bookmarks" ? bookmarkedComics.length : filteredComics.length,
    };
  }, [comicsQuery.data, filteredComics, bookmarkedComics, viewMode]);

  return (
    <section className="space-y-3">
      {!activeLibraryPath ? (
        <ErrorState
          title={t("library.notSet.title")}
          description={t("library.notSet.description")}
        />
      ) : null}

      <section className="rounded-lg border border-[var(--border)] bg-[var(--card)] p-4">
        <div className="mb-4 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h2 className="text-xl font-bold">{t("library.title")}</h2>
            <div className="mt-1.5 flex flex-wrap items-center gap-2 text-xs">
              <span className="rounded-full border border-[var(--border)] bg-[var(--background)] px-2.5 py-1 font-semibold">
                {t("library.count", { count: libraryStats.totalComics })}
              </span>
              {searchText.trim() ? (
                <span className="rounded-full border border-[var(--border)] bg-[var(--background)] px-2.5 py-1 font-semibold text-[var(--muted-foreground)]">
                  {t("library.shown", { count: libraryStats.visibleComics })}
                </span>
              ) : null}
            </div>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <div className="flex items-center rounded-md border border-[var(--border)] p-0.5">
              <button
                onClick={() => setViewMode("all")}
                className={`rounded px-2.5 py-1 text-xs font-semibold transition ${
                  viewMode === "all"
                    ? "bg-[var(--accent)] text-[var(--accent-foreground)]"
                    : "text-[var(--muted-foreground)] hover:text-[var(--foreground)]"
                }`}
              >
                {t("library.all")}
              </button>
              <button
                onClick={() => setViewMode("by_folder")}
                className={`rounded px-2.5 py-1 text-xs font-semibold transition ${
                  viewMode === "by_folder"
                    ? "bg-[var(--accent)] text-[var(--accent-foreground)]"
                    : "text-[var(--muted-foreground)] hover:text-[var(--foreground)]"
                }`}
              >
                {t("library.folder")}
              </button>
              <button
                onClick={() => setViewMode("bookmarks")}
                className={`rounded px-2.5 py-1 text-xs font-semibold transition ${
                  viewMode === "bookmarks"
                    ? "bg-[var(--accent)] text-[var(--accent-foreground)]"
                    : "text-[var(--muted-foreground)] hover:text-[var(--foreground)]"
                }`}
              >
                {t("library.bookmarks")}
              </button>
            </div>
            <Button
              onClick={() => void comicsQuery.refetch()}
              variant="ghost"
              disabled={!activeLibraryPath}
              title={t("library.refresh")}
              aria-label={t("library.refresh")}
              className="gap-1.5 px-2.5"
            >
              <RefreshCw size={14} />
            </Button>
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-2 mb-4">
          <div className="relative min-w-0 flex-1">
            <Search
              size={14}
              className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-[var(--muted-foreground)]"
            />
            <input
              value={searchText}
              onChange={(e) => setSearchText(e.target.value)}
              className="w-full rounded-md border border-[var(--border)] bg-[var(--background)] py-2 pl-8 pr-3 text-sm placeholder:text-[var(--muted-foreground)]"
              placeholder={t("library.searchPlaceholder")}
            />
          </div>
          <select
            value={sortBy}
            onChange={(e) => setSortBy(e.target.value as SortBy)}
            className="rounded-md border border-[var(--border)] bg-[var(--background)] px-2.5 py-2 text-sm"
          >
            <option value="name">{t("common.name")}</option>
            <option value="folder_date">
              {viewMode === "bookmarks" ? t("library.bookmarkDate") : t("library.folderDate")}
            </option>
          </select>
          <select
            value={sortDir}
            onChange={(e) => setSortDir(e.target.value as SortDir)}
            className="rounded-md border border-[var(--border)] bg-[var(--background)] px-2.5 py-2 text-sm"
          >
            <option value="asc">{t("common.asc")}</option>
            <option value="desc">{t("common.desc")}</option>
          </select>
        </div>

        {comicsQuery.isPending ? (
          <SkeletonList rows={7} />
        ) : comicsQuery.isError ? (
          <ErrorState
            title={t("library.readError.title")}
            description={t("library.readError.description")}
            onRetry={() => void comicsQuery.refetch()}
          />
        ) : viewMode === "bookmarks" ? (
          bookmarkedComics.length === 0 ? (
            <EmptyState
              title={t("library.bookmarksEmpty.title")}
              description={t("library.bookmarksEmpty.description")}
            />
          ) : (
            <div className="rounded-md border border-[var(--border)] bg-[var(--card)]">
              {bookmarkedComics.map((bm) => (
                <div
                  key={bm.id}
                  className="library-row flex items-center gap-3 border-b border-[var(--border)] p-3 last:border-b-0"
                >
                  <div className="min-w-0 flex-1">
                    <Link
                      to="/comic/$comicId"
                      params={{ comicId: encodeURIComponent(bm.comic_source_path) }}
                      className="text-base font-semibold text-[var(--accent)] hover:underline"
                    >
                      {bm.comic_title || bm.comic_source_path}
                    </Link>
                    <p className="text-xs text-[var(--muted-foreground)]">{bm.comic_source_path}</p>
                    <p className="text-xs text-[var(--muted-foreground)]">
                      {t("library.bookmarked", { value: unixToLocale(bm.created_at) })}
                    </p>
                  </div>
                  <button
                    onClick={() => toggleBookmark(bm.comic_source_path)}
                    className="text-[var(--accent)] hover:opacity-70"
                    title={t("library.removeBookmark")}
                  >
                    <BookmarkCheck size={18} />
                  </button>
                </div>
              ))}
            </div>
          )
        ) : viewMode === "all" ? (
          filteredComics.length === 0 ? (
            <EmptyState
              title={t("library.emptyFilter.title")}
              description={t("library.emptyFilter.description")}
            />
          ) : (
            <div className="rounded-md border border-[var(--border)] bg-[var(--card)]">
              {filteredComics.map((item) => (
                <div
                  key={item.key}
                  className="library-row flex items-center gap-3 border-b border-[var(--border)] p-3 last:border-b-0"
                >
                  <div className="min-w-0 flex-1">
                    <Link
                      to="/comic/$comicId"
                      params={{ comicId: encodeURIComponent(item.source_path) }}
                      className="text-base font-semibold text-[var(--accent)] hover:underline"
                    >
                      {item.title}
                    </Link>
                    <p className="text-xs text-[var(--muted-foreground)]">{item.source_path}</p>
                    <p className="text-xs text-[var(--muted-foreground)]">
                      {t("library.modified", { value: unixToLocale(item.date_modified) })}
                    </p>
                  </div>
                  <button
                    onClick={() => toggleBookmark(item.source_path)}
                    className={
                      bookmarkSet.has(item.source_path)
                        ? "text-[var(--accent)] hover:opacity-70"
                        : "text-[var(--muted-foreground)] hover:text-[var(--accent)]"
                    }
                    title={
                      bookmarkSet.has(item.source_path)
                        ? t("library.removeBookmark")
                        : t("library.addBookmark")
                    }
                  >
                    {bookmarkSet.has(item.source_path) ? (
                      <BookmarkCheck size={18} />
                    ) : (
                      <Bookmark size={18} />
                    )}
                  </button>
                </div>
              ))}
            </div>
          )
        ) : (
          <div className="space-y-3 rounded-md border border-[var(--border)] bg-[var(--card)] p-3">
            {Array.from(groupedComics.entries()).map(([libraryPath, items]) => (
              <div key={libraryPath} className="rounded-md border border-[var(--border)] p-3">
                <p className="text-sm font-bold">{libraryPath}</p>
                <p className="text-xs text-[var(--muted-foreground)]">
                  {t("library.groupCount", { count: items.length })}
                </p>
                <div className="mt-2 space-y-2">
                  {items.map((item) => (
                    <div
                      key={item.key}
                      className="library-row flex items-center gap-2 rounded-md bg-[var(--background)] px-2 py-2"
                    >
                      <div className="min-w-0 flex-1">
                        <Link
                          to="/comic/$comicId"
                          params={{ comicId: encodeURIComponent(item.source_path) }}
                          className="text-sm font-semibold text-[var(--accent)] hover:underline"
                        >
                          {item.title}
                        </Link>
                        <p className="text-xs text-[var(--muted-foreground)]">
                          {item.source_type} · {unixToLocale(item.date_modified)}
                        </p>
                      </div>
                      <button
                        onClick={() => toggleBookmark(item.source_path)}
                        className={
                          bookmarkSet.has(item.source_path)
                            ? "text-[var(--accent)] hover:opacity-70"
                            : "text-[var(--muted-foreground)] hover:text-[var(--accent)]"
                        }
                        title={
                          bookmarkSet.has(item.source_path)
                            ? t("library.removeBookmark")
                            : t("library.addBookmark")
                        }
                      >
                        {bookmarkSet.has(item.source_path) ? (
                          <BookmarkCheck size={16} />
                        ) : (
                          <Bookmark size={16} />
                        )}
                      </button>
                    </div>
                  ))}
                  {items.length === 0 ? (
                    <p className="text-xs text-[var(--muted-foreground)]">
                      {t("library.noComicsInFolder")}
                    </p>
                  ) : null}
                </div>
              </div>
            ))}
          </div>
        )}
      </section>
    </section>
  );
}
