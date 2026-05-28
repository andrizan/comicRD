import { useEffect, useMemo, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useNavigate, useParams } from "@tanstack/react-router";
import { ArrowLeft, Copy, FolderOpen, Heart, RefreshCw, Search, Type } from "lucide-react";
import {
  addChapterFavorite,
  listChapterFavorites,
  listComicChaptersRaw,
  openChapterForReading,
  openContainingFolder,
  removeChapterFavorite,
} from "../api/tauri";
import { EmptyState, ErrorState, SkeletonList } from "../components/feedback/states";
import { Button } from "../components/ui/button";
import { Card } from "../components/ui/card";
import { ContextMenu, useContextMenu, type ContextMenuItem } from "../components/ui/context-menu";
import { ScrollToTop } from "../components/ui/scroll-to-top";
import { VirtualList, type VirtualListHandle } from "../components/ui/virtual-list";
import { t as translate, useAppI18n } from "../i18n";
import { useChapterSort } from "../stores/libraryStore";
import { setScrollKey, restoreScroll, scrollPositions } from "./Layout";
import type { RawChapter, SortDir } from "../types";

function decodeComicPath(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

function titleFromPath(path: string): string {
  const parts = path.split("/").filter(Boolean);
  const name = parts[parts.length - 1] ?? "Comic";
  return name.replace(/\.(cbz|zip)$/i, "");
}

function chapterStatusLabel(chapter: RawChapter): string {
  if (chapter.is_read) return translate("comic.status.read");
  if (chapter.total_pages > 0 || chapter.page_count > 0) {
    const total = chapter.total_pages || chapter.page_count;
    return translate("comic.status.reading", {
      page: Math.min(chapter.last_page + 1, Math.max(total, 1)),
      total,
    });
  }
  return translate("comic.status.unread");
}

function chapterStatusClass(chapter: RawChapter): string {
  if (chapter.is_read) return "border-emerald-200 bg-emerald-50 text-emerald-700";
  if (chapter.total_pages > 0 || chapter.page_count > 0) {
    return "border-amber-200 bg-amber-50 text-amber-700";
  }
  return "border-[var(--border)] bg-[var(--card)] text-[var(--muted-foreground)]";
}

function lastChapterStorageKey(comicSourcePath: string): string {
  return `comicrd:last-chapter:${comicSourcePath}`;
}

const CHAPTER_ROW_HEIGHT = 72;

export function ComicPage() {
  const { t } = useAppI18n();
  const { comicId } = useParams({ from: "/comic/$comicId" });
  const navigate = useNavigate();
  const comicSourcePath = decodeComicPath(comicId);
  const comicTitle = titleFromPath(comicSourcePath);
  const [searchText, setSearchText] = useState("");
  const { chapterSortDir, setChapterSortDir } = useChapterSort();
  const [scrollEl, setScrollEl] = useState<HTMLElement | null>(null);
  const virtualListRef = useRef<VirtualListHandle>(null);
  const hasScrolledRef = useRef(false);

  useEffect(() => {
    const container = document.querySelector<HTMLElement>(".content-scroll");
    setScrollEl(container);
    const key = `comic:${comicSourcePath}`;
    setScrollKey(key);
    restoreScroll(key);
    if (container && !scrollPositions.has(key)) {
      container.scrollTo({ top: 0, behavior: "instant" });
    }
  }, [comicSourcePath]);

  useEffect(() => {
    hasScrolledRef.current = false;
  }, [comicSourcePath]);

  const chaptersQuery = useQuery({
    queryKey: ["raw-chapters", comicSourcePath],
    queryFn: () => listComicChaptersRaw(comicSourcePath),
  });

  const favoritesQuery = useQuery({
    queryKey: ["chapter-favorites", comicSourcePath],
    queryFn: () => listChapterFavorites(comicSourcePath),
  });

  const favoriteSet = useMemo(() => new Set(favoritesQuery.data ?? []), [favoritesQuery.data]);

  const queryClient = useQueryClient();

  const addFavoriteMutation = useMutation({
    mutationFn: (chapterSourcePath: string) =>
      addChapterFavorite(chapterSourcePath, comicSourcePath),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["chapter-favorites", comicSourcePath] });
    },
  });

  const removeFavoriteMutation = useMutation({
    mutationFn: (chapterSourcePath: string) => removeChapterFavorite(chapterSourcePath),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["chapter-favorites", comicSourcePath] });
    },
  });

  function toggleFavorite(chapterSourcePath: string) {
    if (favoriteSet.has(chapterSourcePath)) {
      removeFavoriteMutation.mutate(chapterSourcePath);
    } else {
      addFavoriteMutation.mutate(chapterSourcePath);
    }
  }

  const [showFavoritesOnly, setShowFavoritesOnly] = useState(false);

  const openChapterMutation = useMutation({
    mutationFn: openChapterForReading,
  });

  const filteredChapters = useMemo(() => {
    const filtered = (chaptersQuery.data ?? []).filter((chapter) => {
      const q = searchText.trim().toLowerCase();
      if (q && !chapter.title.toLowerCase().includes(q) && !chapter.source_path.toLowerCase().includes(q)) {
        return false;
      }
      if (showFavoritesOnly && !favoriteSet.has(chapter.source_path)) {
        return false;
      }
      return true;
    });
    filtered.sort((a, b) => {
      const order = a.title.localeCompare(b.title, undefined, {
        numeric: true,
        sensitivity: "base",
      });
      return chapterSortDir === "desc" ? -order : order;
    });
    return filtered;
  }, [chapterSortDir, chaptersQuery.data, searchText, showFavoritesOnly, favoriteSet]);
  const totalChapters = chaptersQuery.data?.length ?? 0;

  async function onOpenChapter(chapterSourcePath: string) {
    window.sessionStorage.setItem(lastChapterStorageKey(comicSourcePath), chapterSourcePath);
    const chapterId = await openChapterMutation.mutateAsync({
      comic_source_path: comicSourcePath,
      chapter_source_path: chapterSourcePath,
    });
    navigate({
      to: "/reader/$chapterId",
      params: { chapterId: String(chapterId) },
    });
  }

  const ctxMenu = useContextMenu();

  function chapterContextItems(chapter: RawChapter): ContextMenuItem[] {
    const isFav = favoriteSet.has(chapter.source_path);
    return [
      {
        label: t("comic.openChapter"),
        icon: <FolderOpen size={14} />,
        onClick: () => void onOpenChapter(chapter.source_path),
      },
      {
        label: isFav ? t("comic.removeFavorite") : t("comic.addFavorite"),
        icon: <Heart size={14} fill={isFav ? "currentColor" : "none"} />,
        onClick: () => toggleFavorite(chapter.source_path),
      },
      {
        label: t("library.openFolder"),
        icon: <FolderOpen size={14} />,
        onClick: () => void openContainingFolder(chapter.source_path),
      },
      {
        label: t("library.copyTitle"),
        icon: <Type size={14} />,
        onClick: () => void navigator.clipboard.writeText(chapter.title),
      },
      {
        label: t("library.copyPath"),
        icon: <Copy size={14} />,
        onClick: () => void navigator.clipboard.writeText(chapter.source_path),
      },
    ];
  }

  useEffect(() => {
    if (!chaptersQuery.isSuccess || filteredChapters.length === 0) return;
    if (hasScrolledRef.current) return;
    const lastChapter = window.sessionStorage.getItem(lastChapterStorageKey(comicSourcePath));
    if (!lastChapter) return;
    const idx = filteredChapters.findIndex((c) => c.source_path === lastChapter);
    if (idx < 0) return;
    hasScrolledRef.current = true;
    requestAnimationFrame(() => {
      virtualListRef.current?.scrollToIndex(idx, { align: "center" });
    });
  }, [chaptersQuery.isSuccess, comicSourcePath, filteredChapters]);

  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      if (e.key === "Escape") {
        e.preventDefault();
        navigate({ to: "/" });
      }
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [navigate]);

  const renderChapterItem = (_index: number, chapter: RawChapter) => (
    <div
      role="button"
      tabIndex={0}
      onClick={() => void onOpenChapter(chapter.source_path)}
      onContextMenu={(e) => ctxMenu.show(e, chapterContextItems(chapter))}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          void onOpenChapter(chapter.source_path);
        }
      }}
      className={`mb-2 flex flex-wrap items-center justify-between gap-3 rounded-md border border-[var(--border)] bg-[var(--card)] p-3 ${
        openChapterMutation.isPending
          ? "pointer-events-none opacity-60"
          : "cursor-pointer hover:bg-[var(--accent)]/5"
      }`}
    >
      <div className="min-w-0 flex-1">
        <p className="truncate font-semibold text-[var(--accent)] hover:underline">{chapter.title}</p>
        <p className="text-xs text-[var(--muted-foreground)]">
          {chapter.page_count
            ? t("comic.pages", { count: chapter.page_count })
            : t("comic.pagesEmpty")}
        </p>
      </div>
      <button
        type="button"
        onClick={(e) => {
          e.stopPropagation();
          toggleFavorite(chapter.source_path);
        }}
        className={`shrink-0 transition ${
          favoriteSet.has(chapter.source_path)
            ? "text-red-500 hover:text-red-400"
            : "text-[var(--muted-foreground)] hover:text-red-400"
        }`}
        title={
          favoriteSet.has(chapter.source_path) ? t("comic.removeFavorite") : t("comic.addFavorite")
        }
      >
        <Heart size={16} fill={favoriteSet.has(chapter.source_path) ? "currentColor" : "none"} />
      </button>
      <span
        className={`shrink-0 rounded-full border px-2.5 py-1 text-xs font-semibold ${chapterStatusClass(chapter)}`}
      >
        {chapterStatusLabel(chapter)}
      </span>
    </div>
  );

  return (
    <section className="space-y-4">
      <Card>
        <div className="mb-3 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex min-w-0 items-center gap-3 overflow-hidden">
            <Button variant="ghost" onClick={() => navigate({ to: "/" })} className="shrink-0 gap-1.5 px-2">
              <ArrowLeft size={16} />
            </Button>
            <div className="min-w-0 flex-1 overflow-hidden">
              <h2 className="truncate text-xl font-bold">{comicTitle}</h2>
              <p className="truncate text-xs text-[var(--muted-foreground)]">{comicSourcePath}</p>
            </div>
          </div>
          <div className="flex shrink-0 flex-wrap items-center gap-2">
            <span className="rounded-full border border-[var(--border)] bg-[var(--background)] px-2.5 py-1 text-xs font-semibold">
              {t("comic.chapters", { count: totalChapters })}
            </span>
            {searchText.trim() ? (
              <span className="rounded-full border border-[var(--border)] bg-[var(--background)] px-2.5 py-1 text-xs font-semibold text-[var(--muted-foreground)]">
                {t("comic.shown", { count: filteredChapters.length })}
              </span>
            ) : null}
            <Button
              variant="ghost"
              onClick={() => void chaptersQuery.refetch()}
              disabled={chaptersQuery.isFetching}
              title={t("comic.refreshChapters")}
              aria-label={t("comic.refreshChapters")}
              className="gap-1.5 px-2.5"
            >
              <RefreshCw
                size={14}
                className={chaptersQuery.isFetching ? "animate-spin" : undefined}
              />
            </Button>
          </div>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <div className="relative min-w-0 flex-1">
            <Search
              size={14}
              className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-[var(--muted-foreground)]"
            />
            <input
              value={searchText}
              onChange={(e) => setSearchText(e.target.value)}
              className="h-9 w-full rounded-md border border-[var(--border)] bg-[var(--background)] py-2 pl-8 pr-3 text-sm placeholder:text-[var(--muted-foreground)]"
              placeholder={t("comic.searchPlaceholder")}
            />
          </div>
          <select
            value={chapterSortDir}
            onChange={(e) => setChapterSortDir(e.target.value as SortDir)}
            className="h-9 shrink-0 rounded-md border border-[var(--border)] bg-[var(--background)] px-2 text-sm"
          >
            <option value="asc">{t("comic.nameAsc")}</option>
            <option value="desc">{t("comic.nameDesc")}</option>
          </select>
          <button
            type="button"
            onClick={() => setShowFavoritesOnly((v) => !v)}
            className={`flex items-center gap-1 rounded-md border px-2.5 py-2 text-sm transition ${
              showFavoritesOnly
                ? "border-red-400 bg-red-500/10 text-red-500"
                : "border-[var(--border)] bg-[var(--background)] text-[var(--muted-foreground)] hover:text-red-400"
            }`}
            title={t("comic.showFavorites")}
          >
            <Heart size={14} fill={showFavoritesOnly ? "currentColor" : "none"} />
            {showFavoritesOnly ? String(favoriteSet.size) : ""}
          </button>
        </div>
      </Card>
      <Card className="space-y-2">
        {chaptersQuery.isPending ? (
          <SkeletonList rows={5} />
        ) : chaptersQuery.isError ? (
          <ErrorState
            title={t("comic.loadError.title")}
            description={t("comic.loadError.description")}
            onRetry={() => void chaptersQuery.refetch()}
          />
        ) : (chaptersQuery.data?.length ?? 0) === 0 ? (
          <EmptyState title={t("comic.empty.title")} description={t("comic.empty.description")} />
        ) : filteredChapters.length === 0 ? (
          <EmptyState
            title={t("comic.emptyFilter.title")}
            description={t("comic.emptyFilter.description")}
          />
        ) : (
          <VirtualList
            ref={virtualListRef}
            count={filteredChapters.length}
            estimateSize={CHAPTER_ROW_HEIGHT}
            scrollElement={scrollEl}
            items={filteredChapters}
            getItemKey={(i) => filteredChapters[i].key}
            renderItem={renderChapterItem}
            measureElement
          />
        )}
      </Card>
      <ScrollToTop />
      <ContextMenu state={ctxMenu.state} onClose={ctxMenu.close} />
    </section>
  );
}
