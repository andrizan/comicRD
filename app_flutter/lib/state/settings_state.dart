import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_state.dart';

final appSettingsProvider = NotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.localeCode = 'en',
  });

  final ThemeMode themeMode;
  final String localeCode;

  AppSettings copyWith({ThemeMode? themeMode, String? localeCode}) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        localeCode: localeCode ?? this.localeCode,
      );
}

class AppSettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => const AppSettings();

  void setThemeMode(ThemeMode themeMode) {
    state = state.copyWith(themeMode: themeMode);
  }

  void setLocale(String localeCode) {
    state = state.copyWith(localeCode: localeCode);
  }

  void hydrateFromSettings(Map<String, String> values) {
    final theme = themeModeFromSetting(
      _decodeString(values['app_theme'], 'system'),
    );
    final locale = _decodeString(values['app_locale'], 'en');
    state = state.copyWith(themeMode: theme, localeCode: locale);
  }

  String _decodeString(String? raw, String fallback) {
    if (raw == null) return fallback;
    try {
      final decoded = jsonDecode(raw);
      return decoded is String ? decoded : fallback;
    } catch (_) {
      return fallback;
    }
  }

  void toggleTheme() {
    state = state.copyWith(
      themeMode: state.themeMode == ThemeMode.dark
          ? ThemeMode.light
          : ThemeMode.dark,
    );
  }

  void toggleLocale() {
    state = state.copyWith(localeCode: state.localeCode == 'en' ? 'id' : 'en');
  }
}

ThemeMode themeModeFromSetting(String value) {
  return switch (value) {
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    _ => ThemeMode.light,
  };
}

String themeModeToSetting(ThemeMode value) {
  return switch (value) {
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
    ThemeMode.light => 'light',
  };
}

final readerSettingsProvider =
    NotifierProvider<ReaderSettingsNotifier, ReaderSettings>(
      ReaderSettingsNotifier.new,
    );

class ReaderSettings {
  const ReaderSettings({this.zoom = 1.0, this.pageGap = 20.0});

  final double zoom;
  final double pageGap;

  ReaderSettings copyWith({double? zoom, double? pageGap}) =>
      ReaderSettings(zoom: zoom ?? this.zoom, pageGap: pageGap ?? this.pageGap);
}

class ReaderSettingsNotifier extends Notifier<ReaderSettings> {
  @override
  ReaderSettings build() => const ReaderSettings();

  void setZoom(double zoom) {
    state = state.copyWith(zoom: zoom.clamp(0.5, 3.0));
    _saveToDatabase();
  }

  void setPageGap(double gap) {
    state = state.copyWith(pageGap: gap.clamp(0, 80));
    _saveToDatabase();
  }

  void _saveToDatabase() {
    final api = ref.read(comicRdApiProvider);
    api.setSetting('default_zoom', state.zoom.toStringAsFixed(1));
    api.setSetting('page_gap', state.pageGap.round().toString());
  }

  void hydrateFromSettings(Map<String, String> values) {
    final zoom = _decodeDouble(values['default_zoom'], 1.0);
    final gap = _decodeDouble(values['page_gap'], 20.0);
    state = ReaderSettings(
      zoom: zoom.clamp(0.5, 3.0),
      pageGap: gap.clamp(0, 80),
    );
  }

  double _decodeDouble(String? raw, double fallback) {
    if (raw == null) return fallback;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is num) return decoded.toDouble();
      if (decoded is String) {
        return num.tryParse(decoded)?.toDouble() ?? fallback;
      }
    } catch (_) {}
    return fallback;
  }
}

AppStrings stringsFor(String localeCode) =>
    localeCode == 'id' ? AppStrings.id : AppStrings.en;

class AppStrings {
  const AppStrings({
    // App identity
    required this.appName,
    // Navigation
    required this.home,
    required this.theme,
    required this.themeSystem,
    required this.themeLight,
    required this.themeDark,
    required this.locale,
    required this.settings,
    required this.history,
    required this.library,
    required this.bookmarks,
    required this.search,
    required this.refresh,
    required this.totalComics,
    required this.showingComics,
    required this.emptyLibrary,
    required this.comic,
    required this.reader,
    // Language names
    required this.english,
    required this.indonesian,
    // Reader
    required this.noPages,
    required this.close,
    required this.previousChapter,
    required this.previousPage,
    required this.nextPage,
    required this.nextChapter,
    required this.readerControls,
    required this.gap,
    required this.zoom,
    required this.fullscreen,
    // Chapter status
    required this.read,
    required this.reading,
    required this.unread,
    required this.page,
    required this.pages,
    // Sort/filter
    required this.favorites,
    required this.chapter,
    required this.name,
    required this.folderDate,
    required this.ascending,
    required this.descending,
    // Library view modes
    required this.all,
    required this.progress,
    // Comic actions
    required this.comicActions,
    required this.addBookmark,
    required this.removeBookmark,
    required this.addFavorite,
    required this.removeFavorite,
    required this.openFolder,
    required this.copyTitle,
    required this.copyPath,
    required this.noLibrarySource,
    // Settings panel
    required this.librarySection,
    required this.librarySource,
    required this.browseDirectory,
    required this.refreshSourceStatus,
    required this.readerSection,
    required this.defaultZoom,
    required this.pageGap,
    required this.imagePipelineProfile,
    required this.performance,
    required this.balanced,
    required this.quality,
    required this.applicationSection,
    required this.backupSection,
    required this.exportBackup,
    required this.importBackup,
    required this.cancel,
    required this.save,
    required this.settingsSaved,
    required this.backupExported,
    required this.backupImported,
    required this.sqliteDatabase,
  });

  // App identity
  final String appName;
  // Navigation
  final String home;
  final String theme;
  final String themeSystem;
  final String themeLight;
  final String themeDark;
  final String locale;
  final String settings;
  final String history;
  final String library;
  final String bookmarks;
  final String search;
  final String refresh;
  final String totalComics;
  final String showingComics;
  final String emptyLibrary;
  final String comic;
  final String reader;
  // Language names
  final String english;
  final String indonesian;
  // Reader
  final String noPages;
  final String close;
  final String previousChapter;
  final String previousPage;
  final String nextPage;
  final String nextChapter;
  final String readerControls;
  final String gap;
  final String zoom;
  final String fullscreen;
  // Chapter status
  final String read;
  final String reading;
  final String unread;
  final String page;
  final String pages;
  // Sort/filter
  final String favorites;
  final String chapter;
  final String name;
  final String folderDate;
  final String ascending;
  final String descending;
  // Library view modes
  final String all;
  final String progress;
  // Comic actions
  final String comicActions;
  final String addBookmark;
  final String removeBookmark;
  final String addFavorite;
  final String removeFavorite;
  final String openFolder;
  final String copyTitle;
  final String copyPath;
  final String noLibrarySource;
  // Settings panel
  final String librarySection;
  final String librarySource;
  final String browseDirectory;
  final String refreshSourceStatus;
  final String readerSection;
  final String defaultZoom;
  final String pageGap;
  final String imagePipelineProfile;
  final String performance;
  final String balanced;
  final String quality;
  final String applicationSection;
  final String backupSection;
  final String exportBackup;
  final String importBackup;
  final String cancel;
  final String save;
  final String settingsSaved;
  final String backupExported;
  final String backupImported;
  final String sqliteDatabase;

  static const en = AppStrings(
    appName: 'ComicRD',
    home: 'Home',
    theme: 'Theme',
    themeSystem: 'System',
    themeLight: 'Light',
    themeDark: 'Dark',
    locale: 'Language',
    settings: 'Settings',
    history: 'History',
    library: 'Library',
    bookmarks: 'Bookmarks',
    search: 'Search',
    refresh: 'Perbarui',
    totalComics: 'Total comics',
    showingComics: 'Showing',
    emptyLibrary: 'No comics found',
    comic: 'Comic',
    reader: 'Reader',
    english: 'English',
    indonesian: 'Indonesian',
    noPages: 'No pages',
    close: 'Close',
    previousChapter: 'Previous chapter',
    previousPage: 'Previous page',
    nextPage: 'Next page',
    nextChapter: 'Next chapter',
    readerControls: 'Reader controls',
    gap: 'Gap',
    zoom: 'Zoom',
    fullscreen: 'Fullscreen',
    read: 'Read',
    reading: 'Reading',
    unread: 'Unread',
    page: 'page',
    pages: 'pages',
    favorites: 'Favorites',
    chapter: 'Chapter',
    name: 'Name',
    folderDate: 'Folder date',
    ascending: 'Ascending',
    descending: 'Descending',
    all: 'All',
    progress: 'Progress',
    comicActions: 'Comic actions',
    addBookmark: 'Add bookmark',
    removeBookmark: 'Remove bookmark',
    addFavorite: 'Add favorite',
    removeFavorite: 'Remove favorite',
    openFolder: 'Open folder',
    copyTitle: 'Copy title',
    copyPath: 'Copy path',
    noLibrarySource: 'No library source configured',
    librarySection: 'Library',
    librarySource: 'Library source',
    browseDirectory: 'Browse directory',
    refreshSourceStatus: 'Refresh source status',
    readerSection: 'Reader',
    defaultZoom: 'Default zoom',
    pageGap: 'Page gap',
    imagePipelineProfile: 'Image pipeline profile',
    performance: 'Performance',
    balanced: 'Balanced',
    quality: 'Quality',
    applicationSection: 'Application',
    backupSection: 'Backup',
    exportBackup: 'Export backup',
    importBackup: 'Import backup',
    cancel: 'Cancel',
    save: 'Save',
    settingsSaved: 'Settings saved',
    backupExported: 'Backup exported',
    backupImported: 'Backup imported',
    sqliteDatabase: 'SQLite database',
  );

  static const id = AppStrings(
    appName: 'ComicRD',
    home: 'Beranda',
    theme: 'Tema',
    themeSystem: 'Sistem',
    themeLight: 'Terang',
    themeDark: 'Gelap',
    locale: 'Bahasa',
    settings: 'Pengaturan',
    history: 'Riwayat',
    library: 'Pustaka',
    bookmarks: 'Bookmark',
    search: 'Cari',
    refresh: 'Refresh',
    totalComics: 'Total komik',
    showingComics: 'Menampilkan',
    emptyLibrary: 'Komik tidak ditemukan',
    comic: 'Komik',
    reader: 'Reader',
    english: 'Inggris',
    indonesian: 'Indonesia',
    noPages: 'Tidak ada halaman',
    close: 'Tutup',
    previousChapter: 'Chapter sebelumnya',
    previousPage: 'Halaman sebelumnya',
    nextPage: 'Halaman berikutnya',
    nextChapter: 'Chapter berikutnya',
    readerControls: 'Kontrol reader',
    gap: 'Jarak',
    zoom: 'Perbesar',
    fullscreen: 'Layar penuh',
    read: 'Dibaca',
    reading: 'Sedang dibaca',
    unread: 'Belum dibaca',
    page: 'halaman',
    pages: 'halaman',
    favorites: 'Favorit',
    chapter: 'Chapter',
    name: 'Nama',
    folderDate: 'Tanggal folder',
    ascending: 'Menaik',
    descending: 'Menurun',
    all: 'Semua',
    progress: 'Progres',
    comicActions: 'Aksi komik',
    addBookmark: 'Tambah bookmark',
    removeBookmark: 'Hapus bookmark',
    addFavorite: 'Tambah favorit',
    removeFavorite: 'Hapus favorit',
    openFolder: 'Buka folder',
    copyTitle: 'Salin judul',
    copyPath: 'Salin path',
    noLibrarySource: 'Sumber pustaka belum dikonfigurasi',
    librarySection: 'Pustaka',
    librarySource: 'Sumber pustaka',
    browseDirectory: 'Pilih direktori',
    refreshSourceStatus: 'Perbarui status sumber',
    readerSection: 'Reader',
    defaultZoom: 'Zoom default',
    pageGap: 'Jarak halaman',
    imagePipelineProfile: 'Profil pipeline gambar',
    performance: 'Performa',
    balanced: 'Seimbang',
    quality: 'Kualitas',
    applicationSection: 'Aplikasi',
    backupSection: 'Cadangan',
    exportBackup: 'Ekspor cadangan',
    importBackup: 'Impor cadangan',
    cancel: 'Batal',
    save: 'Simpan',
    settingsSaved: 'Pengaturan disimpan',
    backupExported: 'Cadangan diekspor',
    backupImported: 'Cadangan diimpor',
    sqliteDatabase: 'Database SQLite',
  );
}
