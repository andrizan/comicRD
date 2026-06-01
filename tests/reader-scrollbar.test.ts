// @ts-expect-error Node types are intentionally not exposed to the browser app tsconfig.
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import layout from "@/routes/Layout.tsx?raw";
import readerPage from "@/routes/ReaderPage.tsx?raw";

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
    expect(readerPage).not.toContain("animate-pulse rounded-sm bg-white/5");
  });

  it("keeps page refs available for footer segment navigation", () => {
    expect(readerPage).toContain("pageRefs.current.get(nextPage)?.scrollIntoView");
    expect(readerPage).not.toContain("pageRefs.current.clear()");
  });

  it("renders active reader images at their natural aspect ratio", () => {
    expect(readerPage).toContain("mx-auto block h-auto w-full");
    expect(readerPage).not.toContain("flex h-16 items-center justify-center");
  });

  it("animates reader page width changes during zoom", () => {
    expect(readerPage).toContain("transition-[max-width]");
    expect(readerPage).toContain("motion-reduce:transition-none");
  });

  it("keeps every reader page image mounted for native lazy loading", () => {
    expect(readerPage).toContain('loading={isNear ? "eager" : "lazy"}');
    expect(readerPage).not.toContain("<PagePlaceholder");
  });

  it("uses measured image ratios while pages are loading", () => {
    expect(readerPage).toContain("pageAspectRatios");
    expect(readerPage).toContain("naturalWidth");
    expect(readerPage).toContain("naturalHeight");
  });

  it("defines dark native scrollbar styling for WebView2", () => {
    const css = readFileSync("src/index.css", "utf8");
    expect(css).toContain(".reader-scrollbar");
    expect(css).toContain(".reader-shell");
    expect(css).toContain("color-scheme: dark");
    expect(css).toContain("::-webkit-scrollbar-track");
  });
});
