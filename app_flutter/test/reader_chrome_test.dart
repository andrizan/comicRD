import 'package:comicrd_flutter/pages/reader_page.dart';
import 'package:comicrd_flutter/utils/forui_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_api.dart';
import 'support/router_host.dart';

Future<void> _pump(WidgetTester tester, FakeComicRdApi api) async {
  await pumpRoutedPage(
    tester,
    api: api,
    page: const ReaderPage(chapterId: fakeReaderChapterId),
    size: const Size(1200, 800),
  );
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('Display panel changes settings and closes with Esc', (
    tester,
  ) async {
    final api = FakeComicRdApi();
    await _pump(tester, api);

    expect(find.text('Zoom'), findsNothing);
    await tester.tap(find.text('Display'));
    await _settle(tester);
    expect(find.text('Zoom'), findsOneWidget);
    expect(find.text('Page Gap'), findsOneWidget);

    // The one scroll switch covers both directions; there is no separate
    // "scroll up" switch any more.
    expect(find.text('Unlimited Scroll Up'), findsNothing);
    await tester.tap(find.text('Unlimited Scroll'));
    await _settle(tester);
    expect(api.savedSettings['unlimited_scroll'], 'false');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.text('Zoom'), findsNothing);
    expect(find.byType(ReaderPage), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Mark panel toggles page bookmark, chapter bookmark, favorite', (
    tester,
  ) async {
    final api = FakeComicRdApi();
    await _pump(tester, api);

    await tester.tap(find.text('Mark'));
    await _settle(tester);
    expect(find.text('Page 1 of 12'), findsOneWidget);

    await tester.tap(find.text('Add Page Bookmark'));
    await _settle(tester);
    expect(api.addedPageBookmarks, [0]);
    expect(find.text('Remove Page Bookmark'), findsOneWidget);

    await tester.tap(find.text('Add Bookmark'));
    await _settle(tester);
    expect(api.addBookmarkCalls, ['$fakeFeaturedPath/Chapter 27']);

    await tester.tap(find.text('Remove Favorite'));
    await _settle(tester);
    expect(api.removeFavoriteCalls, [fakeFeaturedPath]);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the 0 key rewinds to the first page', (tester) async {
    final api = FakeComicRdApi(lastPage: 5);
    await _pump(tester, api);
    expect(find.text('6'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await _settle(tester);
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('1'), findsOneWidget);
    expect(api.savedProgress, isNotEmpty);
    expect(api.savedProgress.last.lastPage, 0);
  });

  testWidgets('page bar buttons step pages and switch chapters', (
    tester,
  ) async {
    final api = FakeComicRdApi();
    await _pump(tester, api);
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.byTooltip('Next Page'));
    await _settle(tester);
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous Page'));
    await _settle(tester);
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.byTooltip('Next Chapter'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('reader:${fakeReaderChapterId + 1}'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('tapping the track jumps to that page', (tester) async {
    final api = FakeComicRdApi();
    await _pump(tester, api);

    final track = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint &&
          widget.painter.runtimeType.toString() == '_PageIndicatorPainter',
    );
    final rect = tester.getRect(track);
    await tester.tapAt(Offset(rect.left + rect.width * 0.79, rect.center.dy));
    await _settle(tester);
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('10'), findsOneWidget);
    expect(api.savedProgress.last.lastPage, 9);
  });

  testWidgets('back button leaves the reader', (tester) async {
    final api = FakeComicRdApi();
    await _pump(tester, api);

    await tester.tap(find.byIcon(AppIcons.chevronLeft).first);
    await _settle(tester);
    await tester.pumpAndSettle();

    expect(find.text('comic:$fakeFeaturedPath'), findsOneWidget);
    expect(api.savedProgress, isNotEmpty);
  });
}
