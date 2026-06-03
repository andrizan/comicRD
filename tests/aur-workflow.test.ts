import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const desktopBuildWorkflow = readFileSync(
  fileURLToPath(new URL("../.github/workflows/desktop-build.yml", import.meta.url)),
  "utf8",
);

describe("AUR workflow", () => {
  it("generates .SRCINFO from a writable makepkg working directory", () => {
    expect(desktopBuildWorkflow).toContain('-v "$PWD/aur-repo:/aur-src:ro"');
    expect(desktopBuildWorkflow).toContain("install -d -o builder -g builder /pkg");
    expect(desktopBuildWorkflow).toContain("install -m 644 /aur-src/PKGBUILD /pkg/PKGBUILD");
    expect(desktopBuildWorkflow).toContain("su builder -c 'cd /pkg && makepkg --printsrcinfo'");
    expect(desktopBuildWorkflow).not.toContain('-v "$PWD/aur-repo:/pkg:ro"');
  });
});
