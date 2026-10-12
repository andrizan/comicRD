// Shared in-memory ComicRdApi for widget tests: a small library with
// progress, history, favorites, bookmarks and one readable chapter, plus
// call recording so tests can assert what the UI asked Rust to do.
import 'dart:typed_data';

import 'package:comicrd_flutter/api/comicrd_api.dart';
import 'package:comicrd_flutter/bridge_generated.dart' as bridge;

const fakeRoot = '/library';
const fakeFeaturedPath = '$fakeRoot/Penjaga Senja';
const fakeReaderChapterId = 7;

bridge.RawComic fakeComic(
  String title, {
  int chapters = 10,
  int read = 0,
  int inProgress = 0,
  int dateModified = 1700000000,
  int sizeBytes = 1024 * 1024,
}) {
  return bridge.RawComic(
    title: title,
    sourcePath: '$fakeRoot/$title',
    sourceType: 'folder',
    dateModified: dateModified,
    chapterCount: chapters,
    readChapterCount: read,
    inProgressChapterCount: inProgress,
    sizeBytes: sizeBytes,
  );
}

bridge.RawChapter fakeChapter(
  String comicPath,
  int index, {
  bool isRead = false,
  int lastPage = 0,
  int totalPages = 20,
  int progressUpdatedAt = 0,
  int dateModified = 1700000000,
}) {
  return bridge.RawChapter(
    title: 'Chapter $index',
    chapterIndex: index,
    sourcePath: '$comicPath/Chapter $index',
    sourceType: 'folder',
    dateModified: dateModified,
    pageCount: totalPages,
    isRead: isRead,
    lastPage: lastPage,
    totalPages: totalPages,
    sizeBytes: 5 * 1024 * 1024,
    progressUpdatedAt: progressUpdatedAt,
  );
}

bridge.ReadingHistoryEntry fakeHistory(
  String title,
  String chapter, {
  required int chapterId,
  int lastPage = 0,
  int totalPages = 20,
  bool isRead = false,
  int updatedAt = 1700000000,
}) {
  return bridge.ReadingHistoryEntry(
    comicSourcePath: '$fakeRoot/$title',
    comicTitle: title,
    chapterTitle: chapter,
    chapterSourcePath: '$fakeRoot/$title/$chapter',
    chapterId: chapterId,
    lastPage: lastPage,
    totalPages: totalPages,
    isRead: isRead,
    updatedAt: updatedAt,
  );
}

class FakeComicRdApi extends ComicRdApi {
  FakeComicRdApi({
    this.configured = true,
    this.sourceError,
    this.locale = 'en',
    this.theme = 'light',
    this.extraSettings = const {},
    List<bridge.RawComic>? comics,
    List<bridge.ReadingHistoryEntry>? history,
    Set<String>? favorites,
    Map<String, List<bridge.RawChapter>>? chapters,
    Set<String>? chapterBookmarks,
    this.pageCount = 12,
    this.lastPage = 0,
    Set<int>? pageBookmarks,
    this.scanStarts = true,
    this.dbSizeBytes = 2048,
  }) : comics = comics ?? defaultComics(),
       history = history ?? defaultHistory(),
       favorites = favorites ?? {fakeFeaturedPath, '$fakeRoot/Atlas Kucing'},
       chapters = chapters ?? {},
       chapterBookmarks = chapterBookmarks ?? {'$fakeFeaturedPath/Chapter 3'},
       pageBookmarks = pageBookmarks ?? {2};

  static List<bridge.RawComic> defaultComics() => [
    fakeComic('Penjaga Senja', chapters: 30, read: 24, inProgress: 2),
    fakeComic('Kota di Bawah Hujan', chapters: 22, read: 2, inProgress: 1),
    fakeComic(
      'Samudra Kertas',
      chapters: 18,
      dateModified: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    ),
    fakeComic('Atlas Kucing', chapters: 12),
  ];

  static List<bridge.ReadingHistoryEntry> defaultHistory() => [
    fakeHistory(
      'Penjaga Senja',
      'Chapter 27',
      chapterId: fakeReaderChapterId,
      lastPage: 11,
      totalPages: 34,
    ),
    fakeHistory(
      'Kota di Bawah Hujan',
      'Chapter 4',
      chapterId: 12,
      lastPage: 2,
      totalPages: 22,
    ),
    fakeHistory(
      'Atlas Kucing',
      'Chapter 12',
      chapterId: 40,
      lastPage: 19,
      totalPages: 20,
      isRead: true,
    ),
  ];

  final bool configured;
  final String? sourceError;
  final String locale;
  final String theme;
  final Map<String, String> extraSettings;
  final List<bridge.RawComic> comics;
  final List<bridge.ReadingHistoryEntry> history;
  final Set<String> favorites;
  final Map<String, List<bridge.RawChapter>> chapters;
  final Set<String> chapterBookmarks;
  final int pageCount;
  final int lastPage;
  final Set<int> pageBookmarks;
  final bool scanStarts;
  int dbSizeBytes;

  // Recorded calls.
  final savedSettings = <String, String>{};
  final addedLibraries = <String>[];
  final addFavoriteCalls = <String>[];
  final removeFavoriteCalls = <String>[];
  final addBookmarkCalls = <String>[];
  final removeBookmarkCalls = <String>[];
  final openedFolders = <String>[];
  final copiedTitles = <String>[];
  final openedChapters = <bridge.OpenChapterPayload>[];
  final savedProgress = <bridge.SaveProgressPayload>[];
  final addedPageBookmarks = <int>[];
  final removedPageBookmarks = <int>[];
  final loadedChapterIds = <int>[];
  final exportedBackups = <String>[];
  final importedBackups = <String>[];
  int listComicsCalls = 0;
  int purgeCalls = 0;
  int scanStartCalls = 0;
  int scanCancelCalls = 0;
  int optimizeCalls = 0;
  bool scanRunning = false;
  bridge.ScanProgress? scanProgress;

  @override
  Future<List<bridge.SettingEntry>> listSettings() async {
    final entries = <String, String>{
      'library_source_input': configured ? '"$fakeRoot"' : '""',
      'default_zoom': '1',
      'page_gap': '12',
      'unlimited_scroll': 'true',
      'unlimited_scroll_up': 'false',
      'app_theme': '"$theme"',
      'app_locale': '"$locale"',
      ...extraSettings,
    };
    return [
      for (final entry in entries.entries)
        bridge.SettingEntry(key: entry.key, valueJson: entry.value),
    ];
  }

  @override
  Future<void> setSetting(String key, String valueJson) async {
    savedSettings[key] = valueJson;
  }

  @override
  Future<String?> getSetting(String key) async => savedSettings[key];

  @override
  Future<int> addLibrary(String path) async {
    addedLibraries.add(path);
    return addedLibraries.length;
  }

  @override
  Future<bridge.LibrarySourceStatus> checkLibrarySource() async {
    return bridge.LibrarySourceStatus(
      configured: configured,
      path: configured ? fakeRoot : '',
      exists: configured && sourceError == null,
      isDir: configured && sourceError == null,
      readable: configured && sourceError == null,
      error: configured ? sourceError : null,
    );
  }

  @override
  Future<bridge.LibraryStorageStats> getLibraryStorageStats() async {
    return bridge.LibraryStorageStats(
      totalSizeBytes: comics.fold<int>(0, (s, c) => s + c.sizeBytes.toInt()),
      comicCount: comics.length,
    );
  }

  @override
  Future<List<bridge.RawComic>> listLibraryComicsRaw({
    required bridge.SortBy sortBy,
    required bridge.SortDir sortDir,
  }) async {
    listComicsCalls++;
    return List.of(comics);
  }

  @override
  Future<List<String>> listComicsWithProgress() async {
    return [
      for (final comic in comics)
        if (comic.readChapterCount + comic.inProgressChapterCount > 0)
          comic.sourcePath,
    ];
  }

  @override
  Future<List<bridge.ReadingHistoryEntry>> listReadingHistory() async {
    return List.of(history);
  }

  @override
  Future<List<bridge.Favorite>> listFavorites() async {
    var id = 0;
    return [
      for (final path in favorites)
        bridge.Favorite(
          id: ++id,
          comicSourcePath: path,
          comicTitle: path.split('/').last,
          createdAt: id,
        ),
    ];
  }

  @override
  Future<bool> isFavorited({required String comicSourcePath}) async {
    return favorites.contains(comicSourcePath);
  }

  @override
  Future<int> addFavorite({required String comicSourcePath}) async {
    addFavoriteCalls.add(comicSourcePath);
    favorites.add(comicSourcePath);
    return favorites.length;
  }

  @override
  Future<void> removeFavorite({required String comicSourcePath}) async {
    removeFavoriteCalls.add(comicSourcePath);
    favorites.remove(comicSourcePath);
  }

  @override
  Future<List<bridge.RawChapter>> listComicChaptersRaw(
    String comicSourcePath,
  ) async {
    final custom = chapters[comicSourcePath];
    if (custom != null) return custom;
    return [
      for (var index = 1; index <= 5; index++)
        fakeChapter(
          comicSourcePath,
          index,
          isRead: index <= 2,
          lastPage: index == 3 ? 7 : 0,
          progressUpdatedAt: index == 3 ? 1700000500 : 0,
        ),
    ];
  }

  @override
  Future<List<String>> listBookmarks({required String comicSourcePath}) async {
    return [
      for (final path in chapterBookmarks)
        if (path.startsWith('$comicSourcePath/')) path,
    ];
  }

  @override
  Future<int> addBookmark({
    required String chapterSourcePath,
    required String comicSourcePath,
  }) async {
    addBookmarkCalls.add(chapterSourcePath);
    chapterBookmarks.add(chapterSourcePath);
    return chapterBookmarks.length;
  }

  @override
  Future<void> removeBookmark({required String chapterSourcePath}) async {
    removeBookmarkCalls.add(chapterSourcePath);
    chapterBookmarks.remove(chapterSourcePath);
  }

  @override
  Future<Uint8List> getComicThumbnail(
    String sourcePath, {
    int maxWidth = 200,
    int maxHeight = 300,
  }) async {
    return Uint8List(0);
  }

  @override
  Future<void> openContainingFolder(String path) async {
    openedFolders.add(path);
  }

  @override
  Future<void> purgeCaches() async {
    purgeCalls++;
  }

  @override
  Future<bridge.LibraryScanStatus> getLibraryScanStatus() async {
    return bridge.LibraryScanStatus(
      running: scanRunning,
      lastSummary: scanRunning
          ? null
          : const bridge.ScanSummary(comics: 4, chapters: 82),
      progress: scanProgress,
    );
  }

  @override
  Future<bool> startScanLibraries() async {
    scanStartCalls++;
    if (scanStarts) scanRunning = true;
    return scanStarts;
  }

  @override
  Future<void> cancelScanLibraries() async {
    scanCancelCalls++;
    scanRunning = false;
  }

  @override
  Future<int> databaseSizeBytes() async => dbSizeBytes;

  @override
  Future<bridge.OptimizeDatabaseResult> optimizeDatabase() async {
    optimizeCalls++;
    final before = dbSizeBytes;
    dbSizeBytes = 1024;
    return bridge.OptimizeDatabaseResult(
      databaseSizeBefore: before,
      databaseSizeAfter: dbSizeBytes,
      removedComics: 1,
      removedChapters: 2,
      removedReadingProgress: 2,
      removedPageBookmarks: 1,
      removedChapterBookmarks: 1,
      removedFavorites: 0,
      removedThumbnails: 3,
      removedThumbnailBytes: 4096,
      skippedLibraryCount: 0,
    );
  }

  @override
  Future<void> exportDatabaseBackup(String outputPath) async {
    exportedBackups.add(outputPath);
  }

  @override
  Future<void> importDatabaseBackup(String inputPath) async {
    importedBackups.add(inputPath);
  }

  @override
  Future<int> openChapterForReading(bridge.OpenChapterPayload payload) async {
    openedChapters.add(payload);
    return fakeReaderChapterId;
  }

  @override
  Future<bridge.ChapterContext?> getChapterContext(int chapterId) async {
    return bridge.ChapterContext(
      chapterId: chapterId,
      comicId: 1,
      comicTitle: 'Penjaga Senja',
      title: 'Chapter 27',
      comicSourcePath: fakeFeaturedPath,
      chapterSourcePath: '$fakeFeaturedPath/Chapter 27',
      chapterIndex: 27,
      chapterPosition: 27,
      chapterTotal: 30,
      prevChapterId: chapterId - 1,
      nextChapterId: chapterId + 1,
    );
  }

  @override
  Future<List<bridge.PageInfo>> getChapterPages(int chapterId) async {
    loadedChapterIds.add(chapterId);
    return [
      for (var index = 0; index < pageCount; index++)
        bridge.PageInfo(
          index: index,
          name: '${index + 1}.png',
          width: 900,
          height: 1300,
          tileHeights: Uint32List.fromList(const [1300]),
        ),
    ];
  }

  @override
  Future<bridge.ReadingProgress?> getProgress(int chapterId) async {
    return bridge.ReadingProgress(
      chapterId: chapterId,
      lastPage: lastPage,
      totalPages: pageCount,
      isRead: false,
    );
  }

  @override
  Future<List<bridge.PageBookmark>> listPageBookmarks({
    required int chapterId,
  }) async {
    return [
      for (final page in pageBookmarks)
        bridge.PageBookmark(
          id: page + 1,
          chapterId: chapterId,
          page: page,
          createdAt: 0,
          note: '',
        ),
    ];
  }

  @override
  Future<int> addPageBookmark(bridge.SavePageBookmarkPayload payload) async {
    addedPageBookmarks.add(payload.page.toInt());
    pageBookmarks.add(payload.page.toInt());
    return payload.page.toInt() + 1;
  }

  @override
  Future<void> removePageBookmark({required int bookmarkId}) async {
    removedPageBookmarks.add(bookmarkId - 1);
    pageBookmarks.remove(bookmarkId - 1);
  }

  @override
  Future<bridge.RenderedPage> renderPageTile(
    bridge.RenderPageTilePayload payload,
  ) async {
    return bridge.RenderedPage(
      bytes: Uint8List.fromList(onePixelPng),
      mime: 'image/png',
      width: 900,
      height: 1300,
    );
  }

  @override
  Future<void> prefetchTiles(bridge.PrefetchTilesPayload payload) async {}

  @override
  Future<void> evictChapterPages({
    required int chapterId,
    required List<int> keepPages,
  }) async {}

  @override
  Future<void> saveProgress(bridge.SaveProgressPayload payload) async {
    savedProgress.add(payload);
  }
}

/// A valid 1×1 transparent PNG.
const onePixelPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x00, 0x02, 0x00, //
  0x00, 0x05, 0x00, 0x01, 0xE2, 0x26, 0x05, 0x9B, 0x00, 0x00, 0x00, 0x00, //
  0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82, //
];
