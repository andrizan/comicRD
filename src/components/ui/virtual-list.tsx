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
  columns?: number;
  gap?: number;
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
  columns = 1,
  gap = 0,
  getItemKey,
  renderItem,
  items,
  className,
  measureElement = false,
  ref,
}: VirtualListProps<T>) {
  const measureElementRef = useRef<((node: HTMLElement | null) => void) | null>(null);
  const rowCount = Math.ceil(count / columns);

  const virtualizer = useVirtualizer({
    count: rowCount,
    estimateSize: () => estimateSize,
    getScrollElement: () => scrollElement,
    overscan,
    getItemKey: (rowIndex) => getItemKey(rowIndex * columns),
    ...(measureElement ? { measureElement: (node) => node.getBoundingClientRect().height } : {}),
  });

  measureElementRef.current = (node: HTMLElement | null) => {
    if (node) virtualizer.measureElement(node);
  };

  const scrollToIndex = useCallback(
    (index: number, opts?: { align?: "start" | "center" | "end" | "auto" }) => {
      const rowIndex = Math.floor(index / columns);
      virtualizer.scrollToIndex(rowIndex, opts);
    },
    [virtualizer, columns],
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
        const startIndex = virtualRow.index * columns;
        const rowItems: React.ReactNode[] = [];
        for (let col = 0; col < columns; col++) {
          const itemIndex = startIndex + col;
          if (itemIndex >= count) break;
          const item = items[itemIndex];
          if (!item) continue;
          rowItems.push(
            <div key={getItemKey(itemIndex)} style={{ flex: 1, minWidth: 0 }}>
              {renderItem(itemIndex, item, virtualRow)}
            </div>,
          );
        }

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
              display: columns > 1 ? "flex" : undefined,
              gap: columns > 1 ? `${gap}px` : undefined,
            }}
          >
            {rowItems}
          </div>
        );
      })}
    </div>
  );
}
