import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:comicrd_flutter/api/comicrd_api.dart';
import 'package:comicrd_flutter/bridge_generated.dart' as bridge;
import 'package:comicrd_flutter/pages/reader_page.dart';
import 'package:comicrd_flutter/state/api_state.dart';
import 'package:comicrd_flutter/state/comic_state.dart';
import 'package:comicrd_flutter/utils/forui_theme.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

void main() {
  _decodeWidthTests();

  Widget wrap(Widget child, {GoRouter? router}) {
    final core = router == null
        ? MaterialApp(home: child)
        : MaterialApp.router(routerConfig: router);
    return FTheme(
      data: ComicReaderFTheme.light,
      child: FToaster(child: FTooltipGroup(child: core)),
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
    expect(find.text('Chapter 28'), findsOneWidget);
    expect(find.text(' (28/33)'), findsOneWidget);
    expect(find.text('28'), findsOneWidget);
    expect(find.text('33'), findsOneWidget);
    expect(api.prefetchedWindows, contains(equals([25, 26, 27, 28, 29])));
    expect(api.evictedWindows, contains(equals([25, 26, 27, 28, 29])));
  });

  testWidgets('a long chapter title is ellipsised but the position stays', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final longTitle = 'Chapter 28 · ${'The Door That Was Never Opened ' * 6}';
    final api = _ReaderFakeComicRdApi(
      lastPage: 0,
      pageCount: 6,
      chapterTitle: longTitle,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [comicRdApiProvider.overrideWithValue(api)],
        child: wrap(const ReaderPage(chapterId: 7)),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final title = tester.renderObject<RenderParagraph>(find.text(longTitle));
    expect(title.didExceedMaxLines, isTrue);

    // The title pill is at most 540 px wide, starting at the 24 px gutter.
    final position = tester.getRect(find.text(' (28/33)'));
    expect(position.width, greaterThan(0));
    expect(position.right, lessThanOrEqualTo(24 + 540));
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

  group('continuous chapter strip', () {
    // 900x240 pages are landscape, so they draw 1176 px wide (the window less
    // its gutter): 313.6 px tall, 10 px apart. Six pages are 1931.6 px of
    // chapter; the viewport is 800 px tall.
    const pageDrawn = 240 * 1176 / 900;
    const chapterExtent = 6 * pageDrawn + 5 * 10;

    Future<({GoRouter router, ProviderContainer container})> pumpStrip(
      WidgetTester tester,
      _ReaderFakeComicRdApi api, {
      required int chapterId,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer(
        overrides: [comicRdApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: '/reader/$chapterId',
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
        UncontrolledProviderScope(
          container: container,
          child: wrap(ReaderPage(chapterId: chapterId), router: router),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      return (router: router, container: container);
    }

    ScrollPosition position(WidgetTester tester) =>
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;

    Future<void> scrollTo(WidgetTester tester, double offset) async {
      position(tester).jumpTo(offset);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    _ReaderFakeComicRdApi twoChapters() {
      return _ReaderFakeComicRdApi(
        lastPage: 0,
        pageCount: 6,
        pageHeight: 240,
        nextChapterIds: const {7: 8},
        prevChapterIds: const {8: 7},
        unlimitedScroll: true,
        chapterTitles: const {7: 'Chapter 27', 8: 'Chapter 28'},
        chapterPositions: const {7: 27, 8: 28},
      );
    }

    testWidgets('loads the next chapter ahead without leaving the reader', (
      tester,
    ) async {
      final api = twoChapters();
      final host = await pumpStrip(tester, api, chapterId: 7);

      // Within a few screens of the end, so it is already in the strip.
      expect(api.loadedChapterIds, containsAll([7, 8]));
      expect(host.router.routeInformationProvider.value.uri.path, '/reader/7');
      expect(find.byType(FCircularProgress), findsNothing);
    });

    testWidgets(
      'shows what was finished and what comes next between chapters',
      (tester) async {
        final api = twoChapters();
        await pumpStrip(tester, api, chapterId: 7);

        // Just above the boundary: the header sits under the viewport's top.
        await scrollTo(tester, 78 + chapterExtent - 200);

        expect(find.text('Finished'), findsOneWidget);
        expect(find.text('Next Chapter'), findsOneWidget);
        expect(find.text('28/33 · 6 pages'), findsOneWidget);
      },
    );

    testWidgets('scrolling across the boundary switches the status at once', (
      tester,
    ) async {
      final api = twoChapters();
      final host = await pumpStrip(tester, api, chapterId: 7);
      expect(find.text(' (27/33)'), findsOneWidget);

      // Viewport centre lands on the first page of chapter 28.
      await scrollTo(tester, 78 + chapterExtent + 168 - 300);

      expect(find.text(' (28/33)'), findsOneWidget);
      expect(find.text(' (27/33)'), findsNothing);
      // The chapter left behind is finished at once, without waiting for the
      // scroll-save debounce.
      expect(
        api.savedProgress.any(
          (p) => p.chapterId == 7 && p.lastPage == 5 && p.isRead,
        ),
        isTrue,
      );
      expect(
        host.container.read(
          lastOpenedChapterProvider,
        )['/library/Kaichou wa Maid-sama!'],
        '/library/Kaichou wa Maid-sama!/Chapter 28',
      );
      // Still the same reader page: nothing reloaded or navigated.
      expect(host.router.routeInformationProvider.value.uri.path, '/reader/7');
    });

    testWidgets('scrolling back switches the status back', (tester) async {
      final api = twoChapters();
      await pumpStrip(tester, api, chapterId: 7);

      await scrollTo(tester, 78 + chapterExtent + 168 - 300);
      expect(find.text(' (28/33)'), findsOneWidget);

      await scrollTo(tester, 400);
      expect(find.text(' (27/33)'), findsOneWidget);
      expect(find.text(' (28/33)'), findsNothing);
    });

    testWidgets('chains the previous chapter in and keeps the page in place', (
      tester,
    ) async {
      final api = twoChapters();
      await pumpStrip(tester, api, chapterId: 8);

      expect(api.loadedChapterIds, containsAll([7, 8]));
      // Chapter 28's first page was at the top; chapter 27 and the header
      // now sit above it, so the offset moved down by exactly their height.
      expect(
        position(tester).pixels,
        moreOrLessEquals(78 + chapterExtent + 168, epsilon: 1),
      );
      expect(find.text(' (28/33)'), findsOneWidget);
      // The viewport centre is on the second 313 px page, as it is when the
      // chapter opens alone: chapter 27 changed nothing about what is read.
      expect(find.text('2'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
    });

    testWidgets('scrollbar thumb starts over with each chapter', (
      tester,
    ) async {
      final api = twoChapters();
      await pumpStrip(tester, api, chapterId: 7);
      final thumb = find.byKey(const ValueKey('reader-scrollbar-thumb'));
      expect(thumb, findsOneWidget);

      // Chapter 27 spans [0, 78 + chapterExtent]; its last 800 px are the
      // final screen, where the thumb rests on the bottom of the track.
      await scrollTo(tester, 78 + chapterExtent - 800);
      expect(tester.getRect(thumb).bottom, moreOrLessEquals(800, epsilon: 1));

      // One step into chapter 28 and the thumb is back at the top, not
      // part-way down a track that spans both chapters.
      await scrollTo(tester, 78 + chapterExtent + 168 - 300);
      expect(tester.getRect(thumb).top, moreOrLessEquals(0, epsilon: 1));
      expect(find.text(' (28/33)'), findsOneWidget);
    });

    testWidgets('dragging the thumb stays inside the chapter in view', (
      tester,
    ) async {
      final api = twoChapters();
      await pumpStrip(tester, api, chapterId: 7);
      final thumb = find.byKey(const ValueKey('reader-scrollbar-thumb'));

      await tester.drag(thumb, const Offset(0, 3000));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Pulled all the way down, the viewport ends exactly where chapter 27
      // does; the next chapter is reached by scrolling, not by the thumb.
      expect(
        position(tester).pixels,
        moreOrLessEquals(78 + chapterExtent - 800, epsilon: 2),
      );
      expect(find.text(' (27/33)'), findsOneWidget);
    });

    testWidgets(
      'next chapter button jumps within the strip without reloading',
      (tester) async {
        final api = twoChapters();
        final host = await pumpStrip(tester, api, chapterId: 7);

        await tester.tap(find.byTooltip('Next Chapter'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.text(' (28/33)'), findsOneWidget);
        expect(api.loadedChapterIds.where((id) => id == 8), hasLength(1));
        expect(
          host.router.routeInformationProvider.value.uri.path,
          '/reader/7',
        );
      },
    );

    testWidgets('a chapter that fails to load is skipped, not retried', (
      tester,
    ) async {
      final api = _ReaderFakeComicRdApi(
        lastPage: 0,
        pageCount: 6,
        pageHeight: 240,
        nextChapterIds: const {7: 8},
        unlimitedScroll: true,
        chapterPositions: const {7: 27},
        failingChapterIds: const {8},
      );
      await pumpStrip(tester, api, chapterId: 7);

      for (final offset in [300.0, 700.0, 1200.0, 1500.0]) {
        await scrollTo(tester, offset);
      }

      expect(api.loadedChapterIds.where((id) => id == 8), hasLength(1));
      expect(find.text(' (27/33)'), findsOneWidget);
    });
  });

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

    expect(api.bookmarkListRequests, isNot(contains('')));
    expect(
      api.bookmarkListRequests,
      contains('/library/Kaichou wa Maid-sama!'),
    );

    // The chapter bookmark lives in the "Mark" panel.
    await tester.tap(find.text('Mark'));
    await tester.pump();
    await tester.tap(find.byIcon(AppIcons.folderBookmark).first);
    await tester.pump();

    expect(
      api.addedBookmarks,
      contains((
        comicSourcePath: '/library/Kaichou wa Maid-sama!',
        chapterSourcePath: '/library/Kaichou wa Maid-sama!/Chapter 28',
      )),
    );
  });

  testWidgets('multi-tile strip renders tiles but saves page-based progress', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _ReaderFakeComicRdApi(
      lastPage: 0,
      pageCount: 2,
      pageHeight: 5000,
      tileHeightsList: {
        0: [2048, 2048, 904],
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [comicRdApiProvider.overrideWithValue(api)],
        child: wrap(const ReaderPage(chapterId: 7)),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // First tile of the strip renders on open.
    expect(api.renderedTiles, contains((0, 0)));

    await tester.tap(find.byTooltip('Next Page'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Jump lands on the first tile of page 1, and progress saves the
    // page index (1), not a tile index (which would be 3).
    expect(api.renderedTiles, contains((1, 0)));
    expect(api.savedProgress, isNotEmpty);
    expect(api.savedProgress.last.lastPage, 1);
  });

  testWidgets('scroll extent stays stable while scrolling', (tester) async {
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

    double maxExtent() {
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      return scrollable.position.maxScrollExtent;
    }

    // The delegate reports the exact total, so maxScrollExtent must not
    // wobble (estimated totals made the scrollbar thumb jump).
    final before = maxExtent();
    for (var i = 0; i < 4; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(maxExtent(), moreOrLessEquals(before, epsilon: 1.0));
    }
  });
}

void _decodeWidthTests() {
  Widget wrap(Widget child) {
    return FTheme(
      data: ComicReaderFTheme.light,
      child: FToaster(
        child: FTooltipGroup(child: MaterialApp(home: child)),
      ),
    );
  }

  testWidgets('wide tiles decode at the drawn width, not the file width', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // 2048px-wide pages on a 1200px window: the portrait column is 1000px
    // (zoom 1), so tiles decode at the next 128px step above it.
    final api = _ReaderFakeComicRdApi(
      lastPage: 0,
      pageCount: 2,
      pageWidth: 2048,
      pageHeight: 3000,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [comicRdApiProvider.overrideWithValue(api)],
        child: wrap(const ReaderPage(chapterId: 7)),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, isNotEmpty);
    for (final image in images) {
      final provider = image.image;
      expect(provider, isA<ResizeImage>());
      expect((provider as ResizeImage).width, 1024);
      expect(image.filterQuality, FilterQuality.low);
    }
  });

  testWidgets('tiles narrower than the column decode at their own width', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _ReaderFakeComicRdApi(lastPage: 0, pageCount: 2);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [comicRdApiProvider.overrideWithValue(api)],
        child: wrap(const ReaderPage(chapterId: 7)),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, isNotEmpty);
    for (final image in images) {
      expect(image.image, isA<MemoryImage>());
    }
  });
}

class _ReaderFakeComicRdApi extends ComicRdApi {
  _ReaderFakeComicRdApi({
    required this.lastPage,
    required this.pageCount,
    this.pageWidth = 900,
    this.pageHeight = 1300,
    this.tileHeightsList = const {},
    this.nextChapterIds = const {},
    this.prevChapterIds = const {},
    this.unlimitedScroll = false,
    this.prefetchGate,
    this.chapterTitle = 'Chapter 28',
    this.chapterTitles = const {},
    this.chapterPositions = const {},
    this.failingChapterIds = const {},
  });

  final String chapterTitle;
  final Map<int, String> chapterTitles;
  final Map<int, int> chapterPositions;
  final Set<int> failingChapterIds;
  final int lastPage;
  final int pageCount;
  final int pageWidth;
  final int pageHeight;
  final Map<int, List<int>> tileHeightsList;
  final Map<int, int> nextChapterIds;
  final Map<int, int> prevChapterIds;
  final bool unlimitedScroll;
  final Completer<void>? prefetchGate;
  final renderedPageIndices = <int>[];
  final renderedTiles = <(int, int)>[];
  final prefetchedWindows = <List<int>>[];
  final evictedWindows = <List<int>>[];
  final savedProgress = <bridge.SaveProgressPayload>[];
  final loadedChapterIds = <int>[];
  final events = <String>[];
  final bookmarkListRequests = <String>[];
  final bookmarkChapterPaths = <String>{};
  final addedBookmarks =
      <({String comicSourcePath, String chapterSourcePath})>[];
  final removedBookmarks = <String>[];
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
      const bridge.SettingEntry(key: 'app_theme', valueJson: '"dark"'),
      const bridge.SettingEntry(key: 'app_locale', valueJson: '"en"'),
    ];
  }

  @override
  Future<bridge.ChapterContext?> getChapterContext(int chapterId) async {
    final title = chapterTitles[chapterId] ?? chapterTitle;
    return bridge.ChapterContext(
      chapterId: chapterId,
      comicId: 1,
      comicTitle: 'Kaichou wa Maid-sama!',
      title: title,
      comicSourcePath: '/library/Kaichou wa Maid-sama!',
      chapterSourcePath: '/library/Kaichou wa Maid-sama!/$title',
      chapterIndex: 28,
      chapterPosition: chapterPositions[chapterId] ?? 28,
      chapterTotal: 33,
      prevChapterId: prevChapterIds[chapterId],
      nextChapterId: nextChapterIds[chapterId],
    );
  }

  @override
  Future<List<bridge.PageInfo>> getChapterPages(int chapterId) async {
    loadedChapterIds.add(chapterId);
    if (failingChapterIds.contains(chapterId)) {
      throw StateError('chapter $chapterId cannot be opened');
    }
    final pages = [
      for (var index = 0; index < pageCount; index++)
        bridge.PageInfo(
          index: index,
          name: '${index + 1}.png',
          width: pageWidth,
          height: pageHeight,
          tileHeights: Uint32List.fromList(
            tileHeightsList[index] ?? [pageHeight],
          ),
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
  Future<bridge.RenderedPage> renderPageTile(
    bridge.RenderPageTilePayload payload,
  ) async {
    renderedPageIndices.add(payload.pageIndex);
    renderedTiles.add((payload.pageIndex, payload.tileIndex));
    final heights = tileHeightsList[payload.pageIndex];
    final height = heights != null && payload.tileIndex < heights.length
        ? heights[payload.tileIndex]
        : pageHeight;
    return bridge.RenderedPage(
      bytes: Uint8List.fromList(_onePixelPng),
      mime: 'image/png',
      width: 900,
      height: height,
    );
  }

  @override
  Future<void> prefetchTiles(bridge.PrefetchTilesPayload payload) async {
    events.add('prefetch-start-${payload.chapterId}');
    final gate = prefetchGate;
    if (gate != null && !_prefetchGateUsed && payload.chapterId == 7) {
      _prefetchGateUsed = true;
      await gate.future;
    }
    events.add('prefetch-complete-${payload.chapterId}');
    prefetchedWindows.add([for (final tile in payload.tiles) tile.pageIndex]);
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
  Future<List<String>> listBookmarks({required String comicSourcePath}) async {
    bookmarkListRequests.add(comicSourcePath);
    return bookmarkChapterPaths.toList();
  }

  @override
  Future<int> addBookmark({
    required String chapterSourcePath,
    required String comicSourcePath,
  }) async {
    addedBookmarks.add((
      comicSourcePath: comicSourcePath,
      chapterSourcePath: chapterSourcePath,
    ));
    bookmarkChapterPaths.add(chapterSourcePath);
    return addedBookmarks.length;
  }

  @override
  Future<void> removeBookmark({required String chapterSourcePath}) async {
    removedBookmarks.add(chapterSourcePath);
    bookmarkChapterPaths.remove(chapterSourcePath);
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
