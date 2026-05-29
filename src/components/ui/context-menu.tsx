import { useCallback, useEffect, useRef, useState } from "react";

export interface ContextMenuItem {
  label: string;
  icon?: React.ReactNode;
  onClick: () => void;
  danger?: boolean;
}

interface ContextMenuState {
  x: number;
  y: number;
  items: ContextMenuItem[];
}

interface ContextMenuProps {
  state: ContextMenuState | null;
  onClose: () => void;
}

export function ContextMenu({ state, onClose }: ContextMenuProps) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!state) return;
    const handleClick = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        onClose();
      }
    };
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    document.addEventListener("mousedown", handleClick);
    document.addEventListener("keydown", handleKey);
    return () => {
      document.removeEventListener("mousedown", handleClick);
      document.removeEventListener("keydown", handleKey);
    };
  }, [state, onClose]);

  if (!state) return null;

  return (
    <div
      ref={ref}
      className="fixed z-[100] min-w-[180px] rounded-lg border border-app-border bg-app-surface py-1 shadow-lg"
      style={{ left: state.x, top: state.y }}
    >
      {state.items.map((item, i) => (
        <button
          key={i}
          type="button"
          className={`flex w-full items-center gap-2 px-3 py-2 text-left text-sm transition hover:bg-app-bg ${
            item.danger ? "text-red-500 hover:text-red-600" : "text-app-text"
          }`}
          onClick={() => {
            item.onClick();
            onClose();
          }}
        >
          {item.icon ? <span className="flex-shrink-0">{item.icon}</span> : null}
          {item.label}
        </button>
      ))}
    </div>
  );
}

export function useContextMenu() {
  const [state, setState] = useState<ContextMenuState | null>(null);

  const show = useCallback((e: React.MouseEvent, items: ContextMenuItem[]) => {
    e.preventDefault();
    setState({ x: e.clientX, y: e.clientY, items });
  }, []);

  const close = useCallback(() => setState(null), []);

  return { state, show, close };
}
