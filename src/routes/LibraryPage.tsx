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
          onBookmark={() => toggleBookmark(item.source_path)}
        />
      </div>
    );
  }

  function renderHistoryRow(index: number, entry: ReadingHistoryEntry) {
    return (
      <div
        className="flex cursor-pointer items-center gap-2.5 bg-[var(--card)] px-4 py-2.5 transition-colors hover:bg-[var(--muted)]"
        onContextMenu={(e) => ctxMenu.show(e, historyContextItems(entry))}
      >
        <span className="w-5 flex-shrink-0 text-right font-display text-[11px] font-bold text-neutral-800">
          {String(index + 1).padStart(2, "0")}
        </span>
        <div className="min-w-0 flex-1">
          <p className="truncate text-[12px] font-medium text-neutral-300">{entry.comic_title}</p>
          <p className="mt-0.5 truncate text-[10px] text-[#2a3d4f]">
            {entry.chapter_title}
            {!entry.is_read && entry.total_pages > 0
              ? ` — p.${entry.last_page + 1}/${entry.total_pages}`
              : entry.is_read
                ? ` — ${t("comic.status.read")}`
                : ""}
          </p>
        </div>
        <div className="flex flex-shrink-0 items-center gap-2">
          <span className="hidden text-[10px] text-neutral-700 sm:block">
            {unixToLocale(entry.updated_at)}
          </span>
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation();
              toggleBookmark(entry.comic_source_path);
            }}
            className={`text-sm transition-colors ${
              bookmarkSet.has(entry.comic_source_path)
                ? "text-[var(--accent)]"
                : "text-neutral-800 hover:text-neutral-500"
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
    );
  }

  function renderBookmarkRow(index: number, bm: ComicBookmark) {
    return (
      <div
        className="flex cursor-pointer items-center gap-2.5 bg-[var(--card)] px-4 py-2.5 transition-colors hover:bg-[var(--muted)]"
        onContextMenu={(e) => ctxMenu.show(e, comicContextItems({ source_path: bm.comic_source_path, title: bm.comic_title } as RawComic))}
      >
        <span className="w-5 flex-shrink-0 text-right font-display text-[11px] font-bold text-neutral-800">
          {String(index + 1).padStart(2, "0")}
        </span>
        <div className="min-w-0 flex-1">
          <Link
            to="/comic/$comicId"
            params={{ comicId: encodeURIComponent(bm.comic_source_path) }}
            className="truncate text-[12px] font-medium text-neutral-300"
          >
            {bm.comic_title || bm.comic_source_path}
          </Link>
          <p className="mt-0.5 truncate text-[10px] text-[#2a3d4f]">{bm.comic_source_path}</p>
        </div>
        <div className="flex flex-shrink-0 items-center gap-2">
          <span className="hidden text-[10px] text-neutral-700 sm:block">
            {unixToLocale(bm.created_at)}
          </span>
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation();
              toggleBookmark(bm.comic_source_path);
            }}
            className="text-sm text-[var(--accent)] transition-colors hover:opacity-70"
          >
            <BookmarkCheck size={16} />
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
      <div className="border-b border-[var(--border)] bg-[var(--header)]">
        <div className="flex items-center justify-between px-5 pt-4 pb-0">
          <span className="font-display text-xl font-extrabold tracking-tight">
            Comic<span className="text-[var(--accent)]">RD</span>
          </span>
          <div className="flex gap-1.5">
            <button
              type="button"
              onClick={() => {
                void comicsQuery.refetch();
                void historyQuery.refetch();
                void bookmarksQuery.refetch();
              }}
              className="flex h-8 w-8 items-center justify-center rounded-lg border border-[var(--border)] bg-white/5 text-neutral-500 transition-all hover:border-[var(--border-accent)] hover:bg-[var(--accent)]/5 hover:text-[var(--accent)]"
              title={t("library.refresh")}
            >
              <RefreshCw size={14} />
            </button>
          </div>
        </div>

        {/* Tabs */}
        <nav className="mt-3 flex">
          <button
            type="button"
            onClick={() => switchViewMode("history")}
            className={`flex items-center gap-1.5 border-b-2 px-5 py-2.5 text-xs font-medium transition-all ${
              viewMode === "history"
                ? "border-[var(--accent)] text-[var(--accent)]"
                : "border-transparent text-neutral-600 hover:text-neutral-400"
            }`}
          >
            <Clock size={14} />
            {t("library.history")}
          </button>
          <button
            type="button"
            onClick={() => switchViewMode("library")}
            className={`flex items-center gap-1.5 border-b-2 px-5 py-2.5 text-xs font-medium transition-all ${
              viewMode === "library"
                ? "border-[var(--accent)] text-[var(--accent)]"
                : "border-transparent text-neutral-600 hover:text-neutral-400"
            }`}
          >
            <BookOpen size={14} />
            {t("library.library")}
          </button>
          <button
            type="button"
            onClick={() => switchViewMode("bookmarks")}
            className={`flex items-center gap-1.5 border-b-2 px-5 py-2.5 text-xs font-medium transition-all ${
              viewMode === "bookmarks"
                ? "border-[var(--accent)] text-[var(--accent)]"
                : "border-transparent text-neutral-600 hover:text-neutral-400"
            }`}
          >
            <Bookmark size={14} />
            {t("library.bookmarks")}
          </button>
        </nav>
      </div>

      {/* Body */}
      <div className="space-y-4 px-5 py-4">
        {/* Stats */}
        <div className="grid grid-cols-3 gap-2">
          <div className="rounded-xl border border-[var(--border)] bg-[var(--input)] px-3.5 py-2.5">
            <div className="font-display text-lg font-extrabold leading-none text-white">
              {libraryStats.totalComics}
              <sup className="ml-0.5 text-[10px] font-medium not-italic text-[var(--accent)]">
                komik
              </sup>
            </div>
            <div className="mt-1 text-[9px] uppercase tracking-widest text-neutral-600">
              Total Library
            </div>
          </div>
          <div className="rounded-xl border border-[var(--border)] bg-[var(--input)] px-3.5 py-2.5">
            <div className="font-display text-lg font-extrabold leading-none text-white">
              {historyEntries.length}
            </div>
            <div className="mt-1 text-[9px] uppercase tracking-widest text-neutral-600">
              Dibaca
            </div>
          </div>
          <div className="rounded-xl border border-[var(--border)] bg-[var(--input)] px-3.5 py-2.5">
            <div className="font-display text-lg font-extrabold leading-none text-white">
              {bookmarkedComics.length}
            </div>
            <div className="mt-1 text-[9px] uppercase tracking-widest text-neutral-600">
              Bookmark
            </div>
          </div>
        </div>

        {/* Toolbar */}
        <div className="flex items-center gap-2">
          <div className="flex min-w-0 flex-1 items-center gap-2 rounded-lg border border-[var(--border)] bg-[var(--input)] px-3 h-9 transition-all focus-within:border-[var(--border-accent)]">
            <Search size={14} className="flex-shrink-0 text-neutral-600" />
            <input
              type="text"
              value={searchText}
              onChange={(e) => setSearchText(e.target.value)}
              placeholder={t("library.searchPlaceholder")}
              className="min-w-0 flex-1 border-none bg-transparent text-xs text-neutral-300 outline-none placeholder-neutral-700"
            />
          </div>
          {viewMode !== "history" ? (
            <>
              <select
                value={sortBy}
                onChange={(e) => setSortBy(e.target.value as SortBy)}
                className="h-9 flex-shrink-0 cursor-pointer rounded-lg border border-[var(--border)] bg-[var(--input)] px-2.5 text-xs text-neutral-500 transition-all focus:border-[var(--border-accent)] focus:outline-none"
              >
                <option value="name">{t("common.name")}</option>
                <option value="folder_date">{sortLabel}</option>
              </select>
              <select
                value={sortDir}
                onChange={(e) => setSortDir(e.target.value as SortDir)}
                className="h-9 flex-shrink-0 cursor-pointer rounded-lg border border-[var(--border)] bg-[var(--input)] px-2.5 text-xs text-neutral-500 transition-all focus:border-[var(--border-accent)] focus:outline-none"
              >
                <option value="asc">{t("common.asc")}</option>
                <option value="desc">{t("common.desc")}</option>
              </select>
            </>
          ) : null}
          {/* View toggle */}
          <div className="flex flex-shrink-0 overflow-hidden rounded-lg border border-[var(--border)] bg-[var(--input)]">
            <button
              type="button"
              onClick={() => setDisplayMode("grid")}
              aria-label="Grid"
              className={`flex h-9 w-9 items-center justify-center text-sm transition-all ${
                displayMode === "grid"
                  ? "bg-[var(--accent)]/10 text-[var(--accent)]"
                  : "text-neutral-600 hover:bg-white/4 hover:text-neutral-400"
              }`}
            >
              <LayoutGrid size={14} />
            </button>
            <button
              type="button"
              onClick={() => setDisplayMode("list")}
              aria-label="List"
              className={`flex h-9 w-9 items-center justify-center text-sm transition-all ${
                displayMode === "list"
                  ? "bg-[var(--accent)]/10 text-[var(--accent)]"
                  : "text-neutral-600 hover:bg-white/4 hover:text-neutral-400"
              }`}
            >
              <List size={14} />
            </button>
          </div>
        </div>

        {/* Section label */}
        <div className="flex items-center justify-between">
          <span className="font-display text-[10px] font-extrabold uppercase tracking-[0.1em] text-neutral-700">
            {viewMode === "history"
              ? t("library.history")
              : viewMode === "bookmarks"
                ? t("library.bookmarks")
                : t("library.title")}
          </span>
          <span className="text-[11px] text-[var(--accent)] opacity-60 transition-opacity hover:opacity-100">
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
          <div className="overflow-hidden rounded-xl border border-[var(--border)]">
            <VirtualList
              count={currentItems.length}
              estimateSize={ROW_HEIGHT}
              scrollElement={scrollEl}
              items={currentItems as unknown[]}
              getItemKey={(i) => {
                if (viewMode === "history") return `${(currentItems[i] as ReadingHistoryEntry).comic_source_path}-${(currentItems[i] as ReadingHistoryEntry).chapter_id}`;
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
