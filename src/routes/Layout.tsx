import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Link, Outlet, useRouterState } from "@tanstack/react-router";
import { Home, Moon, Settings, Sun } from "lucide-react";
import { listSettings, setSetting } from "@/api/tauri";
import { SettingsPanel } from "@/components/SettingsPanel";
import { WithTooltip } from "@/components/ui/tooltip";
import { activateLocale, resolveLocalePreference, useAppI18n } from "@/i18n";
import { cn } from "@/lib/utils";

function parseTheme(value: string | undefined): "light" | "dark" {
  if (!value) return "dark";
  try {
    const parsed = JSON.parse(value);
    return parsed === "light" ? "light" : "dark";
  } catch {
    return "dark";
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

export const scrollPositions = new Map<string, number>();
let activeScrollKey = "";
let isRestoring = false;

export function getScrollKey(): string {
  return activeScrollKey;
}

export function setScrollKey(key: string): void {
  activeScrollKey = key;
}

export function saveScroll(key: string): void {
  const container = document.querySelector<HTMLElement>(".content-scroll");
  if (container) scrollPositions.set(key, container.scrollTop);
}

export function restoreScroll(key: string): void {
  const container = document.querySelector<HTMLElement>(".content-scroll");
  if (!container) return;
  const saved = scrollPositions.get(key);
  if (saved === undefined || saved <= 0) return;
  isRestoring = true;
  const doRestore = () => {
    container.scrollTo({ top: saved, behavior: "instant" });
  };
  doRestore();
  const delays = [16, 50, 100, 200, 400, 800, 1200, 2000];
  delays.forEach((d) => setTimeout(doRestore, d));
  setTimeout(() => {
    isRestoring = false;
  }, 2500);
}

export function Layout() {
  const { t } = useAppI18n();
  const queryClient = useQueryClient();
  const [settingsOpen, setSettingsOpen] = useState(false);
  const settingsQuery = useQuery({
    queryKey: ["settings"],
    queryFn: listSettings,
  });
  const pathname = useRouterState({
    select: (state) => state.location.pathname,
  });
  const isReaderRoute = pathname.startsWith("/reader/");
  const prevPath = useRef(pathname);
  const settingMap = useMemo(
    () => new Map((settingsQuery.data ?? []).map((setting) => [setting.key, setting.value_json])),
    [settingsQuery.data],
  );
  const theme = parseTheme(settingMap.get("app_theme"));
  const localePreference = parseSettingString(settingMap.get("app_locale"), "en");
  const activeLocale = resolveLocalePreference(localePreference);
  const isLibrarySourceEmpty = !parseSettingString(
    settingMap.get("library_source_input"),
    "",
  ).trim();

  useEffect(() => {
    if (theme === "dark") {
      document.documentElement.classList.add("dark");
    } else {
      document.documentElement.classList.remove("dark");
    }
  }, [theme]);

  useEffect(() => {
    activateLocale(activeLocale);
  }, [activeLocale]);

  useEffect(() => {
    if (isReaderRoute) return;
    const container = document.querySelector<HTMLElement>(".content-scroll");
    if (!container) return;
    const onScroll = () => {
      if (isRestoring) return;
      if (activeScrollKey) {
        scrollPositions.set(activeScrollKey, container.scrollTop);
      }
    };
    container.addEventListener("scroll", onScroll, { passive: true });
    return () => container.removeEventListener("scroll", onScroll);
  }, [isReaderRoute]);

  useLayoutEffect(() => {
    if (isReaderRoute) return;
    if (prevPath.current === pathname) return;
    const container = document.querySelector<HTMLElement>(".content-scroll");
    if (container) {
      if (prevPath.current) scrollPositions.set(prevPath.current, container.scrollTop);
      container.scrollTop = 0;
    }
    prevPath.current = pathname;
  }, [pathname, isReaderRoute]);

  async function toggleTheme() {
    await setSetting("app_theme", theme === "dark" ? "light" : "dark");
    await queryClient.invalidateQueries({ queryKey: ["settings"] });
  }

  return (
    <div className={cn("app-shell", isReaderRoute && "grid-rows-[1fr]")}>
      {!isReaderRoute ? (
        <div className="flex h-10 items-center justify-between border-b border-app-border bg-app-surface px-4">
          <div className="flex items-center gap-2">
            <WithTooltip label="Home">
              <Link
                to="/"
                className="flex h-7 w-7 items-center justify-center rounded-md text-app-muted transition-all hover:bg-app-bg hover:text-app-text"
                aria-label="Home"
              >
                <Home size={14} />
              </Link>
            </WithTooltip>
            <span className="font-display text-xs font-bold leading-tight tracking-widest text-app-muted">
              ComicRD
            </span>
          </div>
          <div className="flex gap-1">
            <WithTooltip label={t("app.toggleTheme")}>
              <button
                type="button"
                onClick={() => void toggleTheme()}
                className="flex h-7 w-7 items-center justify-center rounded-md text-app-muted transition-all hover:bg-app-bg hover:text-app-text"
                aria-label={t("app.toggleTheme")}
              >
                {theme === "dark" ? <Sun size={14} /> : <Moon size={14} />}
              </button>
            </WithTooltip>
            <WithTooltip label={t("nav.settings")}>
              <button
                type="button"
                onClick={() => setSettingsOpen((v) => !v)}
                className={`flex h-7 w-7 items-center justify-center rounded-md transition-all hover:bg-app-bg ${
                  settingsOpen
                    ? "bg-app-accent/10 text-app-accent"
                    : isLibrarySourceEmpty
                      ? "text-red-400 hover:text-red-500"
                      : "text-app-muted hover:text-app-text"
                }`}
                aria-label={t("nav.settings")}
              >
                <Settings size={14} />
              </button>
            </WithTooltip>
          </div>
        </div>
      ) : null}
      <main className={cn("content-scroll", isReaderRoute && "reader-shell")}>
        <Outlet />
      </main>
      <SettingsPanel open={settingsOpen} onClose={() => setSettingsOpen(false)} />
    </div>
  );
}
