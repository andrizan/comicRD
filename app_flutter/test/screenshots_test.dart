// Renders every screen headlessly with the real fonts and sample data, and
// writes PNGs for the README / visual review. Skipped unless
// COMICRD_SCREENSHOTS=1 is set, because it takes ~20 s and writes files:
//
//   COMICRD_SCREENSHOTS=1 flutter test test/screenshots_test.dart
//
// Output goes to COMICRD_SCREENSHOT_DIR (default: build/screenshots).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:comicrd_flutter/app.dart';
import 'package:comicrd_flutter/bridge_generated.dart' as bridge;
import 'package:comicrd_flutter/pages/reader_page.dart';
import 'package:comicrd_flutter/routes/path_codec.dart';
import 'package:comicrd_flutter/state/api_state.dart';
import 'package:comicrd_flutter/utils/forui_theme.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'support/fake_api.dart';

final bool _enabled = Platform.environment['COMICRD_SCREENSHOTS'] == '1';
final String _outDir =
    Platform.environment['COMICRD_SCREENSHOT_DIR'] ?? 'build/screenshots';
final _shotKey = GlobalKey();
const _root = '/home/andrizan/Comics';
const _featured = '$_root/Twilight Keeper';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!_enabled) return;
    PackageInfo.setMockInitialValues(
      appName: 'ComicRD',
      packageName: 'comicrd',
      version: '2.8.3',
      buildNumber: '19',
      buildSignature: '',
      installerStore: null,
    );
    final jakarta = FontLoader('Plus Jakarta Sans');
    for (final weight in [
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
    ]) {
      jakarta.addFont(
        rootBundle.load('assets/fonts/PlusJakartaSans-$weight.ttf'),
      );
    }
    await jakarta.load();
    final lucide = FontLoader('packages/forui_lucide/ForuiLucideIcons');
    lucide.addFont(rootBundle.load('packages/forui_lucide/assets/lucide.ttf'));
    await lucide.load();
    Directory(_outDir).createSync(recursive: true);
  });

  testWidgets('light screens', skip: !_enabled, (tester) async {
    final api = await _ShotApi.create(tester);
    await _pumpApp(tester, api);
    _go(tester, '/');
    await _shoot(tester, '01-library-grid');

    await tester.tap(find.byIcon(AppIcons.list));
    await _shoot(tester, '02-library-list');

    await tester.tap(find.text('History'));
    await _shoot(tester, '03-history');

    await tester.tap(find.text('Favorites'));
    await _shoot(tester, '04-favorites');

    _go(tester, '/comic/${encodeRoutePath(_featured)}');
    await _shoot(tester, '05-comic');

    _go(tester, '/settings');
    await _shoot(tester, '06-settings');

    _go(tester, '/reader/$fakeReaderChapterId');
    await _shoot(tester, '07-reader');
    await tester.tap(find.text('Display'));
    await _shoot(tester, '08-reader-display');
    await tester.tap(find.text('Mark'));
    await _shoot(tester, '09-reader-mark');

    // Unlimited scroll chains the next chapter in below this one: scroll to
    // the end so it loads, then stop on the separator between the two.
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    final endOfChapter = position.maxScrollExtent;
    position.jumpTo(endOfChapter - 100);
    await _settle(tester);
    // The old end plus the viewport is the chapter's bottom edge, less the
    // 90 px of bottom padding; park the separator a little below the top.
    position.jumpTo(endOfChapter + position.viewportDimension - 90 - 250);
    await _settle(tester);
    await _shoot(tester, '17-reader-chapter-break');

    _go(tester, '/');
    await _settle(tester);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('welcome screen', skip: !_enabled, (tester) async {
    final api = await _ShotApi.create(tester, configured: false);
    await _pumpApp(tester, api);
    _go(tester, '/');
    await _shoot(tester, '10-welcome');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('dark screens', skip: !_enabled, (tester) async {
    final api = await _ShotApi.create(tester, theme: 'dark');
    await _pumpApp(tester, api);
    _go(tester, '/');
    await _shoot(tester, '11-dark-library');
    _go(tester, '/comic/${encodeRoutePath(_featured)}');
    await _shoot(tester, '12-dark-comic');
    _go(tester, '/settings');
    await _shoot(tester, '13-dark-settings');
    _go(tester, '/');
    await _settle(tester);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('narrow screens', skip: !_enabled, (tester) async {
    final api = await _ShotApi.create(tester);
    await _pumpApp(tester, api, size: const Size(960, 640));
    _go(tester, '/');
    await _shoot(tester, '14-narrow-library');
    _go(tester, '/comic/${encodeRoutePath(_featured)}');
    await _shoot(tester, '15-narrow-comic');
    _go(tester, '/reader/$fakeReaderChapterId');
    await _shoot(tester, '16-narrow-reader');
    _go(tester, '/');
    await _settle(tester);
    await tester.pump(const Duration(seconds: 3));
  });
}

Future<void> _pumpApp(
  WidgetTester tester,
  FakeComicRdApi api, {
  Size size = const Size(1440, 900),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [comicRdApiProvider.overrideWithValue(api)],
      child: RepaintBoundary(key: _shotKey, child: const ComicRdApp()),
    ),
  );
  await _settle(tester);
}

void _go(WidgetTester tester, String location) {
  final finder = find.byWidgetPredicate(
    (widget) => widget is ComicRdShell || widget is ReaderPage,
  );
  GoRouter.of(tester.element(finder.first)).go(location);
}

/// Pumps with real time passing so image decodes and provider futures land.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _shoot(WidgetTester tester, String name) async {
  await _settle(tester);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_shotKey),
  );
  final image = await tester.runAsync(() => boundary.toImage());
  final data = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );
  File('$_outDir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  image!.dispose();
}

// ---------------------------------------------------------------------------
// Sample art: gradient covers and panelled comic pages drawn with dart:ui.
// ---------------------------------------------------------------------------

const _palette = [
  (Color(0xFF8B7BFF), Color(0xFF3D3564)),
  (Color(0xFF5EC2D6), Color(0xFF24506B)),
  (Color(0xFFFFC37A), Color(0xFFC2543B)),
  (Color(0xFF9AD6B8), Color(0xFF2E6B5A)),
  (Color(0xFFFF9EB5), Color(0xFF7A3A6B)),
  (Color(0xFFC8B27A), Color(0xFF5B4630)),
  (Color(0xFF7BA3FF), Color(0xFF2B3F8F)),
  (Color(0xFF6EC7D9), Color(0xFF2A7A8F)),
  (Color(0xFFB3A6FF), Color(0xFF5B4BC4)),
  (Color(0xFFF2A07B), Color(0xFF8C3B3B)),
];

Future<Uint8List> _png(
  int width,
  int height,
  void Function(ui.Canvas canvas, double w, double h) draw,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  draw(canvas, width.toDouble(), height.toDouble());
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<Uint8List> _cover(int seed) {
  final (a, b) = _palette[seed % _palette.length];
  return _png(200, 300, (canvas, w, h) {
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, w, h),
      ui.Paint()
        ..shader = ui.Gradient.linear(
          seed.isEven ? ui.Offset(0, 0) : ui.Offset(w, 0),
          seed.isEven ? ui.Offset(w, h) : ui.Offset(0, h),
          [a, b],
        ),
    );
    canvas.drawCircle(
      ui.Offset(
        w * (0.24 + (seed * 17 % 52) / 100),
        h * (0.16 + (seed * 23 % 26) / 100),
      ),
      w * 0.11,
      ui.Paint()..color = const Color(0x8CFFFFFF),
    );
    canvas.drawRect(
      ui.Rect.fromLTWH(0, h * 0.45, w, h * 0.55),
      ui.Paint()
        ..shader = ui.Gradient.linear(ui.Offset(0, h * 0.45), ui.Offset(0, h), [
          const Color(0x00140F23),
          const Color(0x66140F23),
        ]),
    );
  });
}

Future<Uint8List> _page(int seed) {
  return _png(900, 1300, (canvas, w, h) {
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, w, h),
      ui.Paint()..color = const Color(0xFFF5F2EA),
    );
    final border = ui.Paint()
      ..color = const Color(0xFF17141F)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 6;
    final panels = switch (seed % 3) {
      0 => [
        ui.Rect.fromLTWH(40, 40, 820, 520),
        ui.Rect.fromLTWH(40, 600, 400, 660),
        ui.Rect.fromLTWH(480, 600, 380, 300),
        ui.Rect.fromLTWH(480, 940, 380, 320),
      ],
      1 => [
        ui.Rect.fromLTWH(40, 40, 400, 600),
        ui.Rect.fromLTWH(480, 40, 380, 600),
        ui.Rect.fromLTWH(40, 680, 820, 580),
      ],
      _ => [
        ui.Rect.fromLTWH(40, 40, 820, 380),
        ui.Rect.fromLTWH(40, 460, 260, 800),
        ui.Rect.fromLTWH(340, 460, 520, 380),
        ui.Rect.fromLTWH(340, 880, 520, 380),
      ],
    };
    for (var i = 0; i < panels.length; i++) {
      final (a, b) = _palette[(seed * 3 + i) % _palette.length];
      final rect = panels[i];
      canvas.drawRect(
        rect,
        ui.Paint()
          ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomRight, [a, b]),
      );
      canvas.drawCircle(
        ui.Offset(rect.left + rect.width * 0.7, rect.top + rect.height * 0.3),
        rect.shortestSide * 0.18,
        ui.Paint()..color = const Color(0x99FFFFFF),
      );
      canvas.drawRect(rect, border);
    }
  });
}

// ---------------------------------------------------------------------------
// A lived-in library on top of the shared fake.
// ---------------------------------------------------------------------------

class _ShotApi extends FakeComicRdApi {
  _ShotApi._({
    required this.covers,
    required this.pages,
    required super.theme,
    required super.configured,
    required super.comics,
    required super.history,
    required super.favorites,
    required super.chapters,
    required super.chapterBookmarks,
  }) : super(
         locale: 'en',
         pageCount: 24,
         lastPage: 15,
         pageBookmarks: {4, 15, 20},
       );

  static Future<_ShotApi> create(
    WidgetTester tester, {
    String theme = 'light',
    bool configured = true,
  }) async {
    final covers = <String, Uint8List>{};
    final pages = <Uint8List>[];
    await tester.runAsync(() async {
      for (var i = 0; i < _comics.length; i++) {
        covers['$_root/${_comics[i].$1}'] = await _cover(i);
      }
      for (var i = 0; i < 3; i++) {
        pages.add(await _page(i));
      }
    });
    return _ShotApi._(
      covers: covers,
      pages: pages,
      theme: theme,
      configured: configured,
      comics: [
        for (final (title, chapters, read, progress, days, gb, _) in _comics)
          bridge.RawComic(
            title: title,
            sourcePath: '$_root/$title',
            sourceType: 'folder',
            dateModified: _daysAgo(days),
            chapterCount: chapters,
            readChapterCount: read,
            inProgressChapterCount: progress,
            sizeBytes: (gb * 1073741824).round(),
          ),
      ],
      history: [
        _entry(
          'Twilight Keeper',
          'Chapter 27 · The Door Never Opened',
          7,
          15,
          24,
          0,
        ),
        _entry('City Beneath the Rain', 'Chapter 4 · Puddles', 12, 2, 22, 0),
        _entry('Full Moon Recipe', 'Chapter 21 · Secret Spice', 19, 19, 24, 1),
        _entry(
          'Last Day at Station 9',
          'Chapter 11 · Empty Platform',
          23,
          23,
          24,
          3,
          isRead: true,
        ),
        _entry(
          'Song of the Iron Forest',
          'Chapter 7 · Rusted Gate',
          31,
          7,
          31,
          6,
        ),
        _entry(
          'Umbrella Detective',
          'Chapter 14 · Rain Out of Season',
          40,
          17,
          29,
          10,
        ),
      ],
      favorites: {
        for (final (title, _, _, _, _, _, favorite) in _comics)
          if (favorite) '$_root/$title',
      },
      chapters: {_featured: _featuredChapters()},
      chapterBookmarks: {
        '$_featured/Chapter 25',
        '$_featured/Chapter 23',
        '$_featured/Chapter 14',
      },
    );
  }

  final Map<String, Uint8List> covers;
  final List<Uint8List> pages;

  static final _now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  static int _daysAgo(int days) => _now - days * 86400;

  // title, chapters, read, inProgress, daysAgo, GB, favorite
  static const _comics = <(String, int, int, int, int, double, bool)>[
    ('Twilight Keeper', 30, 24, 2, 3, 3.2, true),
    ('City Beneath the Rain', 22, 2, 1, 4, 1.8, false),
    ('Full Moon Recipe', 24, 19, 1, 11, 2.1, true),
    ('Paper Ocean', 18, 0, 0, 0, 1.2, false),
    ('Last Day at Station 9', 12, 11, 0, 15, 0.94, false),
    ('Coffee Knight', 45, 0, 0, 23, 5.6, false),
    ('Song of the Iron Forest', 16, 6, 1, 7, 1.4, true),
    ('Child of the Sea', 9, 0, 0, 0, 0.6, false),
    ('Umbrella Detective', 31, 13, 1, 9, 2.7, false),
    ('Message from Orbit', 27, 0, 0, 31, 2.3, false),
    ('Cat Atlas', 12, 0, 0, 40, 0.8, true),
    ('Second Autumn', 20, 9, 0, 52, 1.6, false),
  ];

  static bridge.ReadingHistoryEntry _entry(
    String title,
    String chapter,
    int chapterId,
    int lastPage,
    int total,
    int days, {
    bool isRead = false,
  }) {
    return bridge.ReadingHistoryEntry(
      comicSourcePath: '$_root/$title',
      comicTitle: title,
      chapterTitle: chapter,
      chapterSourcePath: '$_root/$title/$chapter',
      chapterId: chapterId,
      lastPage: lastPage,
      totalPages: total,
      isRead: isRead,
      updatedAt: _daysAgo(days),
    );
  }

  static List<bridge.RawChapter> _featuredChapters() {
    const names = {
      30: 'Lighthouse',
      29: 'The Late Letter',
      28: 'Nameless Sea',
      27: 'The Door Never Opened',
      26: 'Back to the Pier',
      25: 'Morning Bell',
      24: 'Fog',
      23: 'Guest from Across',
    };
    return [
      for (var index = 1; index <= 30; index++)
        bridge.RawChapter(
          title: names.containsKey(index)
              ? 'Chapter $index · ${names[index]}'
              : 'Chapter $index',
          chapterIndex: index,
          sourcePath: '$_featured/Chapter $index',
          sourceType: index == 29 ? 'cbz' : 'folder',
          dateModified: index >= 29 ? _now : _daysAgo((31 - index) * 7),
          pageCount: 26 + (index * 7) % 13,
          isRead: index <= 26,
          lastPage: index == 27 ? 11 : 0,
          totalPages: index == 27 ? 34 : 26 + (index * 7) % 13,
          sizeBytes: 90000000 + index * 1234567,
          progressUpdatedAt: index == 27 ? _now : 0,
        ),
    ];
  }

  @override
  Future<bridge.LibrarySourceStatus> checkLibrarySource() async {
    return bridge.LibrarySourceStatus(
      configured: configured,
      path: configured ? _root : '',
      exists: configured,
      isDir: configured,
      readable: configured,
    );
  }

  @override
  Future<List<bridge.SettingEntry>> listSettings() async {
    final entries = await super.listSettings();
    return [
      for (final entry in entries)
        if (entry.key == 'library_source_input')
          bridge.SettingEntry(
            key: entry.key,
            valueJson: configured ? '"$_root"' : '""',
          )
        else
          entry,
      const bridge.SettingEntry(key: 'chapter_sort_dir', valueJson: '"desc"'),
    ];
  }

  @override
  Future<Uint8List> getComicThumbnail(
    String sourcePath, {
    int maxWidth = 200,
    int maxHeight = 300,
  }) async {
    return covers[sourcePath] ?? covers.values.first;
  }

  @override
  Future<bridge.ChapterContext?> getChapterContext(int chapterId) async {
    return bridge.ChapterContext(
      chapterId: chapterId,
      comicId: 1,
      comicTitle: 'Twilight Keeper',
      title: 'Chapter 27 · The Door Never Opened',
      comicSourcePath: _featured,
      chapterSourcePath: '$_featured/Chapter 27',
      chapterIndex: 27,
      chapterPosition: 27,
      chapterTotal: 30,
      prevChapterId: chapterId - 1,
      nextChapterId: chapterId + 1,
    );
  }

  @override
  Future<bridge.RenderedPage> renderPageTile(
    bridge.RenderPageTilePayload payload,
  ) async {
    return bridge.RenderedPage(
      bytes: pages[payload.pageIndex % pages.length],
      mime: 'image/png',
      width: 900,
      height: 1300,
    );
  }
}
