import 'dart:convert';

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

final comicReadingHistoryProvider =
    FutureProvider.family<List<bridge.ReadingHistoryEntry>, String>((
      ref,
      comicPath,
    ) async {
      final history = await ref.watch(comicRdApiProvider).listReadingHistory();
      return history
          .where((entry) => entry.comicSourcePath == comicPath)
          .toList();
    });

class ComicStats {
  const ComicStats({
    required this.totalSize,
    required this.chapterCount,
    required this.readCount,
    required this.inProgressCount,
    required this.continueChapterTitle,
  });

  final int totalSize;
  final int chapterCount;
  final int readCount;
  final int inProgressCount;
  final String? continueChapterTitle;

  int get effectiveReadCount => readCount + inProgressCount;
}

final comicStatsProvider =
    Provider.family<ComicStats, String>((ref, comicPath) {
      final chapters = ref.watch(comicChaptersProvider(comicPath)).asData?.value;
      if (chapters == null) {
        return const ComicStats(
          totalSize: 0,
          chapterCount: 0,
          readCount: 0,
          inProgressCount: 0,
          continueChapterTitle: null,
        );
      }
      final totalSize =
          chapters.fold<int>(0, (sum, c) => sum + c.sizeBytes.toInt());
      final readCount = chapters.where((c) => c.isRead).length;
      final inProgressCount =
          chapters.where((c) => c.lastPage > 0 && !c.isRead).length;
      String? continueTitle;
      for (final c in chapters) {
        if (c.lastPage > 0 && !c.isRead) {
          continueTitle = c.title;
          break;
        }
      }
      if (continueTitle == null) {
        for (final c in chapters) {
          if (!c.isRead) {
            continueTitle = c.title;
            break;
          }
        }
        continueTitle ??=
            chapters.isNotEmpty ? chapters.first.title : null;
      }
      return ComicStats(
        totalSize: totalSize,
        chapterCount: chapters.length,
        readCount: readCount,
        inProgressCount: inProgressCount,
        continueChapterTitle: continueTitle,
      );
    });

final comicBookmarkedProvider = FutureProvider.family<bool, String>(
  (ref, comicPath) =>
      ref.watch(comicRdApiProvider).isComicBookmarked(comicPath),
);

final filteredComicChaptersProvider =
    Provider.family<AsyncValue<List<bridge.RawChapter>>, String>((
      ref,
      comicPath,
    ) {
      final chaptersAsync = ref.watch(comicChaptersProvider(comicPath));
      final favoritesAsync = ref.watch(chapterFavoritesProvider(comicPath));
      final preferences = ref.watch(
        comicPreferencesProvider.select(
          (state) => state[comicPath] ?? const ComicPreferences(),
        ),
      );
      return chaptersAsync.whenData((chapters) {
        final favorites = favoritesAsync.asData?.value.toSet() ?? const {};
        final query = preferences.query.trim().toLowerCase();
        final filtered = chapters.where((chapter) {
          final matchesQuery =
              query.isEmpty ||
              chapter.title.toLowerCase().contains(query) ||
              chapter.sourcePath.toLowerCase().contains(query);
          final matchesTab = switch (preferences.selectedTab) {
            ChapterTab.all => true,
            ChapterTab.favorites => favorites.contains(chapter.sourcePath),
          };
          return matchesQuery && matchesTab;
        }).toList();
        filtered.sort((a, b) {
          final order = switch (preferences.sortBy) {
            ChapterSortBy.name => a.title.toLowerCase().compareTo(
              b.title.toLowerCase(),
            ),
            ChapterSortBy.folderDate => a.dateModified.compareTo(
              b.dateModified,
            ),
            ChapterSortBy.chapterIndex => a.chapterIndex.compareTo(
              b.chapterIndex,
            ),
          };
          return preferences.sortDir == bridge.SortDir.asc ? order : -order;
        });
        return filtered;
      });
    });

final comicScrollKeyProvider = Provider.family<String, String>(
  (ref, comicPath) => 'comic:$comicPath',
);

final comicPreferencesProvider =
    NotifierProvider<ComicPreferencesNotifier, Map<String, ComicPreferences>>(
      ComicPreferencesNotifier.new,
    );

final lastOpenedChapterProvider =
    NotifierProvider<LastOpenedChapterNotifier, Map<String, String>>(
      LastOpenedChapterNotifier.new,
    );

enum ChapterSortBy { chapterIndex, name, folderDate }

enum ChapterTab { all, favorites }

class ComicPreferences {
  const ComicPreferences({
    this.query = '',
    this.sortBy = ChapterSortBy.chapterIndex,
    this.sortDir = bridge.SortDir.asc,
    this.selectedTab = ChapterTab.all,
  });

  final String query;
  final ChapterSortBy sortBy;
  final bridge.SortDir sortDir;
  final ChapterTab selectedTab;

  ComicPreferences copyWith({
    String? query,
    ChapterSortBy? sortBy,
    bridge.SortDir? sortDir,
    ChapterTab? selectedTab,
  }) => ComicPreferences(
    query: query ?? this.query,
    sortBy: sortBy ?? this.sortBy,
    sortDir: sortDir ?? this.sortDir,
    selectedTab: selectedTab ?? this.selectedTab,
  );
}

class ComicPreferencesNotifier extends Notifier<Map<String, ComicPreferences>> {
  static const _maxSize = 200;
  final _hydratedComics = <String>{};

  @override
  Map<String, ComicPreferences> build() => const {};

  ComicPreferences preferencesFor(String comicPath) =>
      state[comicPath] ?? const ComicPreferences();

  void hydrateFromSettings(String comicPath, Map<String, String> values) {
    if (!_hydratedComics.add(comicPath)) {
      return;
    }
    update(
      comicPath,
      preferencesFor(comicPath).copyWith(
        sortBy: _decodeChapterSortBy(values['chapter_sort_by']),
        sortDir: _decodeSortDir(values['chapter_sort_dir']),
      ),
    );
  }

  void update(String comicPath, ComicPreferences preferences) {
    final updated = {...state, comicPath: preferences};
    if (updated.length > _maxSize) {
      final keys = updated.keys.toList();
      for (var i = 0; i < keys.length - _maxSize; i++) {
        updated.remove(keys[i]);
        _hydratedComics.remove(keys[i]);
      }
    }
    state = updated;
  }

  void setQuery(String comicPath, String query) {
    update(comicPath, preferencesFor(comicPath).copyWith(query: query));
  }

  void setSort(String comicPath, ChapterSortBy sortBy, bridge.SortDir sortDir) {
    update(
      comicPath,
      preferencesFor(comicPath).copyWith(sortBy: sortBy, sortDir: sortDir),
    );
  }

  void setSelectedTab(String comicPath, ChapterTab selectedTab) {
    update(
      comicPath,
      preferencesFor(comicPath).copyWith(selectedTab: selectedTab),
    );
  }
}

ChapterSortBy _decodeChapterSortBy(String? raw) {
  return switch (_decodeString(raw, 'chapter_index')) {
    'name' => ChapterSortBy.name,
    'folder_date' => ChapterSortBy.folderDate,
    _ => ChapterSortBy.chapterIndex,
  };
}

bridge.SortDir _decodeSortDir(String? raw) {
  return switch (_decodeString(raw, 'asc')) {
    'desc' => bridge.SortDir.desc,
    _ => bridge.SortDir.asc,
  };
}

String _decodeString(String? raw, String fallback) {
  if (raw == null) {
    return fallback;
  }
  try {
    final decoded = jsonDecode(raw);
    return decoded is String ? decoded : fallback;
  } catch (_) {
    return fallback;
  }
}

class LastOpenedChapterNotifier extends Notifier<Map<String, String>> {
  static const _maxSize = 200;

  @override
  Map<String, String> build() => const {};

  String? sourcePathFor(String comicPath) => state[comicPath];

  void remember(String comicPath, String chapterSourcePath) {
    final updated = {...state, comicPath: chapterSourcePath};
    if (updated.length > _maxSize) {
      final keys = updated.keys.toList();
      for (var i = 0; i < keys.length - _maxSize; i++) {
        updated.remove(keys[i]);
      }
    }
    state = updated;
  }
}
