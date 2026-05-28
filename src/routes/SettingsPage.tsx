import { useEffect, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { open, save } from "@tauri-apps/plugin-dialog";
import { exportDatabaseBackup, importDatabaseBackup, listSettings, setSetting } from "../api/tauri";
import { ErrorState, SkeletonList } from "../components/feedback/states";
import { Button } from "../components/ui/button";
import { Card } from "../components/ui/card";
import { isLibrarySourceSaveDisabled } from "../lib/settings-state";

function parse<T>(value: string | undefined, fallback: T): T {
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

function parseTheme(value: string | undefined): "light" | "dark" {
  return parse<string>(value, "light") === "dark" ? "dark" : "light";
}

export function SettingsPage() {
  const queryClient = useQueryClient();
  const settingsQuery = useQuery({
    queryKey: ["settings"],
    queryFn: listSettings,
  });

  const [defaultZoom, setDefaultZoom] = useState(1);
  const [pageGap, setPageGap] = useState(10);
  const [appTheme, setAppTheme] = useState<"light" | "dark">("light");
  const [librarySource, setLibrarySource] = useState("");
  const [savedLibrarySource, setSavedLibrarySource] = useState("");
  const [isLibrarySourceSaving, setIsLibrarySourceSaving] = useState(false);
  const [backupMessage, setBackupMessage] = useState("");
  const [isBackupBusy, setIsBackupBusy] = useState(false);

  useEffect(() => {
    const map = new Map((settingsQuery.data ?? []).map((x) => [x.key, x.value_json]));
    setDefaultZoom(parse<number>(map.get("default_zoom"), 1));
    setPageGap(normalizePageGap(parse<number>(map.get("page_gap"), 10)));
    setAppTheme(parseTheme(map.get("app_theme")));
    const storedLibrarySource = parse<string>(map.get("library_source_input"), "");
    setLibrarySource(storedLibrarySource);
    setSavedLibrarySource(storedLibrarySource);
  }, [settingsQuery.data]);

  async function saveAll() {
    await setSetting("default_mode", "webtoon");
    await setSetting("arrow_navigation_enabled", false);
    await setSetting("default_zoom", Number(defaultZoom.toFixed(2)));
    await setSetting("page_gap", normalizePageGap(pageGap));
    await setSetting("app_theme", appTheme);
    await queryClient.invalidateQueries({ queryKey: ["settings"] });
  }

  async function onPickLibrarySource() {
    const selected = await open({
      directory: true,
      multiple: false,
    });
    if (typeof selected === "string" && selected.trim()) {
      setLibrarySource(selected.trim());
    }
  }

  async function saveLibrarySource() {
    if (isLibrarySourceSaveDisabled(librarySource, savedLibrarySource, isLibrarySourceSaving)) {
      return;
    }

    setIsLibrarySourceSaving(true);
    try {
      await setSetting("library_source_input", librarySource.trim());
      await queryClient.invalidateQueries({ queryKey: ["settings"] });
      await queryClient.invalidateQueries({ queryKey: ["raw-comics"] });
    } finally {
      setIsLibrarySourceSaving(false);
    }
  }

  async function onExportBackup() {
    const selected = await save({
      defaultPath: "comicrd-backup.db",
      filters: [
        {
          name: "SQLite DB",
          extensions: ["db"],
        },
      ],
    });
    if (!selected || typeof selected !== "string") return;

    setIsBackupBusy(true);
    try {
      await exportDatabaseBackup(selected);
      setBackupMessage(`Backup berhasil diexport: ${selected}`);
    } catch (error) {
      setBackupMessage(`Backup export gagal: ${String(error)}`);
    } finally {
      setIsBackupBusy(false);
    }
  }

  async function onImportBackup() {
    const selected = await open({
      multiple: false,
      directory: false,
      filters: [
        {
          name: "SQLite DB",
          extensions: ["db"],
        },
      ],
    });
    if (!selected || typeof selected !== "string") return;

    setIsBackupBusy(true);
    try {
      await importDatabaseBackup(selected);
      await queryClient.invalidateQueries();
      setBackupMessage(`Backup berhasil diimport: ${selected}`);
    } catch (error) {
      setBackupMessage(`Backup import gagal: ${String(error)}`);
    } finally {
      setIsBackupBusy(false);
    }
  }

  if (settingsQuery.isPending) {
    return (
      <section className="space-y-4">
        <SkeletonList rows={4} />
      </section>
    );
  }

  if (settingsQuery.isError) {
    return (
      <section className="space-y-4">
        <ErrorState
          title="Gagal memuat settings"
          description="Coba reload halaman settings."
          onRetry={() => void settingsQuery.refetch()}
        />
      </section>
    );
  }

  const isSetFolderDisabled = isLibrarySourceSaveDisabled(
    librarySource,
    savedLibrarySource,
    isLibrarySourceSaving,
  );

  return (
    <section className="space-y-4">
      <Card className="space-y-4">
        <h2 className="text-xl font-bold">Library Source</h2>
        <p className="text-sm text-[var(--muted-foreground)]">
          Folder ini dipakai sebagai root library. Library page hanya membaca title komik dari sini.
        </p>
        <div className="flex flex-wrap items-center gap-2">
          <input
            value={librarySource}
            onChange={(event) => setLibrarySource(event.target.value)}
            className="min-w-[360px] flex-1 rounded-md border border-[var(--border)] bg-[var(--card)] px-3 py-2 text-sm"
            placeholder="/path/ke/folder-komik"
          />
          <Button onClick={() => void onPickLibrarySource()} variant="outline">
            Browse
          </Button>
          <Button onClick={() => void saveLibrarySource()} disabled={isSetFolderDisabled}>
            Set Folder
          </Button>
        </div>
      </Card>

      <Card className="space-y-4">
        <h2 className="text-xl font-bold">Reader Settings</h2>
        <p className="rounded-md border border-[var(--border)] bg-[var(--card)] px-3 py-2 text-sm">
          Reader mode dikunci ke <span className="font-semibold">Webtoon</span>.
        </p>

        <label className="block">
          <span className="mb-1 block text-sm font-semibold">Default Zoom</span>
          <input
            min={0.4}
            max={3}
            step={0.1}
            type="range"
            value={defaultZoom}
            onChange={(e) => setDefaultZoom(Number(e.target.value))}
            className="w-full"
          />
          <p className="text-xs text-[var(--muted-foreground)]">
            Value: {Math.round(defaultZoom * 100)}%
          </p>
        </label>

        <label className="block">
          <span className="mb-1 block text-sm font-semibold">Page Margin / Gap</span>
          <input
            min={0}
            max={100}
            step={10}
            type="range"
            value={pageGap}
            onChange={(e) => setPageGap(Number(e.target.value))}
            className="w-full"
          />
          <p className="text-xs text-[var(--muted-foreground)]">Value: {pageGap}px</p>
        </label>

        <Button onClick={saveAll}>Save Settings</Button>
      </Card>

      <Card className="space-y-3">
        <h2 className="text-lg font-bold">Appearance</h2>
        <label className="block">
          <span className="mb-1 block text-sm font-semibold">Theme</span>
          <select
            value={appTheme}
            onChange={(event) => setAppTheme(event.target.value === "dark" ? "dark" : "light")}
            className="rounded-md border border-[var(--border)] bg-[var(--card)] px-3 py-2 text-sm"
          >
            <option value="light">Light</option>
            <option value="dark">Dark</option>
          </select>
        </label>
        <Button onClick={saveAll}>Save Appearance</Button>
      </Card>

      <Card className="space-y-3">
        <h2 className="text-lg font-bold">Backup Database</h2>
        <p className="text-sm text-[var(--muted-foreground)]">
          Export/import seluruh history baca, bookmark, dan settings.
        </p>
        <div className="flex flex-wrap items-center gap-2">
          <Button onClick={() => void onExportBackup()} disabled={isBackupBusy}>
            Export Backup
          </Button>
          <Button onClick={() => void onImportBackup()} variant="outline" disabled={isBackupBusy}>
            Import Backup
          </Button>
        </div>
        {backupMessage ? (
          <p className="text-xs text-[var(--muted-foreground)] break-all">{backupMessage}</p>
        ) : null}
      </Card>
    </section>
  );
}
