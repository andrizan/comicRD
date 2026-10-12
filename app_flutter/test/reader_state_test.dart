import 'dart:typed_data';

import 'package:comicrd_flutter/api/comicrd_api.dart';
import 'package:comicrd_flutter/bridge_generated.dart' as bridge;
import 'package:comicrd_flutter/state/api_state.dart';
import 'package:comicrd_flutter/state/reader_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('readerDataProvider', () {
    test('exposes tiles flattened once from the page list', () async {
      final container = ProviderContainer(
        overrides: [
          comicRdApiProvider.overrideWithValue(const _PagesOnlyApi()),
        ],
      );
      addTearDown(container.dispose);

      final data = await container.read(readerDataProvider(7).future);

      expect(data.pages, hasLength(2));
      // Memoized per chapter load: a getter that re-flattened on every
      // access would hand out a fresh list each time (the per-scroll
      // allocation this field exists to avoid).
      expect(identical(data.tiles, data.tiles), isTrue);
      final shape = data.tiles
          .map(
            (t) =>
                (t.pageIndex, t.tileIndex, t.isLastTileOfPage, t.pixelHeight),
          )
          .toList();
      expect(shape, [
        (0, 0, false, 2048),
        (0, 1, true, 2048),
        (1, 0, true, 1000),
      ]);
      final recomputed = flattenTiles(data.pages)
          .map(
            (t) =>
                (t.pageIndex, t.tileIndex, t.isLastTileOfPage, t.pixelHeight),
          )
          .toList();
      expect(shape, recomputed);
    });
  });

  group('initialReaderPageForProgress', () {
    test('starts from saved page when chapter is in progress', () {
      final page = initialReaderPageForProgress(
        progress: const bridge.ReadingProgress(
          chapterId: 7,
          lastPage: 11,
          totalPages: 33,
          isRead: false,
        ),
        pageCount: 33,
      );

      expect(page, 11);
    });

    test('starts from first page when chapter is already read', () {
      final page = initialReaderPageForProgress(
        progress: const bridge.ReadingProgress(
          chapterId: 7,
          lastPage: 32,
          totalPages: 33,
          isRead: true,
        ),
        pageCount: 33,
      );

      expect(page, 0);
    });

    test('clamps saved page when progress points past available pages', () {
      final page = initialReaderPageForProgress(
        progress: const bridge.ReadingProgress(
          chapterId: 7,
          lastPage: 99,
          totalPages: 100,
          isRead: false,
        ),
        pageCount: 33,
      );

      expect(page, 32);
    });
  });
}

class _PagesOnlyApi extends ComicRdApi {
  const _PagesOnlyApi();

  @override
  Future<bridge.ChapterContext?> getChapterContext(int chapterId) async => null;

  @override
  Future<List<bridge.PageInfo>> getChapterPages(int chapterId) async => [
    bridge.PageInfo(
      index: 0,
      name: '1.png',
      width: 1600,
      height: 4096,
      tileHeights: Uint32List.fromList([2048, 2048]),
    ),
    bridge.PageInfo(
      index: 1,
      name: '2.png',
      width: 900,
      height: 1000,
      tileHeights: Uint32List.fromList([1000]),
    ),
  ];

  @override
  Future<bridge.ReadingProgress?> getProgress(int chapterId) async => null;
}
