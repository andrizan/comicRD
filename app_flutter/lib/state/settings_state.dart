import 'dart:async';
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
  const ReaderSettings({
    this.zoom = 1.0,
    this.pageGap = 20.0,
    this.unlimitedScroll = false,
    this.unlimitedScrollUp = true,
  });

  final double zoom;
  final double pageGap;
  final bool unlimitedScroll;
  final bool unlimitedScrollUp;

  ReaderSettings copyWith({
    double? zoom,
    double? pageGap,
    bool? unlimitedScroll,
    bool? unlimitedScrollUp,
  }) => ReaderSettings(
    zoom: zoom ?? this.zoom,
    pageGap: pageGap ?? this.pageGap,
    unlimitedScroll: unlimitedScroll ?? this.unlimitedScroll,
    unlimitedScrollUp: unlimitedScrollUp ?? this.unlimitedScrollUp,
  );
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

  void setUnlimitedScroll(bool value) {
    state = state.copyWith(unlimitedScroll: value);
    _saveToDatabase();
  }

  void setUnlimitedScrollUp(bool value) {
    state = state.copyWith(unlimitedScrollUp: value);
    _saveToDatabase();
  }

  void _saveToDatabase() {
    final api = ref.read(comicRdApiProvider);
    unawaited(api.setSetting('default_zoom', state.zoom.toStringAsFixed(1)));
    unawaited(api.setSetting('page_gap', state.pageGap.round().toString()));
    unawaited(
      api.setSetting('unlimited_scroll', state.unlimitedScroll.toString()),
    );
    unawaited(
      api.setSetting('unlimited_scroll_up', state.unlimitedScrollUp.toString()),
    );
  }

  void hydrateFromSettings(Map<String, String> values) {
    final zoom = _decodeDouble(values['default_zoom'], 1.0);
    final gap = _decodeDouble(values['page_gap'], 20.0);
    final unlimitedScroll = _decodeBool(values['unlimited_scroll'], false);
    final unlimitedScrollUp = _decodeBool(values['unlimited_scroll_up'], true);
    state = ReaderSettings(
      zoom: zoom.clamp(0.5, 3.0),
      pageGap: gap.clamp(0, 80),
      unlimitedScroll: unlimitedScroll,
      unlimitedScrollUp: unlimitedScrollUp,
    );
  }

  bool _decodeBool(String? raw, bool fallback) {
    if (raw == null) return fallback;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is bool) return decoded;
      if (decoded is String) return decoded.toLowerCase() == 'true';
    } catch (_) {}
    return fallback;
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
    required this.backToTop,
    required this.totalChapters,
    required this.emptyLibrary,
    required this.comic,
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
    required this.unlimitedScroll,
    required this.unlimitedScrollUp,
    // Chapter status
    required this.read,
    required this.reading,
    required this.unread,
    // Sort/filter
    required this.chapter,
    required this.name,
    required this.folderDate,
    // Library view modes
    required this.all,
    required this.progress,
    required this.grid,
    required this.list,
    required this.sortDirection,
    // Comic actions
    required this.bookmark,
    required this.bookmarked,
    required this.addBookmark,
    required this.removeBookmark,
    required this.addFavorite,
    required this.removeFavorite,
    required this.openFolder,
    required this.copyTitle,
    required this.copyPath,
    required this.noLibrarySource,
    // Redesign labels
    required this.menu,
    required this.newBadge,
    required this.continueReading,
    required this.totalSize,
    required this.chapterCountLabel,
    required this.librarySubtitleTemplate,
    required this.bookmarksSubtitleTemplate,
    required this.latestReading,
    // Comic detail labels
    required this.backToLibrary,
    required this.directoryPath,
    required this.lastRead,
    required this.lastReadTemplate,
    required this.readingProgress,
    required this.readingProgressTemplate,
    required this.startFromBeginning,
    required this.filterChapters,
    required this.allChapters,
    required this.favoriteChapters,
    required this.downloaded,
    // Settings panel
    required this.librarySection,
    required this.librarySource,
    required this.librarySourceDescription,
    required this.browseDirectory,
    required this.refreshSourceStatus,
    required this.readerSection,
    required this.defaultZoom,
    required this.pageGap,
    required this.applicationSection,
    required this.backupSection,
    required this.exportBackup,
    required this.importBackup,
    required this.save,
    required this.settingsSaved,
    required this.backupExported,
    required this.backupImported,
    // Scan
    required this.scanLibrary,
    required this.scanning,
    required this.scanNoChange,
    required this.scanProgress,
    required this.scanCompleted,
    required this.cancelScan,
  });

  // App identity
  final String appName;
  // Navigation
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
  final String backToTop;
  final String totalChapters;
  final String emptyLibrary;
  final String comic;
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
  final String unlimitedScroll;
  final String unlimitedScrollUp;
  // Chapter status
  final String read;
  final String reading;
  final String unread;
  // Sort/filter
  final String chapter;
  final String name;
  final String folderDate;
  // Library view modes
  final String all;
  final String progress;
  final String grid;
  final String list;
  final String sortDirection;
  // Comic actions
  final String bookmark;
  final String bookmarked;
  final String addBookmark;
  final String removeBookmark;
  final String addFavorite;
  final String removeFavorite;
  final String openFolder;
  final String copyTitle;
  final String copyPath;
  final String noLibrarySource;
  // Redesign labels
  final String menu;
  final String newBadge;
  final String continueReading;
  final String totalSize;
  final String chapterCountLabel;
  final String librarySubtitleTemplate;
  final String bookmarksSubtitleTemplate;
  final String latestReading;
  // Comic detail labels
  final String backToLibrary;
  final String directoryPath;
  final String lastRead;
  final String lastReadTemplate;
  final String readingProgress;
  final String readingProgressTemplate;
  final String startFromBeginning;
  final String filterChapters;
  final String allChapters;
  final String favoriteChapters;
  final String downloaded;
  // Settings panel
  final String librarySection;
  final String librarySource;
  final String librarySourceDescription;
  final String browseDirectory;
  final String refreshSourceStatus;
  final String readerSection;
  final String defaultZoom;
  final String pageGap;
  final String applicationSection;
  final String backupSection;
  final String exportBackup;
  final String importBackup;
  final String save;
  final String settingsSaved;
  final String backupExported;
  final String backupImported;
  // Scan
  final String scanLibrary;
  final String scanning;
  final String scanNoChange;
  final String scanProgress;
  final String scanCompleted;
  final String cancelScan;

  static const en = AppStrings(
    appName: 'ComicRD',
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
    refresh: 'Refresh',
    backToTop: 'Back to Top',
    totalChapters: 'chapters',
    emptyLibrary: 'No Comics Found',
    comic: 'Comic',
    english: 'English',
    indonesian: 'Indonesian',
    noPages: 'No Pages',
    close: 'Close',
    previousChapter: 'Previous Chapter',
    previousPage: 'Previous Page',
    nextPage: 'Next Page',
    nextChapter: 'Next Chapter',
    readerControls: 'Reader Controls',
    gap: 'Gap',
    zoom: 'Zoom',
    fullscreen: 'Fullscreen',
    unlimitedScroll: 'Unlimited Scroll',
    unlimitedScrollUp: 'Unlimited Scroll Up',
    read: 'Read',
    reading: 'Reading',
    unread: 'Unread',
    chapter: 'Chapter',
    name: 'Name',
    folderDate: 'Folder Date',
    all: 'All',
    progress: 'Progress',
    grid: 'Grid',
    list: 'List',
    sortDirection: 'Sort Direction',
    bookmark: 'Bookmark',
    bookmarked: 'Bookmarked',
    addBookmark: 'Add Bookmark',
    removeBookmark: 'Remove Bookmark',
    addFavorite: 'Add Favorite',
    removeFavorite: 'Remove Favorite',
    openFolder: 'Open Folder',
    copyTitle: 'Copy Title',
    copyPath: 'Copy Path',
    noLibrarySource: 'No Library Source Configured',
    menu: 'Menu',
    newBadge: 'New',
    continueReading: 'Continue',
    totalSize: 'Total Size',
    chapterCountLabel: 'Ch.',
    librarySubtitleTemplate: '{count} Titles Saved',
    bookmarksSubtitleTemplate: '{count} Titles Saved',
    latestReading: 'Latest Reading',
    backToLibrary: 'Back to Library',
    directoryPath: 'Directory Path',
    lastRead: 'Last Read',
    lastReadTemplate: '{chapter} ({date})',
    readingProgress: 'Reading Progress',
    readingProgressTemplate: '{percent}% ({read} of {total} chapters)',
    startFromBeginning: 'Start from Beginning',
    filterChapters: 'Filter Chapters...',
    allChapters: 'All Chapters',
    favoriteChapters: 'Favorites',
    downloaded: 'Downloaded',
    librarySection: 'Library',
    librarySource: 'Library Source',
    librarySourceDescription: 'The root folder containing your comics',
    browseDirectory: 'Browse Directory',
    refreshSourceStatus: 'Refresh Source Status',
    readerSection: 'Reader',
    defaultZoom: 'Default Zoom',
    pageGap: 'Page Gap',
    applicationSection: 'Application',
    backupSection: 'Backup',
    exportBackup: 'Export Backup',
    importBackup: 'Import Backup',
    save: 'Save',
    settingsSaved: 'Settings Saved',
    backupExported: 'Backup Exported',
    backupImported: 'Backup Imported',
    scanLibrary: 'Scan Library',
    scanning: 'Scanning...',
    scanNoChange: 'No Changes Detected',
    scanProgress: 'Scanning',
    scanCompleted: 'Scan Complete: {comics} Comics, {chapters} Chapters Found',
    cancelScan: 'Cancel Scan',
  );

  static const id = AppStrings(
    appName: 'ComicRD',
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
    refresh: 'Perbarui',
    backToTop: 'Kembali ke Atas',
    totalChapters: 'chapter',
    emptyLibrary: 'Tidak Ada Komik',
    comic: 'Komik',
    english: 'Inggris',
    indonesian: 'Indonesia',
    noPages: 'Tidak Ada Halaman',
    close: 'Tutup',
    previousChapter: 'Chapter Sebelumnya',
    previousPage: 'Halaman Sebelumnya',
    nextPage: 'Halaman Berikutnya',
    nextChapter: 'Chapter Berikutnya',
    readerControls: 'Kontrol Reader',
    gap: 'Jarak',
    zoom: 'Perbesar',
    fullscreen: 'Layar Penuh',
    unlimitedScroll: 'Scroll Tanpa Batas',
    unlimitedScrollUp: 'Scroll Tanpa Batas ke Atas',
    read: 'Dibaca',
    reading: 'Sedang Dibaca',
    unread: 'Belum Dibaca',
    chapter: 'Chapter',
    name: 'Nama',
    folderDate: 'Tanggal Folder',
    all: 'Semua',
    progress: 'Progres',
    grid: 'Kisi',
    list: 'Daftar',
    sortDirection: 'Arah Urutan',
    bookmark: 'Bookmark',
    bookmarked: 'Dibookmark',
    addBookmark: 'Tambah Bookmark',
    removeBookmark: 'Hapus Bookmark',
    addFavorite: 'Tambah Favorit',
    removeFavorite: 'Hapus Favorit',
    openFolder: 'Buka Folder',
    copyTitle: 'Salin Judul',
    copyPath: 'Salin Path',
    noLibrarySource: 'Sumber Pustaka Belum Dikonfigurasi',
    menu: 'Menu',
    newBadge: 'Baru',
    continueReading: 'Lanjut',
    totalSize: 'Total Ukuran',
    chapterCountLabel: 'Ch.',
    librarySubtitleTemplate: '{count} Judul Tersimpan',
    bookmarksSubtitleTemplate: '{count} Judul Disimpan',
    latestReading: 'Bacaan Terakhir',
    backToLibrary: 'Kembali ke Pustaka',
    directoryPath: 'Path Direktori',
    lastRead: 'Terakhir Dibaca',
    lastReadTemplate: '{chapter} ({date})',
    readingProgress: 'Progres Baca',
    readingProgressTemplate: '{percent}% ({read} dari {total} chapter)',
    startFromBeginning: 'Mulai dari Awal',
    filterChapters: 'Filter Chapter...',
    allChapters: 'Semua Chapter',
    favoriteChapters: 'Favorit',
    downloaded: 'Diunduh',
    librarySection: 'Pustaka',
    librarySource: 'Sumber Pustaka',
    librarySourceDescription: 'Folder root yang berisi komik Anda',
    browseDirectory: 'Pilih Direktori',
    refreshSourceStatus: 'Perbarui Status Sumber',
    readerSection: 'Reader',
    defaultZoom: 'Zoom Default',
    pageGap: 'Jarak Halaman',
    applicationSection: 'Aplikasi',
    backupSection: 'Cadangan',
    exportBackup: 'Ekspor Cadangan',
    importBackup: 'Impor Cadangan',
    save: 'Simpan',
    settingsSaved: 'Pengaturan Disimpan',
    backupExported: 'Cadangan Diekspor',
    backupImported: 'Cadangan Diimpor',
    scanLibrary: 'Pindai Pustaka',
    scanning: 'Memindai...',
    scanNoChange: 'Tidak Ada Perubahan',
    scanProgress: 'Memindai',
    scanCompleted:
        'Pemindaian Selesai: {comics} Komik, {chapters} Chapter Ditemukan',
    cancelScan: 'Batalkan Pemindaian',
  );
}
