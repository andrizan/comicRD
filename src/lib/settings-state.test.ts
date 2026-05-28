import { describe, expect, it } from "vitest";
import { isLibrarySourceSaveDisabled } from "./settings-state";

describe("isLibrarySourceSaveDisabled", () => {
  it("disables saving when the input matches the saved library source", () => {
    expect(isLibrarySourceSaveDisabled("D:\\Media\\Manga", "D:\\Media\\Manga", false)).toBe(true);
  });

  it("compares trimmed paths", () => {
    expect(isLibrarySourceSaveDisabled(" D:\\Media\\Manga ", "D:\\Media\\Manga", false)).toBe(true);
  });

  it("disables saving empty input", () => {
    expect(isLibrarySourceSaveDisabled("   ", "D:\\Media\\Manga", false)).toBe(true);
  });

  it("disables saving while a save is running", () => {
    expect(isLibrarySourceSaveDisabled("D:\\Media\\Other", "D:\\Media\\Manga", true)).toBe(true);
  });

  it("enables saving when the input points to a different folder", () => {
    expect(isLibrarySourceSaveDisabled("D:\\Media\\Other", "D:\\Media\\Manga", false)).toBe(false);
  });
});
