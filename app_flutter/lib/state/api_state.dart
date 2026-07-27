import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/comicrd_api.dart';

final comicRdApiProvider = Provider<ComicRdApi>((ref) => const ComicRdApi());

class ReaderSaveGuard {
  static int? chapterId;
  static int lastPage = 0;
  static int totalPages = 0;

  static void track(int id, int page, int total) {
    chapterId = id;
    lastPage = page;
    totalPages = total;
  }

  static void clear() {
    chapterId = null;
    lastPage = 0;
    totalPages = 0;
  }
}
