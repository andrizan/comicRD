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
  });

  final bridge.ChapterContext? context;
  final List<bridge.PageInfo> pages;
  final bridge.ReadingProgress? progress;
  final int initialPage;
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
