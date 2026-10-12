import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge_generated.dart' as bridge;
import 'api_state.dart';

final readerDataProvider = FutureProvider.autoDispose.family<ReaderData, int>((
  ref,
  chapterId,
) async {
  final api = ref.watch(comicRdApiProvider);
  // Parallelize the three independent fetches: each crosses the bridge on
  // its own, so serial awaits stack their latencies on every chapter open.
  // Error semantics are unchanged (any failure fails the provider).
  final results = await Future.wait<dynamic>([
    api.getChapterContext(chapterId),
    api.getChapterPages(chapterId),
    api.getProgress(chapterId),
  ]);
  final context = results[0] as bridge.ChapterContext?;
  final pages = results[1] as List<bridge.PageInfo>;
  final progress = results[2] as bridge.ReadingProgress?;
  final initialPage = initialReaderPageForProgress(
    progress: progress,
    pageCount: pages.length,
  );
  return ReaderData(
    context: context,
    pages: pages,
    progress: progress,
    initialPage: initialPage,
    tiles: flattenTiles(pages),
  );
});

final renderedTileProvider = FutureProvider.autoDispose
    .family<bridge.RenderedPage, TileRequest>((ref, request) {
      return ref
          .watch(comicRdApiProvider)
          .renderPageTile(
            bridge.RenderPageTilePayload(
              chapterId: request.chapterId,
              pageIndex: request.pageIndex,
              tileIndex: request.tileIndex,
            ),
          );
    });

class ReaderData {
  const ReaderData({
    required this.context,
    required this.pages,
    required this.progress,
    required this.initialPage,
    required this.tiles,
  });

  final bridge.ChapterContext? context;
  final List<bridge.PageInfo> pages;
  final bridge.ReadingProgress? progress;
  final int initialPage;

  /// `flattenTiles(pages)`, computed once per chapter load: the reader walks
  /// this on every scroll event, so it must not be rebuilt per call.
  final List<TileItem> tiles;
}

/// One render unit: a tile of a page. Single-tile pages have exactly one
/// entry with tileIndex 0.
class TileItem {
  const TileItem({
    required this.pageIndex,
    required this.tileIndex,
    required this.isLastTileOfPage,
    required this.pixelHeight,
  });

  final int pageIndex;
  final int tileIndex;
  final bool isLastTileOfPage;

  /// Fitted pixel height of this tile, from Rust. Never recomputed in Dart.
  final int pixelHeight;
}

class TileRequest {
  const TileRequest({
    required this.chapterId,
    required this.pageIndex,
    required this.tileIndex,
  });

  final int chapterId;
  final int pageIndex;
  final int tileIndex;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TileRequest &&
          runtimeType == other.runtimeType &&
          chapterId == other.chapterId &&
          pageIndex == other.pageIndex &&
          tileIndex == other.tileIndex;

  @override
  int get hashCode => Object.hash(chapterId, pageIndex, tileIndex);
}

/// Display gap after a tile: `pageGap` after the last tile of a page,
/// zero between tiles of one page and after the final tile (seams). Pure.
double tileGapAfter(List<TileItem> tiles, int tilePos, double pageGap) {
  if (tilePos < 0 || tilePos >= tiles.length - 1) {
    return 0;
  }
  return tiles[tilePos].isLastTileOfPage ? pageGap : 0;
}

/// Width to decode a tile at: the physical pixels it is drawn with, rounded
/// up to a 128px step so window resizes do not re-decode on every pixel,
/// and capped at the tile's own width. Null when the tile is already at or
/// below that size (no resize wrapper needed).
///
/// `displayWidth` already includes zoom, so a zoomed-in tile decodes at a
/// correspondingly higher resolution: sharpness tracks the zoom level while
/// a 2048px-wide tile on a 1000px column costs a quarter of the memory.
int? decodeWidthFor({
  required int fittedWidth,
  required double displayWidth,
  required double devicePixelRatio,
}) {
  if (fittedWidth <= 0) {
    return null;
  }
  final physical = (displayWidth * devicePixelRatio).ceil();
  final quantized = ((physical + 127) ~/ 128) * 128;
  if (quantized >= fittedWidth) {
    return null;
  }
  return math.max(quantized, 128);
}

/// First index whose value is >= [target] in a non-decreasing list, or
/// `values.length` when every value is smaller.
int lowerBoundIndex(List<double> values, double target) {
  var low = 0;
  var high = values.length;
  while (low < high) {
    final mid = (low + high) >> 1;
    if (values[mid] < target) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low;
}

/// Last index whose value is <= [target] in a non-decreasing list, or -1
/// when every value is larger.
int upperBoundIndex(List<double> values, double target) {
  var low = 0;
  var high = values.length;
  while (low < high) {
    final mid = (low + high) >> 1;
    if (values[mid] <= target) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low - 1;
}

/// First tile position of [page], or the last tile when the page is past
/// the end. Tiles are ordered by page, so this is a binary search.
int firstTileOfPage(List<TileItem> tiles, int page) {
  if (tiles.isEmpty) {
    return 0;
  }
  var low = 0;
  var high = tiles.length;
  while (low < high) {
    final mid = (low + high) >> 1;
    if (tiles[mid].pageIndex < page) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low < tiles.length ? low : tiles.length - 1;
}

/// Fitted pixel width mirror of Rust `tile_layout_for_dimensions`.
/// Integer-only (`min(original, 2048)`) so parity with Rust is exact.
int fittedPageWidth(bridge.PageInfo page) {
  final width = page.width ?? 900;
  if (width <= 0) {
    return 900;
  }
  return width > 2048 ? 2048 : width;
}

/// Flatten pages into render tiles from Rust-provided `tileHeights`.
/// Pure; the tile grid never depends on zoom or display size.
List<TileItem> flattenTiles(List<bridge.PageInfo> pages) {
  final tiles = <TileItem>[];
  for (final page in pages) {
    final heights = page.tileHeights.isEmpty
        ? [page.height ?? 0]
        : page.tileHeights;
    for (var t = 0; t < heights.length; t++) {
      tiles.add(
        TileItem(
          pageIndex: page.index,
          tileIndex: t,
          isLastTileOfPage: t == heights.length - 1,
          pixelHeight: heights[t],
        ),
      );
    }
  }
  return tiles;
}

int initialReaderPageForProgress({
  required bridge.ReadingProgress? progress,
  required int pageCount,
}) {
  if (progress == null || progress.isRead || pageCount <= 0) {
    return 0;
  }
  return progress.lastPage.clamp(0, pageCount - 1).toInt();
}
