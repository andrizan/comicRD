import { useEffect, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { open, save } from "@tauri-apps/plugin-dialog";
import { AlertTriangle, FolderOpen } from "lucide-react";
import { exportDatabaseBackup, importDatabaseBackup, listSettings, setSetting } from "../api/tauri";
import { ErrorState, SkeletonList } from "../components/feedback/states";
import { localeOptions, type LocalePreference, useAppI18n } from "../i18n";
import { isLibrarySourceSaveDisabled } from "../lib/settings-state";
import { setScrollKey, restoreScroll, scrollPositions } from "./Layout";

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

export function SettingsPage() {
  const { t } = useAppI18n();
  const queryClient = useQueryClient();
  const settingsQuery = useQuery({
    queryKey: ["settings"],
    queryFn: listSettings,
  });

  useEffect(() => {
    setScrollKey("settings");
    restoreScroll("settings");
    if (!scrollPositions.has("settings")) {
      document.querySelector<HTMLElement>(".content-scroll")?.scrollTo({ top: 0, behavior: "instant" });
    }
  }, []);

  const [defaultZoom, setDefaultZoom] = useState(1);
  const [pageGap, setPageGap] = useState(10);
  const [appTheme, setAppTheme] = useState<"light" | "dark">("light");
  const [savedAppTheme, setSavedAppTheme] = useState<"light" | "dark">("light");
  const [localePreference, setLocalePreference] = useState<LocalePreference>("en");
  const [savedLocalePreference, setSavedLocalePreference] = useState<LocalePreference>("en");
  const [isAppearanceSaving, setIsAppearanceSaving] = useState(false);
  const [librarySource, setLibrarySource] = useState("");
  const [savedLibrarySource, setSavedLibrarySource] = useState("");
  const [isLibrarySourceSaving, setIsLibrarySourceSaving] = useState(false);
  const [backupMessage, setBackupMessage] = useState("");
  const [isBackupBusy, setIsBackupBusy] = useState(false);

  useEffect(() => {
    const map = new Map((settingsQuery.data ?? []).map((x) => [x.key, x.value_json]));
    setDefaultZoom(parse<number>(map.get("default_zoom"), 1));
    setPageGap(normalizePageGap(parse<number>(map.get("page_gap"), 10)));
    const theme = parseTheme(map.get("app_theme"));
    setAppTheme(theme);
    setSavedAppTheme(theme);
    const locale = parseLocalePreference(map.get("app_locale"));
    setLocalePreference(locale);
    setSavedLocalePreference(locale);
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
    await setSetting("app_locale", localePreference);
    await queryClient.invalidateQueries({ queryKey: ["settings"] });
  }

  async function saveAppearance() {
    if (isAppearanceDisabled) return;
    setIsAppearanceSaving(true);
    try {
      await setSetting("app_theme", appTheme);
      await setSetting("app_locale", localePreference);
      await queryClient.invalidateQueries({ queryKey: ["settings"] });
      setSavedAppTheme(appTheme);
      setSavedLocalePreference(localePreference);
    } finally {
      setIsAppearanceSaving(false);
    }
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
    const selected = await open({
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

  if (settingsQuery.isPending) {
    return (
      <section className="px-5 py-4">
        <SkeletonList rows={4} />
      </section>
    );
  }

  if (settingsQuery.isError) {
    return (
      <section className="px-5 py-4">
        <ErrorState
          title={t("settings.loadError.title")}
          description={t("settings.loadError.description")}
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

  const isAppearanceDisabled =
    isAppearanceSaving ||
    (appTheme === savedAppTheme && localePreference === savedLocalePreference);

  const isLibrarySourceEmpty = !librarySource.trim();

  return (
    <section className="flex flex-col">
      {/* Header */}
      <div className="border-b border-app-border bg-app-surface">
        <div className="px-5 py-3">
          <h2 className="text-sm font-bold">{t("nav.settings")}</h2>
        </div>
      </div>

      <div className="space-y-5 px-5 py-4">
        {/* Warning banner */}
        {isLibrarySourceEmpty ? (
          <div className="flex items-center gap-3 rounded-lg border border-amber-500/30 bg-amber-500/10 px-4 py-3">
            <AlertTriangle size={18} className="flex-shrink-0 text-amber-500" />
            <div className="min-w-0 flex-1">
              <p className="text-sm font-medium text-amber-500">
                {t("settings.librarySource.title")}
              </p>
              <p className="text-xs text-amber-500/70">
                {t("settings.librarySource.description")}
              </p>
            </div>
          </div>
        ) : null}

        {/* Library Source */}
        <div className="space-y-3">
          <h3 className="font-display text-[11px] font-extrabold uppercase tracking-[0.1em] text-app-muted">
            {t("settings.librarySource.title")}
          </h3>
          <div className="flex items-center gap-2">
            <div className="flex min-w-0 flex-1 items-center gap-2 rounded-lg border border-app-border bg-app-surface px-3.5 h-10">
              <FolderOpen size={16} className="flex-shrink-0 text-app-muted" />
              <input
                value={librarySource}
                onChange={(event) => setLibrarySource(event.target.value)}
                className="min-w-0 flex-1 border-none bg-transparent text-sm outline-none placeholder:text-app-muted"
                placeholder={t("settings.librarySource.placeholder")}
              />
            </div>
            <button
              type="button"
              onClick={() => void onPickLibrarySource()}
              className="h-10 shrink-0 rounded-lg border border-app-border bg-app-surface px-4 text-sm font-medium text-app-text transition-colors hover:bg-app-bg"
            >
              {t("settings.browse")}
            </button>
            <button
              type="button"
              onClick={() => void saveLibrarySource()}
              disabled={isSetFolderDisabled}
              className="h-10 shrink-0 rounded-lg bg-app-accent px-4 text-sm font-medium text-white transition-colors hover:brightness-110 disabled:opacity-50"
            >
              {t("settings.setFolder")}
            </button>
          </div>
        </div>

        {/* Reader Settings */}
        <div className="space-y-3">
          <h3 className="font-display text-[11px] font-extrabold uppercase tracking-[0.1em] text-app-muted">
            {t("settings.reader.title")}
          </h3>
          <div className="rounded-lg border border-app-border bg-app-surface px-4 py-3 text-sm text-app-muted">
            {t("settings.readerModeLocked")}
            <span className="font-semibold text-app-text">{t("settings.webtoon")}</span>.
          </div>

          <label className="block">
            <span className="mb-1.5 block text-sm font-medium">{t("settings.defaultZoom")}</span>
            <input
              min={0.4}
              max={3}
              step={0.1}
              type="range"
              value={defaultZoom}
              onChange={(e) => setDefaultZoom(Number(e.target.value))}
              className="w-full accent-app-accent"
            />
            <p className="mt-1 text-xs text-app-muted">
              {t("common.value", { value: `${Math.round(defaultZoom * 100)}%` })}
            </p>
          </label>

          <label className="block">
            <span className="mb-1.5 block text-sm font-medium">{t("settings.pageGap")}</span>
            <input
              min={0}
              max={100}
              step={10}
              type="range"
              value={pageGap}
              onChange={(e) => setPageGap(Number(e.target.value))}
              className="w-full accent-app-accent"
            />
            <p className="mt-1 text-xs text-app-muted">
              {t("common.value", { value: `${pageGap}px` })}
            </p>
          </label>

          <button
            type="button"
            onClick={() => void saveAll()}
            className="h-10 rounded-lg bg-app-accent px-5 text-sm font-medium text-white transition-colors hover:brightness-110"
          >
            {t("settings.saveSettings")}
          </button>
        </div>

        {/* Appearance */}
        <div className="space-y-3">
          <h3 className="font-display text-[11px] font-extrabold uppercase tracking-[0.1em] text-app-muted">
            {t("settings.appearance.title")}
          </h3>
          <div className="grid grid-cols-2 gap-3">
            <label className="block">
              <span className="mb-1.5 block text-sm font-medium">{t("settings.theme")}</span>
              <select
                value={appTheme}
                onChange={(event) => setAppTheme(event.target.value === "dark" ? "dark" : "light")}
                className="h-10 w-full cursor-pointer rounded-lg border border-app-border bg-app-surface px-3 text-sm text-app-text transition-all focus:border-app-accent focus:outline-none"
              >
                <option value="light">{t("common.light")}</option>
                <option value="dark">{t("common.dark")}</option>
              </select>
            </label>
            <label className="block">
              <span className="mb-1.5 block text-sm font-medium">{t("settings.language")}</span>
              <select
                value={localePreference}
                onChange={(event) => setLocalePreference(event.target.value as LocalePreference)}
                className="h-10 w-full cursor-pointer rounded-lg border border-app-border bg-app-surface px-3 text-sm text-app-text transition-all focus:border-app-accent focus:outline-none"
              >
                {localeOptions.map((option) => (
                  <option key={option.value} value={option.value}>
                    {option.value === "id"
                      ? t("settings.language.indonesian")
                      : t("settings.language.english")}
                  </option>
                ))}
              </select>
            </label>
          </div>
          <button
            type="button"
            onClick={() => void saveAppearance()}
            disabled={isAppearanceDisabled}
            className="h-10 rounded-lg bg-app-accent px-5 text-sm font-medium text-white transition-colors hover:brightness-110 disabled:opacity-50"
          >
            {t("settings.saveAppearance")}
          </button>
        </div>

        {/* Backup */}
        <div className="space-y-3">
          <h3 className="font-display text-[11px] font-extrabold uppercase tracking-[0.1em] text-app-muted">
            {t("settings.backup.title")}
          </h3>
          <p className="text-sm text-app-muted">{t("settings.backup.description")}</p>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => void onExportBackup()}
              disabled={isBackupBusy}
              className="h-10 rounded-lg bg-app-accent px-5 text-sm font-medium text-white transition-colors hover:brightness-110 disabled:opacity-50"
            >
              {t("settings.exportBackup")}
            </button>
            <button
              type="button"
              onClick={() => void onImportBackup()}
              disabled={isBackupBusy}
              className="h-10 rounded-lg border border-app-border bg-app-surface px-5 text-sm font-medium text-app-text transition-colors hover:bg-app-bg disabled:opacity-50"
            >
              {t("settings.importBackup")}
            </button>
          </div>
          {backupMessage ? (
            <p className="break-all text-xs text-app-muted">{backupMessage}</p>
          ) : null}
        </div>
      </div>
    </section>
  );
}
