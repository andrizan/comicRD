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
  "library.history": "History",
  "library.library": "Library",
  "library.bookmarks": "Bookmarks",
  "library.refresh": "Refresh comics",
  "library.searchPlaceholder": "Search comics...",
  "library.folderDate": "Folder Date",
  "library.readError.title": "Failed to read library folder",
  "library.readError.description": "Make sure the folder path is valid and accessible.",
  "library.emptyFilter.title": "No comics match the filter",
  "library.emptyFilter.description":
    "Change sorting/filtering or check the library folder contents.",
  "library.modified": "Modified: {value}",
  "library.groupCount": "Comics: {count}",
  "library.noComicsInFolder": "No comics in this folder.",
  "library.bookmarked": "Bookmarked: {value}",
  "library.addBookmark": "Add bookmark",
  "library.removeBookmark": "Remove bookmark",
  "library.openFolder": "Open containing folder",
  "library.copyPath": "Copy path",
  "library.copyTitle": "Copy title",
  "library.bookmarksEmpty.title": "No bookmarked comics",
  "library.bookmarksEmpty.description": "Bookmark comics to quickly find them later.",
  "library.bookmarkDate": "Bookmark Date",
  "library.readDate": "Read Date",
  "library.readAt": "Read: {value}",
  "library.historyEmpty.title": "No reading history",
  "library.historyEmpty.description": "Start reading comics to see your history here.",

  "comic.refreshChapters": "Refresh chapters",
  "comic.chapters": "{count} chapters",
  "comic.shown": "{count} shown",
  "comic.searchPlaceholder": "Search chapters...",
  "comic.nameAsc": "Name Asc",
  "comic.nameDesc": "Name Desc",
  "comic.loadError.title": "Failed to load chapters",
  "comic.loadError.description": "Try opening this comic again.",
  "comic.openChapter": "Open chapter",
  "comic.addFavorite": "Add to favorites",
  "comic.removeFavorite": "Remove from favorites",
  "comic.showFavorites": "Show favorites only",
  "comic.empty.title": "No chapters found",
  "comic.empty.description": "This comic folder/archive has no valid chapters.",
  "comic.emptyFilter.title": "No chapters match the filter",
  "comic.emptyFilter.description": "Change the filter or search keyword.",
  "comic.pages": "Pages: {count}",
  "comic.pagesEmpty": "Pages: -",
  "comic.status.read": "Read",
  "comic.status.reading": "Reading p.{page}/{total}",
  "comic.status.unread": "Unread",

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
  "app.toggleTheme": "Mode gelap",
  "nav.library": "Library",
  "nav.settings": "Pengaturan",

  "common.retry": "Coba lagi",
  "common.refresh": "Muat ulang",
  "common.search": "Cari",
  "common.name": "Nama",
  "common.asc": "A-Z",
  "common.desc": "Z-A",
  "common.value": "Nilai: {value}",
  "common.light": "Terang",
  "common.dark": "Gelap",

  "library.notSet.title": "Folder library belum diatur",
  "library.notSet.description":
    "Atur folder library di Pengaturan terlebih dahulu. Setelah itu, daftar komik akan langsung dimuat dari folder tersebut.",
  "library.title": "Komik",
  "library.count": "{count} komik",
  "library.shown": "{count} ditampilkan",
  "library.history": "Riwayat",
  "library.library": "Library",
  "library.bookmarks": "Bookmark",
  "library.refresh": "Muat ulang komik",
  "library.searchPlaceholder": "Cari komik...",
  "library.folderDate": "Tanggal Folder",
  "library.readError.title": "Gagal membaca folder library",
  "library.readError.description": "Pastikan path folder valid dan bisa diakses.",
  "library.emptyFilter.title": "Tidak ada komik yang cocok",
  "library.emptyFilter.description": "Ubah pencarian atau filter, atau periksa isi folder library.",
  "library.modified": "Diubah: {value}",
  "library.groupCount": "{count} komik",
  "library.noComicsInFolder": "Tidak ada komik di folder ini.",
  "library.bookmarked": "Dibookmark: {value}",
  "library.addBookmark": "Tambah bookmark",
  "library.removeBookmark": "Hapus bookmark",
  "library.openFolder": "Buka folder",
  "library.copyPath": "Salin path",
  "library.copyTitle": "Salin judul",
  "library.bookmarksEmpty.title": "Belum ada komik di bookmark",
  "library.bookmarksEmpty.description": "Bookmark komik untuk menemukannya dengan cepat nanti.",
  "library.bookmarkDate": "Tanggal Bookmark",
  "library.readDate": "Tanggal Baca",
  "library.readAt": "Dibaca: {value}",
  "library.historyEmpty.title": "Belum ada riwayat baca",
  "library.historyEmpty.description": "Mulai baca komik untuk melihat riwayat di sini.",

  "comic.refreshChapters": "Muat ulang chapter",
  "comic.chapters": "{count} chapter",
  "comic.shown": "{count} ditampilkan",
  "comic.searchPlaceholder": "Cari chapter...",
  "comic.nameAsc": "Nama A-Z",
  "comic.nameDesc": "Nama Z-A",
  "comic.loadError.title": "Gagal memuat chapter",
  "comic.loadError.description": "Coba buka komik ini lagi.",
  "comic.openChapter": "Buka chapter",
  "comic.addFavorite": "Tambah ke favorit",
  "comic.removeFavorite": "Hapus dari favorit",
  "comic.showFavorites": "Tampilkan favorit saja",
  "comic.empty.title": "Chapter tidak ditemukan",
  "comic.empty.description": "Folder/arsip komik ini tidak memiliki chapter yang valid.",
  "comic.emptyFilter.title": "Tidak ada chapter yang cocok",
  "comic.emptyFilter.description": "Ubah filter atau kata kunci pencarian.",
  "comic.pages": "Halaman: {count}",
  "comic.pagesEmpty": "Halaman: -",
  "comic.status.read": "Selesai",
  "comic.status.reading": "Halaman {page}/{total}",
  "comic.status.unread": "Belum dibaca",

  "settings.librarySource.title": "Sumber Library",
  "settings.librarySource.description":
    "Folder ini digunakan sebagai root library. Halaman Library hanya membaca judul komik dari sini.",
  "settings.librarySource.placeholder": "/path/ke/folder-komik",
  "settings.browse": "Pilih",
  "settings.setFolder": "Simpan Folder",
  "settings.reader.title": "Pengaturan Reader",
  "settings.readerModeLocked": "Mode reader dikunci ke ",
  "settings.webtoon": "Webtoon",
  "settings.defaultZoom": "Zoom Default",
  "settings.pageGap": "Jarak Antar Halaman",
  "settings.saveSettings": "Simpan Pengaturan",
  "settings.appearance.title": "Tampilan",
  "settings.theme": "Tema",
  "settings.language": "Bahasa",
  "settings.language.english": "English",
  "settings.language.indonesian": "Indonesia",
  "settings.saveAppearance": "Simpan Tampilan",
  "settings.backup.title": "Backup Database",
  "settings.backup.description": "Export/import seluruh riwayat baca, bookmark, dan pengaturan.",
  "settings.exportBackup": "Export Backup",
  "settings.importBackup": "Import Backup",
  "settings.loadError.title": "Gagal memuat pengaturan",
  "settings.loadError.description": "Coba muat ulang halaman pengaturan.",
  "settings.backupExportSuccess": "Backup berhasil diexport: {path}",
  "settings.backupExportFailure": "Export backup gagal: {error}",
  "settings.backupImportSuccess": "Backup berhasil diimport: {path}",
  "settings.backupImportFailure": "Import backup gagal: {error}",

  "reader.loadError.title": "Gagal memuat reader",
  "reader.loadError.description":
    "Terjadi kesalahan saat memuat data chapter/halaman. Coba muat ulang chapter ini.",
  "reader.empty.title": "Chapter kosong",
  "reader.empty.description": "Tidak ada halaman gambar untuk chapter ini.",
  "reader.comicFallback": "Komik",
  "reader.chapterFallback": "Chapter",
  "reader.chapterPosition": "Chapter {position} / {total}",
  "reader.decreaseGap": "Kurangi jarak",
  "reader.increaseGap": "Tambah jarak",
  "reader.resetZoom": "Reset zoom",
  "reader.fullscreen": "Layar penuh",
  "reader.pageTitle": "Halaman {page}",
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

activateLocale("en");

export { i18n };
