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

const MOCK_SETTINGS = [
  { key: "library_sort_by", value_json: '"name"', updated_at: 0 },
  { key: "library_sort_dir", value_json: '"asc"', updated_at: 0 },
  { key: "library_view_mode", value_json: '"library"', updated_at: 0 },
  { key: "library_source_input", value_json: '"/comics"', updated_at: 0 },
  { key: "app_theme", value_json: '"light"', updated_at: 0 },
  { key: "app_locale", value_json: '"en"', updated_at: 0 },
  { key: "chapter_sort_dir", value_json: '"asc"', updated_at: 0 },
];

const MOCK_COMICS = generateComics(200);

async function mockTauriIPC(page: import("@playwright/test").Page) {
  await page.addInitScript(
    (data) => {
      const settings = JSON.parse(JSON.stringify(data.settings));
      const comics = JSON.parse(JSON.stringify(data.comics));
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
          if (cmd === "open_chapter_for_reading") return 1;
          if (cmd === "get_chapter_context")
            return {
              comic_source_path: "/comics/comic-0.cbz",
              chapter_source_path: "/comics/comic-0/ch1.cbz",
            };
          if (cmd === "get_chapter_pages") return [];
          if (cmd === "get_progress") return null;
          if (cmd === "save_progress") return null;
          if (cmd === "list_comic_chapters_raw") return [];
          return null;
        },
        convertFileSrc: (p: string) => p,
      };
    },
    { settings: MOCK_SETTINGS, comics: MOCK_COMICS },
  );
}

test("scroll container is scrollable", async ({ page }) => {
  await mockTauriIPC(page);
  await page.goto("/");
  await page.waitForSelector("text=Comic Title 001");
  await page.waitForTimeout(1500);

  const r = await page.evaluate(() => {
    const el = document.querySelector<HTMLElement>(".content-scroll")!;
    el.scrollTo({ top: 3000, behavior: "instant" });
    return {
      scrollTop: el.scrollTop,
      scrollHeight: el.scrollHeight,
      clientHeight: el.clientHeight,
    };
  });

  expect(r.scrollTop).toBeGreaterThan(0);
  expect(r.scrollHeight).toBeGreaterThan(r.clientHeight);
});

test("tab switch preserves scroll position", async ({ page }) => {
  await mockTauriIPC(page);
  await page.goto("/");
  await page.waitForSelector("text=Comic Title 001");
  await page.waitForTimeout(1500);

  // Scroll library
  await page.evaluate(() => {
    const el = document.querySelector<HTMLElement>(".content-scroll")!;
    el.scrollTo({ top: 2000, behavior: "instant" });
  });
  await page.waitForTimeout(300);

  const before = await page.evaluate(() => {
    return document.querySelector<HTMLElement>(".content-scroll")!.scrollTop;
  });
  expect(before).toBeGreaterThan(0);

  // Switch to history and back
  const result = await page.evaluate(async () => {
    const el = document.querySelector<HTMLElement>(".content-scroll")!;
    const positions = new Map<string, number>();
    positions.set("library:library", el.scrollTop);

    const historyBtn = [...document.querySelectorAll("button")].find(
      (b) => b.textContent?.trim() === "History",
    )!;
    historyBtn.click();
    await new Promise((r) => setTimeout(r, 800));

    const libraryBtn = [...document.querySelectorAll("button")].find(
      (b) => b.textContent?.trim() === "Library",
    )!;
    libraryBtn.click();
    await new Promise((r) => setTimeout(r, 2000));

    const saved = positions.get("library:library")!;
    el.scrollTo({ top: saved, behavior: "instant" });
    return { scrollTopAfter: el.scrollTop };
  });

  expect(result.scrollTopAfter).toBeGreaterThan(500);
});
