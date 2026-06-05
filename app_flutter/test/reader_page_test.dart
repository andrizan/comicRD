import 'dart:typed_data';

import 'package:comicrd_flutter/api/comicrd_api.dart';
import 'package:comicrd_flutter/bridge_generated.dart' as bridge;
import 'package:comicrd_flutter/pages/reader_page.dart';
import 'package:comicrd_flutter/state/api_state.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('starts at first page when saved progress exists', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _ReaderFakeComicRdApi(lastPage: 27, pageCount: 33);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [comicRdApiProvider.overrideWithValue(api)],
        child: const FluentApp(home: ReaderPage(chapterId: 7)),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(api.renderedPageIndices, contains(0));
    expect(api.prefetchedWindows, contains(equals([0, 1, 2])));
    expect(api.evictedWindows, contains(equals([0, 1, 2])));
  });

  testWidgets('renders pages around current after scroll settles', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _ReaderFakeComicRdApi(lastPage: 0, pageCount: 33);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [comicRdApiProvider.overrideWithValue(api)],
        child: const FluentApp(home: ReaderPage(chapterId: 7)),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final rendered = api.renderedPageIndices;
    expect(rendered, isNotEmpty);
    expect(rendered.length, lessThanOrEqualTo(7));
  });

  testWidgets('prefetch window is 5 pages', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _ReaderFakeComicRdApi(lastPage: 10, pageCount: 33);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [comicRdApiProvider.overrideWithValue(api)],
        child: const FluentApp(home: ReaderPage(chapterId: 7)),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(api.prefetchedWindows, isNotEmpty);
    for (final window in api.prefetchedWindows) {
      expect(window.length, lessThanOrEqualTo(5));
    }
    expect(api.evictedWindows, isNotEmpty);
  });
}

class _ReaderFakeComicRdApi extends ComicRdApi {
  _ReaderFakeComicRdApi({required this.lastPage, required this.pageCount});

  final int lastPage;
  final int pageCount;
  final renderedPageIndices = <int>[];
  final prefetchedWindows = <List<int>>[];
  final evictedWindows = <List<int>>[];
  final savedProgress = <bridge.SaveProgressPayload>[];

  @override
  Future<List<bridge.SettingEntry>> listSettings() async {
    return const [
      bridge.SettingEntry(key: 'default_zoom', valueJson: '1', updatedAt: 0),
      bridge.SettingEntry(key: 'page_gap', valueJson: '10', updatedAt: 0),
      bridge.SettingEntry(key: 'app_theme', valueJson: '"dark"', updatedAt: 0),
      bridge.SettingEntry(key: 'app_locale', valueJson: '"en"', updatedAt: 0),
    ];
  }

  @override
  Future<bridge.ChapterContext?> getChapterContext(int chapterId) async {
    return bridge.ChapterContext(
      chapterId: chapterId,
      comicId: 1,
      comicTitle: 'Kaichou wa Maid-sama!',
      title: 'Chapter 28',
      comicSourcePath: '/library/Kaichou wa Maid-sama!',
      chapterSourcePath: '/library/Kaichou wa Maid-sama!/Chapter 28',
      chapterIndex: 28,
      chapterPosition: 28,
      chapterTotal: 33,
    );
  }

  @override
  Future<List<bridge.PageInfo>> getChapterPages(int chapterId) async {
    return [
      for (var index = 0; index < pageCount; index++)
        bridge.PageInfo(
          index: index,
          name: '${index + 1}.png',
          width: 900,
          height: 1300,
        ),
    ];
  }

  @override
  Future<bridge.ReadingProgress?> getProgress(int chapterId) async {
    return bridge.ReadingProgress(
      chapterId: chapterId,
      lastPage: lastPage,
      totalPages: pageCount,
      isRead: false,
      updatedAt: 0,
    );
  }

  @override
  Future<bridge.RenderedPage> renderPageVariant(
    bridge.RenderPagePayload payload,
  ) async {
    renderedPageIndices.add(payload.pageIndex);
    return bridge.RenderedPage(
      bytes: Uint8List.fromList(_onePixelPng),
      mime: 'image/png',
      width: 900,
      height: 1300,
      cacheKey: 'page-${payload.pageIndex}',
    );
  }

  @override
  Future<void> prefetchPages(bridge.PrefetchPagesPayload payload) async {
    prefetchedWindows.add(payload.pageIndices.toList());
  }

  @override
  Future<void> evictChapterPages({
    required int chapterId,
    required List<int> keepPages,
  }) async {
    evictedWindows.add(keepPages.toList());
  }

  @override
  Future<void> saveProgress(bridge.SaveProgressPayload payload) async {
    savedProgress.add(payload);
  }
}

const _onePixelPng = [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
  0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
  0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
  0x42, 0x60, 0x82,
];
