import 'package:comicrd_flutter/pages/comic_page.dart';
import 'package:comicrd_flutter/utils/forui_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_api.dart';
import 'support/router_host.dart';

Future<void> _pump(WidgetTester tester, FakeComicRdApi api) {
  return pumpRoutedPage(
    tester,
    api: api,
    page: const ComicPage(comicPath: fakeFeaturedPath),
  );
}

void main() {
  testWidgets('header summarises chapters, size, progress and last read', (
    tester,
  ) async {
    await _pump(tester, FakeComicRdApi());

    expect(find.text('Penjaga Senja'), findsOneWidget);
    expect(find.text('5 chapters'), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('3 of 5 chapters finished'), findsOneWidget);
    expect(find.textContaining('Chapter 27 ·'), findsOneWidget);
    expect(find.text('Remove Favorite'), findsOneWidget);
  });

  testWidgets('the in-progress chapter row resumes reading', (tester) async {
    final api = FakeComicRdApi();
    await _pump(tester, api);

    expect(find.text('Page 8 of 20'), findsOneWidget);
    expect(find.text('Finished'), findsNWidgets(2));

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(api.openedChapters, hasLength(1));
    expect(
      api.openedChapters.single.chapterSourcePath,
      '$fakeFeaturedPath/Chapter 3',
    );
    expect(find.text('reader:7'), findsOneWidget);
  });

  testWidgets('"Start from Beginning" opens the first chapter', (tester) async {
    final api = FakeComicRdApi();
    await _pump(tester, api);

    await tester.tap(find.text('Start from Beginning'));
    await tester.pumpAndSettle();

    expect(
      api.openedChapters.single.chapterSourcePath,
      '$fakeFeaturedPath/Chapter 1',
    );
    expect(find.text('reader:7'), findsOneWidget);
  });

  testWidgets('bookmark tab filters to bookmarked chapters', (tester) async {
    await _pump(tester, FakeComicRdApi());

    await tester.tap(find.text('Bookmarks'));
    await tester.pumpAndSettle();

    expect(find.text('Chapter 3'), findsOneWidget);
    expect(find.text('Chapter 1'), findsNothing);
  });

  testWidgets('bookmark button adds a chapter bookmark', (tester) async {
    final api = FakeComicRdApi();
    await _pump(tester, api);

    await tester.tap(find.byIcon(AppIcons.bookmark).first);
    await tester.pumpAndSettle();

    expect(api.addBookmarkCalls, ['$fakeFeaturedPath/Chapter 1']);
  });

  testWidgets('sort field and direction persist the chapter order', (
    tester,
  ) async {
    final api = FakeComicRdApi();
    await _pump(tester, api);

    await tester.tap(find.byIcon(AppIcons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name'));
    await tester.pumpAndSettle();
    expect(api.savedSettings['chapter_sort_by'], '"name"');
    expect(api.savedSettings['chapter_sort_dir'], '"asc"');

    await tester.tap(find.byIcon(AppIcons.arrowUp));
    await tester.pumpAndSettle();
    expect(api.savedSettings['chapter_sort_by'], '"name"');
    expect(api.savedSettings['chapter_sort_dir'], '"desc"');
    // The buttons resized with their new state; let the overlay timers fire
    // before the tree is torn down.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('chapter toolbar shares the heading row and omits the prefix', (
    tester,
  ) async {
    // The test font makes every label far wider than in the app, so the
    // window must be wide for the toolbar to fit beside the heading.
    await pumpRoutedPage(
      tester,
      api: FakeComicRdApi(),
      page: const ComicPage(comicPath: fakeFeaturedPath),
      size: const Size(2200, 900),
    );

    // The sort button reads "Chapter" too; the heading comes first.
    final heading = tester.getCenter(find.text('Chapter').first);
    final filter = tester.getCenter(find.byType(TextField));
    expect((heading.dy - filter.dy).abs(), lessThan(1));
    expect(find.textContaining('Sort'), findsNothing);
    expect(find.byTooltip('Refresh'), findsNothing);
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
  });

  testWidgets('refresh moved into the more menu and purges the caches', (
    tester,
  ) async {
    final api = FakeComicRdApi();
    await _pump(tester, api);

    await tester.tap(find.byIcon(AppIcons.more));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();

    expect(api.purgeCalls, 1);
  });

  testWidgets('more menu copies the path and the chip copies it too', (
    tester,
  ) async {
    final copied = mockClipboard(tester);
    await _pump(tester, FakeComicRdApi());

    await tester.tap(find.byIcon(AppIcons.more));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy Path'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(AppIcons.copyPath).last);
    await tester.pumpAndSettle();

    expect(copied, [fakeFeaturedPath, fakeFeaturedPath]);
  });
}
