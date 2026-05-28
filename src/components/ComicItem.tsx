import { Link } from "@tanstack/react-router";
import { unixToLocale } from "../lib/utils";
import { BookmarkBtn } from "./BookmarkBtn";
import { SpineThumb } from "./SpineThumb";
import { TypeBadge, detectComicType, type ComicType } from "./TypeBadge";
import type { RawComic } from "../types";

interface ComicItemProps {
  comic: RawComic;
  variant: "grid" | "list";
  index: number;
  isBookmarked: boolean;
  onBookmark: () => void;
}

export function ComicItem({ comic, variant, index, isBookmarked, onBookmark }: ComicItemProps) {
  const comicType: ComicType = detectComicType(comic.title, comic.source_path);

  if (variant === "grid") {
    return (
      <Link
        to="/comic/$comicId"
        params={{ comicId: encodeURIComponent(comic.source_path) }}
        className="flex cursor-pointer items-center gap-3 bg-[var(--card)] p-3 transition-colors hover:bg-[var(--muted)]"
      >
        <SpineThumb title={comic.title} index={index} />
        <div className="min-w-0 flex-1">
          <p className="truncate text-[11px] font-medium text-neutral-300">{comic.title}</p>
          <div className="mt-1 flex items-center gap-1.5">
            <TypeBadge type={comicType} />
            <span className="text-[10px] text-neutral-700">
              {unixToLocale(comic.date_modified)}
            </span>
          </div>
        </div>
        <BookmarkBtn isBookmarked={isBookmarked} onToggle={onBookmark} />
      </Link>
    );
  }

  return (
    <Link
      to="/comic/$comicId"
      params={{ comicId: encodeURIComponent(comic.source_path) }}
      className="flex cursor-pointer items-center gap-2.5 bg-[var(--card)] px-4 py-2.5 transition-colors hover:bg-[var(--muted)]"
    >
      <span className="w-5 flex-shrink-0 text-right font-display text-[11px] font-bold text-neutral-800">
        {String(index + 1).padStart(2, "0")}
      </span>
      <div className="min-w-0 flex-1">
        <p className="truncate text-[12px] font-medium text-neutral-300">{comic.title}</p>
        <p className="mt-0.5 truncate text-[10px] text-[#2a3d4f]">{comic.source_path}</p>
      </div>
      <div className="flex flex-shrink-0 items-center gap-2">
        <TypeBadge type={comicType} />
        <span className="hidden text-[10px] text-neutral-700 sm:block">
          {unixToLocale(comic.date_modified)}
        </span>
        <BookmarkBtn isBookmarked={isBookmarked} onToggle={onBookmark} />
      </div>
    </Link>
  );
}
