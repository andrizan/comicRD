import { test, expect } from "@playwright/test";

function generateComics(count: number) {
  return Array.from({ length: count }, (_, i) => ({
    key: `comic-${i}`,
    title: `Comic Title ${String(i + 1).padStart(3, "0")}`,
    source_path: `/comics/comic-${i}.cbz`,
    source_type: "cbz",
    library_path: "/comics",
    date_modified: 1700000000 + i * 1000,
    chapter_count: 10,
    read_chapter_count: 0,
    in_progress_chapter_count: 0,
  }));
}

function generateChapters(count: number) {
  return Array.from({ length: count }, (_, i) => ({
    key: `ch-${i}`,
    title: `Chapter ${String(i + 1).padStart(3, "0")}`,
    chapter_index: i,
    source_path: `/comics/comic-0/ch${i + 1}.cbz`,
    source_type: "cbz",
    page_count: 20,
    is_read: i < 5,
    last_page: i < 5 ? 19 : 0,
    total_pages: 20,
  }));
}

const MOCK_SETTINGS = [
  { key: "library_sort_by", value_json: '"name"', updated_at: 0 },
  { key: "library_sort_dir", value_json: '"asc"', updated_at: 0 },
  { key: "library_view_mode", value_json: '"library"', updated_at: 0 },
  { key: "library_display_mode", value_json: '"list"', updated_at: 0 },
  { key: "library_source_input", value_json: '"/comics"', updated_at: 0 },
  { key: "app_theme", value_json: '"light"', updated_at: 0 },
  { key: "app_locale", value_json: '"en"', updated_at: 0 },
  { key: "chapter_sort_dir", value_json: '"asc"', updated_at: 0 },
];

const MOCK_COMICS = generateComics(30);
const MOCK_CHAPTERS = generateChapters(30);

async function mockTauriIPC(page: import("@playwright/test").Page) {
  await page.addInitScript(
    (data) => {
      const settings = JSON.parse(JSON.stringify(data.settings));
      const comics = JSON.parse(JSON.stringify(data.comics));
      const chapters = JSON.parse(JSON.stringify(data.chapters));
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
          if (cmd === "list_library_comics_raw") return comics;
          if (cmd === "list_all_bookmarks") return [];
          if (cmd === "list_reading_history") return [];
          if (cmd === "list_comic_chapters_raw") return chapters;
          if (cmd === "list_chapter_favorites") return [];
          if (cmd === "add_chapter_favorite") return 1;
          if (cmd === "remove_chapter_favorite") return null;
          if (cmd === "open_chapter_for_reading") return 1;
          if (cmd === "get_chapter_context")
            return {
              comic_source_path: "/comics/comic-0.cbz",
              chapter_source_path: "/comics/comic-0/ch1.cbz",
            };
          if (cmd === "get_chapter_pages") return [];
          if (cmd === "get_progress") return null;
          if (cmd === "save_progress") return null;
          return null;
        },
        convertFileSrc: (p: string) => p,
      };
    },
    { settings: MOCK_SETTINGS, comics: MOCK_COMICS, chapters: MOCK_CHAPTERS },
  );
}

function getItemRects(page: import("@playwright/test").Page) {
  return page.evaluate(() => {
    const items = document.querySelectorAll("[data-virtual-item]");
    return Array.from(items).map((el) => {
      const rect = el.getBoundingClientRect();
      return {
        top: Math.round(rect.top),
        left: Math.round(rect.left),
        width: Math.round(rect.width),
      };
    });
  });
}

test.describe("Library grid system", () => {
  test("list mode: items are stacked vertically (different tops)", async ({ page }) => {
    await mockTauriIPC(page);
    await page.goto("/");
    await page.waitForSelector("text=Comic Title 001");
    await page.waitForTimeout(1000);

    const rects = await getItemRects(page);
    expect(rects.length).toBeGreaterThan(1);

    const uniqueTops = new Set(rects.map((r) => r.top));
    expect(uniqueTops.size).toBeGreaterThan(1);
  });

  test("grid mode: items are arranged horizontally (same top in pairs)", async ({ page }) => {
    await mockTauriIPC(page);
    await page.goto("/");
    await page.waitForSelector("text=Comic Title 001");
    await page.waitForTimeout(1000);

    // Click grid toggle (LayoutGrid button)
    await page.locator('button[aria-label="Grid"]').click();
    await page.waitForTimeout(500);

    const rects = await getItemRects(page);
    expect(rects.length).toBeGreaterThan(2);

    // First two items should have the same top (same row)
    expect(rects[0].top).toBe(rects[1].top);
    // They should have different left positions
    expect(rects[0].left).not.toBe(rects[1].left);
  });

  test("grid mode toggle persists across tab switch", async ({ page }) => {
    await mockTauriIPC(page);
    await page.goto("/");
    await page.waitForSelector("text=Comic Title 001");
    await page.waitForTimeout(1000);

    // Switch to grid
    await page.locator('button[aria-label="Grid"]').click();
    await page.waitForTimeout(300);

    // Switch to history tab
    await page.getByRole("button", { name: "History" }).click();
    await page.waitForTimeout(300);

    // Switch back to library tab
    await page.getByRole("button", { name: "Library" }).click();
    await page.waitForSelector("text=Comic Title 001");
    await page.waitForTimeout(500);

    // Should still be in grid mode
    const rects = await getItemRects(page);
    expect(rects.length).toBeGreaterThan(2);
    expect(rects[0].top).toBe(rects[1].top);
  });
});

test.describe("Comic page grid system", () => {
  test("chapter list grid mode: 2 items per row", async ({ page }) => {
    await mockTauriIPC(page);
    await page.goto("/");
    await page.waitForSelector("text=Comic Title 001");
    await page.waitForTimeout(1000);

    // Navigate to comic page
    await page.locator("a[href*='/comic/']").first().click();
    await page.waitForURL(/\/comic\//);
    await page.waitForTimeout(1000);

    // Switch to grid
    await page.locator('button[aria-label="Grid"]').click();
    await page.waitForTimeout(500);

    const rects = await getItemRects(page);
    expect(rects.length).toBeGreaterThan(2);

    // First 2 items should have the same top (same row)
    expect(rects[0].top).toBe(rects[1].top);
    // Third item should be on a different row
    expect(rects[2]?.top).not.toBe(rects[0].top);
  });

  test("chapter list list mode: items stacked vertically", async ({ page }) => {
    await mockTauriIPC(page);
    await page.goto("/");
    await page.waitForSelector("text=Comic Title 001");
    await page.waitForTimeout(1000);

    // Navigate to comic page
    await page.locator("a[href*='/comic/']").first().click();
    await page.waitForURL(/\/comic\//);
    await page.waitForTimeout(1000);

    // Should be in list mode by default
    const rects = await getItemRects(page);
    expect(rects.length).toBeGreaterThan(1);

    const uniqueTops = new Set(rects.map((r) => r.top));
    expect(uniqueTops.size).toBe(rects.length);
  });
});
