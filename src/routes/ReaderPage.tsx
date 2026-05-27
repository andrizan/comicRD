import { startTransition, useEffect, useEffectEvent, useMemo, useRef, useState } from "react";
import { useMutation, useQuery } from "@tanstack/react-query";
import { useNavigate, useParams } from "@tanstack/react-router";
import {
  BookmarkPlus,
  ChevronLeft,
  ChevronRight,
  Fullscreen,
  Maximize2,
  Minimize2,
  Shrink,
  X,
  ZoomIn,
  ZoomOut,
} from "lucide-react";
import {
  addBookmark,
  getChapterContext,
  getChapterPages,
  getProgress,
  listSettings,
  saveProgress,
  setSetting,
} from "../api/tauri";
import { ErrorState, SkeletonList } from "../components/feedback/states";
import { Button } from "../components/ui/button";

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

  const pageSrc = `comicrd://localhost/page/${chapterId}/${pageIndex}`;

  return (
    <div
      className="mx-auto w-full"
      style={{
        maxWidth: `${Math.round(980 * zoom)}px`,
      }}
    >
      {!loaded ? <div className="my-2 h-[220px] rounded-md bg-white/10" /> : null}
      <img
        src={pageSrc}
        alt={`Page ${pageIndex + 1}`}
        loading="lazy"
        decoding="async"
        draggable={false}
        className={`mx-auto block w-full rounded-md ${loaded ? "opacity-100" : "opacity-0"} transition-opacity duration-150`}
        onLoad={() => setLoaded(true)}
        onError={() => setLoaded(true)}
      />
    </div>
  );
}

export function ReaderPage() {
  const { chapterId } = useParams({ from: "/reader/$chapterId" });
  const navigate = useNavigate({ from: "/reader/$chapterId" });
  const chapterIdNum = Number(chapterId);

  const settingsQuery = useQuery({
    queryKey: ["settings"],
    queryFn: listSettings,
  });
  const pagesQuery = useQuery({
    queryKey: ["chapter-pages", chapterIdNum],
    queryFn: () => getChapterPages(chapterIdNum),
  });
  const chapterContextQuery = useQuery({
    queryKey: ["chapter-context", chapterIdNum],
    queryFn: () => getChapterContext(chapterIdNum),
  });
  const progressQuery = useQuery({
    queryKey: ["progress", chapterIdNum],
    queryFn: () => getProgress(chapterIdNum),
  });

  const settingMap = useMemo(() => parseSettingMap(settingsQuery.data ?? []), [settingsQuery.data]);
  const defaultZoom = parseJsonOr<number>(settingMap.get("default_zoom"), 1);
  const defaultPageGap = normalizePageGap(parseJsonOr<number>(settingMap.get("page_gap"), 10));

  const totalPages = pagesQuery.data?.length ?? 0;
  const [currentPage, setCurrentPage] = useState(0);
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
  });

  const bookmarkMutation = useMutation({
    mutationFn: addBookmark,
  });

  const clampPage = (value: number) => {
    if (totalPages === 0) return 0;
    return Math.max(0, Math.min(totalPages - 1, value));
  };

  const goToChapter = (nextChapterId: number) => {
    navigate({
      to: "/reader/$chapterId",
      params: { chapterId: String(nextChapterId) },
    });
  };

  const closeReader = () => {
    const chapterContext = chapterContextQuery.data;
    if (chapterContext?.comic_source_path) {
      window.sessionStorage.setItem(
        `comicrd:last-chapter:${chapterContext.comic_source_path}`,
        chapterContext.chapter_source_path,
      );
      navigate({
        to: "/comic/$comicId",
        params: { comicId: encodeURIComponent(chapterContext.comic_source_path) },
      });
      return;
    }
    navigate({ to: "/" });
  };

  const persistProgressDebounced = useEffectEvent((nextPage: number) => {
    const isRead = totalPages > 0 && nextPage >= totalPages - 1;
    progressMutation.mutate({
      chapter_id: chapterIdNum,
      last_page: nextPage,
      total_pages: totalPages,
      mode: "webtoon",
      is_read: isRead,
    });
  });

  useEffect(() => {
    if (totalPages <= 0) return;
    const timer = window.setTimeout(() => persistProgressDebounced(currentPage), 900);
    return () => window.clearTimeout(timer);
  }, [currentPage, totalPages]);

  useEffect(() => {
    if (totalPages <= 1) return;
    const ahead = [currentPage + 1, currentPage + 2, currentPage + 3].filter(
      (idx) => idx >= 0 && idx < totalPages,
    );
    for (const idx of ahead) {
      const image = new Image();
      image.src = `comicrd://localhost/page/${chapterIdNum}/${idx}`;
    }
  }, [chapterIdNum, currentPage, totalPages]);

  const scrollRef = useRef<HTMLDivElement>(null);
  const pageRefs = useRef(new Map<number, HTMLDivElement>());
  const lastWebtoonPageSyncTsRef = useRef(0);
  const restoredChapterRef = useRef<number | null>(null);
  const goToPage = (targetPage: number) => {
    const nextPage = clampPage(targetPage);
    setCurrentPage(nextPage);
    pageRefs.current.get(nextPage)?.scrollIntoView({ block: "start" });
  };

  useEffect(() => {
    restoredChapterRef.current = null;
    lastWebtoonPageSyncTsRef.current = 0;
    setCurrentPage(0);
    pageRefs.current.clear();
    if (scrollRef.current) {
      scrollRef.current.scrollTop = 0;
    }
  }, [chapterIdNum]);

  useEffect(() => {
    if (totalPages <= 0 || !progressQuery.isFetched) return;
    if (restoredChapterRef.current === chapterIdNum) return;
    const target = clampPage(progressQuery.data?.last_page ?? 0);
    restoredChapterRef.current = chapterIdNum;
    setCurrentPage(target);
    window.requestAnimationFrame(() => {
      if (target === 0) {
        if (scrollRef.current) {
          scrollRef.current.scrollTop = 0;
        }
        return;
      }
      pageRefs.current.get(target)?.scrollIntoView({ block: "start" });
    });
  }, [chapterIdNum, progressQuery.data, progressQuery.isFetched, totalPages]);

  useEffect(() => {
    if (restoredChapterRef.current !== chapterIdNum) return;
    const root = scrollRef.current;
    if (!root) return;
    const observer = new IntersectionObserver(
      (entries) => {
        const now = performance.now();
        if (now - lastWebtoonPageSyncTsRef.current < 120) return;
        const visible = entries
          .filter((entry) => entry.isIntersecting)
          .sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top);
        const pageIndex = Number(visible[0]?.target.getAttribute("data-page-index"));
        if (!Number.isFinite(pageIndex)) return;
        lastWebtoonPageSyncTsRef.current = now;
        startTransition(() => {
          setCurrentPage((prev) => (prev === pageIndex ? prev : clampPage(pageIndex)));
        });
      },
      {
        root,
        rootMargin: "-20% 0px -65% 0px",
        threshold: 0.01,
      },
    );
    for (const node of pageRefs.current.values()) {
      observer.observe(node);
    }
    return () => observer.disconnect();
  }, [chapterIdNum, pagesQuery.data, totalPages]);

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
        closeReader();
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
        if (currentPage <= 0 && chapterContextQuery.data?.prev_chapter_id) {
          goToChapter(chapterContextQuery.data.prev_chapter_id);
          return;
        }
        goToPage(currentPage - 1);
      }
      if (event.key === "ArrowRight") {
        event.preventDefault();
        if (currentPage >= totalPages - 1 && chapterContextQuery.data?.next_chapter_id) {
          goToChapter(chapterContextQuery.data.next_chapter_id);
          return;
        }
        goToPage(currentPage + 1);
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [chapterContextQuery.data, currentPage, totalPages]);

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
          title="Gagal memuat reader"
          description="Terjadi error saat mengambil data chapter/page. Coba reload chapter ini."
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
        <div className="fixed inset-x-0 top-0 z-50 border-b border-white/10 bg-[#151922]/95 px-3 py-2 backdrop-blur">
          <div className="mx-auto flex max-w-[1400px] items-center gap-3">
            <Button
              variant="outline"
              className="border-white/20 bg-transparent text-white hover:bg-white/10"
              onClick={closeReader}
            >
              <X size={14} />
            </Button>
            <div className="min-w-0">
              <p className="truncate text-sm font-semibold">
                {chapterContextQuery.data?.comic_title ?? "Comic"}
              </p>
              <p className="truncate text-xs text-white/70">
                {chapterContextQuery.data?.title ?? "Chapter"}
              </p>
            </div>
          </div>
        </div>
        <div className="mx-auto max-w-[980px] px-3 pt-24">
          <ErrorState
            title="Chapter kosong"
            description="Tidak ada halaman gambar untuk chapter ini."
          />
        </div>
      </section>
    );
  }

  return (
    <section className="min-h-[100dvh] bg-[#0f1115] text-[#f4f4f5]">
      <div className="fixed inset-x-0 top-0 z-50 border-b border-white/10 bg-[#151922]/95 px-3 py-2 backdrop-blur">
        <div className="mx-auto flex max-w-[1400px] flex-wrap items-center gap-2">
          <Button
            variant="outline"
            className="border-white/20 bg-transparent text-white hover:bg-white/10"
            onClick={closeReader}
          >
            <X size={14} />
          </Button>
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-semibold">
              {chapterContextQuery.data?.comic_title ?? "Comic"}
            </p>
            <p className="truncate text-xs text-white/70">
              {chapterContextQuery.data?.title ?? "Chapter"} · Chapter{" "}
              {chapterContextQuery.data?.chapter_position ?? "-"} /{" "}
              {chapterContextQuery.data?.chapter_total ?? "-"}
            </p>
          </div>
          <div className="flex items-center gap-1">
            <Button
              variant="outline"
              className="border-white/20 bg-transparent px-2 py-1 text-xs text-white hover:bg-white/10"
              title="Kurangi gap"
              onClick={() => setPageGap((value) => Math.max(0, value - 10))}
            >
              <Minimize2 size={14} />
            </Button>
            <Button
              variant="outline"
              className="border-white/20 bg-transparent px-2 py-1 text-xs text-white hover:bg-white/10"
              title="Tambah gap"
              onClick={() => setPageGap((value) => Math.min(100, value + 10))}
            >
              <Maximize2 size={14} />
            </Button>
            <Button
              variant="outline"
              className="border-white/20 bg-transparent px-2 py-1 text-xs text-white hover:bg-white/10"
              onClick={() => {
                if (currentPage <= 0 && chapterContextQuery.data?.prev_chapter_id) {
                  goToChapter(chapterContextQuery.data.prev_chapter_id);
                  return;
                }
                goToPage(currentPage - 1);
              }}
            >
              <ChevronLeft size={14} />
            </Button>
            <Button
              variant="outline"
              className="border-white/20 bg-transparent px-2 py-1 text-xs text-white hover:bg-white/10"
              onClick={() => {
                if (currentPage >= totalPages - 1 && chapterContextQuery.data?.next_chapter_id) {
                  goToChapter(chapterContextQuery.data.next_chapter_id);
                  return;
                }
                goToPage(currentPage + 1);
              }}
            >
              <ChevronRight size={14} />
            </Button>
            <Button
              variant="outline"
              className="border-white/20 bg-transparent px-2 py-1 text-xs text-white hover:bg-white/10"
              onClick={() => setZoom((z) => Math.max(0.4, z - 0.1))}
            >
              <ZoomOut size={14} />
            </Button>
            <span className="w-12 text-center text-xs font-semibold">
              {Math.round(zoom * 100)}%
            </span>
            <Button
              variant="outline"
              className="border-white/20 bg-transparent px-2 py-1 text-xs text-white hover:bg-white/10"
              onClick={() => setZoom((z) => Math.min(3, z + 0.1))}
            >
              <ZoomIn size={14} />
            </Button>
            <Button
              variant="outline"
              className="border-white/20 bg-transparent px-2 py-1 text-xs text-white hover:bg-white/10"
              title="Reset zoom"
              onClick={() => setZoom(1)}
            >
              <Shrink size={14} />
            </Button>
            <Button
              variant="outline"
              className="border-white/20 bg-transparent px-2 py-1 text-xs text-white hover:bg-white/10"
              title="Fullscreen"
              onClick={() => {
                if (document.fullscreenElement) {
                  void document.exitFullscreen();
                  return;
                }
                void document.documentElement.requestFullscreen();
              }}
            >
              <Fullscreen size={14} className={isFullscreen ? "text-[#ff6a3d]" : ""} />
            </Button>
            <Button
              variant="outline"
              className="border-white/20 bg-transparent px-2 py-1 text-xs text-white hover:bg-white/10"
              onClick={() =>
                bookmarkMutation.mutate({ chapter_id: chapterIdNum, page: currentPage })
              }
            >
              <BookmarkPlus size={14} />
            </Button>
            <span className="w-10 text-center text-xs font-semibold text-white/80">
              {pageGap}px
            </span>
          </div>
        </div>
      </div>

      <div className="bg-black px-2 pt-20">
        <div
          key={chapterIdNum}
          ref={scrollRef}
          className="h-[calc(100dvh-120px)] overflow-auto bg-black pr-1"
          style={{ scrollBehavior: "smooth" }}
        >
          <div className="mx-auto w-full">
            {Array.from({ length: totalPages }).map((_, index) => (
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
                <PageImage chapterId={chapterIdNum} pageIndex={index} zoom={zoom} />
              </div>
            ))}
          </div>
        </div>
      </div>

      <div className="group fixed inset-x-0 bottom-0 z-40 border-t border-white/10 bg-[#151922d9] px-6 py-1 opacity-80 transition-all duration-150 hover:bg-[#151922f0] hover:py-3 hover:opacity-100">
        <div className="mx-auto flex w-full max-w-[1400px] items-center gap-3">
          <span className="w-0 overflow-hidden text-left text-sm text-white opacity-0 transition-all duration-150 group-hover:w-8 group-hover:opacity-100">
            {pageIndicator}
          </span>
          <div className="flex flex-1 items-center gap-0.5 group-hover:gap-1">
            {Array.from({ length: segmentCount }).map((_, idx) => (
              <button
                key={idx}
                type="button"
                title={`Page ${idx + 1}`}
                className={`h-1 flex-1 rounded-sm transition-all duration-150 group-hover:h-3 ${
                  idx <= activeSegment ? "bg-[#ff6a3d]" : "bg-white/20"
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
    </section>
  );
}
