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
  return ReaderData(context: context, pages: pages, progress: progress);
});

final chapterBookmarksProvider =
    FutureProvider.family<List<bridge.Bookmark>, int>((ref, chapterId) {
      return ref.watch(comicRdApiProvider).listBookmarks(chapterId);
    });

class ReaderData {
  const ReaderData({
    required this.context,
    required this.pages,
    required this.progress,
  });

  final bridge.ChapterContext? context;
  final List<bridge.PageInfo> pages;
  final bridge.ReadingProgress? progress;
}
