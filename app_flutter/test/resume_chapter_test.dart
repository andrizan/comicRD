import 'package:comicrd_flutter/bridge_generated.dart' as bridge;
import 'package:comicrd_flutter/state/comic_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';

const _comic = '/library/Comic';

bridge.RawChapter _chapter(
  int index, {
  bool read = false,
  int page = 0,
  int updated = 0,
}) => fakeChapter(
  _comic,
  index,
  isRead: read,
  lastPage: page,
  progressUpdatedAt: updated,
);

String? _resume(List<bridge.RawChapter> chapters, [String? lastOpened]) =>
    resumeChapter(chapters, lastOpened)?.title;

void main() {
  group('resumeChapter', () {
    test('goes to the first chapter when nothing was read', () {
      expect(_resume([_chapter(1), _chapter(2), _chapter(3)]), 'Chapter 1');
    });

    test('resumes the chapter that was stopped in the middle', () {
      expect(
        _resume([
          _chapter(1, read: true, updated: 100),
          _chapter(2, page: 7, updated: 200),
          _chapter(3),
        ]),
        'Chapter 2',
      );
    });

    test('moves on to the next chapter once the last one is finished', () {
      expect(
        _resume([
          _chapter(1, read: true, updated: 100),
          _chapter(2, read: true, updated: 200),
          _chapter(3),
          _chapter(4),
        ]),
        'Chapter 3',
      );
    });

    test('stays on the last chapter when nothing follows it', () {
      expect(
        _resume([
          _chapter(1, read: true, updated: 100),
          _chapter(2, read: true, updated: 200),
        ]),
        'Chapter 2',
      );
    });

    test('an old chapter left half-read does not win over newer reading', () {
      // Chapter 1 was abandoned on page 5 long ago; reading since then ran
      // straight through 2-4 and into 5, which is only on page 0.
      expect(
        _resume([
          _chapter(1, page: 5, updated: 100),
          _chapter(2, read: true, updated: 200),
          _chapter(3, read: true, updated: 250),
          _chapter(4, read: true, updated: 300),
          _chapter(5, updated: 300),
        ]),
        'Chapter 5',
      );
    });

    test('chapters written in the same second resolve to the later one', () {
      // Scrolling out of 3 into 4 writes both within one second.
      expect(
        _resume([
          _chapter(3, read: true, updated: 500),
          _chapter(4, page: 2, updated: 500),
        ]),
        'Chapter 4',
      );
      // The list order must not matter.
      expect(
        _resume([
          _chapter(4, page: 2, updated: 500),
          _chapter(3, read: true, updated: 500),
        ]),
        'Chapter 4',
      );
    });

    test('the chapter opened in this session wins, finished or not', () {
      final chapters = [
        _chapter(1, read: true, updated: 100),
        _chapter(2, page: 3, updated: 200),
        _chapter(3),
      ];
      expect(_resume(chapters, '$_comic/Chapter 2'), 'Chapter 2');
      // A last-opened chapter that is finished still moves on, to the next
      // chapter that has not been read.
      expect(
        _resume([
          _chapter(1, read: true, updated: 100),
          _chapter(2, read: true, updated: 150),
          _chapter(3),
        ], '$_comic/Chapter 1'),
        'Chapter 3',
      );
    });

    test('ignores a last-opened chapter that no longer exists', () {
      expect(
        _resume([
          _chapter(1, read: true, updated: 100),
          _chapter(2, page: 4, updated: 200),
        ], '$_comic/Gone'),
        'Chapter 2',
      );
    });

    test('is null for a comic with no chapters', () {
      expect(_resume(const []), isNull);
    });
  });
}
