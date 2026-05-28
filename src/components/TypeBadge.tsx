export type ComicType = "manga" | "manhwa" | "manhua";

const TYPE_META: Record<ComicType, { label: string; flag: string; cls: string }> = {
  manga: { label: "Manga", flag: "🇯🇵", cls: "badge-manga" },
  manhwa: { label: "Manhwa", flag: "🇰🇷", cls: "badge-manhwa" },
  manhua: { label: "Manhua", flag: "🇨🇳", cls: "badge-manhua" },
};

interface TypeBadgeProps {
  type: ComicType;
}

export function TypeBadge({ type }: TypeBadgeProps) {
  const meta = TYPE_META[type];
  return (
    <span className={`rounded px-2 py-0.5 text-[10px] font-medium ${meta.cls}`}>
      {meta.flag} {meta.label}
    </span>
  );
}

export function detectComicType(title: string, path: string): ComicType {
  const lower = (title + " " + path).toLowerCase();
  if (lower.includes("manhwa") || lower.includes("korean")) return "manhwa";
  if (lower.includes("manhua") || lower.includes("chinese")) return "manhua";
  return "manga";
}
