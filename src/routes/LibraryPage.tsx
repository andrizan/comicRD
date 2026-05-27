import { useEffect, useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Link } from "@tanstack/react-router";
import { RefreshCw, Search } from "lucide-react";
import { getSetting, initDb, listLibraryComicsRaw, setSetting } from "../api/tauri";
import { EmptyState, ErrorState, SkeletonList } from "../components/feedback/states";
import { Button } from "../components/ui/button";
import { unixToLocale } from "../lib/utils";
import type { RawComic, SortBy, SortDir } from "../types";

function parseStoredString(value: string | null): string {
  if (!value) return "";
  try {
    const parsed = JSON.parse(value);
    return typeof parsed === "string" ? parsed : "";
  } catch {
    return "";
  }
}

function isViewMode(value: string): value is "all" | "by_folder" {
  return value === "all" || value === "by_folder";
}

export function LibraryPage() {
  const [inputPath, setInputPath] = useState("");
  const [sortBy, setSortBy] = useState<SortBy>("name");
  const [sortDir, setSortDir] = useState<SortDir>("asc");
  const [viewMode, setViewMode] = useState<"all" | "by_folder">("all");
  const [searchText, setSearchText] = useState("");
  const [preferencesReady, setPreferencesReady] = useState(false);
  const activeLibraryPath = inputPath.trim();

  useEffect(() => {
    initDb().catch(console.error);
  }, []);

  useEffect(() => {
    let active = true;
    void (async () => {
      const savedPath = parseStoredString(await getSetting("library_source_input"));
      const savedSortBy = parseStoredString(await getSetting("library_sort_by"));
      const savedSortDir = parseStoredString(await getSetting("library_sort_dir"));
      const savedViewMode = parseStoredString(await getSetting("library_view_mode"));
      if (!active) return;
      if (savedPath.trim()) setInputPath(savedPath.trim());
      if (savedSortBy === "name" || savedSortBy === "folder_date") {
        setSortBy(savedSortBy);
      }
      if (savedSortDir === "asc" || savedSortDir === "desc") {
        setSortDir(savedSortDir);
      }
      if (isViewMode(savedViewMode)) {
        setViewMode(savedViewMode);
      }
      setPreferencesReady(true);
    })();
    return () => {
      active = false;
    };
  }, []);

  useEffect(() => {
    if (!preferencesReady) return;
    void setSetting("library_sort_by", sortBy);
  }, [preferencesReady, sortBy]);

  useEffect(() => {
    if (!preferencesReady) return;
    void setSetting("library_sort_dir", sortDir);
  }, [preferencesReady, sortDir]);

  useEffect(() => {
    if (!preferencesReady) return;
    void setSetting("library_view_mode", viewMode);
  }, [preferencesReady, viewMode]);

  const comicsQuery = useQuery({
    queryKey: ["raw-comics", sortBy, sortDir, activeLibraryPath],
    enabled: activeLibraryPath.length > 0,
    queryFn: () => listLibraryComicsRaw(sortBy, sortDir),
  });

  const filteredComics = useMemo(
    () =>
      (comicsQuery.data ?? []).filter((comic) => {
        const q = searchText.trim().toLowerCase();
        if (!q) return true;
        return comic.title.toLowerCase().includes(q) || comic.source_path.toLowerCase().includes(q);
      }),
    [comicsQuery.data, searchText],
  );

  const groupedComics = useMemo(() => {
    const groups = new Map<string, RawComic[]>();
    for (const comic of filteredComics) {
      const current = groups.get(comic.library_path) ?? [];
      current.push(comic);
      groups.set(comic.library_path, current);
    }
    return groups;
  }, [filteredComics]);

  const libraryStats = useMemo(() => {
    const allComics = comicsQuery.data ?? [];
    return {
      totalComics: allComics.length,
      visibleComics: filteredComics.length,
    };
  }, [comicsQuery.data, filteredComics]);

  return (
    <section className="space-y-3">
      {!activeLibraryPath ? (
        <ErrorState
          title="Folder Library Belum Diset"
          description="Set folder library di Settings terlebih dahulu. Setelah diset, list komik langsung diambil dari folder."
        />
      ) : null}

      <section className="rounded-lg border border-[var(--border)] bg-[var(--card)] p-4">
        <div className="mb-4 flex items-start justify-between gap-4">
          <div>
            <h2 className="text-xl font-bold">Comics</h2>
            <p className="text-xs text-[var(--muted-foreground)]">
              Data diambil langsung dari folder library (raw filesystem).
            </p>
            <div className="mt-2 flex flex-wrap gap-2 text-xs">
              <span className="rounded-full border border-[var(--border)] bg-[var(--card)] px-2.5 py-1 font-semibold">
                Total Komik/Folder: {libraryStats.totalComics}
              </span>
              {searchText.trim() ? (
                <span className="rounded-full border border-[var(--border)] bg-[var(--card)] px-2.5 py-1 font-semibold text-[var(--muted-foreground)]">
                  Filtered: {libraryStats.visibleComics} komik
                </span>
              ) : null}
            </div>
          </div>
          <div className="flex flex-wrap items-center justify-end gap-2">
            <Button
              onClick={() => void comicsQuery.refetch()}
              variant="outline"
              disabled={!activeLibraryPath}
            >
              <RefreshCw size={14} />
              <span>Refresh</span>
            </Button>
            <div className="rounded-md border border-[var(--border)] bg-[var(--card)] p-1">
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
            <input
              value={searchText}
              onChange={(e) => setSearchText(e.target.value)}
              className="min-w-[220px] rounded-md border border-[var(--border)] bg-[var(--card)] px-3 py-2 text-sm"
              placeholder="Cari komik..."
            />
            <select
              value={sortBy}
              onChange={(e) => setSortBy(e.target.value as SortBy)}
              className="rounded-md border border-[var(--border)] bg-[var(--card)] px-2 py-2 text-sm"
            >
              <option value="name">Sort: Name</option>
              <option value="folder_date">Sort: Folder Date</option>
            </select>
            <select
              value={sortDir}
              onChange={(e) => setSortDir(e.target.value as SortDir)}
              className="rounded-md border border-[var(--border)] bg-[var(--card)] px-2 py-2 text-sm"
            >
              <option value="asc">Asc</option>
              <option value="desc">Desc</option>
            </select>
          </div>
        </div>

        {comicsQuery.isPending ? (
          <SkeletonList rows={7} />
        ) : comicsQuery.isError ? (
          <ErrorState
            title="Gagal membaca folder library"
            description="Pastikan path folder valid dan punya izin akses."
            onRetry={() => void comicsQuery.refetch()}
          />
        ) : viewMode === "all" ? (
          filteredComics.length === 0 ? (
            <EmptyState
              title="Tidak ada komik sesuai filter"
              description="Ubah sorting/filter atau cek isi folder library."
            />
          ) : (
            <div className="rounded-md border border-[var(--border)] bg-[var(--card)]">
              {filteredComics.map((item) => (
                <div
                  key={item.key}
                  className="library-row border-b border-[var(--border)] p-3 last:border-b-0"
                >
                  <Link
                    to="/comic/$comicId"
                    params={{ comicId: encodeURIComponent(item.source_path) }}
                    className="text-base font-semibold text-[var(--accent)] hover:underline"
                  >
                    {item.title}
                  </Link>
                  <p className="text-xs text-[var(--muted-foreground)]">{item.source_path}</p>
                  <p className="text-xs text-[var(--muted-foreground)]">
                    Modified: {unixToLocale(item.date_modified)}
                  </p>
                </div>
              ))}
            </div>
          )
        ) : (
          <div className="space-y-3 rounded-md border border-[var(--border)] bg-[var(--card)] p-3">
            {Array.from(groupedComics.entries()).map(([libraryPath, items]) => (
              <div key={libraryPath} className="rounded-md border border-[var(--border)] p-3">
                <p className="text-sm font-bold">{libraryPath}</p>
                <p className="text-xs text-[var(--muted-foreground)]">Comics: {items.length}</p>
                <div className="mt-2 space-y-2">
                  {items.map((item) => (
                    <div
                      key={item.key}
                      className="library-row rounded-md bg-[var(--background)] px-2 py-2"
                    >
                      <Link
                        to="/comic/$comicId"
                        params={{ comicId: encodeURIComponent(item.source_path) }}
                        className="text-sm font-semibold text-[var(--accent)] hover:underline"
                      >
                        {item.title}
                      </Link>
                      <p className="text-xs text-[var(--muted-foreground)]">
                        {item.source_type} · {unixToLocale(item.date_modified)}
                      </p>
                    </div>
                  ))}
                  {items.length === 0 ? (
                    <p className="text-xs text-[var(--muted-foreground)]">
                      No comics in this folder.
                    </p>
                  ) : null}
                </div>
              </div>
            ))}
          </div>
        )}
      </section>
    </section>
  );
}
