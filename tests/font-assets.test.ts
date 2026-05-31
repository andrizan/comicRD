import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const appCss = readFileSync(fileURLToPath(new URL("../src/index.css", import.meta.url)), "utf8");

describe("font assets", () => {
  it("loads DM Sans weights", () => {
    for (const weight of [300, 400, 500]) {
      expect(appCss).toContain(`@import "@fontsource/dm-sans/${weight}.css";`);
    }
  });

  it("loads Syne bold weights for display text", () => {
    for (const weight of [600, 700]) {
      expect(appCss).toContain(`@import "@fontsource/syne/${weight}.css";`);
    }
  });

  it("uses Syne for display text", () => {
    expect(appCss).toContain('--font-display: "Syne", sans-serif;');
  });
});
