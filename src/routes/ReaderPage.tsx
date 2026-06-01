import { startTransition, useEffect, useEffectEvent, useMemo, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useNavigate, useParams } from "@tanstack/react-router";
import {
  ChevronLeft,
  ChevronRight,
  Fullscreen,
  Maximize2,
  Minimize2,
  Settings,
  Shrink,
  SkipBack,
  SkipForward,
  X,
  ZoomIn,
  ZoomOut,
} from "lucide-react";
import {
  getChapterContext,
  getChapterPages,
  getProgress,
  listSettings,
  saveProgress,
  setSetting,
} from "@/api/tauri";
import { ErrorState, SkeletonList } from "@/components/feedback/states";
import { Button } from "@/components/ui/button";
import { useAppI18n } from "@/i18n";
import { comicPageSrc } from "@/lib/comic-protocol";
import { buildProgressPayload } from "@/lib/reader-progress";

function parseSettingMap(entries: { key: string; value_json: string }[]) {
  return new Map(entries.map((item) => [item.key, item.value_json]));
}

function parseJsonOr<T>(value: string | undefined, fallback: T): T {
  if (!value) return fallback;
  try {
    return JSON.parse(value) as T;
  } catch {
    return fallback;
  }
}

function normalizePageGap(value: number): number {
  return Math.max(0, Math.min(100, Math.round(value / 10) * 10));
}

const READER_OUTLINE_BUTTON_CLASS =
  "dark:border-white/20 bg-transparent text-white/70 hover:bg-transparent hover:text-white/70 dark:bg-transparent dark:hover:bg-transparent cursor-pointer";
const READER_TOOLBAR_BUTTON_CLASS = `${READER_OUTLINE_BUTTON_CLASS} px-2 py-1 text-xs`;
const READER_REVEAL_BUTTON_CLASS =
  "fixed right-3 top-3 z-50 rounded-full border dark:border-white/20 bg-transparent p-2 text-white/70 backdrop-blur transition-all duration-300 hover:bg-transparent hover:text-white/70 dark:bg-transparent dark:hover:bg-transparent";

const READER_PAGE_WINDOW = 3;

function PageImage({
  chapterId,
  pageIndex,
  zoom,
}: {
  chapterId: number;
  pageIndex: number;
  zoom: number;
}) {
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    setLoaded(false);
  }, [chapterId, pageIndex]);

  const pageSrc = comicPageSrc(chapterId, pageIndex);

  return (
    <div
      className="mx-auto w-full"
      style={{
        maxWidth: `${Math.round(980 * zoom)}px`,
      }}
    >
      {!loaded ? <div className="my-2 h-[220px] bg-white/10" /> : null}
      <img
        src={pageSrc}
        alt={`Page ${pageIndex + 1}`}
        loading="lazy"
        decoding="async"
        draggable={false}
        className={`mx-auto block w-full ${loaded ? "opacity-100" : "opacity-0"} transition-opacity duration-150`}
        onLoad={() => setLoaded(true)}
        onError={() => setLoaded(true)}
      />
    </div>
  );
}

function PagePlaceholder() {
  return <div className="my-2 h-[220px] bg-white/10" aria-hidden="true" />;
}

export function ReaderPage() {
  const { t } = useAppI18n();
  const { chapterId } = useParams({ from: "/reader/$chapterId" });
  const navigate = useNavigate({ from: "/reader/$chapterId" });
  const chapterIdNum = Number(chapterId);
  const queryClient = useQueryClient();

  const settingsQuery = useQuery({
    queryKey: ["settings"],
    queryFn: listSettings,
  });
  const pagesQuery = useQuery({
    queryKey: ["chapter-pages", chapterIdNum],
    queryFn: () => getChapterPages(chapterIdNum),
    gcTime: 60_000,
  });
  const chapterContextQuery = useQuery({
    queryKey: ["chapter-context", chapterIdNum],
    queryFn: () => getChapterContext(chapterIdNum),
    gcTime: 60_000,
  });
  const progressQuery = useQuery({
    queryKey: ["progress", chapterIdNum],
    queryFn: () => getProgress(chapterIdNum),
    staleTime: 0,
    gcTime: 60_000,
  });

  const settingMap = useMemo(() => parseSettingMap(settingsQuery.data ?? []), [settingsQuery.data]);
  const defaultZoom = parseJsonOr<number>(settingMap.get("default_zoom"), 1);
  const defaultPageGap = normalizePageGap(parseJsonOr<number>(settingMap.get("page_gap"), 10));

  const totalPages = pagesQuery.data?.length ?? 0;
  const [currentPage, setCurrentPage] = useState(0);
  const currentPageRef = useRef(0);
  const [zoom, setZoom] = useState(defaultZoom);
  const [pageGap, setPageGap] = useState(defaultPageGap);

  useEffect(() => {
    setZoom(defaultZoom);
  }, [defaultZoom]);

  useEffect(() => {
    setPageGap(defaultPageGap);
  }, [defaultPageGap]);

  const progressMutation = useMutation({
    mutationFn: saveProgress,
    onSuccess: (_data, variables) => {
      queryClient.setQueryData(["progress", variables.chapter_id], {
        chapter_id: variables.chapter_id,
        last_page: variables.last_page,
        total_pages: variables.total_pages,
        mode: variables.mode,
        is_read: variables.is_read,
        updated_at: Math.floor(Date.now() / 1000),
      });
    },
  });

  const clampPage = (value: number) => {
    if (totalPages === 0) return 0;
    return Math.max(0, Math.min(totalPages - 1, value));
  };

  const persistProgressNow = async (page: number) => {
    const payload = buildProgressPayload(chapterIdNum, page, totalPages);
    await saveProgress(payload);
    queryClient.setQueryData(["progress", chapterIdNum], {
      chapter_id: payload.chapter_id,
      last_page: payload.last_page,
      total_pages: payload.total_pages,
      mode: payload.mode,
      is_read: payload.is_read,
      updated_at: Math.floor(Date.now() / 1000),
    });
  };

  const goToChapter = async (nextChapterId: number) => {
    if (totalPages > 0) {
      await persistProgressNow(currentPageRef.current);
    }
    navigate({
      to: "/reader/$chapterId",
      params: { chapterId: String(nextChapterId) },
    });
  };

  const closeReader = async () => {
    if (totalPages > 0) {
      await persistProgressNow(currentPageRef.current);
    }
    const chapterContext = chapterContextQuery.data;
    if (chapterContext?.comic_source_path) {
      window.sessionStorage.setItem(
        `comicrd:last-chapter:${chapterContext.comic_source_path}`,
        chapterContext.chapter_source_path,
      );
      await queryClient.invalidateQueries({
        queryKey: ["raw-chapters", chapterContext.comic_source_path],
      });
      await queryClient.invalidateQueries({
        queryKey: ["reading-history"],
      });
      navigate({
        to: "/comic/$comicId",
        params: { comicId: encodeURIComponent(chapterContext.comic_source_path) },
      });
      return;
    }
    navigate({ to: "/" });
  };

  const persistProgressDebounced = useEffectEvent((nextPage: number) => {
    progressMutation.mutate(buildProgressPayload(chapterIdNum, nextPage, totalPages));
  });

  const syncCurrentPage = (nextPage: number) => {
    const clampedPage = clampPage(nextPage);
    currentPageRef.current = clampedPage;
    setCurrentPage((prev) => (prev === clampedPage ? prev : clampedPage));
    return clampedPage;
  };

  useEffect(() => {
    if (totalPages <= 0) return;
    const timer = window.setTimeout(() => persistProgressDebounced(currentPage), 900);
    return () => window.clearTimeout(timer);
  }, [currentPage, totalPages]);

  const scrollRef = useRef<HTMLDivElement>(null);
  const pageRefs = useRef(new Map<number, HTMLDivElement>());
  const lastWebtoonPageSyncTsRef = useRef(0);
  const restoredChapterRef = useRef<number | null>(null);
  const goToPage = (targetPage: number) => {
    const nextPage = syncCurrentPage(targetPage);
    lastWebtoonPageSyncTsRef.current = performance.now();
    pageRefs.current.get(nextPage)?.scrollIntoView({ block: "start" });
  };

  useEffect(() => {
    restoredChapterRef.current = null;
    lastWebtoonPageSyncTsRef.current = 0;
    currentPageRef.current = 0;
    setCurrentPage(0);
    if (scrollRef.current) {
      scrollRef.current.scrollTop = 0;
    }
  }, [chapterIdNum]);

  useEffect(() => {
    if (totalPages <= 0 || !progressQuery.isFetched || progressQuery.isFetching) return;

    if (restoredChapterRef.current !== chapterIdNum) {
      const target = clampPage(progressQuery.data?.last_page ?? 0);
      restoredChapterRef.current = chapterIdNum;
      syncCurrentPage(target);
      lastWebtoonPageSyncTsRef.current = performance.now();
      window.requestAnimationFrame(() => {
        if (target === 0) {
          if (scrollRef.current) {
            scrollRef.current.scrollTop = 0;
          }
          return;
        }
        pageRefs.current.get(target)?.scrollIntoView({ block: "start" });
      });
    }
  }, [
    chapterIdNum,
    progressQuery.data,
    progressQuery.isFetched,
    progressQuery.isFetching,
    totalPages,
  ]);

  useEffect(() => {
    const root = scrollRef.current;
    if (!root) return;
    const observer = new IntersectionObserver(
      (entries) => {
        const now = performance.now();
        if (now - lastWebtoonPageSyncTsRef.current < 200) return;
        const visible = entries
          .filter((entry) => entry.isIntersecting)
          .sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top);
        const pageIndex = Number(visible[0]?.target.getAttribute("data-page-index"));
        if (!Number.isFinite(pageIndex)) return;
        lastWebtoonPageSyncTsRef.current = now;
        startTransition(() => {
          syncCurrentPage(pageIndex);
        });
      },
      {
        root,
        rootMargin: "-10% 0px -70% 0px",
        threshold: 0.01,
      },
    );
    for (const node of pageRefs.current.values()) {
      observer.observe(node);
    }
    return () => observer.disconnect();
  }, [chapterIdNum, totalPages, pagesQuery.data]);

  const handleReaderScroll = () => {
    const root = scrollRef.current;
    if (!root || totalPages <= 0) return;
    const bottomDistance = root.scrollHeight - root.scrollTop - root.clientHeight;
    if (bottomDistance <= 24) {
      syncCurrentPage(totalPages - 1);
    }
    if (!toolbarVisible) return;
    setToolbarVisible(false);
  };

  const showToolbar = () => {
    setToolbarVisible(true);
  };

  useEffect(() => {
    const timer = window.setTimeout(() => {
      void setSetting("default_zoom", Number(zoom.toFixed(2)));
    }, 300);
    return () => window.clearTimeout(timer);
  }, [zoom]);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      void setSetting("page_gap", pageGap);
    }, 300);
    return () => window.clearTimeout(timer);
  }, [pageGap]);

  useEffect(() => {
    const root = scrollRef.current;
    if (!root) return;
    const scrollTop = root.scrollTop;
    window.requestAnimationFrame(() => {
      root.scrollTop = scrollTop;
    });
  }, [pageGap, zoom]);

  const [isFullscreen, setIsFullscreen] = useState(false);
  const [toolbarVisible, setToolbarVisible] = useState(true);
  useEffect(() => {
    const onFullscreenChange = () => {
      setIsFullscreen(Boolean(document.fullscreenElement));
    };
    onFullscreenChange();
    document.addEventListener("fullscreenchange", onFullscreenChange);
    return () => document.removeEventListener("fullscreenchange", onFullscreenChange);
  }, []);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault();
        void closeReader();
        return;
      }
      if (event.key === "ArrowUp") {
        event.preventDefault();
        scrollRef.current?.scrollBy({ top: -520, behavior: "smooth" });
        return;
      }
      if (event.key === "ArrowDown") {
        event.preventDefault();
        scrollRef.current?.scrollBy({ top: 520, behavior: "smooth" });
        return;
      }
      if (event.key === "PageUp") {
        event.preventDefault();
        scrollRef.current?.scrollBy({ top: -window.innerHeight * 0.85, behavior: "smooth" });
        return;
      }
      if (event.key === "PageDown") {
        event.preventDefault();
        scrollRef.current?.scrollBy({ top: window.innerHeight * 0.85, behavior: "smooth" });
        return;
      }
      if (event.key === "ArrowLeft") {
        event.preventDefault();
        if (currentPageRef.current <= 0 && chapterContextQuery.data?.prev_chapter_id) {
          void goToChapter(chapterContextQuery.data.prev_chapter_id);
          return;
        }
        goToPage(currentPageRef.current - 1);
      }
      if (event.key === "ArrowRight") {
        event.preventDefault();
        if (currentPageRef.current >= totalPages - 1 && chapterContextQuery.data?.next_chapter_id) {
          void goToChapter(chapterContextQuery.data.next_chapter_id);
          return;
        }
        goToPage(currentPageRef.current + 1);
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [chapterContextQuery.data, totalPages]);

  const pageIndicator = `${Math.min(currentPage + 1, Math.max(totalPages, 1))}`;
  const segmentCount = Math.max(1, totalPages);
  const activeSegment =
    totalPages <= 1
      ? 0
      : Math.round((currentPage / (totalPages - 1)) * Math.max(0, segmentCount - 1));

  const criticalQueryError =
    settingsQuery.error ?? pagesQuery.error ?? chapterContextQuery.error ?? progressQuery.error;

  if (criticalQueryError) {
    return (
      <section className="space-y-3">
        <ErrorState
          title={t("reader.loadError.title")}
          description={t("reader.loadError.description")}
          onRetry={() => {
            void settingsQuery.refetch();
            void pagesQuery.refetch();
            void chapterContextQuery.refetch();
            void progressQuery.refetch();
          }}
        />
      </section>
    );
  }

  if (settingsQuery.isPending || pagesQuery.isPending || chapterContextQuery.isPending) {
    return (
      <section className="space-y-3">
        <SkeletonList rows={1} />
        <SkeletonList rows={4} />
      </section>
    );
  }

  if (totalPages === 0) {
    return (
      <section className="min-h-[100dvh] bg-[#0f1115] text-[#f4f4f5]">
        <div className="fixed inset-x-0 top-0 z-50 border-b border-white/5 bg-[#151922]/60 px-3 py-2 backdrop-blur-md">
          <div className="mx-auto flex max-w-[1400px] items-center gap-3">
            <Button
              variant="outline"
              className={READER_OUTLINE_BUTTON_CLASS}
              title={t("reader.close")}
              onClick={() => void closeReader()}
            >
              <X size={14} />
            </Button>
            <div className="min-w-0">
              <p className="truncate text-sm font-semibold">
                {chapterContextQuery.data?.comic_title ?? t("reader.comicFallback")}
              </p>
              <p className="truncate text-xs text-white/70">
                {chapterContextQuery.data?.title ?? t("reader.chapterFallback")}
              </p>
            </div>
          </div>
        </div>
        <div className="mx-auto max-w-[980px] px-3 pt-24">
          <ErrorState title={t("reader.empty.title")} description={t("reader.empty.description")} />
        </div>
      </section>
    );
  }

  return (
    <section className="fixed inset-0 overflow-hidden bg-black text-[#f4f4f5]">
      <div className="group/tb fixed inset-x-0 top-0 z-50" onMouseEnter={showToolbar}>
        <div
          className={`border-b border-white/5 bg-[#151922]/60 px-3 py-2 backdrop-blur-md transition-all duration-300 ${
            toolbarVisible
              ? "translate-y-0 opacity-100"
              : "-translate-y-full opacity-0 pointer-events-none"
          }`}
        >
          <div className="mx-auto flex max-w-[1400px] flex-wrap items-center gap-2">
            <Button
              variant="outline"
              className={READER_OUTLINE_BUTTON_CLASS}
              title={t("reader.close")}
              onClick={() => void closeReader()}
            >
              <X size={14} />
            </Button>
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-semibold">
                {chapterContextQuery.data?.comic_title ?? t("reader.comicFallback")}
              </p>
              <p className="truncate text-xs text-white/70">
                {chapterContextQuery.data?.title ?? t("reader.chapterFallback")} ·{" "}
                {t("reader.chapterPosition", {
                  position: chapterContextQuery.data?.chapter_position ?? "-",
                  total: chapterContextQuery.data?.chapter_total ?? "-",
                })}
              </p>
            </div>
            <div className="flex items-center gap-1">
              <Button
                variant="outline"
                className={READER_TOOLBAR_BUTTON_CLASS}
                title={t("reader.decreaseGap")}
                onClick={() => setPageGap((value) => Math.max(0, value - 10))}
              >
                <Minimize2 size={14} />
              </Button>
              <Button
                variant="outline"
                className={READER_TOOLBAR_BUTTON_CLASS}
                title={t("reader.increaseGap")}
                onClick={() => setPageGap((value) => Math.min(100, value + 10))}
              >
                <Maximize2 size={14} />
              </Button>
              <Button
                variant="outline"
                className={READER_TOOLBAR_BUTTON_CLASS}
                title={
                  currentPage <= 0 && chapterContextQuery.data?.prev_chapter_id
                    ? t("reader.prevChapter")
                    : t("reader.prevPage")
                }
                onClick={() => {
                  if (currentPageRef.current <= 0 && chapterContextQuery.data?.prev_chapter_id) {
                    void goToChapter(chapterContextQuery.data.prev_chapter_id);
                    return;
                  }
                  goToPage(currentPageRef.current - 1);
                }}
              >
                <ChevronLeft size={14} />
              </Button>
              <Button
                variant="outline"
                className={READER_TOOLBAR_BUTTON_CLASS}
                title={
                  currentPage >= totalPages - 1 && chapterContextQuery.data?.next_chapter_id
                    ? t("reader.nextChapter")
                    : t("reader.nextPage")
                }
                onClick={() => {
                  if (
                    currentPageRef.current >= totalPages - 1 &&
                    chapterContextQuery.data?.next_chapter_id
                  ) {
                    void goToChapter(chapterContextQuery.data.next_chapter_id);
                    return;
                  }
                  goToPage(currentPageRef.current + 1);
                }}
              >
                <ChevronRight size={14} />
              </Button>
              <Button
                variant="outline"
                className={READER_TOOLBAR_BUTTON_CLASS}
                title={
                  chapterContextQuery.data?.prev_chapter_title
                    ? t("reader.prevChapterTitle", {
                        title: chapterContextQuery.data.prev_chapter_title,
                      })
                    : t("reader.prevChapter")
                }
                disabled={chapterContextQuery.data?.prev_chapter_id == null}
                onClick={() => {
                  const prevId = chapterContextQuery.data?.prev_chapter_id;
                  if (prevId == null) return;
                  void goToChapter(prevId);
                }}
              >
                <SkipBack size={14} />
              </Button>
              <Button
                variant="outline"
                className={READER_TOOLBAR_BUTTON_CLASS}
                title={
                  chapterContextQuery.data?.next_chapter_title
                    ? t("reader.nextChapterTitle", {
                        title: chapterContextQuery.data.next_chapter_title,
                      })
                    : t("reader.nextChapter")
                }
                disabled={chapterContextQuery.data?.next_chapter_id == null}
                onClick={() => {
                  const nextId = chapterContextQuery.data?.next_chapter_id;
                  if (nextId == null) return;
                  void goToChapter(nextId);
                }}
              >
                <SkipForward size={14} />
              </Button>
              <Button
                variant="outline"
                className={READER_TOOLBAR_BUTTON_CLASS}
                title={t("reader.zoomOut")}
                onClick={() => setZoom((z) => Math.max(0.4, z - 0.1))}
              >
                <ZoomOut size={14} />
              </Button>
              <span className="w-12 text-center text-xs font-semibold">
                {Math.round(zoom * 100)}%
              </span>
              <Button
                variant="outline"
                className={READER_TOOLBAR_BUTTON_CLASS}
                title={t("reader.zoomIn")}
                onClick={() => setZoom((z) => Math.min(3, z + 0.1))}
              >
                <ZoomIn size={14} />
              </Button>
              <Button
                variant="outline"
                className={READER_TOOLBAR_BUTTON_CLASS}
                title={t("reader.resetZoom")}
                onClick={() => setZoom(1)}
              >
                <Shrink size={14} />
              </Button>
              <Button
                variant="outline"
                className={READER_TOOLBAR_BUTTON_CLASS}
                title={t("reader.fullscreen")}
                onClick={() => {
                  if (document.fullscreenElement) {
                    void document.exitFullscreen();
                    return;
                  }
                  void document.documentElement.requestFullscreen();
                }}
              >
                <Fullscreen size={14} className={isFullscreen ? "text-app-accent" : ""} />
              </Button>
              <span className="w-10 text-center text-xs font-semibold text-white/80">
                {pageGap}px
              </span>
            </div>
          </div>
        </div>
      </div>

      <button
        type="button"
        className={`${READER_REVEAL_BUTTON_CLASS} ${
          toolbarVisible ? "pointer-events-none opacity-0" : "opacity-100"
        }`}
        title={t("reader.showToolbar")}
        onMouseEnter={showToolbar}
        onClick={showToolbar}
      >
        <Settings size={16} />
      </button>

      <div className="h-full bg-black">
        <div
          key={chapterIdNum}
          ref={scrollRef}
          className="reader-scrollbar h-dvh overflow-x-hidden overflow-y-auto bg-black"
          style={{ scrollBehavior: "smooth" }}
          onScroll={handleReaderScroll}
        >
          <div className="w-full">
            {Array.from({ length: totalPages }).map((_, index) => {
              const isNear =
                index >= currentPage - READER_PAGE_WINDOW &&
                index <= currentPage + READER_PAGE_WINDOW;
              return (
                <div
                  key={`${chapterIdNum}-${index}`}
                  ref={(node) => {
                    if (node) {
                      pageRefs.current.set(index, node);
                      return;
                    }
                    pageRefs.current.delete(index);
                  }}
                  data-page-index={index}
                  className="w-full"
                  style={{
                    marginBottom: `${index >= totalPages - 1 ? 0 : Math.max(0, pageGap)}px`,
                  }}
                >
                  {isNear ? (
                    <PageImage chapterId={chapterIdNum} pageIndex={index} zoom={zoom} />
                  ) : (
                    <PagePlaceholder />
                  )}
                </div>
              );
            })}
          </div>
        </div>
      </div>

      <div className="group fixed inset-x-0 bottom-0 z-40" onMouseMove={showToolbar}>
        <div
          className={`border-t border-white/5 bg-[#151922]/50 px-6 py-1 backdrop-blur-md transition-all duration-300 hover:bg-[#151922]/70 hover:py-3 ${
            toolbarVisible
              ? "translate-y-0 opacity-100"
              : "translate-y-full opacity-0 pointer-events-none"
          }`}
        >
          <div className="mx-auto flex w-full max-w-[1400px] items-center gap-3">
            <span className="w-0 overflow-hidden text-left text-sm text-white opacity-0 transition-all duration-150 group-hover:w-8 group-hover:opacity-100">
              {pageIndicator}
            </span>
            <div className="flex flex-1 items-center gap-0.5 group-hover:gap-1">
              {Array.from({ length: segmentCount }).map((_, idx) => (
                <button
                  key={idx}
                  type="button"
                  title={t("reader.pageTitle", { page: idx + 1 })}
                  className={`h-1 flex-1 rounded-sm transition-all duration-150 group-hover:h-3 ${
                    idx <= activeSegment ? "bg-app-accent" : "bg-white/20"
                  }`}
                  onClick={() => {
                    goToPage(idx);
                  }}
                />
              ))}
            </div>
            <span className="w-0 overflow-hidden text-right text-sm text-white opacity-0 transition-all duration-150 group-hover:w-8 group-hover:opacity-100">
              {Math.max(totalPages, 1)}
            </span>
          </div>
        </div>
      </div>
    </section>
  );
}
