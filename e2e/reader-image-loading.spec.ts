import { expect, test } from "@playwright/test";

const MOCK_SETTINGS = [
  { key: "library_sort_by", value_json: '"name"', updated_at: 0 },
  { key: "library_sort_dir", value_json: '"asc"', updated_at: 0 },
  { key: "library_view_mode", value_json: '"library"', updated_at: 0 },
  { key: "library_source_input", value_json: '"/comics"', updated_at: 0 },
  { key: "app_theme", value_json: '"dark"', updated_at: 0 },
  { key: "app_locale", value_json: '"en"', updated_at: 0 },
  { key: "default_zoom", value_json: "1", updated_at: 0 },
  { key: "page_gap", value_json: "10", updated_at: 0 },
];

const MOCK_PAGES = Array.from({ length: 12 }, (_, index) => ({
  index,
  name: `page-${index}.svg`,
}));

const PAGE_SIZES = [
  { width: 360, height: 900, color: "#ffffff" },
  { width: 900, height: 45, color: "#f6f6f6" },
  { width: 900, height: 45, color: "#ffffff" },
  { width: 900, height: 45, color: "#f6f6f6" },
  { width: 360, height: 900, color: "#ffffff" },
  { width: 900, height: 300, color: "#f6f6f6" },
  { width: 420, height: 700, color: "#ffffff" },
  { width: 720, height: 360, color: "#f6f6f6" },
];

function svgPage(width: number, height: number, color: string, label: string) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
    <rect width="100%" height="100%" fill="${color}"/>
    <rect x="12" y="12" width="${width - 24}" height="${height - 24}" fill="none" stroke="#111" stroke-width="6"/>
    <text x="24" y="64" font-size="48" fill="#111">${label}</text>
  </svg>`;
}

async function mockTauriIPC(page: import("@playwright/test").Page) {
  await page.addInitScript(
    (data) => {
      Object.defineProperty(window.navigator, "userAgent", {
        get: () => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
      });

      const settings = JSON.parse(JSON.stringify(data.settings));
      const pages = JSON.parse(JSON.stringify(data.pages));
      (window as any).__TAURI_INTERNALS__ = {
        transformCallback: () => 0,
        unregisterCallback: () => {},
        invoke: async (cmd: string, args: Record<string, unknown>) => {
          if (cmd === "list_settings") return settings;
          if (cmd === "get_setting") {
            const found = settings.find((s: any) => s.key === args.key);
            return found?.value_json ?? null;
          }
          if (cmd === "set_setting") {
            const existing = settings.find((s: any) => s.key === args.key);
            if (existing) existing.value_json = args.valueJson;
            else settings.push({ key: args.key, value_json: args.valueJson, updated_at: 0 });
            return null;
          }
          if (cmd === "init_db") return null;
          if (cmd === "get_chapter_pages") return pages;
          if (cmd === "get_chapter_context")
            return {
              comic_title: "Reader E2E Comic",
              title: "Chapter With Mixed Ratios",
              comic_source_path: "/comics/reader-e2e.cbz",
              chapter_source_path: "/comics/reader-e2e/ch1.cbz",
              chapter_position: 1,
              chapter_total: 1,
              prev_chapter_id: null,
              prev_chapter_title: null,
              next_chapter_id: null,
              next_chapter_title: null,
            };
          if (cmd === "get_progress") return null;
          if (cmd === "save_progress") return null;
          return null;
        },
        convertFileSrc: (p: string) => p,
      };
    },
    { settings: MOCK_SETTINGS, pages: MOCK_PAGES },
  );
}

test("reader loads the next image and keeps its natural aspect ratio", async ({ page }) => {
  await mockTauriIPC(page);
  await page.route("http://comicrd.localhost/page/1/*", async (route) => {
    const pageIndex = Number(new URL(route.request().url()).pathname.split("/").at(-1));
    const size = PAGE_SIZES[pageIndex] ?? PAGE_SIZES[0];
    await route.fulfill({
      status: 200,
      contentType: "image/svg+xml",
      body: svgPage(size.width, size.height, size.color, `Page ${pageIndex + 1}`),
    });
  });

  await page.goto("/reader/1");
  await page.waitForSelector('[data-reader-page-image="1"]');
  await page.waitForFunction(() => {
    const firstImages = [0, 1].map((index) =>
      document.querySelector<HTMLImageElement>(`[data-reader-page-image="${index}"]`),
    );
    return firstImages.every((image) => image?.complete && image.naturalWidth > 0);
  });

  const metrics = await page.evaluate(() => {
    const first = document.querySelector<HTMLImageElement>('[data-reader-page-image="0"]')!;
    const next = document.querySelector<HTMLImageElement>('[data-reader-page-image="1"]')!;
    const firstRect = first.getBoundingClientRect();
    const nextRect = next.getBoundingClientRect();
    return {
      firstNaturalRatio: first.naturalHeight / first.naturalWidth,
      firstRenderedRatio: firstRect.height / firstRect.width,
      nextNaturalRatio: next.naturalHeight / next.naturalWidth,
      nextRenderedRatio: nextRect.height / nextRect.width,
      nextRenderedHeight: nextRect.height,
    };
  });

  expect(metrics.nextRenderedHeight).toBeGreaterThan(0);
  expect(metrics.nextRenderedRatio).toBeCloseTo(metrics.nextNaturalRatio, 1);
  expect(metrics.nextRenderedRatio).toBeLessThan(0.5);
  expect(metrics.firstRenderedRatio).toBeCloseTo(metrics.firstNaturalRatio, 1);
});

test("reader loads a page before it becomes visible while scrolling down", async ({ page }) => {
  await mockTauriIPC(page);
  await page.route("http://comicrd.localhost/page/1/*", async (route) => {
    const pageIndex = Number(new URL(route.request().url()).pathname.split("/").at(-1));
    const size = PAGE_SIZES[pageIndex % PAGE_SIZES.length];
    await route.fulfill({
      status: 200,
      contentType: "image/svg+xml",
      body: svgPage(size.width, size.height, size.color, `Page ${pageIndex + 1}`),
    });
  });

  await page.goto("/reader/1");
  await page.waitForFunction(() => {
    const first = document.querySelector<HTMLImageElement>('[data-reader-page-image="0"]');
    return first?.complete && first.naturalWidth > 0;
  });
  await page.waitForSelector('[data-page-index="4"] [data-reader-page-image="4"]');

  await page.evaluate(() => {
    const scroller = document.querySelector<HTMLElement>(".reader-scrollbar")!;
    const target = document.querySelector<HTMLElement>('[data-page-index="4"]')!;
    scroller.style.scrollBehavior = "auto";
    scroller.scrollTop = target.offsetTop - scroller.clientHeight + 180;
  });
  await page.waitForFunction(() => {
    const scroller = document.querySelector<HTMLElement>(".reader-scrollbar")!;
    const target = document.querySelector<HTMLElement>('[data-page-index="4"]')!;
    const rect = target.getBoundingClientRect();
    return rect.top > 0 && rect.top < scroller.clientHeight;
  });

  const position = await page.evaluate(() => {
    const scroller = document.querySelector<HTMLElement>(".reader-scrollbar")!;
    const target = document.querySelector<HTMLElement>('[data-page-index="4"]')!;
    const rect = target.getBoundingClientRect();
    return { targetTop: rect.top, viewportHeight: scroller.clientHeight };
  });

  expect(position.targetTop).toBeGreaterThan(0);
  expect(position.targetTop).toBeLessThan(position.viewportHeight);
  await expect(page.locator('[data-reader-page-image="4"]')).toHaveCount(1);
  await page.waitForFunction(() => {
    const image = document.querySelector<HTMLImageElement>('[data-reader-page-image="4"]');
    return image?.complete && image.naturalWidth > 0 && image.getBoundingClientRect().height > 0;
  });
});
