import 'package:comicrd_flutter/app.dart';
import 'package:comicrd_flutter/api/comicrd_api.dart';
import 'package:comicrd_flutter/bridge_generated.dart' as bridge;
import 'package:comicrd_flutter/state/api_state.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders ComicRD app', (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    expect(find.text('ComicRD'), findsOneWidget);
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
    return const [
      bridge.RawComic(
        key: '/library/Demo Comic',
        title: 'Demo Comic',
        sourcePath: '/library/Demo Comic',
        sourceType: 'folder',
        libraryPath: '/library',
        dateModified: 0,
        chapterCount: 0,
        readChapterCount: 0,
        inProgressChapterCount: 0,
      ),
    ];
  }

  @override
  Future<List<String>> listComicsWithProgress() async {
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

  @override
  Future<List<bridge.RawChapter>> listComicChaptersRaw(
    String comicSourcePath,
  ) async {
    return const [
      bridge.RawChapter(
        key: '/library/Demo Comic/Chapter 1',
        title: 'Chapter 1',
        chapterIndex: 1,
        sourcePath: '/library/Demo Comic/Chapter 1',
        sourceType: 'folder',
        dateModified: 0,
        pageCount: 12,
        isRead: false,
        lastPage: 0,
        totalPages: 12,
      ),
    ];
  }

  @override
  Future<List<String>> listChapterFavorites(String comicSourcePath) async {
    return const [];
  }
}
