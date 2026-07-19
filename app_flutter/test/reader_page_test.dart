import 'dart:async';
import 'dart:ui';

import 'package:comicrd_flutter/api/comicrd_api.dart';
import 'package:comicrd_flutter/bridge_generated.dart' as bridge;
import 'package:comicrd_flutter/pages/reader_page.dart';
import 'package:comicrd_flutter/state/api_state.dart';
import 'package:comicrd_flutter/state/comic_state.dart';
import 'package:comicrd_flutter/utils/forui_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

void main() {
  Widget wrap(Widget child, {GoRouter? router}) {
    final core = router == null
        ? MaterialApp(home: child)
        : MaterialApp.router(routerConfig: router);
    return FTheme(
      data: ComicReaderFTheme.light,
      child: FToaster(
        child: FTooltipGroup(child: core),
      ),
    );
  }

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
        child: wrap(const ReaderPage(chapterId: 7)),
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
        child: wrap(const ReaderPage(chapterId: 7)),
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
        child: wrap(const ReaderPage(chapterId: 7)),
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

  testWidgets('shows hovered page number tooltip on progress bar', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _ReaderFakeComicRdApi(lastPage: 0, pageCount: 9);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [comicRdApiProvider.overrideWithValue(api)],
        child: wrap(const ReaderPage(chapterId: 7)),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final progressBar = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint &&
          widget.painter.runtimeType.toString() == '_PageIndicatorPainter',
    );
    expect(progressBar, findsOneWidget);

    final rect = tester.getRect(progressBar);
    final hoverPoint = Offset(rect.left + rect.width * 4.5 / 9, rect.center.dy);
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      pointer: 1,
    );
    await gesture.addPointer(location: Offset.zero);
    await tester.pump();
    await gesture.moveTo(hoverPoint);
    await tester.pumpAndSettle(const Duration(milliseconds: 1500));

    expect(find.text('5'), findsOneWidget);
    final tooltipBox = find.byWidgetPredicate((widget) {
      final decoration = widget is DecoratedBox ? widget.decoration : null;
      return decoration is BoxDecoration &&
          decoration.color == const Color(0xff222831);
    });
    expect(tooltipBox, findsOneWidget);
    final tooltipRect = tester.getRect(tooltipBox);
    expect(tooltipRect.bottom, lessThanOrEqualTo(rect.top - 4));

    await gesture.removePointer();
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
        child: wrap(const ReaderPage(chapterId: 7)),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(FCircularProgress), findsNothing);
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
        child: wrap(const ReaderPage(chapterId: 7), router: router),
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

  testWidgets('switching chapter waits for pending prefetch before cleanup', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefetchGate = Completer<void>();
    final api = _ReaderFakeComicRdApi(
      lastPage: 0,
      pageCount: 6,
      nextChapterIds: const {7: 8},
      prefetchGate: prefetchGate,
    );
    final router = GoRouter(
      initialLocation: '/reader/7',
      routes: [
        GoRoute(
          path: '/reader/:chapterId',
          builder: (context, state) => ReaderPage(
            chapterId: int.parse(state.pathParameters['chapterId']!),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [comicRdApiProvider.overrideWithValue(api)],
        child: wrap(const ReaderPage(chapterId: 7), router: router),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(api.events, contains('prefetch-start-7'));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(api.loadedChapterIds, isNot(contains(8)));
    expect(api.events.where((event) => event == 'evict-7-[]'), isEmpty);

    prefetchGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(api.loadedChapterIds, contains(8));
    final prefetchComplete = api.events.indexOf('prefetch-complete-7');
    final finalEvict = api.events.indexOf('evict-7-[]');
    expect(prefetchComplete, isNonNegative);
    expect(finalEvict, greaterThan(prefetchComplete));
  });

  testWidgets('unlimited scroll opens previous chapter on top overscroll', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _ReaderFakeComicRdApi(
      lastPage: 0,
      pageCount: 6,
      pageHeight: 240,
      prevChapterIds: const {8: 7},
      unlimitedScroll: true,
    );
    final router = GoRouter(
      initialLocation: '/reader/8',
      routes: [
        GoRoute(
          path: '/reader/:chapterId',
          builder: (context, state) => ReaderPage(
            chapterId: int.parse(state.pathParameters['chapterId']!),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [comicRdApiProvider.overrideWithValue(api)],
        child: wrap(const ReaderPage(chapterId: 8), router: router),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(api.loadedChapterIds, contains(8));
    expect(api.loadedChapterIds, isNot(contains(7)));

    final scrollableCenter = tester.getCenter(find.byType(ListView));
    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: scrollableCenter,
        scrollDelta: const Offset(0, -360),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(api.loadedChapterIds, contains(7));
  });

  testWidgets(
    'unlimited scroll opens previous chapter when scrolling up at top',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final api = _ReaderFakeComicRdApi(
        lastPage: 0,
        pageCount: 6,
        pageHeight: 240,
        prevChapterIds: const {8: 7},
        unlimitedScroll: true,
      );
      final router = GoRouter(
        initialLocation: '/reader/8',
        routes: [
          GoRoute(
            path: '/reader/:chapterId',
            builder: (context, state) => ReaderPage(
              chapterId: int.parse(state.pathParameters['chapterId']!),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [comicRdApiProvider.overrideWithValue(api)],
          child: wrap(const ReaderPage(chapterId: 8), router: router),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(api.loadedChapterIds, contains(8));
      expect(api.loadedChapterIds, isNot(contains(7)));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(api.loadedChapterIds, contains(7));
    },
  );

  testWidgets(
    'unlimited scroll does not open previous chapter when scroll up is disabled',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final api = _ReaderFakeComicRdApi(
        lastPage: 0,
        pageCount: 6,
        pageHeight: 240,
        prevChapterIds: const {8: 7},
        unlimitedScroll: true,
        unlimitedScrollUp: false,
      );
      final router = GoRouter(
        initialLocation: '/reader/8',
        routes: [
          GoRoute(
            path: '/reader/:chapterId',
            builder: (context, state) => ReaderPage(
              chapterId: int.parse(state.pathParameters['chapterId']!),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [comicRdApiProvider.overrideWithValue(api)],
          child: wrap(const ReaderPage(chapterId: 8), router: router),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(api.loadedChapterIds, contains(8));
      expect(api.loadedChapterIds, isNot(contains(7)));
    },
  );

  testWidgets('reader favorite uses the current chapter path', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _ReaderFakeComicRdApi(lastPage: 0, pageCount: 3);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [comicRdApiProvider.overrideWithValue(api)],
        child: wrap(const ReaderPage(chapterId: 7)),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(api.favoriteListRequests, isNot(contains('')));
    expect(
      api.favoriteListRequests,
      contains('/library/Kaichou wa Maid-sama!'),
    );

    await tester.tap(find.byIcon(AppIcons.star));
    await tester.pump();

    expect(
      api.addedChapterFavorites,
      contains((
        comicSourcePath: '/library/Kaichou wa Maid-sama!',
        chapterSourcePath: '/library/Kaichou wa Maid-sama!/Chapter 28',
      )),
    );
  });
}

class _ReaderFakeComicRdApi extends ComicRdApi {
  _ReaderFakeComicRdApi({
    required this.lastPage,
    required this.pageCount,
    this.pageHeight = 1300,
    this.nextChapterIds = const {},
    this.prevChapterIds = const {},
    this.unlimitedScroll = false,
    this.unlimitedScrollUp = true,
    this.prefetchGate,
  });

  final int lastPage;
  final int pageCount;
  final int pageHeight;
  final Map<int, int> nextChapterIds;
  final Map<int, int> prevChapterIds;
  final bool unlimitedScroll;
  final bool unlimitedScrollUp;
  final Completer<void>? prefetchGate;
  final renderedPageIndices = <int>[];
  final prefetchedWindows = <List<int>>[];
  final evictedWindows = <List<int>>[];
  final savedProgress = <bridge.SaveProgressPayload>[];
  final loadedChapterIds = <int>[];
  final events = <String>[];
  final favoriteListRequests = <String>[];
  final favoriteChapterPaths = <String>{};
  final addedChapterFavorites =
      <({String comicSourcePath, String chapterSourcePath})>[];
  final removedChapterFavorites = <String>[];
  bool _prefetchGateUsed = false;
  int loadedPageEntries = 0;

  @override
  Future<List<bridge.SettingEntry>> listSettings() async {
    return [
      const bridge.SettingEntry(key: 'default_zoom', valueJson: '1'),
      const bridge.SettingEntry(key: 'page_gap', valueJson: '10'),
      bridge.SettingEntry(
        key: 'unlimited_scroll',
        valueJson: unlimitedScroll.toString(),
      ),
      bridge.SettingEntry(
        key: 'unlimited_scroll_up',
        valueJson: unlimitedScrollUp.toString(),
      ),
      const bridge.SettingEntry(key: 'app_theme', valueJson: '"dark"'),
      const bridge.SettingEntry(key: 'app_locale', valueJson: '"en"'),
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
      prevChapterId: prevChapterIds[chapterId],
      nextChapterId: nextChapterIds[chapterId],
    );
  }

  @override
  Future<List<bridge.PageInfo>> getChapterPages(int chapterId) async {
    loadedChapterIds.add(chapterId);
    final pages = [
      for (var index = 0; index < pageCount; index++)
        bridge.PageInfo(
          index: index,
          name: '${index + 1}.png',
          width: 900,
          height: pageHeight,
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
      height: pageHeight,
    );
  }

  @override
  Future<void> prefetchPages(bridge.PrefetchPagesPayload payload) async {
    events.add('prefetch-start-${payload.chapterId}');
    final gate = prefetchGate;
    if (gate != null && !_prefetchGateUsed && payload.chapterId == 7) {
      _prefetchGateUsed = true;
      await gate.future;
    }
    events.add('prefetch-complete-${payload.chapterId}');
    prefetchedWindows.add(payload.pageIndices.toList());
  }

  @override
  Future<void> evictChapterPages({
    required int chapterId,
    required List<int> keepPages,
  }) async {
    events.add('evict-$chapterId-[${keepPages.join(',')}]');
    evictedWindows.add(keepPages.toList());
  }

  @override
  Future<void> saveProgress(bridge.SaveProgressPayload payload) async {
    savedProgress.add(payload);
  }

  @override
  Future<List<String>> listChapterFavorites(String comicSourcePath) async {
    favoriteListRequests.add(comicSourcePath);
    return favoriteChapterPaths.toList();
  }

  @override
  Future<int> addChapterFavorite({
    required String chapterSourcePath,
    required String comicSourcePath,
  }) async {
    addedChapterFavorites.add((
      comicSourcePath: comicSourcePath,
      chapterSourcePath: chapterSourcePath,
    ));
    favoriteChapterPaths.add(chapterSourcePath);
    return addedChapterFavorites.length;
  }

  @override
  Future<void> removeChapterFavorite(String chapterSourcePath) async {
    removedChapterFavorites.add(chapterSourcePath);
    favoriteChapterPaths.remove(chapterSourcePath);
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
