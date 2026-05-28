import { useVirtualizer, type VirtualItem } from "@tanstack/react-virtual";
import { useCallback, useImperativeHandle, useRef } from "react";

export interface VirtualListHandle {
  scrollToIndex: (index: number, opts?: { align?: "start" | "center" | "end" | "auto" }) => void;
}

interface VirtualListProps<T> {
  count: number;
  estimateSize: number;
  scrollElement: HTMLElement | null;
  overscan?: number;
  getItemKey: (index: number) => string | number;
  renderItem: (index: number, item: T, virtualRow: VirtualItem) => React.ReactNode;
  items: T[];
  className?: string;
  measureElement?: boolean;
  ref?: React.Ref<VirtualListHandle>;
}

export function VirtualList<T>({
  count,
  estimateSize,
  scrollElement,
  overscan = 5,
  getItemKey,
  renderItem,
  items,
  className,
  measureElement = false,
  ref,
}: VirtualListProps<T>) {
  const measureElementRef = useRef<((node: HTMLElement | null) => void) | null>(null);

  const virtualizer = useVirtualizer({
    count,
    estimateSize: () => estimateSize,
    getScrollElement: () => scrollElement,
    overscan,
    getItemKey,
    ...(measureElement ? { measureElement: (node) => node.getBoundingClientRect().height } : {}),
  });

  measureElementRef.current = (node: HTMLElement | null) => {
    if (node) virtualizer.measureElement(node);
  };

  const scrollToIndex = useCallback(
    (index: number, opts?: { align?: "start" | "center" | "end" | "auto" }) => {
      virtualizer.scrollToIndex(index, opts);
    },
    [virtualizer],
  );

  useImperativeHandle(ref, () => ({ scrollToIndex }), [scrollToIndex]);

  const virtualItems = virtualizer.getVirtualItems();

  return (
    <div
      className={className}
      style={{
        height: virtualizer.getTotalSize(),
        width: "100%",
        position: "relative",
      }}
    >
      {virtualItems.map((virtualRow) => {
        const item = items[virtualRow.index];
        if (!item) return null;
        return (
          <div
            key={virtualRow.key}
            data-index={virtualRow.index}
            ref={measureElement ? measureElementRef.current : undefined}
            style={{
              position: "absolute",
              top: 0,
              left: 0,
              width: "100%",
              transform: `translateY(${virtualRow.start}px)`,
            }}
          >
            {renderItem(virtualRow.index, item, virtualRow)}
          </div>
        );
      })}
    </div>
  );
}
