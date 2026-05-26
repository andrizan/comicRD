import { Link, Outlet, useRouterState } from "@tanstack/react-router";
import { BookOpenText, FolderOpen, Settings } from "lucide-react";
import { cn } from "../lib/utils";

export function Layout() {
  const pathname = useRouterState({
    select: (state) => state.location.pathname,
  });
  const isReaderRoute = pathname.startsWith("/reader/");

  return (
    <div className={cn("app-shell", isReaderRoute && "grid-rows-[1fr]")}>
      {!isReaderRoute ? (
        <header className="sticky top-0 z-20 border-b border-[var(--border)] bg-[#fef7e6cc] backdrop-blur">
          <div className="mx-auto flex max-w-7xl items-center justify-between px-4 py-3">
            <h1 className="text-lg font-black tracking-wide">ComicRD</h1>
            <nav className="flex items-center gap-2">
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
          <div className="mx-auto max-w-7xl px-4 py-4">
            <Outlet />
          </div>
        )}
      </main>
    </div>
  );
}
