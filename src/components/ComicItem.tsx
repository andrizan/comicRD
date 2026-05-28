import { Link } from "@tanstack/react-router";
import { unixToLocale } from "../lib/utils";
import { BookmarkBtn } from "./BookmarkBtn";
import { SpineThumb } from "./SpineThumb";
import type { RawComic } from "../types";

interface ComicItemProps {
  comic: RawComic;
  variant: "grid" | "list";
  index: number;
  isBookmarked: boolean;
  onBookmark: () => void;
}

export function ComicItem({ comic, variant, index, isBookmarked, onBookmark }: ComicItemProps) {
  if (variant === "grid") {
    return (
      <Link
        to="/comic/$comicId"
        params={{ comicId: encodeURIComponent(comic.source_path) }}
        title={comic.title}
        className="flex cursor-pointer items-start gap-2.5 border-b border-r border-app-border bg-app-surface p-3 transition-colors hover:bg-app-bg"
      >
        <SpineThumb title={comic.title} index={index} />
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-medium hover:underline">{comic.title}</p>
          <div className="mt-1 flex items-center justify-between">
            <span className="text-[10px] text-app-muted">
              {unixToLocale(comic.date_modified)}
            </span>
            <BookmarkBtn isBookmarked={isBookmarked} onToggle={onBookmark} />
          </div>
        </div>
      </Link>
    );
  }

  return (
    <Link
      to="/comic/$comicId"
      params={{ comicId: encodeURIComponent(comic.source_path) }}
      className="flex cursor-pointer items-center gap-3 border-b border-app-border bg-app-surface px-4 py-3 transition-colors hover:bg-app-bg"
    >
      <span className="w-6 flex-shrink-0 text-right font-display text-xs font-bold text-app-muted">
        {String(index + 1).padStart(2, "0")}
      </span>
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-medium hover:underline">{comic.title}</p>
        <p className="mt-0.5 truncate text-xs text-app-muted">{comic.source_path}</p>
      </div>
      <div className="flex flex-shrink-0 items-center gap-2">
        <span className="hidden text-xs text-app-muted sm:block">
          {unixToLocale(comic.date_modified)}
        </span>
        <BookmarkBtn isBookmarked={isBookmarked} onToggle={onBookmark} />
      </div>
    </Link>
  );
}
