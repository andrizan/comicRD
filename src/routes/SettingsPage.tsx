import { useEffect, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { open, save } from "@tauri-apps/plugin-dialog";
import { exportDatabaseBackup, importDatabaseBackup, listSettings, setSetting } from "../api/tauri";
import { ErrorState, SkeletonList } from "../components/feedback/states";
import { Button } from "../components/ui/button";
import { Card } from "../components/ui/card";
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
      setBackupMessage(t("settings.backupImportSuccess", { path: selected }));
    } catch (error) {
      setBackupMessage(t("settings.backupImportFailure", { error: String(error) }));
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

  return (
    <section className="space-y-4">
      <Card className="space-y-4">
        <h2 className="text-xl font-bold">{t("settings.librarySource.title")}</h2>
        <p className="text-sm text-[var(--muted-foreground)]">
          {t("settings.librarySource.description")}
        </p>
        <div className="flex flex-wrap items-center gap-2">
          <input
            value={librarySource}
            onChange={(event) => setLibrarySource(event.target.value)}
            className="min-w-[360px] flex-1 rounded-md border border-[var(--border)] bg-[var(--card)] px-3 py-2 text-sm"
            placeholder={t("settings.librarySource.placeholder")}
          />
          <Button onClick={() => void onPickLibrarySource()} variant="outline">
            {t("settings.browse")}
          </Button>
          <Button onClick={() => void saveLibrarySource()} disabled={isSetFolderDisabled}>
            {t("settings.setFolder")}
          </Button>
        </div>
      </Card>

      <Card className="space-y-4">
        <h2 className="text-xl font-bold">{t("settings.reader.title")}</h2>
        <p className="rounded-md border border-[var(--border)] bg-[var(--card)] px-3 py-2 text-sm">
          {t("settings.readerModeLocked")}
          <span className="font-semibold">{t("settings.webtoon")}</span>.
        </p>

        <label className="block">
          <span className="mb-1 block text-sm font-semibold">{t("settings.defaultZoom")}</span>
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
            {t("common.value", { value: `${Math.round(defaultZoom * 100)}%` })}
          </p>
        </label>

        <label className="block">
          <span className="mb-1 block text-sm font-semibold">{t("settings.pageGap")}</span>
          <input
            min={0}
            max={100}
            step={10}
            type="range"
            value={pageGap}
            onChange={(e) => setPageGap(Number(e.target.value))}
            className="w-full"
          />
          <p className="text-xs text-[var(--muted-foreground)]">
            {t("common.value", { value: `${pageGap}px` })}
          </p>
        </label>

        <Button onClick={saveAll}>{t("settings.saveSettings")}</Button>
      </Card>

      <Card className="space-y-3">
        <h2 className="text-lg font-bold">{t("settings.appearance.title")}</h2>
        <label className="block">
          <span className="mb-1 block text-sm font-semibold">{t("settings.theme")}</span>
          <select
            value={appTheme}
            onChange={(event) => setAppTheme(event.target.value === "dark" ? "dark" : "light")}
            className="rounded-md border border-[var(--border)] bg-[var(--card)] px-3 py-2 text-sm"
          >
            <option value="light">{t("common.light")}</option>
            <option value="dark">{t("common.dark")}</option>
          </select>
        </label>
        <label className="block">
          <span className="mb-1 block text-sm font-semibold">{t("settings.language")}</span>
          <select
            value={localePreference}
            onChange={(event) => setLocalePreference(event.target.value as LocalePreference)}
            className="rounded-md border border-[var(--border)] bg-[var(--card)] px-3 py-2 text-sm"
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
        <Button onClick={() => void saveAppearance()} disabled={isAppearanceDisabled}>
          {t("settings.saveAppearance")}
        </Button>
      </Card>

      <Card className="space-y-3">
        <h2 className="text-lg font-bold">{t("settings.backup.title")}</h2>
        <p className="text-sm text-[var(--muted-foreground)]">{t("settings.backup.description")}</p>
        <div className="flex flex-wrap items-center gap-2">
          <Button onClick={() => void onExportBackup()} disabled={isBackupBusy}>
            {t("settings.exportBackup")}
          </Button>
          <Button onClick={() => void onImportBackup()} variant="outline" disabled={isBackupBusy}>
            {t("settings.importBackup")}
          </Button>
        </div>
        {backupMessage ? (
          <p className="text-xs text-[var(--muted-foreground)] break-all">{backupMessage}</p>
        ) : null}
      </Card>
    </section>
  );
}
