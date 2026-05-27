import { useEffect, useMemo, useRef, useState } from "react";
import { useMutation, useQuery } from "@tanstack/react-query";
import { useNavigate, useParams } from "@tanstack/react-router";
import { ArrowLeft } from "lucide-react";
import { listComicChaptersRaw, openChapterForReading } from "../api/tauri";
import { EmptyState, ErrorState, SkeletonList } from "../components/feedback/states";
import { Button } from "../components/ui/button";
import { Card } from "../components/ui/card";
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
  if (chapter.is_read) return "Read";
  if (chapter.total_pages > 0 || chapter.page_count > 0) {
    const total = chapter.total_pages || chapter.page_count;
    return `Reading p.${Math.min(chapter.last_page + 1, Math.max(total, 1))}/${total}`;
  }
  return "Unread";
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

  return (
    <section className="space-y-4">
      <Card>
        <div className="mb-3 flex flex-wrap items-center gap-3">
          <Button variant="outline" onClick={() => navigate({ to: "/" })}>
            <ArrowLeft size={14} />
            Back
          </Button>
          <h2 className="text-xl font-bold">{comicTitle}</h2>
        </div>
        <p className="text-sm text-[var(--muted-foreground)] break-all">{comicSourcePath}</p>
        <p className="mt-1 text-sm text-[var(--muted-foreground)]">
          Klik chapter untuk mulai baca. Saat itu baru data chapter/register masuk ke database.
        </p>
        <div className="mt-3 flex flex-wrap gap-2 text-xs">
          <span className="rounded-full border border-[var(--border)] bg-[var(--card)] px-2.5 py-1 font-semibold">
            Total Chapter: {totalChapters}
          </span>
          {searchText.trim() ? (
            <span className="rounded-full border border-[var(--border)] bg-[var(--card)] px-2.5 py-1 font-semibold text-[var(--muted-foreground)]">
              Filtered: {filteredChapters.length} chapter
            </span>
          ) : null}
        </div>
        <div className="mt-3 flex flex-wrap items-center gap-2">
          <input
            value={searchText}
            onChange={(e) => setSearchText(e.target.value)}
            className="min-w-[260px] flex-1 rounded-md border border-[var(--border)] bg-[var(--card)] px-3 py-2 text-sm"
            placeholder="Cari chapter..."
          />
          <select
            value={chapterSortDir}
            onChange={(e) => setChapterSortDir(e.target.value as SortDir)}
            className="rounded-md border border-[var(--border)] bg-[var(--card)] px-3 py-2 text-sm"
          >
            <option value="asc">Name Asc</option>
            <option value="desc">Name Desc</option>
          </select>
        </div>
      </Card>
      <Card className="space-y-2">
        {chaptersQuery.isPending ? (
          <SkeletonList rows={5} />
        ) : chaptersQuery.isError ? (
          <ErrorState
            title="Gagal memuat chapter"
            description="Coba buka ulang komik."
            onRetry={() => void chaptersQuery.refetch()}
          />
        ) : (chaptersQuery.data?.length ?? 0) === 0 ? (
          <EmptyState
            title="Chapter tidak ditemukan"
            description="Folder/arsip komik ini tidak punya chapter yang valid."
          />
        ) : filteredChapters.length === 0 ? (
          <EmptyState
            title="Tidak ada chapter sesuai filter"
            description="Ubah filter atau kata kunci pencarian."
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
                  Pages: {chapter.page_count || "-"}
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
                Baca
              </Button>
            </div>
          ))
        )}
      </Card>
    </section>
  );
}
