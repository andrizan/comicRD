import { useEffect, useMemo, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useNavigate, useParams } from "@tanstack/react-router";
import {
  ArrowLeft,
  ArrowRight,
  Copy,
  FolderOpen,
  Heart,
  LayoutGrid,
  List,
  RefreshCw,
  Search,
  Type,
} from "lucide-react";
import {
  addChapterFavorite,
  listChapterFavorites,
  listComicChaptersRaw,
  openChapterForReading,
  openContainingFolder,
  prefetchPageVariants,
  removeChapterFavorite,
} from "@/api/tauri";
import { EmptyState, ErrorState, SkeletonList } from "@/components/feedback/states";
import { ContextMenu, useContextMenu, type ContextMenuItem } from "@/components/ui/context-menu";
import { ScrollToTop } from "@/components/ui/scroll-to-top";
import { WithTooltip } from "@/components/ui/tooltip";
import { VirtualList, type VirtualListHandle } from "@/components/ui/virtual-list";
import { InputGroup, InputGroupAddon, InputGroupInput } from "@/components/ui/input-group";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { t as translate, useAppI18n } from "@/i18n";
import {
  DEFAULT_IMAGE_PIPELINE_PROFILE,
  DEFAULT_READER_IMAGE_WIDTH,
} from "@/lib/reader-image-policy";
import { useChapterSort, useLibraryPreferences } from "@/stores/libraryStore";
import { setScrollKey, restoreScroll, scrollPositions } from "@/routes/Layout";
import type { RawChapter, SortBy, SortDir } from "@/types";

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

function chapterStatusColor(chapter: RawChapter): string {
  if (chapter.is_read) return "bg-emerald-500/15 text-emerald-500";
  if (chapter.total_pages > 0 || chapter.page_count > 0) {
    return "bg-amber-500/15 text-amber-500";
  }
  return "bg-app-border/40 text-app-text";
}

function lastChapterStorageKey(comicSourcePath: string): string {
  return `comicrd:last-chapter:${comicSourcePath}`;
}

const CHAPTER_ROW_HEIGHT = 60;

export function ComicPage() {
  const { t } = useAppI18n();
  const { comicId } = useParams({ from: "/comic/$comicId" });
  const navigate = useNavigate();
  const comicSourcePath = decodeComicPath(comicId);
  const comicTitle = titleFromPath(comicSourcePath);
  const [searchText, setSearchText] = useState("");
  const { chapterSortBy, chapterSortDir, setChapterSortBy, setChapterSortDir } = useChapterSort();
  const { displayMode, setDisplayMode } = useLibraryPreferences();
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
      if (
        q &&
        !chapter.title.toLowerCase().includes(q) &&
        !chapter.source_path.toLowerCase().includes(q)
      ) {
        return false;
      }
      if (showFavoritesOnly && !favoriteSet.has(chapter.source_path)) {
        return false;
      }
      return true;
    });
    filtered.sort((a, b) => {
      let order: number;
      if (chapterSortBy === "folder_date") {
        order = a.chapter_index - b.chapter_index;
      } else {
        order = a.title.localeCompare(b.title, undefined, {
          numeric: true,
          sensitivity: "base",
        });
      }
      return chapterSortDir === "desc" ? -order : order;
    });
    return filtered;
  }, [
    chapterSortBy,
    chapterSortDir,
    chaptersQuery.data,
    searchText,
    showFavoritesOnly,
    favoriteSet,
  ]);
  const totalChapters = chaptersQuery.data?.length ?? 0;

  async function onOpenChapter(chapterSourcePath: string) {
    window.sessionStorage.setItem(lastChapterStorageKey(comicSourcePath), chapterSourcePath);
    const chapterId = await openChapterMutation.mutateAsync({
      comic_source_path: comicSourcePath,
      chapter_source_path: chapterSourcePath,
    });
    const selectedChapter = chaptersQuery.data?.find(
      (chapter) => chapter.source_path === chapterSourcePath,
    );
    const warmStartPage = Math.max(0, selectedChapter?.last_page ?? 0);
    const warmEndPage =
      selectedChapter?.page_count && selectedChapter.page_count > 0
        ? Math.min(selectedChapter.page_count - 1, warmStartPage + 4)
        : warmStartPage + 4;
    void prefetchPageVariants({
      chapter_id: chapterId,
      start_page: warmStartPage,
      end_page: warmEndPage,
      target_width: DEFAULT_READER_IMAGE_WIDTH,
      profile: DEFAULT_IMAGE_PIPELINE_PROFILE,
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
        icon: <ArrowRight size={14} />,
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

  function renderChapterRow(index: number, chapter: RawChapter) {
    const isFav = favoriteSet.has(chapter.source_path);

    if (displayMode === "grid") {
      return (
        <div
          role="button"
          tabIndex={0}
          aria-label={chapter.title}
          onClick={() => void onOpenChapter(chapter.source_path)}
          onContextMenu={(e) => ctxMenu.show(e, chapterContextItems(chapter))}
          onKeyDown={(e) => {
            if (e.key === "Enter" || e.key === " ") {
              e.preventDefault();
              void onOpenChapter(chapter.source_path);
            }
          }}
          className={`flex cursor-pointer items-start gap-2.5 border-b border-r border-app-border bg-app-surface p-3 transition-colors hover:bg-app-bg ${
            openChapterMutation.isPending ? "pointer-events-none opacity-60" : ""
          }`}
        >
          <div className="flex h-16 w-14 flex-shrink-0 items-center justify-center rounded-lg border border-app-border bg-app-accent/15">
            <span className="font-display text-sm font-bold leading-tight text-app-accent opacity-80">
              {String(index + 1).padStart(2, "0")}
            </span>
          </div>
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-medium hover:underline">{chapter.title}</p>
            <div className="mt-1 flex items-center justify-between">
              <span className="text-[10px] text-app-muted">
                {chapter.page_count
                  ? t("comic.pages", { count: chapter.page_count })
                  : t("comic.pagesEmpty")}
              </span>
              <div className="flex items-center gap-1.5">
                <span
                  className={`rounded-full px-1.5 py-0.5 text-[9px] font-medium ${chapterStatusColor(chapter)}`}
                >
                  {chapterStatusLabel(chapter)}
                </span>
                <WithTooltip label={isFav ? t("comic.removeFavorite") : t("comic.addFavorite")}>
                  <button
                    type="button"
                    onClick={(e) => {
                      e.preventDefault();
                      e.stopPropagation();
                      toggleFavorite(chapter.source_path);
                    }}
                    aria-label={isFav ? t("comic.removeFavorite") : t("comic.addFavorite")}
                    className={`flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-md transition-colors ${
                      isFav ? "text-red-400" : "text-app-muted hover:text-red-400"
                    }`}
                  >
                    <Heart size={18} fill={isFav ? "currentColor" : "none"} />
                  </button>
                </WithTooltip>
              </div>
            </div>
          </div>
        </div>
      );
    }

    return (
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
        className={`flex cursor-pointer gap-3 border-b border-app-border bg-app-surface px-4 py-3 transition-colors hover:bg-app-bg ${
          openChapterMutation.isPending ? "pointer-events-none opacity-60" : ""
        }`}
      >
        <span className="w-6 flex-shrink-0 pt-0.5 text-right font-display text-xs font-bold leading-tight text-app-muted">
          {String(index + 1).padStart(2, "0")}
        </span>
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <p className="min-w-0 flex-1 truncate text-sm font-medium hover:underline">
              {chapter.title}
            </p>
            <span
              className={`shrink-0 rounded-full px-2 py-0.5 text-[10px] font-medium ${chapterStatusColor(chapter)}`}
            >
              {chapterStatusLabel(chapter)}
            </span>
            <WithTooltip label={isFav ? t("comic.removeFavorite") : t("comic.addFavorite")}>
              <button
                type="button"
                onClick={(e) => {
                  e.preventDefault();
                  e.stopPropagation();
                  toggleFavorite(chapter.source_path);
                }}
                aria-label={isFav ? t("comic.removeFavorite") : t("comic.addFavorite")}
                className={`flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-md transition-colors ${
                  isFav ? "text-red-400" : "text-app-muted hover:bg-app-bg hover:text-red-400"
                }`}
              >
                <Heart size={18} fill={isFav ? "currentColor" : "none"} />
              </button>
            </WithTooltip>
          </div>
          <p className="mt-0.5 text-xs text-app-muted">
            {chapter.page_count
              ? t("comic.pages", { count: chapter.page_count })
              : t("comic.pagesEmpty")}
          </p>
        </div>
      </div>
    );
  }

  return (
    <section className="flex flex-col">
      {/* Header */}
      <div className="border-b border-app-border bg-app-surface">
        <div className="flex items-center gap-3 px-5 py-3">
          <WithTooltip label={t("nav.library")}>
            <button
              type="button"
              onClick={() => navigate({ to: "/" })}
              aria-label={t("nav.library")}
              className="flex h-8 w-8 items-center justify-center rounded-md text-app-muted transition-all hover:bg-app-bg hover:text-app-text"
            >
              <ArrowLeft size={18} />
            </button>
          </WithTooltip>
          <div className="min-w-0 flex-1">
            <h2 className="truncate text-sm font-bold">{comicTitle}</h2>
            <p className="truncate text-[10px] text-app-muted">{comicSourcePath}</p>
          </div>
          <span className="shrink-0 rounded-full border border-app-border bg-app-bg px-2.5 py-1 text-[11px] font-semibold text-app-muted">
            {t("comic.chapters", { count: totalChapters })}
          </span>
          <WithTooltip label={t("comic.refreshChapters")}>
            <span className="inline-flex">
              <button
                type="button"
                onClick={() => void chaptersQuery.refetch()}
                disabled={chaptersQuery.isFetching}
                aria-label={t("comic.refreshChapters")}
                className="flex h-8 w-8 items-center justify-center rounded-md text-app-muted transition-all hover:bg-app-bg hover:text-app-text disabled:opacity-50"
              >
                <RefreshCw
                  size={14}
                  className={chaptersQuery.isFetching ? "animate-spin" : undefined}
                />
              </button>
            </span>
          </WithTooltip>
        </div>
      </div>

      {/* Toolbar */}
      <div className="space-y-3 px-5 py-4">
        <div className="flex items-center gap-2">
          <InputGroup className="w-[200px] flex-1">
            <InputGroupInput
              value={searchText}
              onChange={(e) => setSearchText(e.target.value)}
              placeholder={t("comic.searchPlaceholder")}
            />
            <InputGroupAddon>
              <Search size={16} />
            </InputGroupAddon>
          </InputGroup>
          <Select
            items={[
              { label: t("common.name"), value: "name" },
              { label: t("library.folderDate"), value: "folder_date" },
            ]}
            value={chapterSortBy}
            onValueChange={(v) => setChapterSortBy(v as SortBy)}
          >
            <SelectTrigger className="h-10 w-[140px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="name">{t("common.name")}</SelectItem>
              <SelectItem value="folder_date">{t("library.folderDate")}</SelectItem>
            </SelectContent>
          </Select>
          <Select
            items={[
              { label: t("common.asc"), value: "asc" },
              { label: t("common.desc"), value: "desc" },
            ]}
            value={chapterSortDir}
            onValueChange={(v) => setChapterSortDir(v as SortDir)}
          >
            <SelectTrigger className="h-10 w-[80px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="asc">{t("common.asc")}</SelectItem>
              <SelectItem value="desc">{t("common.desc")}</SelectItem>
            </SelectContent>
          </Select>
          <WithTooltip label={t("comic.showFavorites")}>
            <button
              type="button"
              onClick={() => setShowFavoritesOnly((v) => !v)}
              aria-label={t("comic.showFavorites")}
              className={`flex h-10 w-10 items-center justify-center rounded-lg border transition-all ${
                showFavoritesOnly
                  ? "border-red-400/30 bg-red-500/10 text-red-400"
                  : "border-app-border bg-app-surface text-app-muted hover:text-red-400"
              }`}
            >
              <Heart size={16} fill={showFavoritesOnly ? "currentColor" : "none"} />
            </button>
          </WithTooltip>
          <div className="flex flex-shrink-0 overflow-hidden rounded-lg border border-app-border bg-app-surface">
            <WithTooltip label="Grid">
              <button
                type="button"
                onClick={() => setDisplayMode("grid")}
                aria-label="Grid"
                className={`flex h-10 w-10 items-center justify-center text-sm transition-all ${
                  displayMode === "grid"
                    ? "bg-app-accent/10 text-app-accent"
                    : "text-app-muted hover:text-app-text"
                }`}
              >
                <LayoutGrid size={16} />
              </button>
            </WithTooltip>
            <WithTooltip label="List">
              <button
                type="button"
                onClick={() => setDisplayMode("list")}
                aria-label="List"
                className={`flex h-10 w-10 items-center justify-center text-sm transition-all ${
                  displayMode === "list"
                    ? "bg-app-accent/10 text-app-accent"
                    : "text-app-muted hover:text-app-text"
                }`}
              >
                <List size={16} />
              </button>
            </WithTooltip>
          </div>
        </div>

        {/* Chapter list */}
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
          <div className="overflow-hidden rounded-xl border border-app-border">
            <VirtualList
              ref={virtualListRef}
              count={filteredChapters.length}
              estimateSize={displayMode === "grid" ? 140 : CHAPTER_ROW_HEIGHT}
              scrollElement={scrollEl}
              columns={displayMode === "grid" ? 2 : 1}
              gap={1}
              items={filteredChapters}
              getItemKey={(i) => filteredChapters[i].key}
              renderItem={renderChapterRow}
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
