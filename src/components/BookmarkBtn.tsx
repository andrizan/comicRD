import { Bookmark, BookmarkCheck } from "lucide-react";

interface BookmarkBtnProps {
  isBookmarked: boolean;
  onToggle: () => void;
}

export function BookmarkBtn({ isBookmarked, onToggle }: BookmarkBtnProps) {
  return (
    <button
      type="button"
      onClick={(e) => {
        e.stopPropagation();
        onToggle();
      }}
      className={`flex-shrink-0 text-sm transition-colors ${
        isBookmarked
          ? "text-[var(--accent)]"
          : "text-neutral-800 hover:text-neutral-500"
      }`}
      aria-label={isBookmarked ? "Remove bookmark" : "Add bookmark"}
    >
      {isBookmarked ? <BookmarkCheck size={16} /> : <Bookmark size={16} />}
    </button>
  );
}
