import 'package:comicrd_flutter/api/comicrd_api.dart';
import 'package:comicrd_flutter/bridge_generated.dart' as bridge;
import 'package:comicrd_flutter/pages/comic_page.dart';
import 'package:comicrd_flutter/state/api_state.dart';
import 'package:comicrd_flutter/state/library_state.dart';
import 'package:comicrd_flutter/utils/forui_theme.dart';
import 'package:material_ui/material_ui.dart';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

void main() {
  testWidgets('favorite button toggles comic favorite', (tester) async {
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

    expect(api.addFavoriteCalls, isEmpty);
    expect(api.removeFavoriteCalls, isEmpty);

    final favoritesBefore = await container.read(
      allFavoritesProvider.future,
    );
    expect(favoritesBefore, isEmpty);

    await tester.tap(find.text('Add Favorite'));
    await tester.pump();
    await tester.pump();

    expect(api.addFavoriteCalls, [comicPath]);
    expect(api.removeFavoriteCalls, isEmpty);

    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    expect(find.text('Remove Favorite'), findsOneWidget);

    final favoritesAfter = await container.read(
      allFavoritesProvider.future,
    );
    expect(favoritesAfter.length, 1);
    expect(favoritesAfter.first.comicSourcePath, comicPath);
    expect(container.read(favoriteCountProvider), 1);

    final bookmarkedIcon = tester.widget<Icon>(
      find.descendant(
        of: find.ancestor(
          of: find.text('Remove Favorite'),
          matching: find.byType(GestureDetector),
        ),
        matching: find.byType(Icon),
      ),
    );
    expect(bookmarkedIcon.color, isNotNull);
    expect(bookmarkedIcon.color, ComicReaderColors.light.star);

    await tester.tap(find.text('Remove Favorite'));
    await tester.pump();
    await tester.pump();

    expect(api.removeFavoriteCalls, [comicPath]);
    expect(api.addFavoriteCalls.length, 1);

    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    expect(find.text('Add Favorite'), findsOneWidget);

    final unbookmarkedIcon = tester.widget<Icon>(
      find.descendant(
        of: find.ancestor(
          of: find.text('Add Favorite'),
          matching: find.byType(GestureDetector),
        ),
        matching: find.byType(Icon),
      ),
    );
    expect(unbookmarkedIcon.color, isNot(ComicReaderColors.light.star));

    final favoritesRemoved = await container.read(
      allFavoritesProvider.future,
    );
    expect(favoritesRemoved, isEmpty);
    expect(container.read(favoriteCountProvider), 0);
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
  final List<String> addFavoriteCalls = [];
  final List<String> removeFavoriteCalls = [];
  bool _isFavorited = false;
  final List<bridge.Favorite> _favorites = [];

  @override
  Future<bool> isFavorited({required String comicSourcePath}) async {
    return _isFavorited;
  }

  @override
  Future<int> addFavorite({required String comicSourcePath}) async {
    addFavoriteCalls.add(comicSourcePath);
    _isFavorited = true;
    _favorites.add(
      bridge.Favorite(
        id: _favorites.length + 1,
        comicSourcePath: comicSourcePath,
        comicTitle: comicSourcePath.split('/').last,
        createdAt: 0,
      ),
    );
    return _favorites.length;
  }

  @override
  Future<void> removeFavorite({required String comicSourcePath}) async {
    removeFavoriteCalls.add(comicSourcePath);
    _isFavorited = false;
    _favorites.removeWhere((b) => b.comicSourcePath == comicSourcePath);
  }

  @override
  Future<List<bridge.Favorite>> listFavorites() async {
    return List.unmodifiable(_favorites);
  }

  @override
  Future<List<bridge.SettingEntry>> listSettings() async => const [];

  @override
  Future<List<bridge.RawChapter>> listComicChaptersRaw(
    String comicSourcePath,
  ) async => const [];

  @override
  Future<List<String>> listBookmarks({required String comicSourcePath}) async =>
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
