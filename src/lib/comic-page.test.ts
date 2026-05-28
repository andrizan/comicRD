import { describe, expect, it } from "vitest";
import comicPage from "../routes/ComicPage.tsx?raw";

describe("ComicPage", () => {
  it("has an icon-only refresh button for the chapter list", () => {
    expect(comicPage).toContain("comic.refreshChapters");
    expect(comicPage).toContain("chaptersQuery.refetch()");
    expect(comicPage).toContain("chaptersQuery.isFetching");
    expect(comicPage).toContain("RefreshCw");
    expect(comicPage).not.toContain('<span className="text-xs">Refresh</span>');
  });
});
