import { useEffect, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { listSettings, setSetting } from "../api/tauri";
import { ErrorState, SkeletonList } from "../components/feedback/states";
import { Button } from "../components/ui/button";
import { Card } from "../components/ui/card";

function parse<T>(value: string | undefined, fallback: T): T {
  if (!value) return fallback;
  try {
    return JSON.parse(value) as T;
  } catch {
    return fallback;
  }
}

export function SettingsPage() {
  const queryClient = useQueryClient();
  const settingsQuery = useQuery({
    queryKey: ["settings"],
    queryFn: listSettings,
  });

  const [smoothSpeed, setSmoothSpeed] = useState(1);
  const [defaultZoom, setDefaultZoom] = useState(1);
  const [pageGap, setPageGap] = useState(8);

  useEffect(() => {
    const map = new Map((settingsQuery.data ?? []).map((x) => [x.key, x.value_json]));
    setSmoothSpeed(parse<number>(map.get("smooth_scroll_speed"), 1));
    setDefaultZoom(parse<number>(map.get("default_zoom"), 1));
    setPageGap(parse<number>(map.get("page_gap"), 8));
  }, [settingsQuery.data]);

  async function saveAll() {
    await setSetting("default_mode", "webtoon");
    await setSetting("arrow_navigation_enabled", false);
    await setSetting("smooth_scroll_speed", smoothSpeed);
    await setSetting("default_zoom", Number(defaultZoom.toFixed(2)));
    await setSetting("page_gap", pageGap);
    await setSetting("interpolation_method", "off");
    await queryClient.invalidateQueries({ queryKey: ["settings"] });
  }

  if (settingsQuery.isPending) {
    return (
      <section className="space-y-4">
        <SkeletonList rows={4} />
      </section>
    );
  }

  if (settingsQuery.isError) {
    return (
      <section className="space-y-4">
        <ErrorState
          title="Gagal memuat settings"
          description="Coba reload halaman settings."
          onRetry={() => void settingsQuery.refetch()}
        />
      </section>
    );
  }

  return (
    <section className="space-y-4">
      <Card className="space-y-4">
        <h2 className="text-xl font-bold">Reader Settings</h2>
        <p className="rounded-md border border-[var(--border)] bg-[var(--card)] px-3 py-2 text-sm">
          Reader mode dikunci ke <span className="font-semibold">Webtoon</span>.
        </p>

        <label className="block">
          <span className="mb-1 block text-sm font-semibold">Smooth Scroll Speed</span>
          <input
            min={0.5}
            max={3}
            step={0.1}
            type="range"
            value={smoothSpeed}
            onChange={(e) => setSmoothSpeed(Number(e.target.value))}
            className="w-full"
          />
          <p className="text-xs text-[var(--muted-foreground)]">Value: {smoothSpeed.toFixed(1)}</p>
        </label>

        <label className="block">
          <span className="mb-1 block text-sm font-semibold">Default Zoom</span>
          <input
            min={0.4}
            max={3}
            step={0.1}
            type="range"
            value={defaultZoom}
            onChange={(e) => setDefaultZoom(Number(e.target.value))}
            className="w-full"
          />
          <p className="text-xs text-[var(--muted-foreground)]">
            Value: {Math.round(defaultZoom * 100)}%
          </p>
        </label>

        <label className="block">
          <span className="mb-1 block text-sm font-semibold">Page Margin / Gap</span>
          <input
            min={0}
            max={32}
            step={1}
            type="range"
            value={pageGap}
            onChange={(e) => setPageGap(Number(e.target.value))}
            className="w-full"
          />
          <p className="text-xs text-[var(--muted-foreground)]">Value: {pageGap}px</p>
        </label>

        <Button onClick={saveAll}>Save Settings</Button>
      </Card>
    </section>
  );
}
