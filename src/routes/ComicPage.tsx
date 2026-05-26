import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Link, useParams } from "@tanstack/react-router";
import { listChapters } from "../api/tauri";
import { EmptyState, ErrorState, SkeletonList } from "../components/feedback/states";
import { Card } from "../components/ui/card";

export function ComicPage() {
  const { comicId } = useParams({ from: "/comic/$comicId" });
  const comicIdNum = Number(comicId);
  const [readFilter, setReadFilter] = useState<"all" | "read" | "unread">("all");
  const [completeFilter, setCompleteFilter] = useState<"all" | "complete" | "incomplete">("all");
  const chaptersQuery = useQuery({
    queryKey: ["chapters", comicIdNum],
    queryFn: () => listChapters(comicIdNum),
  });
  const filteredChapters = useMemo(
    () =>
      (chaptersQuery.data ?? [])
        .filter((chapter) => {
          if (readFilter === "all") return true;
          const isRead = chapter.is_read || chapter.last_page > 0;
          return readFilter === "read" ? isRead : !isRead;
        })
        .filter((chapter) => {
          if (completeFilter === "all") return true;
          return completeFilter === "complete" ? chapter.is_read : !chapter.is_read;
        }),
    [chaptersQuery.data, completeFilter, readFilter],
  );

  return (
    <section className="space-y-4">
      <Card>
        <h2 className="text-xl font-bold">Chapters</h2>
        <p className="text-sm text-[var(--muted-foreground)]">
          Klik judul chapter untuk masuk reader. Read status, progress page, dan continue reading
          tersimpan di database lokal.
        </p>
        <div className="mt-3 flex flex-wrap items-center gap-2">
          <select
            value={readFilter}
            onChange={(e) => setReadFilter(e.target.value as typeof readFilter)}
            className="rounded-md border border-[var(--border)] bg-white px-2 py-2 text-sm"
          >
            <option value="all">Read: All</option>
            <option value="read">Read: Sudah Dibaca</option>
            <option value="unread">Read: Belum Dibaca</option>
          </select>
          <select
            value={completeFilter}
            onChange={(e) => setCompleteFilter(e.target.value as typeof completeFilter)}
            className="rounded-md border border-[var(--border)] bg-white px-2 py-2 text-sm"
          >
            <option value="all">Complete: All</option>
            <option value="complete">Complete: Ya</option>
            <option value="incomplete">Complete: Belum</option>
          </select>
        </div>
      </Card>
      <Card className="space-y-2">
        {chaptersQuery.isPending ? (
          <SkeletonList rows={5} />
        ) : chaptersQuery.isError ? (
          <ErrorState
            title="Gagal memuat chapter"
            description="Coba buka ulang komik atau lakukan scan ulang."
            onRetry={() => void chaptersQuery.refetch()}
          />
        ) : (chaptersQuery.data?.length ?? 0) === 0 ? (
          <EmptyState
            title="Chapter tidak ditemukan"
            description="Komik ini belum punya chapter terdeteksi. Jalankan scan ulang."
          />
        ) : filteredChapters.length === 0 ? (
          <EmptyState
            title="Tidak ada chapter sesuai filter"
            description="Ubah filter read/complete untuk menampilkan chapter lain."
          />
        ) : (
          filteredChapters.map((chapter) => (
            <div
              key={chapter.id}
              className="flex flex-wrap items-center justify-between gap-3 rounded-md border border-[var(--border)] bg-white p-3"
            >
              <div>
                <Link
                  to="/reader/$chapterId"
                  params={{ chapterId: String(chapter.id) }}
                  search={{ mode: "webtoon" }}
                  className="font-semibold text-[var(--accent)] hover:underline"
                >
                  {chapter.title}
                </Link>
                <p className="text-xs text-[var(--muted-foreground)]">
                  Pages: {chapter.page_count} | Last: {chapter.last_page + 1} | Status:{" "}
                  {chapter.is_read ? "Read" : "Unread"}
                </p>
              </div>
            </div>
          ))
        )}
      </Card>
    </section>
  );
}
