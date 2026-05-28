// @ts-expect-error Node types are intentionally not exposed to the browser app tsconfig.
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import layout from "../routes/Layout.tsx?raw";
import readerPage from "../routes/ReaderPage.tsx?raw";

describe("reader scrollbar styling", () => {
  it("uses a dark scrollbar class on the reader scroll container", () => {
    expect(readerPage).toContain("reader-scrollbar");
  });

  it("keeps the outer reader shell black without a second page scrollbar", () => {
    expect(layout).toContain("reader-shell");
    expect(readerPage).toContain("fixed inset-0");
  });

  it("renders chapter page images without rounded corners", () => {
    expect(readerPage).not.toContain("rounded-md ${loaded");
    expect(readerPage).not.toContain("h-[220px] rounded-md");
  });

  it("defines dark native scrollbar styling for WebView2", () => {
    const css = readFileSync("src/index.css", "utf8");
    expect(css).toContain(".reader-scrollbar");
    expect(css).toContain(".reader-shell");
    expect(css).toContain("color-scheme: dark");
    expect(css).toContain("::-webkit-scrollbar-track");
  });
});
