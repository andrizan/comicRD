import { useEffect, useMemo } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Link, Outlet, useRouterState } from "@tanstack/react-router";
import { FolderOpen, Moon, Settings, Sun } from "lucide-react";
import { listSettings, setSetting } from "../api/tauri";
import { activateLocale, resolveLocalePreference, useAppI18n } from "../i18n";
import { cn } from "../lib/utils";

function parseTheme(value: string | undefined): "light" | "dark" {
  if (!value) return "light";
  try {
    const parsed = JSON.parse(value);
    return parsed === "dark" ? "dark" : "light";
  } catch {
    return "light";
  }
}

function parseSettingString(value: string | undefined, fallback: string): string {
  if (!value) return fallback;
  try {
    const parsed = JSON.parse(value);
    return typeof parsed === "string" ? parsed : fallback;
  } catch {
    return fallback;
  }
}

export function Layout() {
  const { t } = useAppI18n();
  const queryClient = useQueryClient();
  const settingsQuery = useQuery({
    queryKey: ["settings"],
    queryFn: listSettings,
  });
  const pathname = useRouterState({
    select: (state) => state.location.pathname,
  });
  const isReaderRoute = pathname.startsWith("/reader/");
  const settingMap = useMemo(
    () => new Map((settingsQuery.data ?? []).map((setting) => [setting.key, setting.value_json])),
    [settingsQuery.data],
  );
  const theme = parseTheme(settingMap.get("app_theme"));
  const localePreference = parseSettingString(settingMap.get("app_locale"), "en");
  const activeLocale = resolveLocalePreference(localePreference);

  useEffect(() => {
    document.documentElement.dataset.theme = theme;
  }, [theme]);

  useEffect(() => {
    activateLocale(activeLocale);
  }, [activeLocale]);

  async function toggleTheme() {
    await setSetting("app_theme", theme === "dark" ? "light" : "dark");
    await queryClient.invalidateQueries({ queryKey: ["settings"] });
  }

  return (
    <div className={cn("app-shell", isReaderRoute && "grid-rows-[1fr]")}>
      {!isReaderRoute ? (
        <header className="sticky top-0 z-20 border-b border-[var(--border)] bg-[var(--header)] backdrop-blur">
          <div className="mx-auto flex max-w-[1680px] items-center justify-between px-4 py-3">
            <h1 className="text-lg font-black tracking-wide">ComicRD</h1>
            <nav className="flex items-center gap-1.5">
              <button
                type="button"
                onClick={() => void toggleTheme()}
                className="inline-flex items-center gap-1.5 rounded-md px-2.5 py-1.5 text-sm font-medium transition hover:bg-[var(--muted)]"
                title={t("app.toggleTheme")}
              >
                {theme === "dark" ? <Sun size={15} /> : <Moon size={15} />}
              </button>
              <Link
                to="/"
                className="inline-flex items-center gap-1.5 rounded-md px-2.5 py-1.5 text-sm font-medium transition hover:bg-[var(--muted)]"
                activeProps={{
                  className:
                    "inline-flex items-center gap-1.5 rounded-md bg-[var(--accent)] px-2.5 py-1.5 text-sm font-medium text-[var(--accent-foreground)]",
                }}
              >
                <FolderOpen size={15} /> {t("nav.library")}
              </Link>
              <Link
                to="/settings"
                className="inline-flex items-center gap-1.5 rounded-md px-2.5 py-1.5 text-sm font-medium transition hover:bg-[var(--muted)]"
                activeProps={{
                  className:
                    "inline-flex items-center gap-1.5 rounded-md bg-[var(--accent)] px-2.5 py-1.5 text-sm font-medium text-[var(--accent-foreground)]",
                }}
              >
                <Settings size={15} /> {t("nav.settings")}
              </Link>
            </nav>
          </div>
        </header>
      ) : null}
      <main className={cn("content-scroll", isReaderRoute && "reader-shell")}>
        {isReaderRoute ? (
          <Outlet />
        ) : (
          <div className="mx-auto max-w-[1680px] px-4 py-4">
            <Outlet />
          </div>
        )}
      </main>
    </div>
  );
}
