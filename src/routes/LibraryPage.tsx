import { useEffect, useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Link } from "@tanstack/react-router";
import {
  Bookmark,
  BookmarkCheck,
  BookOpen,
  Clock,
  Copy,
  FolderOpen,
  LayoutGrid,
  List,
  RefreshCw,
  Search,
  Type,
} from "lucide-react";
import {
  addComicBookmark,
  initDb,
  listAllBookmarks,
  listComicsWithProgress,
  listLibraryComicsRaw,
  listReadingHistory,
  openContainingFolder,
  removeComicBookmark,
} from "../api/tauri";
import { ComicItem } from "../components/ComicItem";
import { EmptyState, ErrorState, SkeletonList } from "../components/feedback/states";
import { ContextMenu, useContextMenu, type ContextMenuItem } from "../components/ui/context-menu";
import { ScrollToTop } from "../components/ui/scroll-to-top";
import { VirtualList } from "../components/ui/virtual-list";
import { useAppI18n } from "../i18n";
import { unixToLocale } from "../lib/utils";
import { useLibraryPreferences } from "../stores/libraryStore";
import { saveScroll, restoreScroll, setScrollKey } from "./Layout";
import type { ComicBookmark, RawComic, ReadingHistoryEntry, SortBy, SortDir } from "../types";

const ROW_HEIGHT = 56;

export function LibraryPage() {
  const { t } = useAppI18n();
  const queryClient = useQueryClient();
  const [searchText, setSearchText] = useState("");
  const [scrollEl, setScrollEl] = useState<HTMLElement | null>(null);

  const {
    sortBy,
    sortDir,
    viewMode,
    displayMode,
    inputPath,
    setSortBy,
    setSortDir,
    setViewMode,
    setDisplayMode,
    loadPreferences,
  } = useLibraryPreferences();
  const activeLibraryPath = inputPath.trim();

  useEffect(() => {
    setScrollEl(document.querySelector<HTMLElement>(".content-scroll"));
  }, []);

  useEffect(() => {
    initDb().catch(console.error);
  }, []);

  useEffect(() => {
    void loadPreferences();
  }, [loadPreferences]);

  useEffect(() => {
    setScrollKey(`library:${viewMode}`);
    restoreScroll(`library:${viewMode}`);
  }, []);

  const comicsQuery = useQuery({
    queryKey: ["raw-comics", sortBy, sortDir, activeLibraryPath],
    enabled: activeLibraryPath.length > 0,
    queryFn: () => listLibraryComicsRaw(sortBy, sortDir),
  });

  const bookmarksQuery = useQuery({
    queryKey: ["comic-bookmarks"],
    queryFn: listAllBookmarks,
  });

  const historyQuery = useQuery({
    queryKey: ["reading-history"],
    queryFn: listReadingHistory,
    staleTime: 0,
  });

  const comicsWithProgressQuery = useQuery({
    queryKey: ["comics-with-progress"],
    queryFn: listComicsWithProgress,
  });

  const readingSet = useMemo(() => {
    return new Set(comicsWithProgressQuery.data ?? []);
  }, [comicsWithProgressQuery.data]);

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

  const ctxMenu = useContextMenu();

  function comicContextItems(item: RawComic): ContextMenuItem[] {
    const isBookmarked = bookmarkSet.has(item.source_path);
    return [
      {
        label: t("library.openFolder"),
        icon: <FolderOpen size={14} />,
        onClick: () => void openContainingFolder(item.source_path),
      },
      {
        label: isBookmarked ? t("library.removeBookmark") : t("library.addBookmark"),
        icon: isBookmarked ? <BookmarkCheck size={14} /> : <Bookmark size={14} />,
        onClick: () => toggleBookmark(item.source_path),
      },
      {
        label: t("library.copyTitle"),
        icon: <Type size={14} />,
        onClick: () => void navigator.clipboard.writeText(item.title),
      },
      {
        label: t("library.copyPath"),
        icon: <Copy size={14} />,
        onClick: () => void navigator.clipboard.writeText(item.source_path),
      },
    ];
  }

  function historyContextItems(entry: ReadingHistoryEntry): ContextMenuItem[] {
    const isBookmarked = bookmarkSet.has(entry.comic_source_path);
    return [
      {
        label: t("library.openFolder"),
        icon: <FolderOpen size={14} />,
        onClick: () => void openContainingFolder(entry.comic_source_path),
      },
      {
        label: isBookmarked ? t("library.removeBookmark") : t("library.addBookmark"),
        icon: isBookmarked ? <BookmarkCheck size={14} /> : <Bookmark size={14} />,
        onClick: () => toggleBookmark(entry.comic_source_path),
      },
      {
        label: t("library.copyTitle"),
        icon: <Type size={14} />,
        onClick: () => void navigator.clipboard.writeText(entry.comic_title),
      },
      {
        label: t("library.copyPath"),
        icon: <Copy size={14} />,
        onClick: () => void navigator.clipboard.writeText(entry.comic_source_path),
      },
    ];
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

  const bookmarkedComics = useMemo(() => {
    const bookmarks = bookmarksQuery.data ?? [];
    const q = searchText.trim().toLowerCase();
    const filtered = bookmarks.filter((b) => {
      if (!q) return true;
      return (
        b.comic_title.toLowerCase().includes(q) || b.comic_source_path.toLowerCase().includes(q)
      );
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

  const historyEntries = useMemo(() => {
    const entries = historyQuery.data ?? [];
    const q = searchText.trim().toLowerCase();
    const seen = new Set<string>();
    const unique: ReadingHistoryEntry[] = [];
    for (const entry of entries) {
      if (seen.has(entry.comic_source_path)) continue;
      seen.add(entry.comic_source_path);
      if (
        q &&
        !entry.comic_title.toLowerCase().includes(q) &&
        !entry.comic_source_path.toLowerCase().includes(q)
      ) {
        continue;
      }
      unique.push(entry);
    }
    return unique;
  }, [historyQuery.data, searchText]);

  const sortLabel =
    viewMode === "bookmarks"
      ? t("library.bookmarkDate")
      : viewMode === "history"
        ? t("library.readDate")
        : t("library.folderDate");

  const libraryStats = useMemo(() => {
    const allComics = comicsQuery.data ?? [];
    let visible: number;
    if (viewMode === "bookmarks") visible = bookmarkedComics.length;
    else if (viewMode === "history") visible = historyEntries.length;
    else visible = filteredComics.length;
    return { totalComics: allComics.length, visibleComics: visible };
  }, [comicsQuery.data, filteredComics, bookmarkedComics, historyEntries, viewMode]);

  function switchViewMode(mode: typeof viewMode) {
    if (mode === viewMode) return;
    saveScroll(`library:${viewMode}`);
    setViewMode(mode);
    setScrollKey(`library:${mode}`);
    restoreScroll(`library:${mode}`);
  }

  function renderComicRow(index: number, item: RawComic) {
    return (
      <div onContextMenu={(e) => ctxMenu.show(e, comicContextItems(item))}>
        <ComicItem
          comic={item}
          variant={displayMode}
          index={index}
          isBookmarked={bookmarkSet.has(item.source_path)}
          isReading={readingSet.has(item.source_path)}
          onBookmark={() => toggleBookmark(item.source_path)}
        />
      </div>
    );
  }

  function renderHistoryRow(index: number, entry: ReadingHistoryEntry) {
    if (displayMode === "grid") {
      return (
        <Link
          to="/comic/$comicId"
          params={{ comicId: encodeURIComponent(entry.comic_source_path) }}
          title={entry.comic_title}
          className="flex cursor-pointer items-start gap-2.5 border-b border-r border-app-border bg-app-surface p-3 transition-colors hover:bg-app-bg"
          onContextMenu={(e) => ctxMenu.show(e, historyContextItems(entry))}
        >
          <div className="flex h-16 w-14 flex-shrink-0 items-center justify-center rounded-lg border border-app-border bg-app-accent/15">
            <span className="font-display text-sm font-extrabold text-app-accent opacity-80">
              {entry.comic_title
                .split(" ")
                .slice(0, 2)
                .map((w) => w[0] || "")
                .join("")
                .toUpperCase()}
            </span>
          </div>
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-medium hover:underline">{entry.comic_title}</p>
            <p className="mt-1 truncate text-xs text-app-muted">{entry.chapter_title}</p>
            <div className="mt-1 flex items-center justify-between">
              <span className="text-[10px] text-app-muted">{unixToLocale(entry.updated_at)}</span>
              <button
                type="button"
                onClick={(e) => {
                  e.preventDefault();
                  e.stopPropagation();
                  toggleBookmark(entry.comic_source_path);
                }}
                className={`transition-colors ${
                  bookmarkSet.has(entry.comic_source_path)
                    ? "text-app-accent"
                    : "text-app-muted hover:text-app-text"
                }`}
              >
                {bookmarkSet.has(entry.comic_source_path) ? (
                  <BookmarkCheck size={16} />
                ) : (
                  <Bookmark size={16} />
                )}
              </button>
            </div>
          </div>
        </Link>
      );
    }
    return (
      <Link
        to="/comic/$comicId"
        params={{ comicId: encodeURIComponent(entry.comic_source_path) }}
        className="flex cursor-pointer items-center gap-2.5 border-b border-app-border bg-app-surface px-4 py-3 transition-colors hover:bg-app-bg"
        onContextMenu={(e) => ctxMenu.show(e, historyContextItems(entry))}
      >
        <span className="w-6 flex-shrink-0 text-right font-display text-xs font-bold text-app-muted">
          {String(index + 1).padStart(2, "0")}
        </span>
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-medium hover:underline">{entry.comic_title}</p>
          <p className="mt-0.5 truncate text-xs text-app-muted">
            {entry.chapter_title}
            {!entry.is_read && entry.total_pages > 0
              ? ` — p.${entry.last_page + 1}/${entry.total_pages}`
              : entry.is_read
                ? ` — ${t("comic.status.read")}`
                : ""}
          </p>
        </div>
        <div className="flex flex-shrink-0 items-center gap-2">
          <span className="hidden text-xs text-app-muted sm:block">
            {unixToLocale(entry.updated_at)}
          </span>
          <button
            type="button"
            onClick={(e) => {
              e.preventDefault();
              e.stopPropagation();
              toggleBookmark(entry.comic_source_path);
            }}
            className={`transition-colors ${
              bookmarkSet.has(entry.comic_source_path)
                ? "text-app-accent"
                : "text-app-muted hover:text-app-text"
            }`}
          >
            {bookmarkSet.has(entry.comic_source_path) ? (
              <BookmarkCheck size={18} />
            ) : (
              <Bookmark size={18} />
            )}
          </button>
        </div>
      </Link>
    );
  }

  function renderBookmarkRow(index: number, bm: ComicBookmark) {
    if (displayMode === "grid") {
      return (
        <div
          title={bm.comic_title || bm.comic_source_path}
          className="flex cursor-pointer items-start gap-2.5 border-b border-r border-app-border bg-app-surface p-3 transition-colors hover:bg-app-bg"
          onContextMenu={(e) =>
            ctxMenu.show(
              e,
              comicContextItems({
                source_path: bm.comic_source_path,
                title: bm.comic_title,
              } as RawComic),
            )
          }
        >
          <div className="flex h-16 w-14 flex-shrink-0 items-center justify-center rounded-lg border border-app-border bg-app-accent/15">
            <span className="font-display text-sm font-extrabold text-app-accent opacity-80">
              {(bm.comic_title || bm.comic_source_path)
                .split(" ")
                .slice(0, 2)
                .map((w) => w[0] || "")
                .join("")
                .toUpperCase()}
            </span>
          </div>
          <div className="min-w-0 flex-1">
            <Link
              to="/comic/$comicId"
              params={{ comicId: encodeURIComponent(bm.comic_source_path) }}
              className="truncate text-sm font-medium hover:underline"
            >
              {bm.comic_title || bm.comic_source_path}
            </Link>
            <div className="mt-1 flex items-center justify-between">
              <span className="text-[10px] text-app-muted">{unixToLocale(bm.created_at)}</span>
              <button
                type="button"
                onClick={(e) => {
                  e.stopPropagation();
                  toggleBookmark(bm.comic_source_path);
                }}
                className="text-app-accent transition-colors hover:opacity-70"
              >
                <BookmarkCheck size={16} />
              </button>
            </div>
          </div>
        </div>
      );
    }
    return (
      <div
        className="flex cursor-pointer items-center gap-2.5 border-b border-app-border bg-app-surface px-4 py-3 transition-colors hover:bg-app-bg"
        onContextMenu={(e) =>
          ctxMenu.show(
            e,
            comicContextItems({
              source_path: bm.comic_source_path,
              title: bm.comic_title,
            } as RawComic),
          )
        }
      >
        <span className="w-6 flex-shrink-0 text-right font-display text-xs font-bold text-app-muted">
          {String(index + 1).padStart(2, "0")}
        </span>
        <div className="min-w-0 flex-1">
          <Link
            to="/comic/$comicId"
            params={{ comicId: encodeURIComponent(bm.comic_source_path) }}
            className="truncate text-sm font-medium hover:underline"
          >
            {bm.comic_title || bm.comic_source_path}
          </Link>
          <p className="mt-0.5 truncate text-xs text-app-muted">{bm.comic_source_path}</p>
        </div>
        <div className="flex flex-shrink-0 items-center gap-2">
          <span className="hidden text-xs text-app-muted sm:block">
            {unixToLocale(bm.created_at)}
          </span>
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation();
              toggleBookmark(bm.comic_source_path);
            }}
            className="text-app-accent transition-colors hover:opacity-70"
          >
            <BookmarkCheck size={18} />
          </button>
        </div>
      </div>
    );
  }

  const currentItems =
    viewMode === "history"
      ? historyEntries
      : viewMode === "bookmarks"
        ? bookmarkedComics
        : filteredComics;

  const isEmpty =
    viewMode === "history"
      ? historyEntries.length === 0
      : viewMode === "bookmarks"
        ? bookmarkedComics.length === 0
        : filteredComics.length === 0;

  return (
    <section className="flex flex-col">
      {/* Header */}
      <div className="border-b border-app-border bg-app-surface">
        <div className="flex items-center justify-between px-5 pt-3 pb-0">
          <nav className="flex">
            <button
              type="button"
              onClick={() => switchViewMode("history")}
              className={`flex items-center gap-2 border-b-2 px-5 py-3 text-sm font-medium transition-all ${
                viewMode === "history"
                  ? "border-app-accent text-app-accent"
                  : "border-transparent text-app-muted hover:text-app-text"
              }`}
            >
              <Clock size={16} />
              {t("library.history")}
            </button>
            <button
              type="button"
              onClick={() => switchViewMode("library")}
              className={`flex items-center gap-2 border-b-2 px-5 py-3 text-sm font-medium transition-all ${
                viewMode === "library"
                  ? "border-app-accent text-app-accent"
                  : "border-transparent text-app-muted hover:text-app-text"
              }`}
            >
              <BookOpen size={16} />
              {t("library.library")}
            </button>
            <button
              type="button"
              onClick={() => switchViewMode("bookmarks")}
              className={`flex items-center gap-2 border-b-2 px-5 py-3 text-sm font-medium transition-all ${
                viewMode === "bookmarks"
                  ? "border-app-accent text-app-accent"
                  : "border-transparent text-app-muted hover:text-app-text"
              }`}
            >
              <Bookmark size={16} />
              {t("library.bookmarks")}
            </button>
          </nav>
          <button
            type="button"
            onClick={() => {
              void comicsQuery.refetch();
              void historyQuery.refetch();
              void bookmarksQuery.refetch();
            }}
            className="flex h-7 w-7 items-center justify-center rounded-md text-app-muted transition-all hover:bg-app-bg hover:text-app-text"
            title={t("library.refresh")}
          >
            <RefreshCw size={14} />
          </button>
        </div>
      </div>

      {/* Body */}
      <div className="space-y-4 px-5 py-4">
        {/* Stats */}
        <div className="grid grid-cols-3 gap-3">
          <div className="rounded-lg border border-app-border bg-app-surface px-4 py-3">
            <div className="font-display text-2xl font-extrabold leading-none">
              {libraryStats.totalComics}
              <sup className="ml-0.5 text-[11px] font-medium not-italic text-app-accent">komik</sup>
            </div>
            <div className="mt-1.5 text-[10px] uppercase tracking-widest text-app-muted">
              Total Library
            </div>
          </div>
          <div className="rounded-lg border border-app-border bg-app-surface px-4 py-3">
            <div className="font-display text-2xl font-extrabold leading-none">
              {historyEntries.length}
            </div>
            <div className="mt-1.5 text-[10px] uppercase tracking-widest text-app-muted">
              Dibaca
            </div>
          </div>
          <div className="rounded-lg border border-app-border bg-app-surface px-4 py-3">
            <div className="font-display text-2xl font-extrabold leading-none">
              {bookmarkedComics.length}
            </div>
            <div className="mt-1.5 text-[10px] uppercase tracking-widest text-app-muted">
              Bookmark
            </div>
          </div>
        </div>

        {/* Toolbar */}
        <div className="flex items-center gap-3">
          <div className="flex min-w-0 flex-1 items-center gap-2 rounded-lg border border-app-border bg-app-surface px-3.5 h-10 transition-all focus-within:border-app-accent">
            <Search size={16} className="flex-shrink-0 text-app-muted" />
            <input
              type="text"
              value={searchText}
              onChange={(e) => setSearchText(e.target.value)}
              placeholder={t("library.searchPlaceholder")}
              className="min-w-0 flex-1 border-none bg-transparent text-sm outline-none placeholder:text-app-muted"
            />
          </div>
          {viewMode !== "history" ? (
            <>
              <select
                value={sortBy}
                onChange={(e) => setSortBy(e.target.value as SortBy)}
                className="h-10 flex-shrink-0 cursor-pointer rounded-lg border border-app-border bg-app-surface px-3 text-sm text-app-muted transition-all focus:border-app-accent focus:outline-none"
              >
                <option value="name">{t("common.name")}</option>
                <option value="folder_date">{sortLabel}</option>
              </select>
              <select
                value={sortDir}
                onChange={(e) => setSortDir(e.target.value as SortDir)}
                className="h-10 flex-shrink-0 cursor-pointer rounded-lg border border-app-border bg-app-surface px-3 text-sm text-app-muted transition-all focus:border-app-accent focus:outline-none"
              >
                <option value="asc">{t("common.asc")}</option>
                <option value="desc">{t("common.desc")}</option>
              </select>
            </>
          ) : null}
          <div className="flex flex-shrink-0 overflow-hidden rounded-lg border border-app-border bg-app-surface">
            <button
              type="button"
              onClick={() => setDisplayMode("grid")}
              aria-label="Grid"
              title="Grid"
              className={`flex h-10 w-10 items-center justify-center text-sm transition-all ${
                displayMode === "grid"
                  ? "bg-app-accent/10 text-app-accent"
                  : "text-app-muted hover:text-app-text"
              }`}
            >
              <LayoutGrid size={16} />
            </button>
            <button
              type="button"
              onClick={() => setDisplayMode("list")}
              aria-label="List"
              title="List"
              className={`flex h-10 w-10 items-center justify-center text-sm transition-all ${
                displayMode === "list"
                  ? "bg-app-accent/10 text-app-accent"
                  : "text-app-muted hover:text-app-text"
              }`}
            >
              <List size={16} />
            </button>
          </div>
        </div>

        {/* Section label */}
        <div className="flex items-center justify-between">
          <span className="font-display text-[11px] font-extrabold uppercase tracking-[0.1em] text-app-muted">
            {viewMode === "history"
              ? t("library.history")
              : viewMode === "bookmarks"
                ? t("library.bookmarks")
                : t("library.title")}
          </span>
          <span className="text-[11px] text-app-accent opacity-60 transition-opacity hover:opacity-100">
            {libraryStats.visibleComics} item
          </span>
        </div>

        {/* List/Grid */}
        {comicsQuery.isPending ? (
          <SkeletonList rows={7} />
        ) : comicsQuery.isError ? (
          <ErrorState
            title={t("library.readError.title")}
            description={t("library.readError.description")}
            onRetry={() => void comicsQuery.refetch()}
          />
        ) : isEmpty ? (
          <EmptyState
            title={
              viewMode === "history"
                ? t("library.historyEmpty.title")
                : viewMode === "bookmarks"
                  ? t("library.bookmarksEmpty.title")
                  : t("library.emptyFilter.title")
            }
            description={
              viewMode === "history"
                ? t("library.historyEmpty.description")
                : viewMode === "bookmarks"
                  ? t("library.bookmarksEmpty.description")
                  : t("library.emptyFilter.description")
            }
          />
        ) : (
          <div className="overflow-hidden rounded-xl border border-app-border">
            <VirtualList
              count={currentItems.length}
              estimateSize={displayMode === "grid" ? 120 : ROW_HEIGHT}
              scrollElement={scrollEl}
              columns={displayMode === "grid" ? 2 : 1}
              gap={1}
              items={currentItems as unknown[]}
              getItemKey={(i) => {
                if (viewMode === "history")
                  return `${(currentItems[i] as ReadingHistoryEntry).comic_source_path}-${(currentItems[i] as ReadingHistoryEntry).chapter_id}`;
                if (viewMode === "bookmarks") return (currentItems[i] as ComicBookmark).id;
                return (currentItems[i] as RawComic).key;
              }}
              renderItem={(i, item) => {
                if (viewMode === "history") return renderHistoryRow(i, item as ReadingHistoryEntry);
                if (viewMode === "bookmarks") return renderBookmarkRow(i, item as ComicBookmark);
                return renderComicRow(i, item as RawComic);
              }}
              measureElement
            />
          </div>
        )}
      </div>

      <ScrollToTop />
      <ContextMenu state={ctxMenu.state} onClose={ctxMenu.close} />
    </section>
  );
}
