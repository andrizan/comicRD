import { useEffect, useMemo } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Link, Outlet, useRouterState } from "@tanstack/react-router";
import { BookOpenText, FolderOpen, Moon, Settings, Sun } from "lucide-react";
import { listSettings, setSetting } from "../api/tauri";
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

export function Layout() {
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

  useEffect(() => {
    document.documentElement.dataset.theme = theme;
  }, [theme]);

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
            <nav className="flex items-center gap-2">
              <button
                type="button"
                onClick={() => void toggleTheme()}
                className="inline-flex items-center gap-2 rounded-md bg-[var(--card)] px-3 py-2 text-sm font-semibold transition hover:bg-[var(--muted)]"
                title="Toggle dark mode"
              >
                {theme === "dark" ? <Sun size={16} /> : <Moon size={16} />}
                {theme === "dark" ? "Light" : "Dark"}
              </button>
              <Link
                to="/"
                className="inline-flex items-center gap-2 rounded-md bg-[var(--card)] px-3 py-2 text-sm font-semibold transition hover:bg-[var(--muted)]"
                activeProps={{
                  className:
                    "inline-flex items-center gap-2 rounded-md bg-[var(--accent)] px-3 py-2 text-sm font-semibold text-[var(--accent-foreground)]",
                }}
              >
                <FolderOpen size={16} /> Library
              </Link>
              <Link
                to="/settings"
                className="inline-flex items-center gap-2 rounded-md bg-[var(--card)] px-3 py-2 text-sm font-semibold transition hover:bg-[var(--muted)]"
                activeProps={{
                  className:
                    "inline-flex items-center gap-2 rounded-md bg-[var(--accent)] px-3 py-2 text-sm font-semibold text-[var(--accent-foreground)]",
                }}
              >
                <Settings size={16} /> Settings
              </Link>
              <a
                className="inline-flex items-center gap-2 rounded-md bg-[var(--card)] px-3 py-2 text-sm font-semibold"
                href="https://tauri.app/"
                target="_blank"
                rel="noreferrer"
              >
                <BookOpenText size={16} /> Tauri 2
              </a>
            </nav>
          </div>
        </header>
      ) : null}
      <main className="content-scroll">
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
