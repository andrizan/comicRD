import { startTransition, useEffect, useEffectEvent, useMemo, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useVirtualizer } from "@tanstack/react-virtual";
import { useNavigate, useParams } from "@tanstack/react-router";
import { BookmarkPlus, ChevronLeft, ChevronRight, X, ZoomIn, ZoomOut } from "lucide-react";
import {
  addBookmark,
  getChapterContext,
  getChapterPages,
  getPageData,
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

function PageImage({
  chapterId,
  pageIndex,
  zoom,
  targetWidth,
}: {
  chapterId: number;
  pageIndex: number;
  zoom: number;
  targetWidth: number;
}) {
  const pageQuery = useQuery({
    queryKey: ["page", chapterId, pageIndex, targetWidth, "off"],
    queryFn: () =>
      getPageData(chapterId, pageIndex, {
        target_width: Math.max(560, Math.min(900, targetWidth)),
      }),
    staleTime: 5 * 60 * 1000,
    gcTime: 15 * 60 * 1000,
    retry: 0,
  });

  if (!pageQuery.data) {
    return <div className="my-2 h-[220px] rounded-md bg-white/10" />;
  }

  return (
    <img
      src={pageQuery.data}
      alt={`Page ${pageIndex + 1}`}
      loading="lazy"
      className="mx-auto block w-full max-w-[980px] rounded-md"
      style={{
        transform: `scale(${zoom})`,
        transformOrigin: "top center",
        imageRendering: "auto",
      }}
    />
  );
}

export function ReaderPage() {
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
  const smoothSpeed = parseJsonOr<number>(settingMap.get("smooth_scroll_speed"), 1);
  const defaultZoom = parseJsonOr<number>(settingMap.get("default_zoom"), 1);
  const defaultPageGap = parseJsonOr<number>(settingMap.get("page_gap"), 8);

  const totalPages = pagesQuery.data?.length ?? 0;
  const [currentPage, setCurrentPage] = useState(0);
  const [zoom, setZoom] = useState(defaultZoom);
  const [pageGap, setPageGap] = useState(defaultPageGap);
  const [viewportWidth, setViewportWidth] = useState(1280);

  useEffect(() => {
    setCurrentPage(0);
  }, [chapterIdNum]);

  useEffect(() => {
    setZoom(defaultZoom);
  }, [defaultZoom]);

  useEffect(() => {
    setPageGap(defaultPageGap);
  }, [defaultPageGap]);

  useEffect(() => {
    const update = () => {
      const next = Math.max(560, Math.floor(window.innerWidth * 0.9));
      setViewportWidth(next);
    };
    update();
    window.addEventListener("resize", update);
    return () => window.removeEventListener("resize", update);
  }, []);

  useEffect(() => {
    if (progressQuery.data) {
      setCurrentPage(progressQuery.data.last_page);
    }
  }, [progressQuery.data]);

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
      search: { mode: "webtoon" },
    });
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
      queryClient.prefetchQuery({
        queryKey: ["page", chapterIdNum, idx, viewportWidth, "off"],
        queryFn: () =>
          getPageData(chapterIdNum, idx, {
            target_width: Math.max(560, Math.min(900, viewportWidth)),
          }),
        staleTime: 45_000,
      });
    }
  }, [chapterIdNum, currentPage, queryClient, totalPages, viewportWidth]);

  const scrollRef = useRef<HTMLDivElement>(null);
  const rowVirtualizer = useVirtualizer({
    count: totalPages,
    getScrollElement: () => scrollRef.current,
    estimateSize: () => 1200 / Math.max(1, smoothSpeed),
    overscan: 2,
  });
  const virtualItems = rowVirtualizer.getVirtualItems();
  const lastWebtoonPageSyncTsRef = useRef(0);

  useEffect(() => {
    if (virtualItems.length === 0) return;
    const now = performance.now();
    if (now - lastWebtoonPageSyncTsRef.current < 120) return;
    lastWebtoonPageSyncTsRef.current = now;
    const firstVisible = virtualItems[0]?.index ?? 0;
    startTransition(() => {
      setCurrentPage((prev) => (prev === firstVisible ? prev : clampPage(firstVisible)));
    });
  }, [virtualItems, totalPages]);

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

  const pageIndicator = `${Math.min(currentPage + 1, Math.max(totalPages, 1))}`;
  const progressPercent = totalPages <= 1 ? 0 : (currentPage / (totalPages - 1)) * 100;
  const segmentCount = Math.max(1, totalPages);
  const activeSegment =
    totalPages <= 1 ? 0 : Math.round((currentPage / (totalPages - 1)) * Math.max(0, segmentCount - 1));

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
              onClick={() => {
                if (chapterContextQuery.data?.comic_id) {
                  navigate({
                    to: "/comic/$comicId",
                    params: { comicId: String(chapterContextQuery.data.comic_id) },
                  });
                  return;
                }
                navigate({ to: "/" });
              }}
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
            onClick={() => {
              if (chapterContextQuery.data?.comic_id) {
                navigate({
                  to: "/comic/$comicId",
                  params: { comicId: String(chapterContextQuery.data.comic_id) },
                });
                return;
              }
              navigate({ to: "/" });
            }}
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
              onClick={() => {
                if (currentPage <= 0 && chapterContextQuery.data?.prev_chapter_id) {
                  goToChapter(chapterContextQuery.data.prev_chapter_id);
                  return;
                }
                setCurrentPage((v) => clampPage(v - 1));
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
                setCurrentPage((v) => clampPage(v + 1));
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
              onClick={() =>
                bookmarkMutation.mutate({ chapter_id: chapterIdNum, page: currentPage })
              }
            >
              <BookmarkPlus size={14} />
            </Button>
            <label className="ml-1 hidden text-xs font-semibold text-white/80 md:block">
              Gap
              <input
                type="range"
                min={0}
                max={32}
                step={1}
                value={pageGap}
                onChange={(e) => setPageGap(Number(e.target.value))}
                className="ml-2 w-24 align-middle"
              />
            </label>
          </div>
        </div>
      </div>

      <div className="px-2 pt-20">
        <div
          ref={scrollRef}
          className="h-[calc(100dvh-120px)] overflow-auto pr-1"
          style={{ scrollBehavior: "smooth" }}
        >
          <div style={{ height: `${rowVirtualizer.getTotalSize()}px`, position: "relative" }}>
            {virtualItems.map((v) => (
              <div
                key={v.key}
                className="absolute left-0 top-0 w-full"
                style={{
                  transform: `translateY(${v.start}px)`,
                  paddingTop: `${Math.max(0, pageGap / 2)}px`,
                  paddingBottom: `${Math.max(0, pageGap / 2)}px`,
                }}
              >
                <PageImage
                  chapterId={chapterIdNum}
                  pageIndex={v.index}
                  zoom={zoom}
                  targetWidth={viewportWidth}
                />
              </div>
            ))}
          </div>
        </div>
      </div>

      <div className="group fixed inset-x-0 bottom-0 z-40 border-t border-white/10 bg-[#151922f0] px-6 py-2 transition-all duration-150 hover:py-3">
        <div className="mx-auto flex w-full max-w-[1400px] items-center gap-3">
          <span className="w-8 text-left text-sm text-white">{pageIndicator}</span>
          <div className="flex flex-1 items-center gap-1">
            {Array.from({ length: segmentCount }).map((_, idx) => (
              <button
                key={idx}
                type="button"
                title={`Page ${idx + 1}`}
                className={`h-2 flex-1 rounded-sm transition-all duration-150 group-hover:h-3 ${
                  idx <= activeSegment ? "bg-[#ff6a3d]" : "bg-white/20"
                }`}
                onClick={() => {
                  const target = idx;
                  setCurrentPage(target);
                  rowVirtualizer.scrollToIndex(target, { align: "start" });
                }}
              />
            ))}
          </div>
          <span className="w-8 text-right text-sm text-white">{Math.max(totalPages, 1)}</span>
        </div>
        <div className="mt-1 h-0.5 w-full rounded-full bg-white/10">
          <div
            className="h-full rounded-full bg-[#ff6a3d] transition-[width] duration-150"
            style={{ width: `${progressPercent}%` }}
          />
        </div>
      </div>
    </section>
  );
}
