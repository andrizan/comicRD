import { useEffect, useMemo, useRef, useState } from "react";
import { useMutation, useQuery } from "@tanstack/react-query";
import { useNavigate, useParams } from "@tanstack/react-router";
import { ArrowLeft, RefreshCw, Search } from "lucide-react";
import { listComicChaptersRaw, openChapterForReading } from "../api/tauri";
import { EmptyState, ErrorState, SkeletonList } from "../components/feedback/states";
import { Button } from "../components/ui/button";
import { Card } from "../components/ui/card";
import { t as translate, useAppI18n } from "../i18n";
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

export function ComicPage() {
  const { t } = useAppI18n();
  const { comicId } = useParams({ from: "/comic/$comicId" });
  const navigate = useNavigate();
  const comicSourcePath = decodeComicPath(comicId);
  const comicTitle = titleFromPath(comicSourcePath);
  const [searchText, setSearchText] = useState("");
  const [chapterSortDir, setChapterSortDir] = useState<SortDir>("asc");
  const chapterRefs = useRef(new Map<string, HTMLDivElement>());

  const chaptersQuery = useQuery({
    queryKey: ["raw-chapters", comicSourcePath],
    queryFn: () => listComicChaptersRaw(comicSourcePath),
  });

  const openChapterMutation = useMutation({
    mutationFn: openChapterForReading,
  });

  const filteredChapters = useMemo(() => {
    const filtered = (chaptersQuery.data ?? []).filter((chapter) => {
      const q = searchText.trim().toLowerCase();
      if (!q) return true;
      return (
        chapter.title.toLowerCase().includes(q) || chapter.source_path.toLowerCase().includes(q)
      );
    });
    filtered.sort((a, b) => {
      const order = a.title.localeCompare(b.title, undefined, {
        numeric: true,
        sensitivity: "base",
      });
      return chapterSortDir === "desc" ? -order : order;
    });
    return filtered;
  }, [chapterSortDir, chaptersQuery.data, searchText]);
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

  useEffect(() => {
    if (!chaptersQuery.isSuccess || filteredChapters.length === 0) return;
    const lastChapter = window.sessionStorage.getItem(lastChapterStorageKey(comicSourcePath));
    if (!lastChapter) return;
    window.requestAnimationFrame(() => {
      chapterRefs.current.get(lastChapter)?.scrollIntoView({
        block: "center",
      });
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

  return (
    <section className="space-y-4">
      <Card>
        <div className="mb-3 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex items-center gap-3">
            <Button variant="ghost" onClick={() => navigate({ to: "/" })} className="gap-1.5 px-2">
              <ArrowLeft size={16} />
            </Button>
            <div className="min-w-0">
              <h2 className="truncate text-xl font-bold">{comicTitle}</h2>
              <p className="truncate text-xs text-[var(--muted-foreground)]">{comicSourcePath}</p>
            </div>
          </div>
          <div className="flex flex-wrap items-center gap-2">
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
              className="w-full rounded-md border border-[var(--border)] bg-[var(--background)] py-2 pl-8 pr-3 text-sm placeholder:text-[var(--muted-foreground)]"
              placeholder={t("comic.searchPlaceholder")}
            />
          </div>
          <select
            value={chapterSortDir}
            onChange={(e) => setChapterSortDir(e.target.value as SortDir)}
            className="rounded-md border border-[var(--border)] bg-[var(--background)] px-2.5 py-2 text-sm"
          >
            <option value="asc">{t("comic.nameAsc")}</option>
            <option value="desc">{t("comic.nameDesc")}</option>
          </select>
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
          <EmptyState
            title={t("comic.empty.title")}
            description={t("comic.empty.description")}
          />
        ) : filteredChapters.length === 0 ? (
          <EmptyState
            title={t("comic.emptyFilter.title")}
            description={t("comic.emptyFilter.description")}
          />
        ) : (
          filteredChapters.map((chapter) => (
            <div
              key={chapter.key}
              ref={(node) => {
                if (node) {
                  chapterRefs.current.set(chapter.source_path, node);
                  return;
                }
                chapterRefs.current.delete(chapter.source_path);
              }}
              className="flex flex-wrap items-center justify-between gap-3 rounded-md border border-[var(--border)] bg-[var(--card)] p-3"
            >
              <div className="min-w-[220px] flex-1">
                <p className="font-semibold text-[var(--accent)]">{chapter.title}</p>
                <p className="text-xs text-[var(--muted-foreground)]">
                  {chapter.page_count
                    ? t("comic.pages", { count: chapter.page_count })
                    : t("comic.pagesEmpty")}
                </p>
              </div>
              <span
                className={`rounded-full border px-2.5 py-1 text-xs font-semibold ${chapterStatusClass(chapter)}`}
              >
                {chapterStatusLabel(chapter)}
              </span>
              <Button
                onClick={() => void onOpenChapter(chapter.source_path)}
                disabled={openChapterMutation.isPending}
              >
                {t("comic.read")}
              </Button>
            </div>
          ))
        )}
      </Card>
    </section>
  );
}
