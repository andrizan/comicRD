import { useEffect, useMemo, useRef, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useVirtualizer } from "@tanstack/react-virtual";
import { Link } from "@tanstack/react-router";
import { open } from "@tauri-apps/plugin-dialog";
import { RefreshCw, Search } from "lucide-react";
import {
  addLibrary,
  getSetting,
  getLibraryScanStatus,
  initDb,
  listComics,
  listLibraries,
  setSetting,
  startScanLibraries,
} from "../api/tauri";
import { EmptyState, ErrorState, SkeletonList } from "../components/feedback/states";
import { Button } from "../components/ui/button";
import { Card } from "../components/ui/card";
import { unixToLocale } from "../lib/utils";
import type { Comic, SortBy, SortDir } from "../types";

type ReadFilter = "all" | "read" | "unread";
type CompleteFilter = "all" | "complete" | "incomplete";

function comicMatchesReadFilter(comic: Comic, filter: ReadFilter): boolean {
  if (filter === "all") return true;
  const started = comic.read_chapter_count > 0 || comic.in_progress_chapter_count > 0;
  return filter === "read" ? started : !started;
}

function comicMatchesCompleteFilter(comic: Comic, filter: CompleteFilter): boolean {
  if (filter === "all") return true;
  const complete = comic.chapter_count > 0 && comic.read_chapter_count >= comic.chapter_count;
  return filter === "complete" ? complete : !complete;
}

function parseStoredString(value: string | null): string {
  if (!value) return "";
  try {
    const parsed = JSON.parse(value);
    return typeof parsed === "string" ? parsed : "";
  } catch {
    return "";
  }
}

export function LibraryPage() {
  const [inputPath, setInputPath] = useState("");
  const [sortBy, setSortBy] = useState<SortBy>("name");
  const [sortDir, setSortDir] = useState<SortDir>("asc");
  const [readFilter, setReadFilter] = useState<ReadFilter>("all");
  const [completeFilter, setCompleteFilter] = useState<CompleteFilter>("all");
  const [viewMode, setViewMode] = useState<"all" | "by_folder">("all");
  const [isScanStarting, setIsScanStarting] = useState(false);
  const [scanSummary, setScanSummary] = useState<string>("");
  const hasBootstrappedAutoScan = useRef(false);
  const prevRunningRef = useRef(false);
  const queryClient = useQueryClient();

  useEffect(() => {
    initDb().catch(console.error);
  }, []);

  useEffect(() => {
    let active = true;
    void (async () => {
      const saved = parseStoredString(await getSetting("library_source_input"));
      if (!active) return;
      if (saved.trim()) {
        setInputPath(saved.trim());
      }
    })();
    return () => {
      active = false;
    };
  }, []);

  const librariesQuery = useQuery({
    queryKey: ["libraries"],
    queryFn: listLibraries,
  });

  const comicsQuery = useQuery({
    queryKey: ["comics", sortBy, sortDir],
    queryFn: () => listComics(sortBy, sortDir),
  });
  const scanStatusQuery = useQuery({
    queryKey: ["library-scan-status"],
    queryFn: getLibraryScanStatus,
    refetchInterval: (query) => (query.state.data?.running ? 700 : false),
    refetchOnWindowFocus: false,
  });

  const libraryLabel = useMemo(
    () => librariesQuery.data?.map((x) => x.path).join("\n") ?? "",
    [librariesQuery.data],
  );
  const filteredComics = useMemo(
    () =>
      (comicsQuery.data ?? [])
        .filter((comic) => comicMatchesReadFilter(comic, readFilter))
        .filter((comic) => comicMatchesCompleteFilter(comic, completeFilter)),
    [comicsQuery.data, readFilter, completeFilter],
  );
  const groupedComics = useMemo(() => {
    const groups = new Map<number, Comic[]>();
    for (const comic of filteredComics) {
      const current = groups.get(comic.library_id) ?? [];
      current.push(comic);
      groups.set(comic.library_id, current);
    }
    return groups;
  }, [filteredComics]);
  const hasLibraries = (librariesQuery.data?.length ?? 0) > 0;
  const isScanRunning = scanStatusQuery.data?.running ?? false;
  const isScanBusy = isScanRunning || isScanStarting;

  async function triggerBackgroundScan(reason: "manual" | "auto-add" | "auto-startup") {
    setIsScanStarting(true);
    try {
      const started = await startScanLibraries();
      if (started) {
        if (reason === "manual") {
          setScanSummary("Scan berjalan di background...");
        } else if (reason === "auto-add") {
          setScanSummary("Auto detect berjalan di background...");
        } else {
          setScanSummary("Auto detect startup berjalan di background...");
        }
      } else {
        setScanSummary("Scan sedang berjalan. Mohon tunggu sampai selesai.");
      }
      await scanStatusQuery.refetch();
    } finally {
      setIsScanStarting(false);
    }
  }

  async function onAddLibrary() {
    const nextPath = inputPath.trim();
    if (!nextPath) return;
    await addLibrary(nextPath);
    await setSetting("library_source_input", nextPath);
    setInputPath(nextPath);
    await queryClient.invalidateQueries({ queryKey: ["libraries"] });
    await triggerBackgroundScan("auto-add");
  }

  async function onPickFolder() {
    const selected = await open({
      directory: true,
      multiple: false,
    });
    if (typeof selected === "string" && selected.trim()) {
      const nextPath = selected.trim();
      setInputPath(nextPath);
      await setSetting("library_source_input", nextPath);
    }
  }

  async function onScan() {
    if (!hasLibraries) {
      setScanSummary("Set folder library terlebih dahulu sebelum scan.");
      return;
    }
    await triggerBackgroundScan("manual");
  }

  useEffect(() => {
    if (hasBootstrappedAutoScan.current) return;
    if (librariesQuery.isPending || librariesQuery.isError) return;
    if ((librariesQuery.data?.length ?? 0) === 0) return;
    hasBootstrappedAutoScan.current = true;
    void triggerBackgroundScan("auto-startup");
  }, [librariesQuery.data, librariesQuery.isError, librariesQuery.isPending, queryClient]);

  useEffect(() => {
    const status = scanStatusQuery.data;
    if (!status) return;
    if (prevRunningRef.current && !status.running) {
      if (status.error) {
        setScanSummary(`Scan gagal: ${status.error}`);
      } else if (status.last_summary) {
        setScanSummary(
          `Scan selesai: ${status.last_summary.comics} comics, ${status.last_summary.chapters} chapters`,
        );
      } else {
        setScanSummary("Scan selesai.");
      }
      void queryClient.invalidateQueries({ queryKey: ["comics"] });
      void queryClient.invalidateQueries({ queryKey: ["libraries"] });
    }
    prevRunningRef.current = status.running;
  }, [scanStatusQuery.data, queryClient]);

  useEffect(() => {
    if (inputPath.trim()) return;
    const firstLibraryPath = librariesQuery.data?.[0]?.path?.trim();
    if (firstLibraryPath) {
      setInputPath(firstLibraryPath);
    }
  }, [librariesQuery.data, inputPath]);

  const parentRef = useRef<HTMLDivElement>(null);
  const rowVirtualizer = useVirtualizer({
    count: filteredComics.length,
    getScrollElement: () => parentRef.current,
    estimateSize: () => 96,
    overscan: 8,
  });

  return (
    <section className="space-y-4">
      <Card>
        <h2 className="mb-3 text-xl font-bold">Library Source</h2>
        <div className="flex flex-wrap items-center gap-2">
          <input
            value={inputPath}
            onChange={(e) => setInputPath(e.target.value)}
            className="min-w-[360px] flex-1 rounded-md border border-[var(--border)] bg-white px-3 py-2 text-sm"
            placeholder="/path/ke/folder-komik"
          />
          <Button onClick={onPickFolder} variant="outline">
            Browse
          </Button>
          <Button onClick={onAddLibrary} disabled={isScanBusy}>
            {isScanBusy ? "Working..." : "Set Folder"}
          </Button>
          <Button onClick={onScan} variant="outline" disabled={isScanBusy || !hasLibraries}>
            <RefreshCw size={14} className={isScanBusy ? "animate-spin" : ""} />
            <span>{isScanBusy ? "Scanning..." : "Scan Ulang"}</span>
          </Button>
        </div>
        <p className="mt-2 text-xs text-[var(--muted-foreground)] whitespace-pre-wrap">
          {libraryLabel || "Belum ada folder library. Set folder lalu komik akan auto-detect."}
        </p>
        {scanSummary ? (
          <p className="mt-1 text-xs font-semibold text-[var(--accent)]">{scanSummary}</p>
        ) : null}
        {isScanRunning ? (
          <p className="mt-1 text-xs font-semibold text-[var(--foreground)]">
            Scan berjalan di background. UI tetap responsif.
          </p>
        ) : null}
      </Card>

      {!librariesQuery.isPending && !librariesQuery.isError && !hasLibraries ? (
        <ErrorState
          title="Folder Library Belum Diset"
          description="Sebelum baca komik, set folder library terlebih dahulu lewat input path atau tombol Browse di atas."
        />
      ) : null}

      <Card>
        <div className="mb-3 flex items-center justify-between gap-2">
          <div>
            <h2 className="text-xl font-bold">Comics</h2>
            <p className="text-xs text-[var(--muted-foreground)]">
              Klik title komik untuk buka daftar chapter.
            </p>
          </div>
          <div className="flex items-center gap-2">
            <div className="rounded-md border border-[var(--border)] bg-white p-1">
              <button
                onClick={() => setViewMode("all")}
                className={`rounded px-2 py-1 text-xs font-semibold ${
                  viewMode === "all"
                    ? "bg-[var(--accent)] text-white"
                    : "text-[var(--muted-foreground)]"
                }`}
              >
                All
              </button>
              <button
                onClick={() => setViewMode("by_folder")}
                className={`rounded px-2 py-1 text-xs font-semibold ${
                  viewMode === "by_folder"
                    ? "bg-[var(--accent)] text-white"
                    : "text-[var(--muted-foreground)]"
                }`}
              >
                Folder View
              </button>
            </div>
            <Search size={14} />
            <select
              value={sortBy}
              onChange={(e) => setSortBy(e.target.value as SortBy)}
              className="rounded-md border border-[var(--border)] bg-white px-2 py-2 text-sm"
            >
              <option value="name">Sort: Name</option>
              <option value="folder_date">Sort: Folder Date</option>
            </select>
            <select
              value={sortDir}
              onChange={(e) => setSortDir(e.target.value as SortDir)}
              className="rounded-md border border-[var(--border)] bg-white px-2 py-2 text-sm"
            >
              <option value="asc">Asc</option>
              <option value="desc">Desc</option>
            </select>
            <select
              value={readFilter}
              onChange={(e) => setReadFilter(e.target.value as ReadFilter)}
              className="rounded-md border border-[var(--border)] bg-white px-2 py-2 text-sm"
            >
              <option value="all">Read: All</option>
              <option value="read">Read: Sudah Dibaca</option>
              <option value="unread">Read: Belum Dibaca</option>
            </select>
            <select
              value={completeFilter}
              onChange={(e) => setCompleteFilter(e.target.value as CompleteFilter)}
              className="rounded-md border border-[var(--border)] bg-white px-2 py-2 text-sm"
            >
              <option value="all">Complete: All</option>
              <option value="complete">Complete: Ya</option>
              <option value="incomplete">Complete: Belum</option>
            </select>
          </div>
        </div>

        {!hasLibraries && !librariesQuery.isPending ? (
          <EmptyState
            title="Belum bisa menampilkan komik"
            description="Set folder library terlebih dahulu. Setelah diset, komik akan dideteksi otomatis."
          />
        ) : librariesQuery.isPending || comicsQuery.isPending ? (
          <SkeletonList rows={7} />
        ) : librariesQuery.isError || comicsQuery.isError ? (
          <ErrorState
            title="Gagal memuat library/comics"
            description="Periksa path library atau coba scan ulang."
            onRetry={() => {
              void librariesQuery.refetch();
              void comicsQuery.refetch();
            }}
          />
        ) : viewMode === "all" ? (
          filteredComics.length === 0 ? (
            <EmptyState
              title="Tidak ada komik sesuai filter"
              description="Ubah sorting/filter atau lakukan scan ulang."
            />
          ) : (
            <div
              ref={parentRef}
              className="h-[60vh] overflow-auto rounded-md border border-[var(--border)] bg-white"
            >
              <div style={{ height: `${rowVirtualizer.getTotalSize()}px`, position: "relative" }}>
                {rowVirtualizer.getVirtualItems().map((v) => {
                  const item = filteredComics[v.index];
                  if (!item) return null;
                  const isComplete =
                    item.chapter_count > 0 && item.read_chapter_count >= item.chapter_count;
                  const isRead = item.read_chapter_count > 0 || item.in_progress_chapter_count > 0;
                  return (
                    <div
                      key={item.id}
                      className="absolute left-0 top-0 w-full border-b border-[var(--border)] p-3"
                      style={{ transform: `translateY(${v.start}px)` }}
                    >
                      <div>
                        <Link
                          to="/comic/$comicId"
                          params={{ comicId: String(item.id) }}
                          className="text-base font-semibold text-[var(--accent)] hover:underline"
                        >
                          {item.title}
                        </Link>
                        <p className="text-xs text-[var(--muted-foreground)]">{item.source_path}</p>
                        <p className="text-xs text-[var(--muted-foreground)]">
                          Modified: {unixToLocale(item.date_modified)}
                        </p>
                        <p className="text-xs text-[var(--muted-foreground)]">
                          Chapters: {item.read_chapter_count}/{item.chapter_count} · Read:{" "}
                          {isRead ? "Ya" : "Belum"} · Complete: {isComplete ? "Ya" : "Belum"}
                        </p>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          )
        ) : (librariesQuery.data?.length ?? 0) === 0 ? (
          <EmptyState
            title="Belum ada folder library"
            description="Gunakan tombol Browse atau isi path folder, lalu klik Add Folder."
          />
        ) : (
          <div className="h-[60vh] space-y-3 overflow-auto rounded-md border border-[var(--border)] bg-white p-3">
            {(librariesQuery.data ?? []).map((library) => {
              const items = groupedComics.get(library.id) ?? [];
              return (
                <div key={library.id} className="rounded-md border border-[var(--border)] p-3">
                  <p className="text-sm font-bold">{library.path}</p>
                  <p className="text-xs text-[var(--muted-foreground)]">
                    Comics: {items.length} · Updated: {unixToLocale(library.updated_at)}
                  </p>
                  <div className="mt-2 space-y-2">
                    {items.map((item) => (
                      <div key={item.id} className="rounded-md bg-[#fffdf6] px-2 py-2">
                        <div>
                          <Link
                            to="/comic/$comicId"
                            params={{ comicId: String(item.id) }}
                            className="text-sm font-semibold text-[var(--accent)] hover:underline"
                          >
                            {item.title}
                          </Link>
                          <p className="text-xs text-[var(--muted-foreground)]">
                            {item.source_type} · {unixToLocale(item.date_modified)} ·{" "}
                            {item.read_chapter_count}/{item.chapter_count} read
                          </p>
                        </div>
                      </div>
                    ))}
                    {items.length === 0 && (
                      <p className="text-xs text-[var(--muted-foreground)]">
                        No comics in this folder.
                      </p>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </Card>
    </section>
  );
}
