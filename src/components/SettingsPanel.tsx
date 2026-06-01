import { useEffect, useMemo, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { open as openDialog, save as saveDialog } from "@tauri-apps/plugin-dialog";
import { AlertTriangle, Check, FolderOpen, HardDrive, RefreshCw, X } from "lucide-react";
import {
  checkLibrarySource,
  exportDatabaseBackup,
  importDatabaseBackup,
  listSettings,
  setSetting,
} from "@/api/tauri";
import { SkeletonList } from "@/components/feedback/states";
import { localeOptions, type LocalePreference, useAppI18n } from "@/i18n";
import { usePreferencesStore } from "@/stores/libraryStore";
import { InputGroup, InputGroupAddon, InputGroupInput } from "@/components/ui/input-group";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Slider } from "@/components/ui/slider";

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

function parseLocalePreference(value: string | undefined): LocalePreference {
  const parsed = parse<string>(value, "en");
  return parsed === "id" ? "id" : "en";
}

interface SettingsPanelProps {
  open: boolean;
  onClose: () => void;
}

export function SettingsPanel({ open, onClose }: SettingsPanelProps) {
  const { t } = useAppI18n();
  const queryClient = useQueryClient();
  const settingsQuery = useQuery({
    queryKey: ["settings"],
    queryFn: listSettings,
  });

  const [defaultZoom, setDefaultZoom] = useState(1);
  const [pageGap, setPageGap] = useState(10);
  const [appTheme, setAppTheme] = useState<"light" | "dark">("light");
  const [localePreference, setLocalePreference] = useState<LocalePreference>("en");
  const [librarySource, setLibrarySource] = useState("");
  const [isSaving, setIsSaving] = useState(false);
  const [backupMessage, setBackupMessage] = useState("");
  const [isBackupBusy, setIsBackupBusy] = useState(false);

  useEffect(() => {
    const map = new Map((settingsQuery.data ?? []).map((x) => [x.key, x.value_json]));
    setDefaultZoom(parse<number>(map.get("default_zoom"), 1));
    setPageGap(normalizePageGap(parse<number>(map.get("page_gap"), 10)));
    setAppTheme(parseTheme(map.get("app_theme")));
    setLocalePreference(parseLocalePreference(map.get("app_locale")));
    const storedLibrarySource = parse<string>(map.get("library_source_input"), "");
    setLibrarySource(storedLibrarySource);
  }, [settingsQuery.data]);

  const sourceStatusQuery = useQuery({
    queryKey: ["library-source-status"],
    queryFn: checkLibrarySource,
    refetchOnWindowFocus: true,
    enabled: open,
  });

  const trimmedLiveSource = librarySource.trim();
  const sourceStatus = useMemo(() => {
    const s = sourceStatusQuery.data;
    if (!s) return null;
    if (trimmedLiveSource === "") {
      return {
        state: "empty" as const,
        label: t("settings.librarySource.statusUnconfigured"),
        tone: "muted" as const,
      };
    }
    if (s.path.trim() !== trimmedLiveSource) {
      return {
        state: "pending" as const,
        label: t("settings.librarySource.statusUnconfigured"),
        tone: "muted" as const,
      };
    }
    if (s.readable) {
      return {
        state: "ok" as const,
        label: t("settings.librarySource.statusAccessible"),
        tone: "ok" as const,
      };
    }
    const tone = "warn" as const;
    if (!s.exists) {
      return { state: "warn" as const, label: t("settings.librarySource.statusNotFound"), tone };
    }
    if (!s.is_dir) {
      return { state: "warn" as const, label: t("settings.librarySource.statusNotDirectory"), tone };
    }
    return { state: "warn" as const, label: t("settings.librarySource.statusNotReadable"), tone };
  }, [sourceStatusQuery.data, trimmedLiveSource, t]);

  useEffect(() => {
    if (open) {
      void queryClient.invalidateQueries({ queryKey: ["settings"] });
    }
  }, [open, queryClient]);

  async function saveAll() {
    setIsSaving(true);
    try {
      const trimmedSource = librarySource.trim();
      await setSetting("default_mode", "webtoon");
      await setSetting("arrow_navigation_enabled", false);
      await setSetting("default_zoom", Number(defaultZoom.toFixed(2)));
      await setSetting("page_gap", normalizePageGap(pageGap));
      await setSetting("app_theme", appTheme);
      await setSetting("app_locale", localePreference);
      if (trimmedSource) {
        await setSetting("library_source_input", trimmedSource);
        usePreferencesStore.getState().setInputPath(trimmedSource);
      }
      await queryClient.invalidateQueries({ queryKey: ["settings"] });
      await queryClient.invalidateQueries({ queryKey: ["raw-comics"] });
      await queryClient.refetchQueries({ queryKey: ["raw-comics"] });
    } finally {
      setIsSaving(false);
    }
  }

  async function onPickLibrarySource() {
    const selected = await openDialog({ directory: true, multiple: false });
    if (typeof selected === "string" && selected.trim()) {
      setLibrarySource(selected.trim());
    }
  }

  async function onExportBackup() {
    const selected = await saveDialog({
      defaultPath: "comicrd-backup.db",
      filters: [{ name: "SQLite DB", extensions: ["db"] }],
    });
    if (!selected || typeof selected !== "string") return;
    setIsBackupBusy(true);
    try {
      await exportDatabaseBackup(selected);
      setBackupMessage(t("settings.backupExportSuccess", { path: selected }));
    } catch (error) {
      setBackupMessage(t("settings.backupExportFailure", { error: String(error) }));
    } finally {
      setIsBackupBusy(false);
    }
  }

  async function onImportBackup() {
    const selected = await openDialog({
      multiple: false,
      directory: false,
      filters: [{ name: "SQLite DB", extensions: ["db"] }],
    });
    if (!selected || typeof selected !== "string") return;
    setIsBackupBusy(true);
    try {
      await importDatabaseBackup(selected);
      await queryClient.invalidateQueries();
      setBackupMessage(t("settings.backupImportSuccess", { path: selected }));
    } catch (error) {
      setBackupMessage(t("settings.backupImportFailure", { error: String(error) }));
    } finally {
      setIsBackupBusy(false);
    }
  }

  const isLibrarySourceEmpty = !librarySource.trim();

  return (
    <>
      {/* Backdrop */}
      <div
        className={`fixed inset-0 z-40 bg-black/40 transition-opacity duration-300 ${
          open ? "opacity-100" : "pointer-events-none opacity-0"
        }`}
        onClick={onClose}
      />

      {/* Panel */}
      <div
        className={`fixed right-0 top-0 z-50 flex h-full w-[400px] flex-col border-l border-app-border bg-app-bg shadow-2xl transition-transform duration-300 ${
          open ? "translate-x-0" : "translate-x-full"
        }`}
      >
        {/* Header */}
        <div className="flex items-center justify-between border-b border-app-border px-5 py-3">
          <h2 className="text-sm font-bold">{t("nav.settings")}</h2>
          <button
            type="button"
            onClick={onClose}
            className="flex h-7 w-7 items-center justify-center rounded-md text-app-muted transition-all hover:bg-app-surface hover:text-app-text"
          >
            <X size={16} />
          </button>
        </div>

        {/* Body */}
        <div className="flex-1 overflow-y-auto">
          {settingsQuery.isPending ? (
            <div className="px-5 py-4">
              <SkeletonList rows={4} />
            </div>
          ) : (
            <>
              {/* Warning */}
              {isLibrarySourceEmpty ? (
                <div className="mx-5 mt-4 flex items-center gap-3 rounded-lg border border-amber-500/30 bg-amber-500/10 px-4 py-3">
                  <AlertTriangle size={18} className="flex-shrink-0 text-amber-500" />
                  <p className="text-xs text-amber-500">
                    {t("settings.librarySource.description")}
                  </p>
                </div>
              ) : null}

              {/* Library Source */}
              <div className="border-b border-app-border px-5 py-4">
                <h3 className="mb-3 font-display text-[11px] font-bold leading-tight uppercase tracking-[0.1em] text-app-muted">
                  {t("settings.librarySource.title")}
                </h3>
                <div className="flex items-center gap-2">
                  <InputGroup className="flex-1">
                    <InputGroupInput
                      value={librarySource}
                      onChange={(event) => setLibrarySource(event.target.value)}
                      placeholder={t("settings.librarySource.placeholder")}
                      className="text-xs"
                    />
                    <InputGroupAddon>
                      <FolderOpen size={14} />
                    </InputGroupAddon>
                  </InputGroup>
                  <button
                    type="button"
                    onClick={() => void onPickLibrarySource()}
                    className="h-9 shrink-0 rounded-lg border border-app-border bg-app-surface px-3 text-xs font-medium text-app-text transition-colors hover:bg-app-bg"
                  >
                    {t("settings.browse")}
                  </button>
                  <button
                    type="button"
                    onClick={() => void sourceStatusQuery.refetch()}
                    title={t("common.refresh")}
                    aria-label={t("common.refresh")}
                    className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg border border-app-border bg-app-surface text-app-muted transition-colors hover:bg-app-bg hover:text-app-text"
                  >
                    <RefreshCw
                      size={14}
                      className={sourceStatusQuery.isFetching ? "animate-spin" : undefined}
                    />
                  </button>
                </div>
                {sourceStatus ? (
                  <div
                    role="status"
                    className={`mt-2 flex items-start gap-2 rounded-md px-2.5 py-1.5 text-[11px] ${
                      sourceStatus.tone === "ok"
                        ? "bg-emerald-500/10 text-emerald-500"
                        : sourceStatus.tone === "warn"
                          ? "bg-amber-500/10 text-amber-500"
                          : "bg-app-bg text-app-muted"
                    }`}
                  >
                    {sourceStatus.tone === "ok" ? (
                      <Check size={12} className="mt-0.5 flex-shrink-0" />
                    ) : sourceStatus.tone === "warn" ? (
                      <AlertTriangle size={12} className="mt-0.5 flex-shrink-0" />
                    ) : (
                      <HardDrive size={12} className="mt-0.5 flex-shrink-0" />
                    )}
                    <span className="leading-snug">{sourceStatus.label}</span>
                  </div>
                ) : null}
              </div>

              {/* Reader */}
              <div className="border-b border-app-border px-5 py-4">
                <h3 className="mb-3 font-display text-[11px] font-bold leading-tight uppercase tracking-[0.1em] text-app-muted">
                  {t("settings.reader.title")}
                </h3>
                <div className="mb-3 rounded-lg border border-app-border bg-app-surface px-3 py-2 text-xs text-app-muted">
                  {t("settings.readerModeLocked")}
                  <span className="font-semibold text-app-text">{t("settings.webtoon")}</span>.
                </div>
                <label className="mb-3 block">
                  <span className="mb-1.5 block text-xs font-medium">
                    {t("settings.defaultZoom")}
                  </span>
                  <Slider
                    value={[defaultZoom]}
                    min={0.4}
                    max={3}
                    step={0.1}
                    onValueChange={(v) => setDefaultZoom(Array.isArray(v) ? v[0] : v)}
                  />
                  <p className="mt-1 text-[10px] text-app-muted">
                    {t("common.value", { value: `${Math.round(defaultZoom * 100)}%` })}
                  </p>
                </label>
                <label className="block">
                  <span className="mb-1.5 block text-xs font-medium">{t("settings.pageGap")}</span>
                  <Slider
                    value={[pageGap]}
                    min={0}
                    max={100}
                    step={10}
                    onValueChange={(v) => setPageGap(Array.isArray(v) ? v[0] : v)}
                  />
                  <p className="mt-1 text-[10px] text-app-muted">
                    {t("common.value", { value: `${pageGap}px` })}
                  </p>
                </label>
              </div>

              {/* Appearance */}
              <div className="border-b border-app-border px-5 py-4">
                <h3 className="mb-3 font-display text-[11px] font-bold leading-tight uppercase tracking-[0.1em] text-app-muted">
                  {t("settings.appearance.title")}
                </h3>
                <div className="grid grid-cols-2 gap-3">
                  <label className="block">
                    <span className="mb-1.5 block text-xs font-medium">{t("settings.theme")}</span>
                    <Select
                      items={[
                        { label: t("common.light"), value: "light" },
                        { label: t("common.dark"), value: "dark" },
                      ]}
                      value={appTheme}
                      onValueChange={(v) => setAppTheme(v as "light" | "dark")}
                    >
                      <SelectTrigger className="h-9 w-full">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="light">{t("common.light")}</SelectItem>
                        <SelectItem value="dark">{t("common.dark")}</SelectItem>
                      </SelectContent>
                    </Select>
                  </label>
                  <label className="block">
                    <span className="mb-1.5 block text-xs font-medium">
                      {t("settings.language")}
                    </span>
                    <Select
                      items={localeOptions.map((option) => ({
                        label: option.value === "id" ? t("settings.language.indonesian") : t("settings.language.english"),
                        value: option.value,
                      }))}
                      value={localePreference}
                      onValueChange={(v) => setLocalePreference(v as LocalePreference)}
                    >
                      <SelectTrigger className="h-9 w-full">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {localeOptions.map((option) => (
                          <SelectItem key={option.value} value={option.value}>
                            {option.value === "id"
                              ? t("settings.language.indonesian")
                              : t("settings.language.english")}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </label>
                </div>
              </div>

              {/* Backup */}
              <div className="px-5 py-4">
                <h3 className="mb-3 font-display text-[11px] font-bold leading-tight uppercase tracking-[0.1em] text-app-muted">
                  {t("settings.backup.title")}
                </h3>
                <p className="mb-3 text-xs text-app-muted">{t("settings.backup.description")}</p>
                <div className="flex items-center gap-2">
                  <button
                    type="button"
                    onClick={() => void onExportBackup()}
                    disabled={isBackupBusy}
                    className="h-9 rounded-lg bg-app-accent px-4 text-xs font-medium text-white transition-colors hover:brightness-110 disabled:opacity-50"
                  >
                    {t("settings.exportBackup")}
                  </button>
                  <button
                    type="button"
                    onClick={() => void onImportBackup()}
                    disabled={isBackupBusy}
                    className="h-9 rounded-lg border border-app-border bg-app-surface px-4 text-xs font-medium text-app-text transition-colors hover:bg-app-bg disabled:opacity-50"
                  >
                    {t("settings.importBackup")}
                  </button>
                </div>
                {backupMessage ? (
                  <p className="mt-2 break-all text-[10px] text-app-muted">{backupMessage}</p>
                ) : null}
              </div>
            </>
          )}
        </div>

        {/* Footer */}
        <div className="border-t border-app-border px-5 py-3 space-y-2">
          <button
            type="button"
            onClick={() => void saveAll()}
            disabled={isSaving}
            className="h-10 w-full rounded-lg bg-app-accent text-sm font-medium text-white transition-colors hover:brightness-110 disabled:opacity-50"
          >
            {isSaving ? "..." : t("settings.saveSettings")}
          </button>
          <p className="text-center text-[10px] text-app-muted">v{__APP_VERSION__}</p>
        </div>
      </div>
    </>
  );
}
