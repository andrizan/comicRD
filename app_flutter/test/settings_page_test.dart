import 'package:comicrd_flutter/bridge_generated.dart' as bridge;
import 'package:comicrd_flutter/pages/settings_page.dart';
import 'package:comicrd_flutter/state/update_state.dart';
import 'package:comicrd_flutter/utils/forui_theme.dart';
import 'package:comicrd_flutter/utils/update_checker.dart';
import 'package:comicrd_flutter/widgets/soft_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'support/fake_api.dart';
import 'support/router_host.dart';

Future<void> _pump(WidgetTester tester, FakeComicRdApi api) {
  return pumpRoutedPage(tester, api: api, page: const SettingsPage());
}

void main() {
  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'ComicRD',
      packageName: 'comicrd',
      version: '2.8.3',
      buildNumber: '19',
      buildSignature: '',
      installerStore: null,
    );
  });

  testWidgets('renders the sections, version and source status', (
    tester,
  ) async {
    await _pump(tester, FakeComicRdApi());

    expect(find.text('ComicRD 2.8.3'), findsOneWidget);
    expect(find.text('Connected · 4 titles'), findsOneWidget);
    // Section navigation on the left and the headings on the right.
    for (final label in ['Reader', 'Appearance', 'Data & Backup']) {
      expect(find.text(label), findsNWidgets(2));
    }
  });

  testWidgets('theme and locale segments persist', (tester) async {
    final api = FakeComicRdApi();
    await _pump(tester, api);

    await tester.ensureVisible(find.text('Dark'));
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(api.savedSettings['app_theme'], '"dark"');

    await tester.ensureVisible(find.text('Indonesian'));
    await tester.tap(find.text('Indonesian'));
    await tester.pumpAndSettle();
    expect(api.savedSettings['app_locale'], '"id"');
    expect(find.text('Pengaturan'), findsOneWidget);
  });

  testWidgets('reader switches persist each flag', (tester) async {
    final api = FakeComicRdApi();
    await _pump(tester, api);

    final switches = find.byType(SoftSwitch);
    expect(switches, findsNWidgets(3));

    await tester.ensureVisible(switches.at(1));
    await tester.tap(switches.at(1));
    await tester.pumpAndSettle();
    expect(api.savedSettings['unlimited_scroll_up'], 'true');

    await tester.ensureVisible(switches.at(2));
    await tester.tap(switches.at(2));
    await tester.pumpAndSettle();
    expect(api.savedSettings['force_portrait'], 'true');

    await tester.ensureVisible(switches.at(0));
    await tester.tap(switches.at(0));
    await tester.pumpAndSettle();
    expect(api.savedSettings['unlimited_scroll'], 'false');
  });

  testWidgets('sliders persist zoom and page gap', (tester) async {
    final api = FakeComicRdApi();
    await _pump(tester, api);

    await tester.drag(find.byType(Slider).first, const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(api.savedSettings['default_zoom'], isNotNull);
    expect(double.parse(api.savedSettings['default_zoom']!), greaterThan(1));

    await tester.drag(find.byType(Slider).last, const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(api.savedSettings['page_gap'], isNotNull);
    expect(int.parse(api.savedSettings['page_gap']!), greaterThan(12));
  });

  testWidgets('scan shows progress inline and reports completion', (
    tester,
  ) async {
    final api = FakeComicRdApi();
    await _pump(tester, api);

    await tester.tap(find.widgetWithText(SoftButton, 'Scan Library'));
    await tester.pump();
    expect(api.scanStartCalls, 1);

    api.scanProgress = const bridge.ScanProgress(
      processed: 2,
      total: 4,
      currentPath: '/library/Kota di Bawah Hujan',
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Scanning · 2 of 4'), findsOneWidget);
    expect(find.text('/library/Kota di Bawah Hujan'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    api.scanRunning = false;
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(
      find.text('Scan Complete: 4 Comics, 82 Chapters Found'),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('cancel stops a running scan', (tester) async {
    final api = FakeComicRdApi();
    await _pump(tester, api);

    await tester.tap(find.widgetWithText(SoftButton, 'Scan Library'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(api.scanCancelCalls, 1);
    expect(find.widgetWithText(SoftButton, 'Scan Library'), findsOneWidget);
  });

  testWidgets('optimize reports what was removed', (tester) async {
    final api = FakeComicRdApi();
    await _pump(tester, api);

    await tester.ensureVisible(find.text('Optimize'));
    await tester.tap(find.text('Optimize'));
    await tester.pumpAndSettle();

    expect(api.optimizeCalls, 1);
    expect(find.text('Optimization Complete'), findsOneWidget);
    expect(find.text('1 comics removed'), findsOneWidget);
    expect(find.text('2 chapters removed'), findsOneWidget);
  });

  testWidgets('saving the path field registers the folder', (tester) async {
    final api = FakeComicRdApi();
    await _pump(tester, api);

    await tester.enterText(find.byType(TextField), '/mnt/new');
    await tester.tap(find.byIcon(AppIcons.save));
    await tester.pumpAndSettle();

    expect(api.addedLibraries, ['/mnt/new']);
    expect(api.savedSettings['library_source_input'], '"/mnt/new"');
    expect(find.text('Settings Saved'), findsNothing);
  });

  testWidgets('an available update shows its notes and actions', (
    tester,
  ) async {
    await pumpRoutedPage(
      tester,
      api: FakeComicRdApi(),
      page: const SettingsPage(),
      overrides: [
        updateCheckerProvider.overrideWithValue(
          () async => const UpdateInfo(
            latestVersion: '9.9.9',
            downloadUrl: 'https://example.invalid/setup.exe',
            releaseNotes: 'Faster scans',
            releaseUrl: 'https://example.invalid/release',
          ),
        ),
      ],
    );

    await tester.ensureVisible(find.text('Check for Updates'));
    await tester.tap(find.text('Check for Updates'));
    await tester.pumpAndSettle();

    expect(find.text('Update available: v9.9.9'), findsOneWidget);
    expect(find.text('Faster scans'), findsOneWidget);
    expect(find.text('Download Installer'), findsOneWidget);
    expect(find.text('View Release'), findsOneWidget);
  });

  testWidgets('section navigation scrolls the matching section into view', (
    tester,
  ) async {
    await _pump(tester, FakeComicRdApi());

    expect(tester.getCenter(find.text('View on GitHub')).dy, greaterThan(800));

    await tester.tap(find.text('Update & About').first);
    await tester.pumpAndSettle();

    expect(tester.getCenter(find.text('View on GitHub')).dy, lessThan(800));
  });
}
