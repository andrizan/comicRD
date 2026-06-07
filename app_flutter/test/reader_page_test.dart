import 'package:comicrd_flutter/api/comicrd_api.dart';
import 'package:comicrd_flutter/bridge_generated.dart' as bridge;
import 'package:comicrd_flutter/pages/reader_page.dart';
import 'package:comicrd_flutter/state/api_state.dart';
import 'package:comicrd_flutter/state/comic_state.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('loads all page entries and lazily renders from saved progress', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _ReaderFakeComicRdApi(lastPage: 27, pageCount: 33);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [comicRdApiProvider.overrideWithValue(api)],
        child: const FluentApp(home: ReaderPage(chapterId: 7)),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(api.loadedPageEntries, api.pageCount);
    expect(api.renderedPageIndices, contains(27));
    expect(
      api.renderedPageIndices.toSet(),
      isNot({for (var index = 0; index < api.pageCount; index++) index}),
    );
    expect(find.textContaining('Chapter 28 (28/33) - 28/33'), findsOneWidget);
    expect(api.prefetchedWindows, contains(equals([25, 26, 27, 28, 29])));
    expect(api.evictedWindows, contains(equals([25, 26, 27, 28, 29])));
  });

  testWidgets('lazy renders only built pages after scroll settles', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _ReaderFakeComicRdApi(lastPage: 0, pageCount: 33);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [comicRdApiProvider.overrideWithValue(api)],
        child: const FluentApp(home: ReaderPage(chapterId: 7)),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final rendered = api.renderedPageIndices;
    expect(api.loadedPageEntries, api.pageCount);
    expect(rendered, isNotEmpty);
    expect(rendered.length, lessThan(api.pageCount));
  });

  testWidgets('prefetch window is 5 pages', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _ReaderFakeComicRdApi(lastPage: 10, pageCount: 33);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [comicRdApiProvider.overrideWithValue(api)],
        child: const FluentApp(home: ReaderPage(chapterId: 7)),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(api.prefetchedWindows, isNotEmpty);
    for (final window in api.prefetchedWindows) {
      expect(window.length, lessThanOrEqualTo(5));
    }
    expect(api.evictedWindows, isNotEmpty);
  });

  testWidgets('does not show page spinners after lazy renders settle', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _ReaderFakeComicRdApi(lastPage: 10, pageCount: 14);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [comicRdApiProvider.overrideWithValue(api)],
        child: const FluentApp(home: ReaderPage(chapterId: 7)),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(ProgressRing), findsNothing);
  });

  testWidgets('closing reader remembers the active chapter for list restore', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _ReaderFakeComicRdApi(lastPage: 0, pageCount: 3);
    final container = ProviderContainer(
      overrides: [comicRdApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/reader/7',
      routes: [
        GoRoute(
          path: '/reader/:chapterId',
          builder: (context, state) => const ReaderPage(chapterId: 7),
        ),
        GoRoute(
          path: '/comic/:comicPath',
          builder: (context, state) => const SizedBox.shrink(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: FluentApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(
      container.read(
        lastOpenedChapterProvider,
      )['/library/Kaichou wa Maid-sama!'],
      '/library/Kaichou wa Maid-sama!/Chapter 28',
    );
  });
}

class _ReaderFakeComicRdApi extends ComicRdApi {
  _ReaderFakeComicRdApi({required this.lastPage, required this.pageCount});

  final int lastPage;
  final int pageCount;
  final renderedPageIndices = <int>[];
  final prefetchedWindows = <List<int>>[];
  final evictedWindows = <List<int>>[];
  final savedProgress = <bridge.SaveProgressPayload>[];
  int loadedPageEntries = 0;

  @override
  Future<List<bridge.SettingEntry>> listSettings() async {
    return const [
      bridge.SettingEntry(key: 'default_zoom', valueJson: '1'),
      bridge.SettingEntry(key: 'page_gap', valueJson: '10'),
      bridge.SettingEntry(key: 'app_theme', valueJson: '"dark"'),
      bridge.SettingEntry(key: 'app_locale', valueJson: '"en"'),
    ];
  }

  @override
  Future<bridge.ChapterContext?> getChapterContext(int chapterId) async {
    return bridge.ChapterContext(
      chapterId: chapterId,
      comicId: 1,
      comicTitle: 'Kaichou wa Maid-sama!',
      title: 'Chapter 28',
      comicSourcePath: '/library/Kaichou wa Maid-sama!',
      chapterSourcePath: '/library/Kaichou wa Maid-sama!/Chapter 28',
      chapterIndex: 28,
      chapterPosition: 28,
      chapterTotal: 33,
    );
  }

  @override
  Future<List<bridge.PageInfo>> getChapterPages(int chapterId) async {
    final pages = [
      for (var index = 0; index < pageCount; index++)
        bridge.PageInfo(
          index: index,
          name: '${index + 1}.png',
          width: 900,
          height: 1300,
        ),
    ];
    loadedPageEntries = pages.length;
    return pages;
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
  Future<bridge.RenderedPage> renderPageVariant(
    bridge.RenderPagePayload payload,
  ) async {
    renderedPageIndices.add(payload.pageIndex);
    return bridge.RenderedPage(
      bytes: Uint8List.fromList(_onePixelPng),
      mime: 'image/png',
      width: 900,
      height: 1300,
    );
  }

  @override
  Future<void> prefetchPages(bridge.PrefetchPagesPayload payload) async {
    prefetchedWindows.add(payload.pageIndices.toList());
  }

  @override
  Future<void> evictChapterPages({
    required int chapterId,
    required List<int> keepPages,
  }) async {
    evictedWindows.add(keepPages.toList());
  }

  @override
  Future<void> saveProgress(bridge.SaveProgressPayload payload) async {
    savedProgress.add(payload);
  }
}

const _onePixelPng = [
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1f,
  0x15,
  0xc4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0a,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9c,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0d,
  0x0a,
  0x2d,
  0xb4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4e,
  0x44,
  0xae,
  0x42,
  0x60,
  0x82,
];
