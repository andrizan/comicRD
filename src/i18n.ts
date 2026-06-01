import { i18n } from "@lingui/core";
import { useLingui } from "@lingui/react";
import {
  getCachedCatalog,
  loadCatalog,
  type AppLocale,
  type LocalePreference,
  type MessageCatalog,
  type MessageKey,
} from "@/i18n/messages";

export { type AppLocale, type LocalePreference, type MessageKey };

export const localeOptions: Array<{ value: LocalePreference; label: string }> = [
  { value: "en", label: "English" },
  { value: "id", label: "Indonesia" },
];

export function resolveLocalePreference(preference: string | undefined): AppLocale {
  if (preference === "en" || preference === "id") return preference;
  return "en";
}

function applyCatalog(locale: AppLocale, catalog: MessageCatalog): void {
  i18n.loadAndActivate({ locale, messages: catalog });
  if (typeof document !== "undefined") {
    document.documentElement.lang = locale;
  }
}

let inFlightActivation: Promise<void> | null = null;

export async function activateLocale(locale: AppLocale): Promise<void> {
  if (i18n.locale === locale) {
    const cached = getCachedCatalog(locale);
    if (cached) {
      applyCatalog(locale, cached);
      return;
    }
  }
  if (inFlightActivation) {
    return inFlightActivation;
  }
  inFlightActivation = (async () => {
    const catalog = await loadCatalog(locale);
    applyCatalog(locale, catalog);
  })().finally(() => {
    inFlightActivation = null;
  });
  return inFlightActivation;
}

export function interpolateI18nPlaceholders(
  message: string,
  values?: Record<string, unknown>,
): string {
  if (!values) return message;
  return message.replace(/\{([A-Za-z0-9_]+)\}/g, (match, key: string) => {
    if (!Object.prototype.hasOwnProperty.call(values, key)) return match;
    const value = values[key];
    return value == null ? "" : String(value);
  });
}

function translateWithValues(
  translator: typeof i18n,
  id: MessageKey,
  values?: Record<string, unknown>,
): string {
  return interpolateI18nPlaceholders(translator._(id, values), values);
}

export function t(id: MessageKey, values?: Record<string, unknown>): string {
  return translateWithValues(i18n, id, values);
}

export function useAppI18n() {
  const { i18n: activeI18n } = useLingui();
  return {
    locale: activeI18n.locale as AppLocale,
    t: (id: MessageKey, values?: Record<string, unknown>) =>
      translateWithValues(activeI18n, id, values),
  };
}

void activateLocale("en");

export { i18n };
