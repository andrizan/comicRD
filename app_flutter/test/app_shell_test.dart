import 'package:comicrd_flutter/app.dart';
import 'package:comicrd_flutter/pages/library_page.dart';
import 'package:comicrd_flutter/pages/settings_page.dart';
import 'package:comicrd_flutter/state/api_state.dart';
import 'package:comicrd_flutter/utils/forui_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fake_api.dart';

Future<void> _pumpApp(WidgetTester tester, FakeComicRdApi api) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [comicRdApiProvider.overrideWithValue(api)],
      child: const ComicRdApp(),
    ),
  );
  await tester.pumpAndSettle();
  // The router is app-global: start every test from the library route.
  if (find.byType(LibraryPage).evaluate().isEmpty) {
    GoRouter.of(tester.element(find.byType(ComicRdShell))).go('/');
    await tester.pumpAndSettle();
  }
}

/// The shell's window-drag detector also listens for double taps, so a tap
/// only wins the gesture arena after the double-tap timeout.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sidebar switches library tabs and persists the choice', (
    tester,
  ) async {
    final api = FakeComicRdApi();
    await _pumpApp(tester, api);

    await _tap(tester, find.text('History'));
    expect(api.savedSettings['library_selected_tab'], '"history"');
    expect(find.text('Latest Reading'), findsOneWidget);

    await _tap(tester, find.text('Favorites'));
    expect(api.savedSettings['library_selected_tab'], '"favorites"');
    expect(find.text('2 Titles Saved'), findsOneWidget);

    await _tap(tester, find.text('Settings'));
    expect(find.byType(SettingsPage), findsOneWidget);
  });

  testWidgets('sidebar badges show library and favorite counts', (
    tester,
  ) async {
    await _pumpApp(tester, FakeComicRdApi());

    expect(find.text('4'), findsWidgets);
    expect(find.text('2'), findsWidgets);
  });

  testWidgets('status card reflects the library source state', (tester) async {
    await _pumpApp(tester, FakeComicRdApi());
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text(fakeRoot), findsOneWidget);

    await _pumpApp(tester, FakeComicRdApi(configured: false));
    expect(find.text('Not Configured'), findsOneWidget);

    await _pumpApp(tester, FakeComicRdApi(sourceError: 'path not found'));
    expect(find.text('Unavailable'), findsOneWidget);
  });

  testWidgets('status card opens Settings', (tester) async {
    await _pumpApp(tester, FakeComicRdApi());

    await _tap(tester, find.text('Local Library'));

    expect(find.byType(SettingsPage), findsOneWidget);
  });

  testWidgets('collapse hides the labels and keeps the icons', (tester) async {
    await _pumpApp(tester, FakeComicRdApi());
    expect(find.text('Favorites'), findsOneWidget);

    await _tap(tester, find.byIcon(AppIcons.panelLeft));

    expect(find.text('Favorites'), findsNothing);
    expect(find.byIcon(AppIcons.star), findsWidgets);
    expect(find.byIcon(AppIcons.settings), findsOneWidget);

    // Expanding again animates the width while the wide layout is already
    // built; sample the animation midway to make sure nothing overflows.
    await tester.tap(find.bySemanticsLabel('Menu'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.text('Favorites'), findsOneWidget);
  });

  testWidgets('Ctrl+T and Ctrl+L persist theme and locale', (tester) async {
    final api = FakeComicRdApi();
    await _pumpApp(tester, api);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(api.savedSettings['app_theme'], '"dark"');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(api.savedSettings['app_locale'], '"id"');
    expect(find.text('Pustaka'), findsWidgets);
  });
}
