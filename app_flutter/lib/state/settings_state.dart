import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
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
    this.forcePortrait = false,
  });

  final double zoom;
  final double pageGap;
  final bool unlimitedScroll;
  final bool unlimitedScrollUp;
  final bool forcePortrait;

  ReaderSettings copyWith({
    double? zoom,
    double? pageGap,
    bool? unlimitedScroll,
    bool? unlimitedScrollUp,
    bool? forcePortrait,
  }) => ReaderSettings(
    zoom: zoom ?? this.zoom,
    pageGap: pageGap ?? this.pageGap,
    unlimitedScroll: unlimitedScroll ?? this.unlimitedScroll,
    unlimitedScrollUp: unlimitedScrollUp ?? this.unlimitedScrollUp,
    forcePortrait: forcePortrait ?? this.forcePortrait,
  );
}

class ReaderSettingsNotifier extends Notifier<ReaderSettings> {
  @override
  ReaderSettings build() => const ReaderSettings();

  void setZoom(double zoom) {
    state = state.copyWith(zoom: zoom.clamp(0.2, 1.5));
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

  void setForcePortrait(bool value) {
    state = state.copyWith(forcePortrait: value);
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
    unawaited(api.setSetting('force_portrait', state.forcePortrait.toString()));
  }

  void hydrateFromSettings(Map<String, String> values) {
    final zoom = _decodeDouble(values['default_zoom'], 1.0);
    final gap = _decodeDouble(values['page_gap'], 20.0);
    final unlimitedScroll = _decodeBool(values['unlimited_scroll'], false);
    final unlimitedScrollUp = _decodeBool(values['unlimited_scroll_up'], true);
    final forcePortrait = _decodeBool(values['force_portrait'], false);
    state = ReaderSettings(
      zoom: zoom.clamp(0.2, 1.5),
      pageGap: gap.clamp(0, 80),
      unlimitedScroll: unlimitedScroll,
      unlimitedScrollUp: unlimitedScrollUp,
      forcePortrait: forcePortrait,
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
    required this.favorites,
    required this.search,
    required this.refresh,
    required this.backToTop,
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
    required this.zoom,
    required this.fullscreen,
    required this.unlimitedScroll,
    required this.unlimitedScrollUp,
    required this.forcePortrait,
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
    // Comic actions
    required this.addPageBookmark,
    required this.removePageBookmark,
    required this.addBookmark,
    required this.removeBookmark,
    required this.addFavorite,
    required this.removeFavorite,
    required this.openFolder,
    required this.copyTitle,
    required this.copyPath,
    // Redesign labels
    required this.menu,
    required this.newBadge,
    required this.continueReading,
    required this.totalSize,
    required this.librarySubtitleTemplate,
    required this.favoritesSubtitleTemplate,
    required this.latestReading,
    // Comic detail labels
    required this.backToLibrary,
    required this.directoryPath,
    required this.lastRead,
    required this.readingProgress,
    required this.readingProgressTemplate,
    required this.startFromBeginning,
    required this.filterChapters,
    required this.bookmarkChapters,
    // Settings panel
    required this.librarySection,
    required this.librarySource,
    required this.librarySourceDescription,
    required this.refreshSourceStatus,
    required this.readerSection,
    required this.defaultZoom,
    required this.defaultZoomDescription,
    required this.pageGap,
    required this.pageGapDescription,
    // Update
    required this.checkForUpdates,
    required this.checkingForUpdates,
    required this.appUpToDate,
    required this.updateAvailable,
    required this.downloadUpdate,
    required this.viewRelease,
    required this.updateCheckFailed,
    // About
    required this.aboutSection,
    required this.aboutDescription,
    required this.viewOnGithub,
    required this.exportBackup,
    required this.exportBackupDescription,
    required this.importBackup,
    required this.importBackupDescription,
    required this.save,
    required this.settingsSaved,
    required this.backupExported,
    required this.backupImported,
    // Optimize Data
    required this.optimizeData,
    required this.optimizeDataDescription,
    required this.databaseSize,
    required this.optimizeDataCompleted,
    required this.optimizeRemovedComics,
    required this.optimizeRemovedChapters,
    required this.optimizeRemovedBookmarks,
    required this.optimizeRemovedFavorites,
    required this.optimizeRemovedThumbnails,
    required this.optimizeFreedSpace,
    required this.optimizeSkippedLibraries,
    // Scan
    required this.scanLibrary,
    required this.scanLibraryDescription,
    required this.scanning,
    required this.scanNoChange,
    required this.scanProgress,
    required this.scanCompleted,
    // Per-setting descriptions (Win 11-style cards)
    required this.themeDescription,
    required this.localeDescription,
    required this.unlimitedScrollDescription,
    required this.unlimitedScrollUpDescription,
    required this.settingsDescription,
    // Soft redesign
    required this.continueReadingSection,
    required this.viewHistory,
    required this.sortLabel,
    required this.sortAscending,
    required this.sortDescending,
    required this.chaptersCountTemplate,
    required this.chaptersReadTemplate,
    required this.chaptersDoneTemplate,
    required this.pageOfTemplate,
    required this.chapterPageTemplate,
    required this.finished,
    required this.readAgain,
    required this.localLibrary,
    required this.connected,
    required this.notConfigured,
    required this.unavailable,
    required this.pickComicFolder,
    required this.changeFolder,
    required this.worksOffline,
    required this.welcomeTitle,
    required this.welcomeBody,
    required this.haveBackupImport,
    required this.supported,
    required this.imageFolder,
    required this.folderStructureTitle,
    required this.folderStructureNote,
    required this.libraryFolderTag,
    required this.oneTitleTag,
    required this.chapterTag,
    required this.markPanel,
    required this.displayPanel,
    required this.pageBookmarkedTemplate,
    required this.pageNotBookmarkedTemplate,
    required this.chapterBookmarkedTemplate,
    required this.chapterNotBookmarkedTemplate,
    required this.inFavoritesTemplate,
    required this.notInFavoritesTemplate,
    required this.forcePortraitDescription,
    required this.keyExit,
    required this.keyScroll,
    required this.keySwitchChapter,
    required this.appearanceSection,
    required this.dataSection,
    required this.updateAboutSection,
    required this.exportAction,
    required this.importAction,
    required this.optimizeAction,
    required this.cancel,
    required this.scanProgressTemplate,
    required this.titlesCountTemplate,
    required this.pagesCountTemplate,
    required this.moreActions,
    required this.keyFirstPage,
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
  final String favorites;
  final String search;
  final String refresh;
  final String backToTop;
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
  final String zoom;
  final String fullscreen;
  final String unlimitedScroll;
  final String unlimitedScrollUp;
  final String forcePortrait;
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
  // Comic actions
  final String addPageBookmark;
  final String removePageBookmark;
  final String addBookmark;
  final String removeBookmark;
  final String addFavorite;
  final String removeFavorite;
  final String openFolder;
  final String copyTitle;
  final String copyPath;
  // Redesign labels
  final String menu;
  final String newBadge;
  final String continueReading;
  final String totalSize;
  final String librarySubtitleTemplate;
  final String favoritesSubtitleTemplate;
  final String latestReading;
  // Comic detail labels
  final String backToLibrary;
  final String directoryPath;
  final String lastRead;
  final String readingProgress;
  final String readingProgressTemplate;
  final String startFromBeginning;
  final String filterChapters;
  final String bookmarkChapters;
  // Settings panel
  final String librarySection;
  final String librarySource;
  final String librarySourceDescription;
  final String refreshSourceStatus;
  final String readerSection;
  final String defaultZoom;
  final String defaultZoomDescription;
  final String pageGap;
  final String pageGapDescription;
  // Update
  final String checkForUpdates;
  final String checkingForUpdates;
  final String appUpToDate;
  final String updateAvailable;
  final String downloadUpdate;
  final String viewRelease;
  final String updateCheckFailed;
  // About
  final String aboutSection;
  final String aboutDescription;
  final String viewOnGithub;
  final String exportBackup;
  final String exportBackupDescription;
  final String importBackup;
  final String importBackupDescription;
  final String save;
  final String settingsSaved;
  final String backupExported;
  final String backupImported;
  // Optimize Data
  final String optimizeData;
  final String optimizeDataDescription;
  final String databaseSize;
  final String optimizeDataCompleted;
  final String optimizeRemovedComics;
  final String optimizeRemovedChapters;
  final String optimizeRemovedBookmarks;
  final String optimizeRemovedFavorites;
  final String optimizeRemovedThumbnails;
  final String optimizeFreedSpace;
  final String optimizeSkippedLibraries;
  // Scan
  final String scanLibrary;
  final String scanLibraryDescription;
  final String scanning;
  final String scanNoChange;
  final String scanProgress;
  final String scanCompleted;
  // Per-setting descriptions (Win 11-style cards)
  final String themeDescription;
  final String localeDescription;
  final String unlimitedScrollDescription;
  final String unlimitedScrollUpDescription;
  final String settingsDescription;
  // Soft redesign
  final String continueReadingSection;
  final String viewHistory;
  final String sortLabel;
  final String sortAscending;
  final String sortDescending;
  final String chaptersCountTemplate;
  final String chaptersReadTemplate;
  final String chaptersDoneTemplate;
  final String pageOfTemplate;
  final String chapterPageTemplate;
  final String finished;
  final String readAgain;
  final String localLibrary;
  final String connected;
  final String notConfigured;
  final String unavailable;
  final String pickComicFolder;
  final String changeFolder;
  final String worksOffline;
  final String welcomeTitle;
  final String welcomeBody;
  final String haveBackupImport;
  final String supported;
  final String imageFolder;
  final String folderStructureTitle;
  final String folderStructureNote;
  final String libraryFolderTag;
  final String oneTitleTag;
  final String chapterTag;
  final String markPanel;
  final String displayPanel;
  final String pageBookmarkedTemplate;
  final String pageNotBookmarkedTemplate;
  final String chapterBookmarkedTemplate;
  final String chapterNotBookmarkedTemplate;
  final String inFavoritesTemplate;
  final String notInFavoritesTemplate;
  final String forcePortraitDescription;
  final String keyExit;
  final String keyScroll;
  final String keySwitchChapter;
  final String appearanceSection;
  final String dataSection;
  final String updateAboutSection;
  final String exportAction;
  final String importAction;
  final String optimizeAction;
  final String cancel;
  final String scanProgressTemplate;
  final String titlesCountTemplate;
  final String pagesCountTemplate;
  final String moreActions;
  final String keyFirstPage;

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
    favorites: 'Favorites',
    search: 'Search',
    refresh: 'Refresh',
    backToTop: 'Back to Top',
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
    zoom: 'Zoom',
    fullscreen: 'Fullscreen',
    unlimitedScroll: 'Unlimited Scroll',
    unlimitedScrollUp: 'Unlimited Scroll Up',
    forcePortrait: 'Force Portrait',
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
    addPageBookmark: 'Add Page Bookmark',
    removePageBookmark: 'Remove Page Bookmark',
    addBookmark: 'Add Bookmark',
    removeBookmark: 'Remove Bookmark',
    addFavorite: 'Add Favorite',
    removeFavorite: 'Remove Favorite',
    openFolder: 'Open Folder',
    copyTitle: 'Copy Title',
    copyPath: 'Copy Path',
    menu: 'Menu',
    newBadge: 'New',
    continueReading: 'Continue',
    totalSize: 'Total Size',
    librarySubtitleTemplate: '{count} Titles Saved',
    favoritesSubtitleTemplate: '{count} Titles Saved',
    latestReading: 'Latest Reading',
    backToLibrary: 'Back to Library',
    directoryPath: 'Directory Path',
    lastRead: 'Last Read',
    readingProgress: 'Reading Progress',
    readingProgressTemplate: '{percent}% ({read} of {total} chapters)',
    startFromBeginning: 'Start from Beginning',
    filterChapters: 'Filter Chapters...',
    bookmarkChapters: 'Bookmarks',
    librarySection: 'Library',
    librarySource: 'Library Source',
    librarySourceDescription: 'The root folder containing your comics',
    refreshSourceStatus: 'Refresh Source Status',
    readerSection: 'Reader',
    defaultZoom: 'Default Zoom',
    defaultZoomDescription: 'Set the default zoom level for pages',
    pageGap: 'Page Gap',
    pageGapDescription: 'Spacing between pages',
    checkForUpdates: 'Check for Updates',
    checkingForUpdates: 'Checking...',
    appUpToDate: 'App is up to date',
    updateAvailable: 'Update available',
    downloadUpdate: 'Download Installer',
    viewRelease: 'View Release',
    updateCheckFailed: 'Could not check for updates',
    aboutSection: 'About',
    aboutDescription: 'A desktop comic reader for local libraries.',
    viewOnGithub: 'View on GitHub',
    exportBackup: 'Export Backup',
    exportBackupDescription: 'Export your database to a backup file',
    importBackup: 'Import Backup',
    importBackupDescription: 'Import a backup file to restore your data',
    save: 'Save',
    settingsSaved: 'Settings Saved',
    backupExported: 'Backup Exported',
    backupImported: 'Backup Imported',
    optimizeData: 'Optimize Data',
    optimizeDataDescription:
        'Remove data for comics no longer on disk and shrink the database',
    databaseSize: 'Database Size',
    optimizeDataCompleted: 'Optimization Complete',
    optimizeRemovedComics: '{count} comics removed',
    optimizeRemovedChapters: '{count} chapters removed',
    optimizeRemovedBookmarks: '{count} bookmarks removed',
    optimizeRemovedFavorites: '{count} favorites removed',
    optimizeRemovedThumbnails: '{count} cover images removed',
    optimizeFreedSpace: '{size} of space freed',
    optimizeSkippedLibraries: '{count} library path(s) unavailable, skipped',
    scanLibrary: 'Scan Library',
    scanLibraryDescription: 'Scan your library for new comics',
    scanning: 'Scanning...',
    scanNoChange: 'No Changes Detected',
    scanProgress: 'Scanning',
    scanCompleted: 'Scan Complete: {comics} Comics, {chapters} Chapters Found',
    themeDescription: 'Choose the app theme',
    localeDescription: 'Choose the app language',
    unlimitedScrollDescription: 'Continue to next chapter at the end',
    unlimitedScrollUpDescription: 'Continue to previous chapter at the top',
    settingsDescription: 'Manage your library, reader, and app preferences.',
    continueReadingSection: 'Continue Reading',
    viewHistory: 'View History',
    sortLabel: 'Sort',
    sortAscending: 'Ascending',
    sortDescending: 'Descending',
    chaptersCountTemplate: '{count} chapters',
    chaptersReadTemplate: '{read} of {total} chapters',
    chaptersDoneTemplate: '{read} of {total} chapters finished',
    pageOfTemplate: 'Page {page} of {total}',
    chapterPageTemplate: '{chapter} · page {page} of {total}',
    finished: 'Finished',
    readAgain: 'Read Again',
    localLibrary: 'Local Library',
    connected: 'Connected',
    notConfigured: 'Not Configured',
    unavailable: 'Unavailable',
    pickComicFolder: 'Choose Comic Folder',
    changeFolder: 'Change Folder',
    worksOffline: 'Works Fully Offline',
    welcomeTitle: 'Read comics from a folder on your computer.',
    welcomeBody:
        'ComicRD reads straight from folders and archives on your device, with no account and no internet. Pick one parent folder; the rest is scanned automatically.',
    haveBackupImport: 'Have a backup? Import it',
    supported: 'Supported',
    imageFolder: 'Image Folder',
    folderStructureTitle: 'Example Folder Structure',
    folderStructureNote:
        'One folder or archive inside the library folder is one title. Subfolders or archives inside it are chapters. You can change the folder anytime in Settings.',
    libraryFolderTag: 'library folder',
    oneTitleTag: '1 title',
    chapterTag: 'chapter',
    markPanel: 'Mark',
    displayPanel: 'Display',
    pageBookmarkedTemplate: 'Page {page} is bookmarked',
    pageNotBookmarkedTemplate: 'Page {page} is not bookmarked',
    chapterBookmarkedTemplate: '{chapter} is bookmarked',
    chapterNotBookmarkedTemplate: '{chapter} is not bookmarked',
    inFavoritesTemplate: '{comic} is in favorites',
    notInFavoritesTemplate: '{comic} is not in favorites',
    forcePortraitDescription: 'Same width for every page',
    keyExit: 'exit',
    keyScroll: 'scroll',
    keySwitchChapter: 'switch chapter',
    appearanceSection: 'Appearance',
    dataSection: 'Data & Backup',
    updateAboutSection: 'Update & About',
    exportAction: 'Export',
    importAction: 'Import',
    optimizeAction: 'Optimize',
    cancel: 'Cancel',
    scanProgressTemplate: 'Scanning · {processed} of {total}',
    titlesCountTemplate: '{count} titles',
    pagesCountTemplate: '{count} pages',
    moreActions: 'More Actions',
    keyFirstPage: 'first page',
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
    favorites: 'Favorit',
    search: 'Cari',
    refresh: 'Perbarui',
    backToTop: 'Kembali ke Atas',
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
    zoom: 'Perbesar',
    fullscreen: 'Layar Penuh',
    unlimitedScroll: 'Scroll Tanpa Batas',
    unlimitedScrollUp: 'Scroll Tanpa Batas ke Atas',
    forcePortrait: 'Mode Potret',
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
    addPageBookmark: 'Bookmark Halaman',
    removePageBookmark: 'Hapus Bookmark Halaman',
    addBookmark: 'Bookmark Chapter',
    removeBookmark: 'Hapus Bookmark Chapter',
    addFavorite: 'Tambah Favorit',
    removeFavorite: 'Hapus Favorit',
    openFolder: 'Buka Folder',
    copyTitle: 'Salin Judul',
    copyPath: 'Salin Path',
    menu: 'Menu',
    newBadge: 'Baru',
    continueReading: 'Lanjut',
    totalSize: 'Total Ukuran',
    librarySubtitleTemplate: '{count} Judul Tersimpan',
    favoritesSubtitleTemplate: '{count} Judul Disimpan',
    latestReading: 'Bacaan Terakhir',
    backToLibrary: 'Kembali ke Pustaka',
    directoryPath: 'Path Direktori',
    lastRead: 'Terakhir Dibaca',
    readingProgress: 'Progres Baca',
    readingProgressTemplate: '{percent}% ({read} dari {total} chapter)',
    startFromBeginning: 'Mulai dari Awal',
    filterChapters: 'Filter Chapter...',
    bookmarkChapters: 'Bookmark',
    librarySection: 'Pustaka',
    librarySource: 'Sumber Pustaka',
    librarySourceDescription: 'Folder root yang berisi komik Anda',
    refreshSourceStatus: 'Perbarui Status Sumber',
    readerSection: 'Reader',
    defaultZoom: 'Zoom Default',
    defaultZoomDescription: 'Atur level zoom default untuk halaman',
    pageGap: 'Jarak Halaman',
    pageGapDescription: 'Jarak antar halaman',
    checkForUpdates: 'Periksa Pembaruan',
    checkingForUpdates: 'Memeriksa...',
    appUpToDate: 'Aplikasi sudah terbaru',
    updateAvailable: 'Pembaruan tersedia',
    downloadUpdate: 'Unduh Installer',
    viewRelease: 'Lihat Rilis',
    updateCheckFailed: 'Gagal memeriksa pembaruan',
    aboutSection: 'Tentang',
    aboutDescription: 'Pembaca komik desktop untuk pustaka lokal.',
    viewOnGithub: 'Lihat di GitHub',
    exportBackup: 'Ekspor Cadangan',
    exportBackupDescription: 'Ekspor database ke file cadangan',
    importBackup: 'Impor Cadangan',
    importBackupDescription: 'Impor file cadangan untuk memulihkan data',
    save: 'Simpan',
    settingsSaved: 'Pengaturan Disimpan',
    backupExported: 'Cadangan Diekspor',
    backupImported: 'Cadangan Diimpor',
    optimizeData: 'Optimalkan Data',
    optimizeDataDescription:
        'Hapus data komik yang sudah tidak ada di disk dan perkecil database',
    databaseSize: 'Ukuran Database',
    optimizeDataCompleted: 'Optimasi Selesai',
    optimizeRemovedComics: '{count} komik dihapus',
    optimizeRemovedChapters: '{count} chapter dihapus',
    optimizeRemovedBookmarks: '{count} bookmark dihapus',
    optimizeRemovedFavorites: '{count} favorit dihapus',
    optimizeRemovedThumbnails: '{count} cover dihapus',
    optimizeFreedSpace: '{size} ruang dibebaskan',
    optimizeSkippedLibraries: '{count} jalur pustaka tidak tersedia, dilewati',
    scanLibrary: 'Pindai Pustaka',
    scanLibraryDescription: 'Pindai pustaka untuk komik baru',
    scanning: 'Memindai...',
    scanNoChange: 'Tidak Ada Perubahan',
    scanProgress: 'Memindai',
    scanCompleted:
        'Pemindaian Selesai: {comics} Komik, {chapters} Chapter Ditemukan',
    themeDescription: 'Pilih tema aplikasi',
    localeDescription: 'Pilih bahasa aplikasi',
    unlimitedScrollDescription: 'Lanjut ke chapter berikutnya di akhir',
    unlimitedScrollUpDescription: 'Lanjut ke chapter sebelumnya di awal',
    settingsDescription:
        'Kelola pustaka, pembaca, dan preferensi aplikasi Anda.',
    continueReadingSection: 'Lanjut Membaca',
    viewHistory: 'Lihat Riwayat',
    sortLabel: 'Urutkan',
    sortAscending: 'Menaik',
    sortDescending: 'Menurun',
    chaptersCountTemplate: '{count} chapter',
    chaptersReadTemplate: '{read} dari {total} chapter',
    chaptersDoneTemplate: '{read} dari {total} chapter selesai',
    pageOfTemplate: 'Halaman {page} dari {total}',
    chapterPageTemplate: '{chapter} · halaman {page} dari {total}',
    finished: 'Selesai',
    readAgain: 'Baca Lagi',
    localLibrary: 'Pustaka Lokal',
    connected: 'Terhubung',
    notConfigured: 'Belum Diatur',
    unavailable: 'Tidak Tersedia',
    pickComicFolder: 'Pilih Folder Komik',
    changeFolder: 'Ganti Folder',
    worksOffline: 'Bekerja Sepenuhnya Offline',
    welcomeTitle: 'Baca komik dari folder di komputermu.',
    welcomeBody:
        'ComicRD membaca langsung dari folder dan arsip di perangkatmu, tanpa akun dan tanpa internet. Pilih satu folder induk, sisanya dipindai otomatis.',
    haveBackupImport: 'Sudah punya cadangan? Impor cadangan',
    supported: 'Didukung',
    imageFolder: 'Folder Gambar',
    folderStructureTitle: 'Contoh Struktur Folder',
    folderStructureNote:
        'Satu folder atau arsip di dalam folder pustaka adalah satu judul. Subfolder atau arsip di dalamnya adalah chapter. Folder bisa diganti kapan saja di Pengaturan.',
    libraryFolderTag: 'folder pustaka',
    oneTitleTag: '1 judul',
    chapterTag: 'chapter',
    markPanel: 'Tandai',
    displayPanel: 'Tampilan',
    pageBookmarkedTemplate: 'Halaman {page} sudah ditandai',
    pageNotBookmarkedTemplate: 'Halaman {page} belum ditandai',
    chapterBookmarkedTemplate: '{chapter} sudah ditandai',
    chapterNotBookmarkedTemplate: '{chapter} belum ditandai',
    inFavoritesTemplate: '{comic} ada di favorit',
    notInFavoritesTemplate: '{comic} belum di favorit',
    forcePortraitDescription: 'Samakan lebar semua halaman',
    keyExit: 'keluar',
    keyScroll: 'scroll',
    keySwitchChapter: 'ganti chapter',
    appearanceSection: 'Tampilan',
    dataSection: 'Data & Cadangan',
    updateAboutSection: 'Pembaruan & Tentang',
    exportAction: 'Ekspor',
    importAction: 'Impor',
    optimizeAction: 'Optimalkan',
    cancel: 'Batalkan',
    scanProgressTemplate: 'Memindai · {processed} dari {total}',
    titlesCountTemplate: '{count} judul',
    pagesCountTemplate: '{count} halaman',
    moreActions: 'Aksi Lainnya',
    keyFirstPage: 'halaman pertama',
  );
}
