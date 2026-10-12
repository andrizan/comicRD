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

  group('decodeWidthFor', () {
    test('rounds the drawn width up to a 128px step below the tile width', () {
      expect(
        decodeWidthFor(
          fittedWidth: 2048,
          displayWidth: 1000,
          devicePixelRatio: 1,
        ),
        1024,
      );
      expect(
        decodeWidthFor(
          fittedWidth: 2048,
          displayWidth: 700,
          devicePixelRatio: 2,
        ),
        1408,
      );
    });

    test('is null when the tile is already at or below the drawn size', () {
      expect(
        decodeWidthFor(
          fittedWidth: 900,
          displayWidth: 1000,
          devicePixelRatio: 1,
        ),
        isNull,
      );
      expect(
        decodeWidthFor(
          fittedWidth: 1024,
          displayWidth: 1000,
          devicePixelRatio: 1,
        ),
        isNull,
      );
      expect(
        decodeWidthFor(fittedWidth: 0, displayWidth: 1000, devicePixelRatio: 1),
        isNull,
      );
    });

    test('follows zoom through the display width', () {
      expect(
        decodeWidthFor(
          fittedWidth: 2048,
          displayWidth: 1000 * 1.5,
          devicePixelRatio: 1,
        ),
        1536,
      );
    });
  });

  group('binary search helpers', () {
    const values = [10.0, 20.0, 20.0, 30.0];

    test('lowerBoundIndex finds the first value >= target', () {
      expect(lowerBoundIndex(values, 5), 0);
      expect(lowerBoundIndex(values, 10), 0);
      expect(lowerBoundIndex(values, 15), 1);
      expect(lowerBoundIndex(values, 20), 1);
      expect(lowerBoundIndex(values, 30), 3);
      expect(lowerBoundIndex(values, 31), 4);
      expect(lowerBoundIndex(const [], 1), 0);
    });

    test('upperBoundIndex finds the last value <= target', () {
      expect(upperBoundIndex(values, 5), -1);
      expect(upperBoundIndex(values, 10), 0);
      expect(upperBoundIndex(values, 20), 2);
      expect(upperBoundIndex(values, 25), 2);
      expect(upperBoundIndex(values, 31), 3);
      expect(upperBoundIndex(const [], 1), -1);
    });

    test('firstTileOfPage matches a linear scan', () {
      const tiles = [
        TileItem(
          pageIndex: 0,
          tileIndex: 0,
          isLastTileOfPage: false,
          pixelHeight: 1,
        ),
        TileItem(
          pageIndex: 0,
          tileIndex: 1,
          isLastTileOfPage: true,
          pixelHeight: 1,
        ),
        TileItem(
          pageIndex: 2,
          tileIndex: 0,
          isLastTileOfPage: true,
          pixelHeight: 1,
        ),
        TileItem(
          pageIndex: 3,
          tileIndex: 0,
          isLastTileOfPage: true,
          pixelHeight: 1,
        ),
      ];
      int linear(int page) {
        for (var i = 0; i < tiles.length; i++) {
          if (tiles[i].pageIndex >= page) return i;
        }
        return tiles.length - 1;
      }

      for (var page = -1; page <= 5; page++) {
        expect(
          firstTileOfPage(tiles, page),
          linear(page),
          reason: 'page $page',
        );
      }
      expect(firstTileOfPage(const [], 3), 0);
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
