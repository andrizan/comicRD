import { describe, expect, it } from "vitest";
import { interpolateI18nPlaceholders, resolveLocalePreference, t } from "../i18n";

describe("i18n locale resolution", () => {
  it("allows explicit English and Indonesian preferences", () => {
    expect(resolveLocalePreference("en")).toBe("en");
    expect(resolveLocalePreference("id")).toBe("id");
  });

  it("falls back to English for missing or unsupported preferences", () => {
    expect(resolveLocalePreference(undefined)).toBe("en");
    expect(resolveLocalePreference("system")).toBe("en");
    expect(resolveLocalePreference("ja")).toBe("en");
  });

  it("interpolates dynamic message values", () => {
    expect(t("library.count", { count: 12 })).toBe("12 comics");
    expect(t("comic.status.reading", { page: 3, total: 9 })).toBe("Reading p.3/9");
    expect(t("reader.chapterPosition", { position: 2, total: 5 })).toBe("Chapter 2 / 5");
  });

  it("can clean up raw placeholder text from runtime messages", () => {
    expect(interpolateI18nPlaceholders("{count} chapters", { count: 7 })).toBe("7 chapters");
    expect(interpolateI18nPlaceholders("Reading p.{page}/{total}", { page: 4, total: 8 })).toBe(
      "Reading p.4/8",
    );
  });
});
