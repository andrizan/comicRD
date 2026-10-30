import 'dart:typed_data';

import 'package:comicrd_flutter/bridge_generated.dart' as bridge;
import 'package:comicrd_flutter/state/reader_state.dart';
import 'package:flutter_test/flutter_test.dart';

StripChapter _chapter(int id, List<List<int>> tileHeightsPerPage) {
  final pages = [
    for (var i = 0; i < tileHeightsPerPage.length; i++)
      bridge.PageInfo(
        index: i,
        name: '$i.png',
        width: 900,
        height: tileHeightsPerPage[i].fold<int>(0, (a, b) => a + b),
        tileHeights: Uint32List.fromList(tileHeightsPerPage[i]),
      ),
  ];
  return StripChapter(
    id,
    ReaderData(
      context: null,
      pages: pages,
      progress: null,
      initialPage: 0,
      tiles: flattenTiles(pages),
    ),
  );
}

void main() {
  group('ReaderStrip', () {
    // Chapter 10 has 3 tiles (page 0 is two tiles), chapter 11 has 2.
    final ten = _chapter(10, [
      [2048, 500],
      [1300],
    ]);
    final eleven = _chapter(11, [
      [1300],
      [1300],
    ]);

    test('counts tiles across chapters and maps them back', () {
      final strip = ReaderStrip([ten, eleven]);

      expect(strip.tileCount, 5);
      expect(strip.tileStart(0), 0);
      expect(strip.tileStart(1), 3);
      expect(strip.locate(0), (slot: 0, local: 0));
      expect(strip.locate(2), (slot: 0, local: 2));
      expect(strip.locate(3), (slot: 1, local: 0));
      expect(strip.locate(4), (slot: 1, local: 1));
      expect(strip.globalTile(1, 1), 4);
    });

    test('tileAt returns the chapter-local tile, not a strip index', () {
      final strip = ReaderStrip([ten, eleven]);

      final tile = strip.tileAt(1);
      expect(tile.pageIndex, 0);
      expect(tile.tileIndex, 1);
      expect(strip.tileAt(3).pageIndex, 0);
      expect(strip.tileAt(3).tileIndex, 0);
    });

    test('finds loaded chapters by id', () {
      final strip = ReaderStrip([ten, eleven]);

      expect(strip.slotOfChapter(10), 0);
      expect(strip.slotOfChapter(11), 1);
      expect(strip.slotOfChapter(12), -1);
    });

    test('appending keeps earlier indices, prepending shifts them', () {
      final base = ReaderStrip([ten]);

      final after = base.appended(eleven);
      expect(after.chapters.map((c) => c.chapterId), [10, 11]);
      expect(after.locate(2), (slot: 0, local: 2));

      final before = base.prepended(eleven);
      expect(before.chapters.map((c) => c.chapterId), [11, 10]);
      // Chapter 10's first tile moved behind chapter 11's two tiles.
      expect(before.tileStart(1), 2);
      expect(before.locate(2), (slot: 1, local: 0));
    });

    test('the original strip is unchanged by appended/prepended', () {
      final base = ReaderStrip([ten]);
      base.appended(eleven);
      base.prepended(eleven);

      expect(base.chapters, hasLength(1));
      expect(base.tileCount, 3);
    });
  });
}
