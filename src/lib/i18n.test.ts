import { describe, expect, it } from "vitest";
import { resolveLocalePreference } from "../i18n";

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
});
