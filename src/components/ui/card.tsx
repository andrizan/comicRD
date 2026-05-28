import type { HTMLAttributes } from "react";
import { cn } from "../../lib/utils";

export function Card({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn(
        "rounded-lg border border-app-border bg-app-surface p-4 shadow-sm",
        className,
      )}
      {...props}
    />
  );
}
