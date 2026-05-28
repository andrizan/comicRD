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

export function SpineThumb({ title, index }: SpineThumbProps) {
  return (
    <div
      className={`spine-${index % 14} flex h-10 w-7 flex-shrink-0 items-center justify-center rounded`}
    >
      <span className="font-display text-[8px] font-extrabold text-white/20">
        {initials(title)}
      </span>
    </div>
  );
}
