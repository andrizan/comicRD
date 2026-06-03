import { memo } from "react";
import { Bookmark, BookmarkCheck } from "lucide-react";
import { useAppI18n } from "@/i18n";
import { WithTooltip } from "@/components/ui/tooltip";

interface BookmarkBtnProps {
  isBookmarked: boolean;
  onToggle: () => void;
}

function BookmarkBtnImpl({ isBookmarked, onToggle }: BookmarkBtnProps) {
  const { t } = useAppI18n();
  const label = isBookmarked ? t("library.removeBookmark") : t("library.addBookmark");

  return (
    <WithTooltip label={label}>
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
        aria-label={label}
      >
        {isBookmarked ? <BookmarkCheck size={20} /> : <Bookmark size={20} />}
      </button>
    </WithTooltip>
  );
}

export const BookmarkBtn = memo(BookmarkBtnImpl);
