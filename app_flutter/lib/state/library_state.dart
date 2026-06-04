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

final libraryComicsProvider = FutureProvider<List<bridge.RawComic>>((
  ref,
) async {
  final api = ref.watch(comicRdApiProvider);
  final preferences = ref.watch(libraryPreferencesProvider);
  final comics = await api.listLibraryComicsRaw(
    sortBy: preferences.sortBy,
    sortDir: preferences.sortDir,
  );
  final query = preferences.query.trim().toLowerCase();
  if (query.isEmpty) {
    return comics;
  }
  return comics
      .where(
        (comic) =>
            comic.title.toLowerCase().contains(query) ||
            comic.sourcePath.toLowerCase().contains(query),
      )
      .toList();
});

final readingHistoryProvider = FutureProvider<List<bridge.ReadingHistoryEntry>>(
  (ref) {
    return ref.watch(comicRdApiProvider).listReadingHistory();
  },
);

final allBookmarksProvider = FutureProvider<List<bridge.ComicBookmark>>((ref) {
  return ref.watch(comicRdApiProvider).listAllBookmarks();
});

final comicsWithProgressProvider = FutureProvider<List<String>>((ref) {
  return ref.watch(comicRdApiProvider).listComicsWithProgress();
});

enum LibraryViewMode { all, unread, reading }

enum LibraryDisplayMode { grid, list }

class LibraryPreferences {
  const LibraryPreferences({
    this.query = '',
    this.sortBy = bridge.SortBy.name,
    this.sortDir = bridge.SortDir.asc,
    this.viewMode = LibraryViewMode.all,
    this.displayMode = LibraryDisplayMode.grid,
  });

  final String query;
  final bridge.SortBy sortBy;
  final bridge.SortDir sortDir;
  final LibraryViewMode viewMode;
  final LibraryDisplayMode displayMode;

  LibraryPreferences copyWith({
    String? query,
    bridge.SortBy? sortBy,
    bridge.SortDir? sortDir,
    LibraryViewMode? viewMode,
    LibraryDisplayMode? displayMode,
  }) => LibraryPreferences(
    query: query ?? this.query,
    sortBy: sortBy ?? this.sortBy,
    sortDir: sortDir ?? this.sortDir,
    viewMode: viewMode ?? this.viewMode,
    displayMode: displayMode ?? this.displayMode,
  );
}

class LibraryPreferencesNotifier extends Notifier<LibraryPreferences> {
  @override
  LibraryPreferences build() => const LibraryPreferences();

  void setQuery(String query) {
    state = state.copyWith(query: query);
  }

  void setSort(bridge.SortBy sortBy, bridge.SortDir sortDir) {
    state = state.copyWith(sortBy: sortBy, sortDir: sortDir);
  }

  void setViewMode(LibraryViewMode viewMode) {
    state = state.copyWith(viewMode: viewMode);
  }

  void setDisplayMode(LibraryDisplayMode displayMode) {
    state = state.copyWith(displayMode: displayMode);
  }
}
