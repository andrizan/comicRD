import { describe, expect, it } from "vitest";
import i18nSource from "@/i18n.ts?raw";
import settingsPanel from "@/components/SettingsPanel.tsx?raw";

describe("i18n UI wiring", () => {
  it("defaults to English and only exposes English and Indonesian language choices", () => {
    expect(i18nSource).toContain('activateLocale("en")');
    expect(i18nSource).toContain('{ value: "en"');
    expect(i18nSource).toContain('{ value: "id"');
    expect(i18nSource).not.toContain('value: "system"');
    expect(settingsPanel).not.toContain('value === "system"');
  });

  it("persists the language preference through app settings", () => {
    expect(settingsPanel).toContain('setSetting("app_locale", localePreference)');
  });
});
