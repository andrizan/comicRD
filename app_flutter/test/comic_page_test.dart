import 'package:comicrd_flutter/api/comicrd_api.dart';
import 'package:comicrd_flutter/bridge_generated.dart' as bridge;
import 'package:comicrd_flutter/pages/comic_page.dart';
import 'package:comicrd_flutter/state/api_state.dart';
import 'package:comicrd_flutter/state/comic_state.dart';
import 'package:comicrd_flutter/utils/forui_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

void main() {
  testWidgets('scrolls the chapter list to the last opened chapter on load', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1920, 1080);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    const comicPath = '/library/Demo Comic';
    const chapterPath = '/library/Demo Comic/Chapter 30';
    final container = ProviderContainer(
      overrides: [
        comicRdApiProvider.overrideWithValue(const _ManyChaptersApi()),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(lastOpenedChapterProvider.notifier)
        .remember(comicPath, chapterPath);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _ForuiHost(child: ComicPage(comicPath: comicPath)),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Chapter 30'), findsOneWidget);
    expect(find.text('Chapter 19'), findsNothing);
    // Chapter 30 should be near the top of the visible chapter list area.
    expect(tester.getTopLeft(find.text('Chapter 30')).dy, lessThan(650));
  });

  testWidgets('chapter back-to-top button returns the chapter list to top', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    const comicPath = '/library/Demo Comic';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRdApiProvider.overrideWithValue(const _ManyChaptersApi()),
        ],
        child: const _ForuiHost(child: ComicPage(comicPath: comicPath)),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey('chapter-back-to-top-button')),
      findsNothing,
    );

    await tester.drag(
      find.byType(Scrollable).last,
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('chapter-back-to-top-button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('chapter-back-to-top-button')));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    expect(find.text('Chapter 1'), findsOneWidget);
  });
}

class _ForuiHost extends StatelessWidget {
  const _ForuiHost({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: FTheme(
        data: ComicReaderFTheme.light,
        child: FToaster(
          child: FTooltipGroup(
            child: Scaffold(body: child),
          ),
        ),
      ),
    );
  }
}

class _ManyChaptersApi extends ComicRdApi {
  const _ManyChaptersApi();

  @override
  Future<List<bridge.SettingEntry>> listSettings() async {
    return const [
      bridge.SettingEntry(key: 'chapter_sort_by', valueJson: '"chapter_index"'),
      bridge.SettingEntry(key: 'chapter_sort_dir', valueJson: '"asc"'),
      bridge.SettingEntry(key: 'app_theme', valueJson: '"light"'),
      bridge.SettingEntry(key: 'app_locale', valueJson: '"en"'),
    ];
  }

  @override
  Future<List<bridge.RawChapter>> listComicChaptersRaw(
    String comicSourcePath,
  ) async {
    return [
      for (var index = 1; index <= 327; index++)
        bridge.RawChapter(
          title: 'Chapter $index',
          chapterIndex: index,
          sourcePath: '$comicSourcePath/Chapter $index',
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

  @override
  Future<List<bridge.ReadingHistoryEntry>> listReadingHistory() async {
    return const [];
  }

  @override
  Future<bool> isComicBookmarked(String comicSourcePath) async {
    return false;
  }
}
