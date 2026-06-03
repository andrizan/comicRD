import { describe, expect, it } from "vitest";
import { comicPagePreviewSrc, comicPageSrc } from "../src/lib/comic-protocol";

describe("comicPageSrc", () => {
  it("uses the Tauri custom protocol outside Windows and Android", () => {
    expect(comicPageSrc(7, 3, { userAgent: "Linux x86_64" })).toBe(
      "comicrd://localhost/page/7/3",
    );
  });

  it("uses the http protocol workaround on Windows", () => {
    expect(comicPageSrc(7, 3, { userAgent: "Mozilla/5.0 Windows" })).toBe(
      "http://comicrd.localhost/page/7/3",
    );
  });

  it("uses the http protocol workaround on Android", () => {
    expect(comicPageSrc(7, 3, { userAgent: "Mozilla/5.0 Linux Android 15" })).toBe(
      "http://comicrd.localhost/page/7/3",
    );
  });

  it("uses the Tauri custom protocol on macOS", () => {
    expect(comicPageSrc(7, 3, { userAgent: "Mozilla/5.0 Macintosh Mac OS X" })).toBe(
      "comicrd://localhost/page/7/3",
    );
  });

  it("passes a bounded integer target width to the protocol", () => {
    expect(
      comicPageSrc(7, 3, {
        targetWidth: 1279.4,
        profile: "performance",
        userAgent: "Linux",
      }),
    ).toBe(
      "comicrd://localhost/page/7/3?w=1279&p=performance",
    );
  });

  it("builds preview URLs on the lightweight preview resource", () => {
    expect(comicPagePreviewSrc(7, 3, { userAgent: "Linux" })).toBe(
      "comicrd://localhost/preview/7/3?w=64&p=performance",
    );
  });
});
