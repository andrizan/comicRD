interface SpineThumbProps {
  title: string;
  index: number;
}

function initials(title: string): string {
  return title
    .split(" ")
    .slice(0, 2)
    .map((w) => w[0] || "")
    .join("")
    .toUpperCase();
}

const SPINE_COLORS = [
  "bg-app-accent/15 text-app-accent",
  "bg-app-accent/25 text-app-accent",
  "bg-app-accent/10 text-app-muted",
  "bg-app-surface text-app-accent",
  "bg-app-accent/20 text-app-accent",
  "bg-app-accent/8 text-app-muted",
];

export function SpineThumb({ title, index }: SpineThumbProps) {
  const cls = SPINE_COLORS[index % SPINE_COLORS.length];
  return (
    <div
      className={`flex h-16 w-14 flex-shrink-0 items-center justify-center rounded-lg border border-app-border ${cls}`}
    >
      <span className="font-display text-sm font-extrabold opacity-80">
        {initials(title)}
      </span>
    </div>
  );
}
