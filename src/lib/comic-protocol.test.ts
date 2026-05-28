import { describe, expect, it } from "vitest";
import { comicPageSrc } from "./comic-protocol";

describe("comicPageSrc", () => {
  it("uses the Wry HTTP workaround on Windows", () => {
    expect(comicPageSrc(4, 2, "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")).toBe(
      "http://comicrd.localhost/page/4/2",
    );
  });

  it("uses the Wry HTTP workaround on Android", () => {
    expect(comicPageSrc(4, 2, "Mozilla/5.0 (Linux; Android 15)")).toBe(
      "http://comicrd.localhost/page/4/2",
    );
  });

  it("uses the native custom scheme on other platforms", () => {
    expect(comicPageSrc(4, 2, "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)")).toBe(
      "comicrd://localhost/page/4/2",
    );
  });
});
