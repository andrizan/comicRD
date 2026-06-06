import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge_generated.dart' as bridge;
import 'api_state.dart';

final readerDataProvider = FutureProvider.family<ReaderData, int>((
  ref,
  chapterId,
) async {
  final api = ref.watch(comicRdApiProvider);
  final context = await api.getChapterContext(chapterId);
  final pages = await api.getChapterPages(chapterId);
  final progress = await api.getProgress(chapterId);
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

final chapterBookmarksProvider =
    FutureProvider.family<List<bridge.Bookmark>, int>((ref, chapterId) {
      return ref.watch(comicRdApiProvider).listBookmarks(chapterId);
    });

final renderedPageProvider = FutureProvider.autoDispose
    .family<bridge.RenderedPage, RenderedPageRequest>((ref, request) {
      return ref
          .watch(comicRdApiProvider)
          .renderPageVariant(
            bridge.RenderPagePayload(
              chapterId: request.chapterId,
              pageIndex: request.pageIndex,
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

class RenderedPageRequest {
  const RenderedPageRequest({required this.chapterId, required this.pageIndex});

  final int chapterId;
  final int pageIndex;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RenderedPageRequest &&
          runtimeType == other.runtimeType &&
          chapterId == other.chapterId &&
          pageIndex == other.pageIndex;

  @override
  int get hashCode => Object.hash(chapterId, pageIndex);
}

int initialReaderPageForProgress({
  required bridge.ReadingProgress? progress,
  required int pageCount,
}) {
  return 0;
}
