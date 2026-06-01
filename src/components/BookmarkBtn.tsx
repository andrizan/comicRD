import { memo } from "react";
import { Bookmark, BookmarkCheck } from "lucide-react";

interface BookmarkBtnProps {
  isBookmarked: boolean;
  onToggle: () => void;
}

function BookmarkBtnImpl({ isBookmarked, onToggle }: BookmarkBtnProps) {
  return (
    <button
      type="button"
      onClick={(e) => {
        e.preventDefault();
        e.stopPropagation();
        onToggle();
      }}
      className={`flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-md transition-colors ${
        isBookmarked ? "text-app-accent" : "text-app-muted hover:bg-app-bg hover:text-app-text"
      }`}
      aria-label={isBookmarked ? "Remove bookmark" : "Add bookmark"}
    >
      {isBookmarked ? <BookmarkCheck size={20} /> : <Bookmark size={20} />}
    </button>
  );
}

export const BookmarkBtn = memo(BookmarkBtnImpl);
