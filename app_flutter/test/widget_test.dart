import 'dart:async';

import 'package:comicrd_flutter/app.dart';
import 'package:comicrd_flutter/api/comicrd_api.dart';
import 'package:comicrd_flutter/bridge_generated.dart' as bridge;
import 'package:comicrd_flutter/state/api_state.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders ComicRD app', (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    expect(find.text('ComicRD'), findsOneWidget);
  });

  testWidgets('shows missing library source without waiting for comics', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(api: const _MissingSourceApi()));
    await tester.pump();
    await tester.pump();

    expect(find.text('No library source configured'), findsOneWidget);
    expect(find.byType(ProgressRing), findsNothing);
  });

  testWidgets('shows mount hint when configured library path is unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(api: const _UnmountedSourceApi()));
    await tester.pump();
    await tester.pump();

    expect(
      find.text(
        "path '/run/media/andrizan/HDD_Hobby/Komik' not found. On Linux, you may need to mount the partition first.",
      ),
      findsOneWidget,
    );
    expect(find.byType(ProgressRing), findsNothing);
  });

  testWidgets('keeps filesystem comics when only one comic is indexed', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(api: const _PartiallyIndexedSourceApi()));
    await tester.pumpAndSettle();

    expect(find.text('8Kaijuu'), findsOneWidget);
    expect(find.text('Other Comic'), findsOneWidget);
    expect(find.text('Total comics: 2'), findsOneWidget);
  });

  testWidgets('opens comic paths that contain URL special characters', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(api: const _PercentPathApi()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('100% Comic #1 [A+B] %20?x=y&z'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('100% Comic #1 [A+B] %20?x=y&z'), findsOneWidget);
    expect(find.text('Chapter 1'), findsOneWidget);
  });
}

Widget _testApp({ComicRdApi api = const _FakeComicRdApi()}) {
  return ProviderScope(
    overrides: [comicRdApiProvider.overrideWithValue(api)],
    child: const ComicRdApp(),
  );
}

class _FakeComicRdApi extends ComicRdApi {
  const _FakeComicRdApi();

  @override
  Future<List<bridge.SettingEntry>> listSettings() async {
    return const [
      bridge.SettingEntry(
        key: 'library_source_input',
        valueJson: '""',
        updatedAt: 0,
      ),
      bridge.SettingEntry(key: 'default_zoom', valueJson: '1', updatedAt: 0),
      bridge.SettingEntry(key: 'page_gap', valueJson: '10', updatedAt: 0),
      bridge.SettingEntry(
        key: 'image_pipeline_profile',
        valueJson: '"balanced"',
        updatedAt: 0,
      ),
      bridge.SettingEntry(key: 'app_theme', valueJson: '"light"', updatedAt: 0),
      bridge.SettingEntry(key: 'app_locale', valueJson: '"en"', updatedAt: 0),
    ];
  }

  @override
  Future<void> setSetting(String key, String valueJson) async {}

  @override
  Future<bridge.LibrarySourceStatus> checkLibrarySource() async {
    return const bridge.LibrarySourceStatus(
      configured: false,
      path: '',
      exists: false,
      isDir: false,
      readable: false,
    );
  }

  @override
  Future<List<bridge.RawComic>> listLibraryComicsRaw({
    required bridge.SortBy sortBy,
    required bridge.SortDir sortDir,
  }) async {
    return const [
      bridge.RawComic(
        key: '/library/Demo Comic',
        title: 'Demo Comic',
        sourcePath: '/library/Demo Comic',
        sourceType: 'folder',
        libraryPath: '/library',
        dateModified: 0,
        chapterCount: 0,
        readChapterCount: 0,
        inProgressChapterCount: 0,
      ),
    ];
  }

  @override
  Future<List<bridge.Comic>> listComics({
    required bridge.SortBy sortBy,
    required bridge.SortDir sortDir,
  }) async {
    return const [
      bridge.Comic(
        id: 1,
        libraryId: 1,
        title: 'Demo Comic',
        sourcePath: '/library/Demo Comic',
        sourceType: 'folder',
        dateModified: 0,
        updatedAt: 0,
        chapterCount: 0,
        readChapterCount: 0,
        inProgressChapterCount: 0,
      ),
    ];
  }

  @override
  Future<List<String>> listComicsWithProgress() async {
    return const [];
  }

  @override
  Future<List<bridge.ReadingHistoryEntry>> listReadingHistory() async {
    return const [];
  }

  @override
  Future<List<bridge.ComicBookmark>> listAllBookmarks() async {
    return const [];
  }

  @override
  Future<List<bridge.RawChapter>> listComicChaptersRaw(
    String comicSourcePath,
  ) async {
    return const [
      bridge.RawChapter(
        key: '/library/Demo Comic/Chapter 1',
        title: 'Chapter 1',
        chapterIndex: 1,
        sourcePath: '/library/Demo Comic/Chapter 1',
        sourceType: 'folder',
        dateModified: 0,
        pageCount: 12,
        isRead: false,
        lastPage: 0,
        totalPages: 12,
      ),
    ];
  }

  @override
  Future<List<String>> listChapterFavorites(String comicSourcePath) async {
    return const [];
  }
}

class _MissingSourceApi extends _FakeComicRdApi {
  const _MissingSourceApi();

  @override
  Future<bridge.LibrarySourceStatus> checkLibrarySource() async {
    return const bridge.LibrarySourceStatus(
      configured: false,
      path: '',
      exists: false,
      isDir: false,
      readable: false,
    );
  }

  @override
  Future<List<bridge.RawComic>> listLibraryComicsRaw({
    required bridge.SortBy sortBy,
    required bridge.SortDir sortDir,
  }) {
    return Completer<List<bridge.RawComic>>().future;
  }

  @override
  Future<List<bridge.Comic>> listComics({
    required bridge.SortBy sortBy,
    required bridge.SortDir sortDir,
  }) {
    return Completer<List<bridge.Comic>>().future;
  }

  @override
  Future<List<String>> listComicsWithProgress() {
    return Completer<List<String>>().future;
  }
}

class _UnmountedSourceApi extends _MissingSourceApi {
  const _UnmountedSourceApi();

  @override
  Future<bridge.LibrarySourceStatus> checkLibrarySource() async {
    return const bridge.LibrarySourceStatus(
      configured: true,
      path: '/run/media/andrizan/HDD_Hobby/Komik',
      exists: false,
      isDir: false,
      readable: false,
      error:
          "path '/run/media/andrizan/HDD_Hobby/Komik' not found. On Linux, you may need to mount the partition first.",
    );
  }
}

class _PartiallyIndexedSourceApi extends _FakeComicRdApi {
  const _PartiallyIndexedSourceApi();

  @override
  Future<bridge.LibrarySourceStatus> checkLibrarySource() async {
    return const bridge.LibrarySourceStatus(
      configured: true,
      path: '/run/media/andrizan/HDD_Hobby/Komik',
      exists: true,
      isDir: true,
      readable: true,
    );
  }

  @override
  Future<List<bridge.RawComic>> listLibraryComicsRaw({
    required bridge.SortBy sortBy,
    required bridge.SortDir sortDir,
  }) async {
    return const [
      bridge.RawComic(
        key: '/run/media/andrizan/HDD_Hobby/Komik/8Kaijuu',
        title: '8Kaijuu',
        sourcePath: '/run/media/andrizan/HDD_Hobby/Komik/8Kaijuu',
        sourceType: 'folder',
        libraryPath: '/run/media/andrizan/HDD_Hobby/Komik',
        dateModified: 2,
        chapterCount: 151,
        readChapterCount: 0,
        inProgressChapterCount: 0,
      ),
      bridge.RawComic(
        key: '/run/media/andrizan/HDD_Hobby/Komik/Other Comic',
        title: 'Other Comic',
        sourcePath: '/run/media/andrizan/HDD_Hobby/Komik/Other Comic',
        sourceType: 'folder',
        libraryPath: '/run/media/andrizan/HDD_Hobby/Komik',
        dateModified: 1,
        chapterCount: 20,
        readChapterCount: 0,
        inProgressChapterCount: 0,
      ),
    ];
  }

  @override
  Future<List<bridge.Comic>> listComics({
    required bridge.SortBy sortBy,
    required bridge.SortDir sortDir,
  }) {
    throw StateError('library catalog must come from filesystem, not database');
  }
}

class _PercentPathApi extends _PartiallyIndexedSourceApi {
  const _PercentPathApi();

  @override
  Future<List<bridge.RawComic>> listLibraryComicsRaw({
    required bridge.SortBy sortBy,
    required bridge.SortDir sortDir,
  }) async {
    return const [
      bridge.RawComic(
        key: '/library/100% Comic #1 [A+B] %20?x=y&z',
        title: '100% Comic #1 [A+B] %20?x=y&z',
        sourcePath: '/library/100% Comic #1 [A+B] %20?x=y&z',
        sourceType: 'folder',
        libraryPath: '/library',
        dateModified: 0,
        chapterCount: 1,
        readChapterCount: 0,
        inProgressChapterCount: 0,
      ),
    ];
  }

  @override
  Future<List<bridge.RawChapter>> listComicChaptersRaw(
    String comicSourcePath,
  ) async {
    if (comicSourcePath != '/library/100% Comic #1 [A+B] %20?x=y&z') {
      throw StateError('unexpected comic path: $comicSourcePath');
    }
    return const [
      bridge.RawChapter(
        key: '/library/100% Comic #1 [A+B] %20?x=y&z/Chapter 1',
        title: 'Chapter 1',
        chapterIndex: 1,
        sourcePath: '/library/100% Comic #1 [A+B] %20?x=y&z/Chapter 1',
        sourceType: 'folder',
        dateModified: 0,
        pageCount: 12,
        isRead: false,
        lastPage: 0,
        totalPages: 12,
      ),
    ];
  }
}
