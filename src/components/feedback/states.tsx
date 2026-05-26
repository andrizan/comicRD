import { AlertTriangle, Inbox } from "lucide-react";
import { Button } from "../ui/button";
import { Card } from "../ui/card";

export function EmptyState({ title, description }: { title: string; description: string }) {
  return (
    <Card className="flex min-h-[180px] flex-col items-center justify-center gap-2 border-dashed text-center">
      <Inbox size={28} className="text-[var(--muted-foreground)]" />
      <p className="text-base font-semibold">{title}</p>
      <p className="max-w-xl text-sm text-[var(--muted-foreground)]">{description}</p>
    </Card>
  );
}

export function ErrorState({
  title,
  description,
  onRetry,
}: {
  title: string;
  description: string;
  onRetry?: () => void;
}) {
  return (
    <Card className="flex min-h-[180px] flex-col items-center justify-center gap-3 border-[#d7a5a5] bg-[#fff5f5] text-center">
      <AlertTriangle size={28} className="text-[#a73131]" />
      <div>
        <p className="text-base font-semibold">{title}</p>
        <p className="max-w-xl text-sm text-[#7c3a3a]">{description}</p>
      </div>
      {onRetry ? (
        <Button variant="danger" onClick={onRetry}>
          Retry
        </Button>
      ) : null}
    </Card>
  );
}

export function SkeletonList({ rows = 6 }: { rows?: number }) {
  return (
    <Card className="space-y-2">
      {Array.from({ length: rows }).map((_, idx) => (
        <div
          key={`skeleton-${idx}`}
          className="h-16 animate-pulse rounded-md border border-[var(--border)] bg-[var(--muted)]"
        />
      ))}
    </Card>
  );
}
