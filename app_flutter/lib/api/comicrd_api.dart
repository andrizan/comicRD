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

  Future<bridge.ScanSummary> scanLibraries() => bridge.scanLibraries();

  Future<bool> startScanLibraries() => bridge.startScanLibraries();

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

  Future<List<bridge.Bookmark>> listBookmarks(int chapterId) =>
      bridge.listBookmarks(chapterId: chapterId);

  Future<int> addBookmark(bridge.SaveBookmarkPayload payload) =>
      bridge.addBookmark(payload: payload);

  Future<void> removeBookmark(int bookmarkId) =>
      bridge.removeBookmark(bookmarkId: bookmarkId);

  Future<List<bridge.ComicBookmark>> listAllBookmarks() =>
      bridge.listAllBookmarks();

  Future<int> addComicBookmark(String comicSourcePath) =>
      bridge.addComicBookmark(comicSourcePath: comicSourcePath);

  Future<void> removeComicBookmark(String comicSourcePath) =>
      bridge.removeComicBookmark(comicSourcePath: comicSourcePath);

  Future<bool> isComicBookmarked(String comicSourcePath) =>
      bridge.isComicBookmarked(comicSourcePath: comicSourcePath);

  Future<int> addChapterFavorite({
    required String chapterSourcePath,
    required String comicSourcePath,
  }) => bridge.addChapterFavorite(
    chapterSourcePath: chapterSourcePath,
    comicSourcePath: comicSourcePath,
  );

  Future<void> removeChapterFavorite(String chapterSourcePath) =>
      bridge.removeChapterFavorite(chapterSourcePath: chapterSourcePath);

  Future<List<String>> listChapterFavorites(String comicSourcePath) =>
      bridge.listChapterFavorites(comicSourcePath: comicSourcePath);

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
