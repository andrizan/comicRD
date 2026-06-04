import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge_generated.dart' as bridge;
import 'api_state.dart';

final comicChaptersProvider =
    FutureProvider.family<List<bridge.RawChapter>, String>((ref, comicPath) {
      return ref.watch(comicRdApiProvider).listComicChaptersRaw(comicPath);
    });

final chapterFavoritesProvider = FutureProvider.family<List<String>, String>((
  ref,
  comicPath,
) {
  return ref.watch(comicRdApiProvider).listChapterFavorites(comicPath);
});

final comicScrollKeyProvider = Provider.family<String, String>(
  (ref, comicPath) => 'comic:$comicPath',
);
