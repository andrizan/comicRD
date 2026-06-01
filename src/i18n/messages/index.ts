import type { enMessages } from "./en";

export type MessageKey = keyof typeof enMessages;
export type MessageCatalog = Record<MessageKey, string>;

export type AppLocale = "en" | "id";
export type LocalePreference = AppLocale;

const loaders: Record<AppLocale, () => Promise<MessageCatalog>> = {
  en: () => import("./en").then((m) => m.enMessages as unknown as MessageCatalog),
  id: () => import("./id").then((m) => m.idMessages as unknown as MessageCatalog),
};

const loadedCatalogs = new Map<AppLocale, MessageCatalog>();

export async function loadCatalog(locale: AppLocale): Promise<MessageCatalog> {
  const cached = loadedCatalogs.get(locale);
  if (cached) return cached;
  const catalog = await loaders[locale]();
  loadedCatalogs.set(locale, catalog);
  return catalog;
}

export function getCachedCatalog(locale: AppLocale): MessageCatalog | undefined {
  return loadedCatalogs.get(locale);
}
