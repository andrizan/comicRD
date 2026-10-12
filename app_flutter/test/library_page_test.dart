import 'package:comicrd_flutter/pages/library_page.dart';
import 'package:comicrd_flutter/utils/forui_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_api.dart';
import 'support/router_host.dart';

Future<void> _pump(WidgetTester tester, FakeComicRdApi api) {
  return pumpRoutedPage(tester, api: api, page: const LibraryPage());
}

void main() {
  testWidgets('shows the welcome screen when no source is configured', (
    tester,
  ) async {
    await _pump(tester, FakeComicRdApi(configured: false));

    expect(
      find.text('Read comics from a folder on your computer.'),
      findsOneWidget,
    );
    expect(find.text('Choose Comic Folder'), findsOneWidget);
    expect(find.text('Example Folder Structure'), findsOneWidget);

    await tester.tap(find.text('Have a backup? Import it'));
    await tester.pumpAndSettle();
    expect(find.text('settings'), findsOneWidget);
  });

  testWidgets('shows the source error in a banner with a folder action', (
    tester,
  ) async {
    await _pump(
      tester,
      FakeComicRdApi(sourceError: "path '/library' not found"),
    );

    expect(find.text("path '/library' not found"), findsOneWidget);

    await tester.tap(find.text('Change Folder'));
    await tester.pumpAndSettle();
    expect(find.text('settings'), findsOneWidget);
  });

  testWidgets('continue-reading shelf lists unfinished history and resumes', (
    tester,
  ) async {
    await _pump(tester, FakeComicRdApi());

    expect(find.text('Continue Reading'), findsOneWidget);
    expect(find.text('Chapter 27 · page 12 of 34'), findsOneWidget);
    // Finished entries never appear on the shelf.
    expect(find.textContaining('Chapter 12'), findsNothing);

    await tester.tap(find.byIcon(AppIcons.play).first);
    await tester.pumpAndSettle();
    expect(find.text('reader:7'), findsOneWidget);
  });

  testWidgets('"View History" switches to the history tab', (tester) async {
    final api = FakeComicRdApi();
    await _pump(tester, api);

    await tester.tap(find.text('View History'));
    await tester.pumpAndSettle();

    expect(api.savedSettings['library_selected_tab'], '"history"');
    expect(find.text('Latest Reading'), findsOneWidget);
  });

  testWidgets('filter chips carry counts and persist the view mode', (
    tester,
  ) async {
    final api = FakeComicRdApi();
    await _pump(tester, api);

    expect(find.textContaining('4 Titles Saved'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('2'), findsNWidgets(2));

    await tester.tap(find.text('Unread'));
    await tester.pumpAndSettle();

    expect(api.savedSettings['library_view_mode'], '"unread"');
    expect(find.text('18 chapters'), findsOneWidget);
    expect(find.text('26 of 30 chapters'), findsNothing);
  });

  testWidgets('sort menu persists the chosen order', (tester) async {
    final api = FakeComicRdApi();
    await _pump(tester, api);

    await tester.tap(find.byIcon(AppIcons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name Z–A'));
    await tester.pumpAndSettle();

    expect(api.savedSettings['library_sort_by'], '"name"');
    expect(api.savedSettings['library_sort_dir'], '"desc"');
  });

  testWidgets('list mode shows percentages and toggles favorites', (
    tester,
  ) async {
    final api = FakeComicRdApi();
    await _pump(tester, api);

    await tester.tap(find.byIcon(AppIcons.list));
    await tester.pumpAndSettle();

    expect(api.savedSettings['library_display_mode'], '"list"');
    expect(find.text('87%'), findsOneWidget);
    expect(find.text('14%'), findsOneWidget);

    await tester.tap(find.byIcon(AppIcons.star).first);
    await tester.pumpAndSettle();
    expect(api.removeFavoriteCalls, [fakeFeaturedPath]);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('search narrows the grid after the debounce', (tester) async {
    await _pump(tester, FakeComicRdApi());

    await tester.enterText(find.byType(TextField), 'atlas');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('Atlas Kucing'), findsOneWidget);
    expect(find.text('Samudra Kertas'), findsNothing);
  });

  testWidgets('history tab offers Continue and Read Again', (tester) async {
    await _pump(
      tester,
      FakeComicRdApi(extraSettings: {'library_selected_tab': '"history"'}),
    );

    expect(find.text('Continue'), findsNWidgets(2));
    expect(find.text('Read Again'), findsOneWidget);
    expect(find.text('Finished'), findsOneWidget);
    expect(find.text('Page 12 of 34'), findsOneWidget);

    await tester.tap(find.text('Read Again'));
    await tester.pumpAndSettle();
    expect(find.text('reader:40'), findsOneWidget);
  });

  testWidgets('favorites tab lists favorites and removes one', (tester) async {
    final api = FakeComicRdApi(
      extraSettings: {'library_selected_tab': '"favorites"'},
    );
    await _pump(tester, api);

    expect(find.text('2 Titles Saved'), findsOneWidget);
    expect(find.text('Atlas Kucing'), findsOneWidget);

    await tester.tap(find.byIcon(AppIcons.star).first);
    await tester.pumpAndSettle();
    expect(api.removeFavoriteCalls, hasLength(1));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('card menu copies the title and opens the folder', (
    tester,
  ) async {
    final api = FakeComicRdApi();
    final copied = mockClipboard(tester);
    await _pump(tester, api);

    await tester.tap(find.byIcon(AppIcons.list));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(AppIcons.more).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy Title'));
    await tester.pumpAndSettle();
    expect(copied, ['Penjaga Senja']);

    if (find.text('Open Folder').evaluate().isEmpty) {
      await tester.tap(find.byIcon(AppIcons.more).first);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Open Folder'));
    await tester.pumpAndSettle();
    expect(api.openedFolders, [fakeFeaturedPath]);
    await tester.pump(const Duration(seconds: 1));
  });
}
