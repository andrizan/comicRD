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
          final matchesFavorite =
              !preferences.favoritesOnly ||
              favorites.contains(chapter.sourcePath);
          return matchesQuery && matchesFavorite;
        }).toList();
        filtered.sort((a, b) {
          final order = switch (preferences.sortBy) {
            ChapterSortBy.name => a.title.toLowerCase().compareTo(
              b.title.toLowerCase(),
            ),
            ChapterSortBy.folderDate => a.dateModified.compareTo(b.dateModified),
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

enum ChapterDisplayMode { grid, list }

class ComicPreferences {
  const ComicPreferences({
    this.query = '',
    this.sortBy = ChapterSortBy.chapterIndex,
    this.sortDir = bridge.SortDir.asc,
    this.displayMode = ChapterDisplayMode.list,
    this.favoritesOnly = false,
  });

  final String query;
  final ChapterSortBy sortBy;
  final bridge.SortDir sortDir;
  final ChapterDisplayMode displayMode;
  final bool favoritesOnly;

  ComicPreferences copyWith({
    String? query,
    ChapterSortBy? sortBy,
    bridge.SortDir? sortDir,
    ChapterDisplayMode? displayMode,
    bool? favoritesOnly,
  }) => ComicPreferences(
    query: query ?? this.query,
    sortBy: sortBy ?? this.sortBy,
    sortDir: sortDir ?? this.sortDir,
    displayMode: displayMode ?? this.displayMode,
    favoritesOnly: favoritesOnly ?? this.favoritesOnly,
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

  void setDisplayMode(String comicPath, ChapterDisplayMode displayMode) {
    update(
      comicPath,
      preferencesFor(comicPath).copyWith(displayMode: displayMode),
    );
  }

  void setFavoritesOnly(String comicPath, bool favoritesOnly) {
    update(
      comicPath,
      preferencesFor(comicPath).copyWith(favoritesOnly: favoritesOnly),
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
  final decoded = jsonDecode(raw);
  return decoded is String ? decoded : fallback;
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
