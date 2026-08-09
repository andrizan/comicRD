import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../bridge_generated.dart' as bridge;

class ComicRdApi {
  const ComicRdApi();

  Future<void> init({String? appDataDir}) async {
    await bridge.RustLib.init();
    final resolvedDir =
        appDataDir ?? (await getApplicationSupportDirectory()).path;
    await bridge.initApp(appDataDir: resolvedDir);
  }

  Future<void> shutdown() async {
    await bridge.shutdownApp();
    bridge.RustLib.dispose();
  }

  Future<bridge.LibrarySourceStatus> checkLibrarySource() =>
      bridge.checkLibrarySource();

  Future<int> addLibrary(String path) => bridge.addLibrary(path: path);

  Future<List<bridge.Library>> listLibraries() => bridge.listLibraries();

  Future<bool> startScanLibraries() => bridge.startScanLibraries();

  Future<void> cancelScanLibraries() => bridge.cancelScanLibraries();

  Future<bridge.LibraryScanStatus> getLibraryScanStatus() =>
      bridge.getLibraryScanStatus();

  Future<List<bridge.RawComic>> listLibraryComicsRaw({
    required bridge.SortBy sortBy,
    required bridge.SortDir sortDir,
  }) => bridge.listLibraryComicsRaw(sortBy: sortBy, sortDir: sortDir);

  Future<bridge.LibraryStorageStats> getLibraryStorageStats() =>
      bridge.getLibraryStorageStats();

  Future<Uint8List> getComicThumbnail(
    String sourcePath, {
    int maxWidth = 200,
    int maxHeight = 300,
  }) => bridge.getComicThumbnail(
    sourcePath: sourcePath,
    maxWidth: maxWidth,
    maxHeight: maxHeight,
  );

  Future<List<String>> listComicsWithProgress() =>
      bridge.listComicsWithProgress();

  Future<List<bridge.ReadingHistoryEntry>> listReadingHistory() =>
      bridge.listReadingHistory();

  Future<List<bridge.RawChapter>> listComicChaptersRaw(
    String comicSourcePath,
  ) => bridge.listComicChaptersRaw(comicSourcePath: comicSourcePath);

  Future<void> purgeCaches() => bridge.purgeCaches();

  Future<int> databaseSizeBytes() => bridge.databaseSizeBytes();

  Future<bridge.OptimizeDatabaseResult> optimizeDatabase() =>
      bridge.optimizeDatabase();

  Future<int> openChapterForReading(bridge.OpenChapterPayload payload) =>
      bridge.openChapterForReading(payload: payload);

  Future<bridge.ChapterContext?> getChapterContext(int chapterId) =>
      bridge.getChapterContext(chapterId: chapterId);

  Future<List<bridge.PageInfo>> getChapterPages(int chapterId) =>
      bridge.getChapterPages(chapterId: chapterId);

  Future<bridge.RenderedPage> renderPageVariant(
    bridge.RenderPagePayload payload,
  ) => bridge.renderPageVariant(payload: payload);

  Future<void> prefetchPages(bridge.PrefetchPagesPayload payload) =>
      bridge.prefetchPages(payload: payload);

  Future<void> evictChapterPages({
    required int chapterId,
    required List<int> keepPages,
  }) => bridge.evictChapterPages(chapterId: chapterId, keepPages: keepPages);

  Future<void> saveProgress(bridge.SaveProgressPayload payload) =>
      bridge.saveProgress(payload: payload);

  Future<bridge.ReadingProgress?> getProgress(int chapterId) =>
      bridge.getProgress(chapterId: chapterId);

  Future<List<bridge.PageBookmark>> listPageBookmarks({
    required int chapterId,
  }) => bridge.listPageBookmarks(chapterId: chapterId);

  Future<int> addPageBookmark(bridge.SavePageBookmarkPayload payload) =>
      bridge.addPageBookmark(payload: payload);

  Future<void> removePageBookmark({required int bookmarkId}) =>
      bridge.removePageBookmark(bookmarkId: bookmarkId);

  Future<List<bridge.Favorite>> listFavorites() => bridge.listFavorites();

  Future<int> addFavorite({required String comicSourcePath}) =>
      bridge.addFavorite(comicSourcePath: comicSourcePath);

  Future<void> removeFavorite({required String comicSourcePath}) =>
      bridge.removeFavorite(comicSourcePath: comicSourcePath);

  Future<bool> isFavorited({required String comicSourcePath}) =>
      bridge.isFavorited(comicSourcePath: comicSourcePath);

  Future<int> addBookmark({
    required String chapterSourcePath,
    required String comicSourcePath,
  }) => bridge.addBookmark(
    chapterSourcePath: chapterSourcePath,
    comicSourcePath: comicSourcePath,
  );

  Future<void> removeBookmark({required String chapterSourcePath}) =>
      bridge.removeBookmark(chapterSourcePath: chapterSourcePath);

  Future<List<String>> listBookmarks({required String comicSourcePath}) =>
      bridge.listBookmarks(comicSourcePath: comicSourcePath);

  Future<List<bridge.SettingEntry>> listSettings() => bridge.listSettings();

  Future<String?> getSetting(String key) => bridge.getSetting(key: key);

  Future<void> setSetting(String key, String valueJson) =>
      bridge.setSetting(key: key, valueJson: valueJson);

  Future<void> exportDatabaseBackup(String outputPath) =>
      bridge.exportDatabaseBackup(outputPath: outputPath);

  Future<void> importDatabaseBackup(String inputPath) =>
      bridge.importDatabaseBackup(inputPath: inputPath);

  Future<void> openContainingFolder(String path) =>
      bridge.openContainingFolder(path: path);
}
