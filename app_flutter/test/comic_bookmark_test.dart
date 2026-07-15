import 'package:comicrd_flutter/api/comicrd_api.dart';
import 'package:comicrd_flutter/bridge_generated.dart' as bridge;
import 'package:comicrd_flutter/pages/comic_page.dart';
import 'package:comicrd_flutter/state/api_state.dart';
import 'package:comicrd_flutter/state/library_state.dart';
import 'package:comicrd_flutter/utils/forui_theme.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

void main() {
  testWidgets('bookmark button toggles comic bookmark', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1920, 1080);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    const comicPath = '/library/Demo Comic';
    final api = _RecordingApi();
    final container = ProviderContainer(
      overrides: [comicRdApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _ForuiHost(child: ComicPage(comicPath: comicPath)),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.addComicBookmarkCalls, isEmpty);
    expect(api.removeComicBookmarkCalls, isEmpty);

    final bookmarksBefore = await container.read(
      allBookmarksProvider.future,
    );
    expect(bookmarksBefore, isEmpty);

    await tester.tap(find.text('Bookmark'));
    await tester.pump();
    await tester.pump();

    expect(api.addComicBookmarkCalls, [comicPath]);
    expect(api.removeComicBookmarkCalls, isEmpty);

    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    expect(find.text('Bookmarked'), findsOneWidget);

    final bookmarksAfter = await container.read(
      allBookmarksProvider.future,
    );
    expect(bookmarksAfter.length, 1);
    expect(bookmarksAfter.first.comicSourcePath, comicPath);
    expect(container.read(bookmarkCountProvider), 1);

    final bookmarkedIcon = tester.widget<Icon>(
      find.descendant(
        of: find.ancestor(
          of: find.text('Bookmarked'),
          matching: find.byType(GestureDetector),
        ),
        matching: find.byType(Icon),
      ),
    );
    expect(bookmarkedIcon.color, isNotNull);
    expect(bookmarkedIcon.color, ComicReaderColors.light.star);

    await tester.tap(find.text('Bookmarked'));
    await tester.pump();
    await tester.pump();

    expect(api.removeComicBookmarkCalls, [comicPath]);
    expect(api.addComicBookmarkCalls.length, 1);

    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    expect(find.text('Bookmark'), findsOneWidget);

    final unbookmarkedIcon = tester.widget<Icon>(
      find.descendant(
        of: find.ancestor(
          of: find.text('Bookmark'),
          matching: find.byType(GestureDetector),
        ),
        matching: find.byType(Icon),
      ),
    );
    expect(unbookmarkedIcon.color, isNot(ComicReaderColors.light.star));

    final bookmarksRemoved = await container.read(
      allBookmarksProvider.future,
    );
    expect(bookmarksRemoved, isEmpty);
    expect(container.read(bookmarkCountProvider), 0);
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
          child: FTooltipGroup(child: Scaffold(body: child)),
        ),
      ),
    );
  }
}

class _RecordingApi extends ComicRdApi {
  final List<String> addComicBookmarkCalls = [];
  final List<String> removeComicBookmarkCalls = [];
  bool _isBookmarked = false;
  final List<bridge.ComicBookmark> _bookmarks = [];

  @override
  Future<bool> isComicBookmarked(String comicSourcePath) async {
    return _isBookmarked;
  }

  @override
  Future<int> addComicBookmark(String comicSourcePath) async {
    addComicBookmarkCalls.add(comicSourcePath);
    _isBookmarked = true;
    _bookmarks.add(
      bridge.ComicBookmark(
        id: _bookmarks.length + 1,
        comicSourcePath: comicSourcePath,
        comicTitle: comicSourcePath.split('/').last,
        createdAt: 0,
      ),
    );
    return _bookmarks.length;
  }

  @override
  Future<void> removeComicBookmark(String comicSourcePath) async {
    removeComicBookmarkCalls.add(comicSourcePath);
    _isBookmarked = false;
    _bookmarks.removeWhere((b) => b.comicSourcePath == comicSourcePath);
  }

  @override
  Future<List<bridge.ComicBookmark>> listAllBookmarks() async {
    return List.unmodifiable(_bookmarks);
  }

  @override
  Future<List<bridge.SettingEntry>> listSettings() async => const [];

  @override
  Future<List<bridge.RawChapter>> listComicChaptersRaw(
    String comicSourcePath,
  ) async => const [];

  @override
  Future<List<String>> listChapterFavorites(String comicSourcePath) async =>
      const [];

  @override
  Future<List<bridge.ReadingHistoryEntry>> listReadingHistory() async =>
      const [];

  @override
  Future<Uint8List> getComicThumbnail(
    String comicSourcePath, {
    int maxWidth = 0,
    int maxHeight = 0,
  }) async =>
      throw Exception('no thumbnail in test');
}
