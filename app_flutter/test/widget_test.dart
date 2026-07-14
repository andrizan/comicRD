import 'dart:async';

import 'package:comicrd_flutter/app.dart';
import 'package:comicrd_flutter/api/comicrd_api.dart';
import 'package:comicrd_flutter/bridge_generated.dart' as bridge;
import 'package:comicrd_flutter/pages/library_page.dart';
import 'package:comicrd_flutter/pages/settings_page.dart';
import 'package:comicrd_flutter/state/api_state.dart';
import 'package:comicrd_flutter/utils/forui_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

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

    expect(find.text('No Library Source Configured'), findsOneWidget);
    expect(find.byType(FCircularProgress), findsNothing);
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
    expect(find.byType(FCircularProgress), findsNothing);
  });

  testWidgets('keeps filesystem comics when only one comic is indexed', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(api: const _PartiallyIndexedSourceApi()));
    await tester.pumpAndSettle();

    expect(find.text('8Kaijuu'), findsOneWidget);
    expect(find.text('Other Comic'), findsOneWidget);
    expect(find.text('2 Titles Saved'), findsOneWidget);
  });

  testWidgets('opens comic paths that contain URL special characters', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_testApp(api: const _PercentPathApi()));
    await tester.pumpAndSettle();

    final comic = find.text('100% Comic #1 [A+B] %20?x=y&z');
    final comicCard = find
        .ancestor(of: comic, matching: find.byType(GestureDetector))
        .first;
    await tester.tap(comicCard, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('100% Comic #1 [A+B] %20?x=y&z'), findsOneWidget);
    expect(find.text('Chapter 1'), findsOneWidget);
  });

  testWidgets('settings page exposes unlimited scroll switches', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final api = _SettingsPanelApi();
    await tester.pumpWidget(_testApp(api: api));
    await tester.pumpAndSettle();

    expect(find.byIcon(AppIcons.settings), findsOneWidget);
    final context = tester.element(find.byType(ComicRdShell));
    GoRouter.of(context).go('/settings');
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Unlimited Scroll'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('Unlimited Scroll'), findsOneWidget);
    expect(find.text('Unlimited Scroll Up'), findsOneWidget);

    await tester.tap(find.byType(FSwitch).first);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.byType(FSwitch).last);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(api.savedSettings['unlimited_scroll'], 'true');
    expect(api.savedSettings['unlimited_scroll_up'], 'false');
  });

  testWidgets('library back-to-top button returns the active list to top', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 700);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_testApp(api: const _ManyComicsApi()));
    await tester.pumpAndSettle();
    if (find.byType(LibraryPage).evaluate().isEmpty) {
      final context = tester.element(find.byType(ComicRdShell));
      GoRouter.of(context).go('/');
      await tester.pumpAndSettle();
    }

    expect(
      find.byKey(const ValueKey('library-back-to-top-button')),
      findsNothing,
    );

    final libraryScrollable = find
        .descendant(
          of: find.byType(LibraryPage),
          matching: find.byType(Scrollable),
        )
        .last;
    await tester.drag(libraryScrollable, const Offset(0, -900));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('library-back-to-top-button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('library-back-to-top-button')));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    expect(find.text('Comic 1'), findsOneWidget);
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
      bridge.SettingEntry(key: 'library_source_input', valueJson: '""'),
      bridge.SettingEntry(key: 'default_zoom', valueJson: '1'),
      bridge.SettingEntry(key: 'page_gap', valueJson: '10'),
      bridge.SettingEntry(
        key: 'image_pipeline_profile',
        valueJson: '"balanced"',
      ),
      bridge.SettingEntry(key: 'app_theme', valueJson: '"light"'),
      bridge.SettingEntry(key: 'app_locale', valueJson: '"en"'),
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
  Future<bridge.LibraryStorageStats> getLibraryStorageStats() async {
    return const bridge.LibraryStorageStats(totalSizeBytes: 0, comicCount: 0);
  }

  @override
  Future<List<bridge.RawComic>> listLibraryComicsRaw({
    required bridge.SortBy sortBy,
    required bridge.SortDir sortDir,
  }) async {
    return const [
      bridge.RawComic(
        title: 'Demo Comic',
        sourcePath: '/library/Demo Comic',
        sourceType: 'folder',
        dateModified: 0,
        chapterCount: 0,
        readChapterCount: 0,
        inProgressChapterCount: 0,
        sizeBytes: 0,
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
        title: 'Chapter 1',
        chapterIndex: 1,
        sourcePath: '/library/Demo Comic/Chapter 1',
        sourceType: 'folder',
        dateModified: 0,
        pageCount: 12,
        isRead: false,
        lastPage: 0,
        totalPages: 12,
        sizeBytes: 0,
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
  Future<bridge.LibraryStorageStats> getLibraryStorageStats() async {
    return const bridge.LibraryStorageStats(totalSizeBytes: 0, comicCount: 0);
  }

  @override
  Future<List<bridge.RawComic>> listLibraryComicsRaw({
    required bridge.SortBy sortBy,
    required bridge.SortDir sortDir,
  }) {
    return Completer<List<bridge.RawComic>>().future;
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
        title: '8Kaijuu',
        sourcePath: '/run/media/andrizan/HDD_Hobby/Komik/8Kaijuu',
        sourceType: 'folder',
        dateModified: 2,
        chapterCount: 151,
        readChapterCount: 0,
        inProgressChapterCount: 0,
        sizeBytes: 0,
      ),
      bridge.RawComic(
        title: 'Other Comic',
        sourcePath: '/run/media/andrizan/HDD_Hobby/Komik/Other Comic',
        sourceType: 'folder',
        dateModified: 1,
        chapterCount: 20,
        readChapterCount: 0,
        inProgressChapterCount: 0,
        sizeBytes: 0,
      ),
    ];
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
        title: '100% Comic #1 [A+B] %20?x=y&z',
        sourcePath: '/library/100% Comic #1 [A+B] %20?x=y&z',
        sourceType: 'folder',
        dateModified: 0,
        chapterCount: 1,
        readChapterCount: 0,
        inProgressChapterCount: 0,
        sizeBytes: 0,
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
        title: 'Chapter 1',
        chapterIndex: 1,
        sourcePath: '/library/100% Comic #1 [A+B] %20?x=y&z/Chapter 1',
        sourceType: 'folder',
        dateModified: 0,
        pageCount: 12,
        isRead: false,
        lastPage: 0,
        totalPages: 12,
        sizeBytes: 0,
      ),
    ];
  }
}

class _SettingsPanelApi extends _FakeComicRdApi {
  _SettingsPanelApi();

  final savedSettings = <String, String>{};

  @override
  Future<void> setSetting(String key, String valueJson) async {
    savedSettings[key] = valueJson;
  }

  @override
  Future<List<bridge.SettingEntry>> listSettings() async {
    return const [
      bridge.SettingEntry(key: 'library_source_input', valueJson: '""'),
      bridge.SettingEntry(key: 'default_zoom', valueJson: '1'),
      bridge.SettingEntry(key: 'page_gap', valueJson: '10'),
      bridge.SettingEntry(key: 'unlimited_scroll', valueJson: 'false'),
      bridge.SettingEntry(key: 'unlimited_scroll_up', valueJson: 'true'),
      bridge.SettingEntry(
        key: 'image_pipeline_profile',
        valueJson: '"balanced"',
      ),
      bridge.SettingEntry(key: 'app_theme', valueJson: '"light"'),
      bridge.SettingEntry(key: 'app_locale', valueJson: '"en"'),
    ];
  }
}

class _ManyComicsApi extends _PartiallyIndexedSourceApi {
  const _ManyComicsApi();

  @override
  Future<List<bridge.RawComic>> listLibraryComicsRaw({
    required bridge.SortBy sortBy,
    required bridge.SortDir sortDir,
  }) async {
    return [
      for (var index = 1; index <= 90; index++)
        bridge.RawComic(
          title: 'Comic $index',
          sourcePath: '/library/Comic $index',
          sourceType: 'folder',
          dateModified: index,
          chapterCount: 12,
          readChapterCount: 0,
          inProgressChapterCount: 0,
          sizeBytes: 0,
        ),
    ];
  }
}
