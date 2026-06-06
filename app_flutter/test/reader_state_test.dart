import 'package:comicrd_flutter/bridge_generated.dart' as bridge;
import 'package:comicrd_flutter/state/reader_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('initialReaderPageForProgress', () {
    test('starts from first page when chapter is in progress', () {
      final page = initialReaderPageForProgress(
        progress: const bridge.ReadingProgress(
          chapterId: 7,
          lastPage: 11,
          totalPages: 33,
          isRead: false,
        ),
        pageCount: 33,
      );

      expect(page, 0);
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

    test('starts from first page when progress points past available pages', () {
      final page = initialReaderPageForProgress(
        progress: const bridge.ReadingProgress(
          chapterId: 7,
          lastPage: 99,
          totalPages: 100,
          isRead: false,
        ),
        pageCount: 33,
      );

      expect(page, 0);
    });
  });
}
