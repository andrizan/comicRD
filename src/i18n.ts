import { i18n } from "@lingui/core";
import { useLingui } from "@lingui/react";

export type AppLocale = "en" | "id";
export type LocalePreference = AppLocale;

export const localeOptions: Array<{ value: LocalePreference; label: string }> = [
  { value: "en", label: "English" },
  { value: "id", label: "Indonesia" },
];

export function resolveLocalePreference(preference: string | undefined): AppLocale {
  if (preference === "en" || preference === "id") return preference;
  return "en";
}

const enMessages = {
  "app.toggleTheme": "Toggle dark mode",
  "nav.library": "Library",
  "nav.settings": "Settings",

  "common.retry": "Retry",
  "common.refresh": "Refresh",
  "common.search": "Search",
  "common.name": "Name",
  "common.asc": "Asc",
  "common.desc": "Desc",
  "common.value": "Value: {value}",
  "common.light": "Light",
  "common.dark": "Dark",

  "library.notSet.title": "Library folder is not set",
  "library.notSet.description":
    "Set the library folder in Settings first. After it is set, the comic list is read directly from that folder.",
  "library.title": "Comics",
  "library.count": "{count} comics",
  "library.shown": "{count} shown",
  "library.all": "All",
  "library.folder": "Folder",
  "library.refresh": "Refresh comics",
  "library.searchPlaceholder": "Search comics...",
  "library.folderDate": "Folder Date",
  "library.readError.title": "Failed to read library folder",
  "library.readError.description": "Make sure the folder path is valid and accessible.",
  "library.emptyFilter.title": "No comics match the filter",
  "library.emptyFilter.description": "Change sorting/filtering or check the library folder contents.",
  "library.modified": "Modified: {value}",
  "library.groupCount": "Comics: {count}",
  "library.noComicsInFolder": "No comics in this folder.",

  "comic.refreshChapters": "Refresh chapters",
  "comic.chapters": "{count} chapters",
  "comic.shown": "{count} shown",
  "comic.searchPlaceholder": "Search chapters...",
  "comic.nameAsc": "Name Asc",
  "comic.nameDesc": "Name Desc",
  "comic.loadError.title": "Failed to load chapters",
  "comic.loadError.description": "Try opening this comic again.",
  "comic.empty.title": "No chapters found",
  "comic.empty.description": "This comic folder/archive has no valid chapters.",
  "comic.emptyFilter.title": "No chapters match the filter",
  "comic.emptyFilter.description": "Change the filter or search keyword.",
  "comic.pages": "Pages: {count}",
  "comic.pagesEmpty": "Pages: -",
  "comic.status.read": "Read",
  "comic.status.reading": "Reading p.{page}/{total}",
  "comic.status.unread": "Unread",
  "comic.read": "Read",

  "settings.librarySource.title": "Library Source",
  "settings.librarySource.description":
    "This folder is used as the library root. The Library page only reads comic titles from here.",
  "settings.librarySource.placeholder": "/path/to/comic-folder",
  "settings.browse": "Browse",
  "settings.setFolder": "Set Folder",
  "settings.reader.title": "Reader Settings",
  "settings.readerModeLocked": "Reader mode is locked to ",
  "settings.webtoon": "Webtoon",
  "settings.defaultZoom": "Default Zoom",
  "settings.pageGap": "Page Margin / Gap",
  "settings.saveSettings": "Save Settings",
  "settings.appearance.title": "Appearance",
  "settings.theme": "Theme",
  "settings.language": "Language",
  "settings.language.english": "English",
  "settings.language.indonesian": "Indonesia",
  "settings.saveAppearance": "Save Appearance",
  "settings.backup.title": "Backup Database",
  "settings.backup.description": "Export/import all reading history, bookmarks, and settings.",
  "settings.exportBackup": "Export Backup",
  "settings.importBackup": "Import Backup",
  "settings.loadError.title": "Failed to load settings",
  "settings.loadError.description": "Try reloading the settings page.",
  "settings.backupExportSuccess": "Backup exported: {path}",
  "settings.backupExportFailure": "Backup export failed: {error}",
  "settings.backupImportSuccess": "Backup imported: {path}",
  "settings.backupImportFailure": "Backup import failed: {error}",

  "reader.loadError.title": "Failed to load reader",
  "reader.loadError.description":
    "An error occurred while loading chapter/page data. Try reloading this chapter.",
  "reader.empty.title": "Empty chapter",
  "reader.empty.description": "There are no image pages for this chapter.",
  "reader.comicFallback": "Comic",
  "reader.chapterFallback": "Chapter",
  "reader.chapterPosition": "Chapter {position} / {total}",
  "reader.decreaseGap": "Decrease gap",
  "reader.increaseGap": "Increase gap",
  "reader.resetZoom": "Reset zoom",
  "reader.fullscreen": "Fullscreen",
  "reader.pageTitle": "Page {page}",
};

export type MessageKey = keyof typeof enMessages;

const idMessages: Record<keyof typeof enMessages, string> = {
  "app.toggleTheme": "Ganti mode gelap",
  "nav.library": "Library",
  "nav.settings": "Settings",

  "common.retry": "Coba lagi",
  "common.refresh": "Refresh",
  "common.search": "Cari",
  "common.name": "Nama",
  "common.asc": "Asc",
  "common.desc": "Desc",
  "common.value": "Value: {value}",
  "common.light": "Light",
  "common.dark": "Dark",

  "library.notSet.title": "Folder Library Belum Diset",
  "library.notSet.description":
    "Set folder library di Settings terlebih dahulu. Setelah diset, list komik langsung diambil dari folder.",
  "library.title": "Comics",
  "library.count": "{count} comics",
  "library.shown": "{count} ditampilkan",
  "library.all": "All",
  "library.folder": "Folder",
  "library.refresh": "Refresh komik",
  "library.searchPlaceholder": "Cari komik...",
  "library.folderDate": "Tanggal Folder",
  "library.readError.title": "Gagal membaca folder library",
  "library.readError.description": "Pastikan path folder valid dan punya izin akses.",
  "library.emptyFilter.title": "Tidak ada komik sesuai filter",
  "library.emptyFilter.description": "Ubah sorting/filter atau cek isi folder library.",
  "library.modified": "Modified: {value}",
  "library.groupCount": "Comics: {count}",
  "library.noComicsInFolder": "Tidak ada komik di folder ini.",

  "comic.refreshChapters": "Refresh chapter",
  "comic.chapters": "{count} chapters",
  "comic.shown": "{count} ditampilkan",
  "comic.searchPlaceholder": "Cari chapter...",
  "comic.nameAsc": "Nama Asc",
  "comic.nameDesc": "Nama Desc",
  "comic.loadError.title": "Gagal memuat chapter",
  "comic.loadError.description": "Coba buka ulang komik.",
  "comic.empty.title": "Chapter tidak ditemukan",
  "comic.empty.description": "Folder/arsip komik ini tidak punya chapter yang valid.",
  "comic.emptyFilter.title": "Tidak ada chapter sesuai filter",
  "comic.emptyFilter.description": "Ubah filter atau kata kunci pencarian.",
  "comic.pages": "Pages: {count}",
  "comic.pagesEmpty": "Pages: -",
  "comic.status.read": "Read",
  "comic.status.reading": "Reading p.{page}/{total}",
  "comic.status.unread": "Unread",
  "comic.read": "Baca",

  "settings.librarySource.title": "Library Source",
  "settings.librarySource.description":
    "Folder ini dipakai sebagai root library. Library page hanya membaca title komik dari sini.",
  "settings.librarySource.placeholder": "/path/ke/folder-komik",
  "settings.browse": "Browse",
  "settings.setFolder": "Set Folder",
  "settings.reader.title": "Reader Settings",
  "settings.readerModeLocked": "Reader mode dikunci ke ",
  "settings.webtoon": "Webtoon",
  "settings.defaultZoom": "Default Zoom",
  "settings.pageGap": "Page Margin / Gap",
  "settings.saveSettings": "Save Settings",
  "settings.appearance.title": "Appearance",
  "settings.theme": "Theme",
  "settings.language": "Language",
  "settings.language.english": "English",
  "settings.language.indonesian": "Indonesia",
  "settings.saveAppearance": "Save Appearance",
  "settings.backup.title": "Backup Database",
  "settings.backup.description": "Export/import seluruh history baca, bookmark, dan settings.",
  "settings.exportBackup": "Export Backup",
  "settings.importBackup": "Import Backup",
  "settings.loadError.title": "Gagal memuat settings",
  "settings.loadError.description": "Coba reload halaman settings.",
  "settings.backupExportSuccess": "Backup berhasil diexport: {path}",
  "settings.backupExportFailure": "Backup export gagal: {error}",
  "settings.backupImportSuccess": "Backup berhasil diimport: {path}",
  "settings.backupImportFailure": "Backup import gagal: {error}",

  "reader.loadError.title": "Gagal memuat reader",
  "reader.loadError.description":
    "Terjadi error saat mengambil data chapter/page. Coba reload chapter ini.",
  "reader.empty.title": "Chapter kosong",
  "reader.empty.description": "Tidak ada halaman gambar untuk chapter ini.",
  "reader.comicFallback": "Comic",
  "reader.chapterFallback": "Chapter",
  "reader.chapterPosition": "Chapter {position} / {total}",
  "reader.decreaseGap": "Kurangi gap",
  "reader.increaseGap": "Tambah gap",
  "reader.resetZoom": "Reset zoom",
  "reader.fullscreen": "Fullscreen",
  "reader.pageTitle": "Page {page}",
};

const catalogs = {
  en: enMessages,
  id: idMessages,
};

export function activateLocale(locale: AppLocale): void {
  i18n.loadAndActivate({ locale, messages: catalogs[locale] });
  if (typeof document !== "undefined") {
    document.documentElement.lang = locale;
  }
}

export function t(id: MessageKey, values?: Record<string, unknown>): string {
  return i18n._(id, values);
}

export function useAppI18n() {
  const { i18n: activeI18n } = useLingui();
  return {
    locale: activeI18n.locale as AppLocale,
    t: (id: MessageKey, values?: Record<string, unknown>) => activeI18n._(id, values),
  };
}

activateLocale("en");

export { i18n };
