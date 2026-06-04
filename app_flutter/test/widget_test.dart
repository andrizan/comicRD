import 'package:comicrd_flutter/app.dart';
import 'package:comicrd_flutter/api/comicrd_api.dart';
import 'package:comicrd_flutter/bridge_generated.dart' as bridge;
import 'package:comicrd_flutter/state/api_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders ComicRD shell with library tabs', (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    expect(find.text('ComicRD'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Bookmarks'), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
  });

  testWidgets('toggles locale from English to Indonesian', (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.translate_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Riwayat'), findsOneWidget);
    expect(find.text('Pustaka'), findsOneWidget);
    expect(find.text('Bookmark'), findsOneWidget);
  });
}

Widget _testApp() {
  return ProviderScope(
    overrides: [comicRdApiProvider.overrideWithValue(const _FakeComicRdApi())],
    child: const ComicRdApp(),
  );
}

class _FakeComicRdApi extends ComicRdApi {
  const _FakeComicRdApi();

  @override
  Future<List<bridge.SettingEntry>> listSettings() async {
    return const [
      bridge.SettingEntry(
        key: 'library_source_input',
        valueJson: '""',
        updatedAt: 0,
      ),
      bridge.SettingEntry(key: 'default_zoom', valueJson: '1', updatedAt: 0),
      bridge.SettingEntry(key: 'page_gap', valueJson: '10', updatedAt: 0),
      bridge.SettingEntry(
        key: 'image_pipeline_profile',
        valueJson: '"balanced"',
        updatedAt: 0,
      ),
      bridge.SettingEntry(key: 'app_theme', valueJson: '"light"', updatedAt: 0),
      bridge.SettingEntry(key: 'app_locale', valueJson: '"en"', updatedAt: 0),
    ];
  }

  @override
  Future<void> setSetting(String key, String valueJson) async {}

  @override
  Future<bridge.LibrarySourceStatus> checkLibrarySource() async {
    return const bridge.LibrarySourceStatus(
      configured: false,
      path: '',
      exists: false,
      isDir: false,
      readable: false,
    );
  }

  @override
  Future<List<bridge.RawComic>> listLibraryComicsRaw({
    required bridge.SortBy sortBy,
    required bridge.SortDir sortDir,
  }) async {
    return const [];
  }

  @override
  Future<List<bridge.ReadingHistoryEntry>> listReadingHistory() async {
    return const [];
  }

  @override
  Future<List<bridge.ComicBookmark>> listAllBookmarks() async {
    return const [];
  }
}
