import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge_generated.dart' as bridge;
import 'api_state.dart';

final libraryPreferencesProvider =
    NotifierProvider<LibraryPreferencesNotifier, LibraryPreferences>(
      LibraryPreferencesNotifier.new,
    );

final librarySourceStatusProvider = FutureProvider<bridge.LibrarySourceStatus>((
  ref,
) {
  return ref.watch(comicRdApiProvider).checkLibrarySource();
});

final rawLibraryComicsProvider = FutureProvider<List<bridge.RawComic>>((
  ref,
) async {
  final sourceStatus = await ref.watch(librarySourceStatusProvider.future);
  if (!sourceStatus.configured || sourceStatus.error != null) {
    return const [];
  }
  final api = ref.watch(comicRdApiProvider);
  final sortBy = ref.watch(
    libraryPreferencesProvider.select(
      (preferences) => preferences.librarySortBy,
    ),
  );
  final sortDir = ref.watch(
    libraryPreferencesProvider.select(
      (preferences) => preferences.librarySortDir,
    ),
  );
  return api.listLibraryComicsRaw(sortBy: sortBy, sortDir: sortDir);
});

class LibraryPaginationNotifier extends Notifier<int> {
  static const int pageSize = 30;

  @override
  int build() => pageSize;

  void loadMore() {
    state = state + pageSize;
  }

  void reset() {
    state = pageSize;
  }
}

final libraryPaginationProvider =
    NotifierProvider<LibraryPaginationNotifier, int>(
      LibraryPaginationNotifier.new,
    );

final filteredLibraryComicsProvider = Provider<List<bridge.RawComic>>((ref) {
  final comics = ref.watch(rawLibraryComicsProvider).asData?.value ?? const [];
  final query = ref
      .watch(libraryPreferencesProvider.select((p) => p.query))
      .trim()
      .toLowerCase();
  final viewMode = ref.watch(
    libraryPreferencesProvider.select((p) => p.viewMode),
  );
  return comics
      .where(
        (comic) =>
            query.isEmpty ||
            comic.title.toLowerCase().contains(query) ||
            comic.sourcePath.toLowerCase().contains(query),
      )
      .where((comic) {
        return switch (viewMode) {
          LibraryViewMode.all => true,
          LibraryViewMode.unread =>
            comic.readChapterCount == 0 && comic.inProgressChapterCount == 0,
          LibraryViewMode.reading => comic.inProgressChapterCount > 0,
        };
      })
      .toList();
});

class LibraryComicsState {
  const LibraryComicsState({
    required this.items,
    required this.filteredTotal,
    required this.visibleCount,
    required this.hasMore,
  });

  final List<bridge.RawComic> items;
  final int filteredTotal;
  final int visibleCount;
  final bool hasMore;
}

final libraryComicsProvider = Provider<LibraryComicsState>((ref) {
  final filtered = ref.watch(filteredLibraryComicsProvider);
  final visibleLimit = ref.watch(libraryPaginationProvider);
  final visibleCount = filtered.length < visibleLimit
      ? filtered.length
      : visibleLimit;
  return LibraryComicsState(
    items: filtered,
    filteredTotal: filtered.length,
    visibleCount: visibleCount,
    hasMore: visibleCount < filtered.length,
  );
});

final readingHistoryProvider = FutureProvider<List<bridge.ReadingHistoryEntry>>(
  (ref) {
    return ref.watch(comicRdApiProvider).listReadingHistory();
  },
);

class HistoryPaginationNotifier extends Notifier<int> {
  static const int pageSize = 30;

  @override
  int build() => pageSize;

  void loadMore() {
    state = state + pageSize;
  }

  void reset() {
    state = pageSize;
  }
}

final historyPaginationProvider =
    NotifierProvider<HistoryPaginationNotifier, int>(
      HistoryPaginationNotifier.new,
    );

final filteredHistoryProvider = Provider<List<bridge.ReadingHistoryEntry>>((
  ref,
) {
  final entries = ref.watch(readingHistoryProvider).asData?.value ?? const [];
  final query = ref
      .watch(libraryPreferencesProvider.select((p) => p.query))
      .trim()
      .toLowerCase();
  if (query.isEmpty) return entries;
  return entries
      .where(
        (entry) =>
            entry.comicTitle.toLowerCase().contains(query) ||
            entry.chapterTitle.toLowerCase().contains(query),
      )
      .toList();
});

class HistoryListState {
  const HistoryListState({
    required this.items,
    required this.filteredTotal,
    required this.visibleCount,
    required this.hasMore,
  });

  final List<bridge.ReadingHistoryEntry> items;
  final int filteredTotal;
  final int visibleCount;
  final bool hasMore;
}

final historyListProvider = Provider<HistoryListState>((ref) {
  final filtered = ref.watch(filteredHistoryProvider);
  final visibleLimit = ref.watch(historyPaginationProvider);
  final visibleCount = filtered.length < visibleLimit
      ? filtered.length
      : visibleLimit;
  return HistoryListState(
    items: filtered,
    filteredTotal: filtered.length,
    visibleCount: visibleCount,
    hasMore: visibleCount < filtered.length,
  );
});

final allFavoritesProvider = FutureProvider<List<bridge.Favorite>>((ref) {
  return ref.watch(comicRdApiProvider).listFavorites();
});

final libraryCountProvider = Provider<int>((ref) {
  final comics = ref.watch(rawLibraryComicsProvider).asData?.value ?? const [];
  final query = ref
      .watch(libraryPreferencesProvider.select((p) => p.libraryQuery))
      .trim()
      .toLowerCase();
  final viewMode = ref.watch(
    libraryPreferencesProvider.select((p) => p.viewMode),
  );
  return comics
      .where(
        (comic) =>
            query.isEmpty ||
            comic.title.toLowerCase().contains(query) ||
            comic.sourcePath.toLowerCase().contains(query),
      )
      .where((comic) {
        return switch (viewMode) {
          LibraryViewMode.all => true,
          LibraryViewMode.unread =>
            comic.readChapterCount == 0 && comic.inProgressChapterCount == 0,
          LibraryViewMode.reading => comic.inProgressChapterCount > 0,
        };
      })
      .length;
});

final favoriteCountProvider = Provider<int>((ref) {
  final favorites = ref.watch(allFavoritesProvider).asData?.value ?? const [];
  final query = ref
      .watch(libraryPreferencesProvider.select((p) => p.favoritesQuery))
      .trim()
      .toLowerCase();
  if (query.isEmpty) return favorites.length;
  return favorites
      .where(
        (f) =>
            f.comicTitle.toLowerCase().contains(query) ||
            f.comicSourcePath.toLowerCase().contains(query),
      )
      .length;
});

final comicsWithProgressProvider = FutureProvider<List<String>>((ref) {
  return ref.watch(comicRdApiProvider).listComicsWithProgress();
});

final comicThumbnailProvider = FutureProvider.autoDispose
    .family<Uint8List?, ({String sourcePath, int maxWidth, int maxHeight})>((
      ref,
      key,
    ) async {
      try {
        final bytes = await ref
            .watch(comicRdApiProvider)
            .getComicThumbnail(
              key.sourcePath,
              maxWidth: key.maxWidth,
              maxHeight: key.maxHeight,
            );
        if (bytes.isEmpty) return null;
        return bytes;
      } catch (e, st) {
        debugPrint('thumbnail error for ${key.sourcePath}: $e\n$st');
        return null;
      }
    });

enum LibraryViewMode { all, unread, reading }

enum LibraryDisplayMode { grid, list }

enum LibraryTab { history, library, favorites }

class LibraryPreferences {
  const LibraryPreferences({
    this.libraryQuery = '',
    this.favoritesQuery = '',
    this.historyQuery = '',
    this.librarySortBy = bridge.SortBy.name,
    this.librarySortDir = bridge.SortDir.asc,
    this.favoritesSortBy = bridge.SortBy.name,
    this.favoritesSortDir = bridge.SortDir.asc,
    this.libraryDisplayMode = LibraryDisplayMode.grid,
    this.favoritesDisplayMode = LibraryDisplayMode.grid,
    this.viewMode = LibraryViewMode.all,
    this.selectedTab = LibraryTab.library,
  });

  final String libraryQuery;
  final String favoritesQuery;
  final String historyQuery;
  final bridge.SortBy librarySortBy;
  final bridge.SortDir librarySortDir;
  final bridge.SortBy favoritesSortBy;
  final bridge.SortDir favoritesSortDir;
  final LibraryDisplayMode libraryDisplayMode;
  final LibraryDisplayMode favoritesDisplayMode;
  final LibraryViewMode viewMode;
  final LibraryTab selectedTab;

  String get query => switch (selectedTab) {
    LibraryTab.library => libraryQuery,
    LibraryTab.favorites => favoritesQuery,
    LibraryTab.history => historyQuery,
  };

  (bridge.SortBy, bridge.SortDir) get sort => switch (selectedTab) {
    LibraryTab.library => (librarySortBy, librarySortDir),
    LibraryTab.favorites => (favoritesSortBy, favoritesSortDir),
    LibraryTab.history => (librarySortBy, librarySortDir),
  };

  LibraryDisplayMode get displayMode => switch (selectedTab) {
    LibraryTab.library => libraryDisplayMode,
    LibraryTab.favorites => favoritesDisplayMode,
    LibraryTab.history => libraryDisplayMode,
  };

  LibraryPreferences copyWith({
    String? libraryQuery,
    String? favoritesQuery,
    String? historyQuery,
    bridge.SortBy? librarySortBy,
    bridge.SortDir? librarySortDir,
    bridge.SortBy? favoritesSortBy,
    bridge.SortDir? favoritesSortDir,
    LibraryDisplayMode? libraryDisplayMode,
    LibraryDisplayMode? favoritesDisplayMode,
    LibraryViewMode? viewMode,
    LibraryTab? selectedTab,
  }) => LibraryPreferences(
    libraryQuery: libraryQuery ?? this.libraryQuery,
    favoritesQuery: favoritesQuery ?? this.favoritesQuery,
    historyQuery: historyQuery ?? this.historyQuery,
    librarySortBy: librarySortBy ?? this.librarySortBy,
    librarySortDir: librarySortDir ?? this.librarySortDir,
    favoritesSortBy: favoritesSortBy ?? this.favoritesSortBy,
    favoritesSortDir: favoritesSortDir ?? this.favoritesSortDir,
    libraryDisplayMode: libraryDisplayMode ?? this.libraryDisplayMode,
    favoritesDisplayMode: favoritesDisplayMode ?? this.favoritesDisplayMode,
    viewMode: viewMode ?? this.viewMode,
    selectedTab: selectedTab ?? this.selectedTab,
  );
}

class LibraryPreferencesNotifier extends Notifier<LibraryPreferences> {
  bool _hydrated = false;

  @override
  LibraryPreferences build() => const LibraryPreferences();

  void hydrateFromSettings(Map<String, String> values) {
    if (_hydrated) {
      return;
    }
    _hydrated = true;
    state = state.copyWith(
      librarySortBy: _decodeSortBy(values['library_sort_by']),
      librarySortDir: _decodeSortDir(values['library_sort_dir']),
      favoritesSortBy: _decodeSortBy(values['favorites_sort_by']),
      favoritesSortDir: _decodeSortDir(values['favorites_sort_dir']),
      libraryDisplayMode: _decodeDisplayMode(values['library_display_mode']),
      favoritesDisplayMode: _decodeDisplayMode(
        values['favorites_display_mode'],
      ),
      viewMode: _decodeViewMode(values['library_view_mode']),
      selectedTab: _decodeLibraryTab(values['library_selected_tab']),
    );
  }

  void setQuery(String query) {
    state = switch (state.selectedTab) {
      LibraryTab.library => state.copyWith(libraryQuery: query),
      LibraryTab.favorites => state.copyWith(favoritesQuery: query),
      LibraryTab.history => state.copyWith(historyQuery: query),
    };
  }

  void setSort(bridge.SortBy sortBy, bridge.SortDir sortDir) {
    state = switch (state.selectedTab) {
      LibraryTab.library => state.copyWith(
        librarySortBy: sortBy,
        librarySortDir: sortDir,
      ),
      LibraryTab.favorites => state.copyWith(
        favoritesSortBy: sortBy,
        favoritesSortDir: sortDir,
      ),
      LibraryTab.history => state.copyWith(
        librarySortBy: sortBy,
        librarySortDir: sortDir,
      ),
    };
  }

  void setViewMode(LibraryViewMode viewMode) {
    state = state.copyWith(viewMode: viewMode);
  }

  void setDisplayMode(LibraryDisplayMode displayMode) {
    state = switch (state.selectedTab) {
      LibraryTab.library => state.copyWith(libraryDisplayMode: displayMode),
      LibraryTab.favorites => state.copyWith(favoritesDisplayMode: displayMode),
      LibraryTab.history => state.copyWith(libraryDisplayMode: displayMode),
    };
  }

  void setSelectedTab(LibraryTab selectedTab) {
    state = state.copyWith(selectedTab: selectedTab);
  }
}

bridge.SortBy _decodeSortBy(String? raw) {
  return switch (_decodeString(raw, 'name')) {
    'folder_date' => bridge.SortBy.folderDate,
    _ => bridge.SortBy.name,
  };
}

bridge.SortDir _decodeSortDir(String? raw) {
  return switch (_decodeString(raw, 'asc')) {
    'desc' => bridge.SortDir.desc,
    _ => bridge.SortDir.asc,
  };
}

LibraryViewMode _decodeViewMode(String? raw) {
  return switch (_decodeString(raw, 'all')) {
    'unread' => LibraryViewMode.unread,
    'reading' => LibraryViewMode.reading,
    _ => LibraryViewMode.all,
  };
}

LibraryDisplayMode _decodeDisplayMode(String? raw) {
  return switch (_decodeString(raw, 'grid')) {
    'list' => LibraryDisplayMode.list,
    _ => LibraryDisplayMode.grid,
  };
}

LibraryTab _decodeLibraryTab(String? raw) {
  return switch (_decodeString(raw, 'library')) {
    'history' => LibraryTab.history,
    'favorites' => LibraryTab.favorites,
    _ => LibraryTab.library,
  };
}

String encodeSortBy(bridge.SortBy value) {
  return switch (value) {
    bridge.SortBy.folderDate => 'folder_date',
    bridge.SortBy.name => 'name',
  };
}

String encodeSortDir(bridge.SortDir value) {
  return switch (value) {
    bridge.SortDir.desc => 'desc',
    bridge.SortDir.asc => 'asc',
  };
}

String encodeViewMode(LibraryViewMode value) {
  return switch (value) {
    LibraryViewMode.unread => 'unread',
    LibraryViewMode.reading => 'reading',
    LibraryViewMode.all => 'all',
  };
}

String encodeDisplayMode(LibraryDisplayMode value) {
  return switch (value) {
    LibraryDisplayMode.list => 'list',
    LibraryDisplayMode.grid => 'grid',
  };
}

String encodeLibraryTab(LibraryTab value) {
  return switch (value) {
    LibraryTab.history => 'history',
    LibraryTab.favorites => 'favorites',
    LibraryTab.library => 'library',
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
