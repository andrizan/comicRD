import 'dart:typed_data';

import 'package:comicrd_flutter/bridge_generated.dart' as bridge;
import 'package:comicrd_flutter/state/reader_state.dart';
import 'package:flutter_test/flutter_test.dart';

bridge.PageInfo testPage({
  required int index,
  int? width = 900,
  int? height = 1300,
  List<int> tiles = const [1300],
}) {
  return bridge.PageInfo(
    index: index,
    name: '${index + 1}.png',
    width: width,
    height: height,
    tileHeights: Uint32List.fromList(tiles),
  );
}

void main() {
  group('flattenTiles', () {
    test('single-tile pages map one to one', () {
      final tiles = flattenTiles([testPage(index: 0), testPage(index: 1)]);

      expect(tiles, hasLength(2));
      expect(tiles[0].pageIndex, 0);
      expect(tiles[0].tileIndex, 0);
      expect(tiles[0].isLastTileOfPage, isTrue);
      expect(tiles[0].pixelHeight, 1300);
      expect(tiles[1].pageIndex, 1);
      expect(tiles[1].tileIndex, 0);
      expect(tiles[1].isLastTileOfPage, isTrue);
    });

    test('multi-tile strip expands in order with last-tile flags', () {
      final tiles = flattenTiles([
        testPage(index: 0),
        testPage(index: 1, height: 6144, tiles: [2048, 2048, 2048]),
        testPage(index: 2),
      ]);

      expect(tiles, hasLength(5));
      expect([for (final t in tiles) t.pageIndex], [0, 1, 1, 1, 2]);
      expect([for (final t in tiles) t.tileIndex], [0, 0, 1, 2, 0]);
      expect(
        [for (final t in tiles) t.isLastTileOfPage],
        [true, false, false, true, true],
      );
      expect(
        [for (final t in tiles) t.pixelHeight],
        [1300, 2048, 2048, 2048, 1300],
      );
    });

    test('empty tileHeights falls back to a single tile', () {
      final tiles = flattenTiles([testPage(index: 0, tiles: [])]);

      expect(tiles, hasLength(1));
      expect(tiles[0].pageIndex, 0);
      expect(tiles[0].tileIndex, 0);
      expect(tiles[0].isLastTileOfPage, isTrue);
    });

    test('empty pages flatten to no tiles', () {
      expect(flattenTiles(const []), isEmpty);
    });
  });

  group('fittedPageWidth', () {
    test('caps wide pages at 2048', () {
      expect(fittedPageWidth(testPage(index: 0, width: 3000)), 2048);
    });

    test('keeps narrow pages as-is', () {
      expect(fittedPageWidth(testPage(index: 0, width: 900)), 900);
      expect(fittedPageWidth(testPage(index: 0, width: 2048)), 2048);
    });

    test('falls back for null or zero widths', () {
      expect(fittedPageWidth(testPage(index: 0, width: null)), 900);
      expect(fittedPageWidth(testPage(index: 0, width: 0)), 900);
      expect(fittedPageWidth(testPage(index: 0, width: -10)), 900);
    });
  });

  group('tileGapAfter', () {
    test('gap only after last tile of a page', () {
      final tiles = flattenTiles([
        testPage(index: 0),
        testPage(index: 1, height: 4096, tiles: [2048, 2048]),
        testPage(index: 2),
      ]);
      // Tiles: (0,0) | (1,0) (1,1) | (2,0) → gaps after tile 0 and tile 2.
      expect(
        [for (var i = 0; i < tiles.length; i++) tileGapAfter(tiles, i, 10)],
        [10.0, 0.0, 10.0, 0.0],
      );
    });

    test('no gap after final tile or out of range', () {
      final tiles = flattenTiles([testPage(index: 0)]);
      expect(tileGapAfter(tiles, 0, 10), 0.0);
      expect(tileGapAfter(tiles, -1, 10), 0.0);
      expect(tileGapAfter(tiles, 5, 10), 0.0);
      expect(tileGapAfter(const [], 0, 10), 0.0);
    });
  });

  group('tile grid zoom invariance', () {
    test('same pages always flatten identically', () {
      // flattenTiles takes no zoom/display input by design: zoom must only
      // scale display, never re-tile. This locks the invariant.
      final pages = [
        testPage(index: 0),
        testPage(index: 1, height: 5000, tiles: [2048, 2048, 904]),
      ];

      List<(int, int, bool, int)> shape(List<TileItem> tiles) => [
        for (final t in tiles)
          (t.pageIndex, t.tileIndex, t.isLastTileOfPage, t.pixelHeight),
      ];

      expect(shape(flattenTiles(pages)), shape(flattenTiles(pages)));
      expect(flattenTiles(pages), hasLength(4));
    });
  });
}
