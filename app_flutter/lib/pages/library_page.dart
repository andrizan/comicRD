import 'dart:convert';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../bridge_generated.dart' as bridge;
import '../routes/path_codec.dart';
import '../state/api_state.dart';
import '../state/library_state.dart';
import '../state/scroll_state.dart';
import '../state/settings_data_state.dart';
import '../state/settings_state.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  int _currentIndex = 0;
  late final ScrollController _historyScroll;
  late final ScrollController _libraryScroll;
  late final ScrollController _bookmarksScroll;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _historyScroll = _restoredScrollController('library:history');
    _libraryScroll = _restoredScrollController('library:library');
    _bookmarksScroll = _restoredScrollController('library:bookmarks');
    _search.addListener(() {
      ref.read(libraryPreferencesProvider.notifier).setQuery(_search.text);
    });
  }

  @override
  void dispose() {
    _saveScrollOffset('library:history', _historyScroll);
    _saveScrollOffset('library:library', _libraryScroll);
    _saveScrollOffset('library:bookmarks', _bookmarksScroll);
    _historyScroll.dispose();
    _libraryScroll.dispose();
    _bookmarksScroll.dispose();
    _search.dispose();
    super.dispose();
  }

  ScrollController _restoredScrollController(String key) {
    final offsets = ref.read(scrollOffsetsProvider.notifier);
    final controller = ScrollController(
      initialScrollOffset: offsets.offsetFor(key),
    );
    controller.addListener(() => _saveScrollOffset(key, controller));
    return controller;
  }

  void _saveScrollOffset(String key, ScrollController controller) {
    if (!controller.hasClients) {
      return;
    }
    ref.read(scrollOffsetsProvider.notifier).save(key, controller.offset);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<Map<String, String>>>(settingsMapProvider, (_, next) {
      next.whenData(
        ref.read(libraryPreferencesProvider.notifier).hydrateFromSettings,
      );
    });

    final text = stringsFor(ref.watch(appSettingsProvider).localeCode);
    final preferences = ref.watch(libraryPreferencesProvider);
    final sourceStatus = ref.watch(librarySourceStatusProvider);
    final history = ref.watch(readingHistoryProvider);
    final comics = ref.watch(libraryComicsProvider);
    final bookmarks = ref.watch(allBookmarksProvider);
    final bookmarkedPaths =
        bookmarks.asData?.value
            .map((bookmark) => bookmark.comicSourcePath)
            .toSet() ??
        const <String>{};
    return ScaffoldPage(
      content: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextBox(
                    controller: _search,
                    prefix: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(FluentIcons.search, size: 16),
                    ),
                    placeholder: text.search,
                    onChanged: (value) => ref
                        .read(libraryPreferencesProvider.notifier)
                        .setQuery(value),
                  ),
                ),
                const SizedBox(width: 12),
                ToggleButton(
                  checked: preferences.displayMode == LibraryDisplayMode.grid,
                  onChanged: (value) => _setDisplayMode(
                    value ? LibraryDisplayMode.grid : LibraryDisplayMode.list,
                  ),
                  child: const Icon(FluentIcons.grid_view_medium),
                ),
                const SizedBox(width: 4),
                ToggleButton(
                  checked: preferences.displayMode == LibraryDisplayMode.list,
                  onChanged: (value) => _setDisplayMode(
                    value ? LibraryDisplayMode.list : LibraryDisplayMode.grid,
                  ),
                  child: const Icon(FluentIcons.list),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Row(
              children: [
                ToggleButton(
                  checked: preferences.viewMode == LibraryViewMode.all,
                  onChanged: (value) => _setViewMode(LibraryViewMode.all),
                  child: Text(text.all),
                ),
                const SizedBox(width: 4),
                ToggleButton(
                  checked: preferences.viewMode == LibraryViewMode.unread,
                  onChanged: (value) => _setViewMode(LibraryViewMode.unread),
                  child: Text(text.unread),
                ),
                const SizedBox(width: 4),
                ToggleButton(
                  checked: preferences.viewMode == LibraryViewMode.reading,
                  onChanged: (value) => _setViewMode(LibraryViewMode.reading),
                  child: Text(text.progress),
                ),
                const SizedBox(width: 12),
                ComboBox<bridge.SortBy>(
                  value: preferences.sortBy,
                  items: [
                    ComboBoxItem(
                      value: bridge.SortBy.name,
                      child: Text(text.name),
                    ),
                    ComboBoxItem(
                      value: bridge.SortBy.folderDate,
                      child: Text(text.folderDate),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      _setSort(value, preferences.sortDir);
                    }
                  },
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message: preferences.sortDir == bridge.SortDir.asc
                      ? text.ascending
                      : text.descending,
                  child: IconButton(
                    onPressed: () => _setSort(
                      preferences.sortBy,
                      preferences.sortDir == bridge.SortDir.asc
                          ? bridge.SortDir.desc
                          : bridge.SortDir.asc,
                    ),
                    icon: Icon(
                      preferences.sortDir == bridge.SortDir.asc
                          ? FluentIcons.sort_up
                          : FluentIcons.sort_down,
                    ),
                  ),
                ),
              ],
            ),
          ),
          sourceStatus.when(
            data: (status) {
              if (status.configured && status.error == null) {
                return const SizedBox.shrink();
              }
              final message = status.configured
                  ? status.error!
                  : text.noLibrarySource;
              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    message,
                    style: TextStyle(
                      color: FluentTheme.of(context).accentColor,
                    ),
                  ),
                ),
              );
            },
            error: (error, _) => Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  error.toString(),
                  style: TextStyle(color: FluentTheme.of(context).accentColor),
                ),
              ),
            ),
            loading: () => const SizedBox.shrink(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                _buildTab(text.history, FluentIcons.history, 0),
                const SizedBox(width: 4),
                _buildTab(text.library, FluentIcons.library, 1),
                const SizedBox(width: 4),
                _buildTab(text.bookmarks, FluentIcons.bookmarks, 2),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: [
                _HistoryList(
                  history: history,
                  displayMode: preferences.displayMode,
                  controller: _historyScroll,
                  emptyLabel: text.emptyLibrary,
                ),
                _ComicList(
                  text: text,
                  comics: comics,
                  displayMode: preferences.displayMode,
                  bookmarkedPaths: bookmarkedPaths,
                  controller: _libraryScroll,
                  emptyLabel: text.emptyLibrary,
                  onToggleBookmark: _toggleComicBookmark,
                  onCopyTitle: _copyComicTitle,
                  onCopyPath: _copyComicPath,
                  onOpenFolder: _openContainingFolder,
                ),
                _BookmarkList(
                  bookmarks: bookmarks,
                  displayMode: preferences.displayMode,
                  controller: _bookmarksScroll,
                  emptyLabel: text.emptyLibrary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(String label, IconData icon, int index) {
    final isActive = _currentIndex == index;
    final theme = FluentTheme.of(context);
    return Expanded(
      child: HoverButton(
        onPressed: () => setState(() => _currentIndex = index),
        builder: (context, states) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: isActive
                  ? theme.accentColor.withValues(alpha: 0.1)
                  : states.isHovered
                  ? theme.resources.cardBackgroundFillColorSecondary
                  : Colors.transparent,
              border: Border(
                bottom: BorderSide(
                  color: isActive ? theme.accentColor : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isActive ? theme.accentColor : null,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: isActive ? theme.accentColor : null,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _setSort(bridge.SortBy sortBy, bridge.SortDir sortDir) async {
    ref.read(libraryPreferencesProvider.notifier).setSort(sortBy, sortDir);
    final api = ref.read(comicRdApiProvider);
    await api.setSetting('library_sort_by', jsonEncode(encodeSortBy(sortBy)));
    await api.setSetting(
      'library_sort_dir',
      jsonEncode(encodeSortDir(sortDir)),
    );
  }

  Future<void> _setViewMode(LibraryViewMode viewMode) async {
    ref.read(libraryPreferencesProvider.notifier).setViewMode(viewMode);
    await ref
        .read(comicRdApiProvider)
        .setSetting('library_view_mode', jsonEncode(encodeViewMode(viewMode)));
  }

  Future<void> _setDisplayMode(LibraryDisplayMode displayMode) async {
    ref.read(libraryPreferencesProvider.notifier).setDisplayMode(displayMode);
    await ref
        .read(comicRdApiProvider)
        .setSetting(
          'library_display_mode',
          jsonEncode(encodeDisplayMode(displayMode)),
        );
  }

  Future<void> _toggleComicBookmark(
    bridge.RawComic comic,
    bool bookmarked,
  ) async {
    final api = ref.read(comicRdApiProvider);
    if (bookmarked) {
      await api.removeComicBookmark(comic.sourcePath);
    } else {
      await api.addComicBookmark(comic.sourcePath);
    }
    ref.invalidate(allBookmarksProvider);
  }

  Future<void> _copyComicTitle(bridge.RawComic comic) async {
    await Clipboard.setData(ClipboardData(text: comic.title));
  }

  Future<void> _copyComicPath(bridge.RawComic comic) async {
    await Clipboard.setData(ClipboardData(text: comic.sourcePath));
  }

  Future<void> _openContainingFolder(bridge.RawComic comic) async {
    await ref.read(comicRdApiProvider).openContainingFolder(comic.sourcePath);
  }
}

class _ComicList extends StatelessWidget {
  const _ComicList({
    required this.text,
    required this.comics,
    required this.displayMode,
    required this.bookmarkedPaths,
    required this.controller,
    required this.emptyLabel,
    required this.onToggleBookmark,
    required this.onCopyTitle,
    required this.onCopyPath,
    required this.onOpenFolder,
  });

  final AppStrings text;
  final AsyncValue<List<bridge.RawComic>> comics;
  final LibraryDisplayMode displayMode;
  final Set<String> bookmarkedPaths;
  final ScrollController controller;
  final String emptyLabel;
  final Future<void> Function(bridge.RawComic comic, bool bookmarked)
  onToggleBookmark;
  final Future<void> Function(bridge.RawComic comic) onCopyTitle;
  final Future<void> Function(bridge.RawComic comic) onCopyPath;
  final Future<void> Function(bridge.RawComic comic) onOpenFolder;

  @override
  Widget build(BuildContext context) {
    return comics.when(
      data: (items) {
        if (items.isEmpty) {
          return _EmptyState(label: emptyLabel);
        }
        if (displayMode == LibraryDisplayMode.grid) {
          return GridView.builder(
            controller: controller,
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisExtent: 164,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final comic = items[index];
              final bookmarked = bookmarkedPaths.contains(comic.sourcePath);
              return _ComicGridTile(
                text: text,
                comic: comic,
                bookmarked: bookmarked,
                onOpen: () =>
                    context.go('/comic/${encodeRoutePath(comic.sourcePath)}'),
                onToggleBookmark: () => onToggleBookmark(comic, bookmarked),
                onCopyTitle: () => onCopyTitle(comic),
                onCopyPath: () => onCopyPath(comic),
                onOpenFolder: () => onOpenFolder(comic),
              );
            },
          );
        }
        return ListView.separated(
          controller: controller,
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, index) {
            final comic = items[index];
            final bookmarked = bookmarkedPaths.contains(comic.sourcePath);
            return HoverButton(
              onPressed: () =>
                  context.go('/comic/${encodeRoutePath(comic.sourcePath)}'),
              builder: (context, states) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: states.isHovered
                        ? FluentTheme.of(
                            context,
                          ).resources.cardBackgroundFillColorSecondary
                        : null,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        bookmarked
                            ? FluentIcons.bookmarks
                            : FluentIcons.reading_mode,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(comic.title),
                            Text(
                              comic.sourcePath,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: FluentTheme.of(context).typography.caption,
                            ),
                          ],
                        ),
                      ),
                      _ReadStatusBadge(
                        readCount: comic.readChapterCount,
                        totalCount: comic.chapterCount,
                        inProgressCount: comic.inProgressChapterCount,
                      ),
                      const SizedBox(width: 8),
                      Text(comic.sourceType.toUpperCase()),
                      _ComicActionsButton(
                        text: text,
                        bookmarked: bookmarked,
                        onToggleBookmark: () =>
                            onToggleBookmark(comic, bookmarked),
                        onCopyTitle: () => onCopyTitle(comic),
                        onCopyPath: () => onCopyPath(comic),
                        onOpenFolder: () => onOpenFolder(comic),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
      error: (error, _) => _ErrorState(message: error.toString()),
      loading: () =>
          const Align(alignment: Alignment.center, child: ProgressRing()),
    );
  }
}

class _ComicGridTile extends StatelessWidget {
  const _ComicGridTile({
    required this.text,
    required this.comic,
    required this.bookmarked,
    required this.onOpen,
    required this.onToggleBookmark,
    required this.onCopyTitle,
    required this.onCopyPath,
    required this.onOpenFolder,
  });

  final AppStrings text;
  final bridge.RawComic comic;
  final bool bookmarked;
  final VoidCallback onOpen;
  final Future<void> Function() onToggleBookmark;
  final Future<void> Function() onCopyTitle;
  final Future<void> Function() onCopyPath;
  final Future<void> Function() onOpenFolder;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: HoverButton(
        onPressed: onOpen,
        builder: (context, states) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: states.isHovered
                  ? FluentTheme.of(
                      context,
                    ).resources.cardBackgroundFillColorSecondary
                  : null,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      bookmarked
                          ? FluentIcons.bookmarks
                          : FluentIcons.reading_mode,
                      size: 20,
                    ),
                    const Spacer(),
                    _ReadStatusBadge(
                      readCount: comic.readChapterCount,
                      totalCount: comic.chapterCount,
                      inProgressCount: comic.inProgressChapterCount,
                    ),
                    _ComicActionsButton(
                      text: text,
                      bookmarked: bookmarked,
                      onToggleBookmark: onToggleBookmark,
                      onCopyTitle: onCopyTitle,
                      onCopyPath: onCopyPath,
                      onOpenFolder: onOpenFolder,
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  comic.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: FluentTheme.of(context).typography.bodyStrong,
                ),
                const SizedBox(height: 6),
                Text(
                  comic.sourceType.toUpperCase(),
                  style: FluentTheme.of(context).typography.caption,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ReadStatusBadge extends StatelessWidget {
  const _ReadStatusBadge({
    required this.readCount,
    required this.totalCount,
    required this.inProgressCount,
  });

  final int readCount;
  final int totalCount;
  final int inProgressCount;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    if (totalCount == 0) {
      return const SizedBox.shrink();
    }
    if (readCount >= totalCount) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: theme.accentColor.withAlpha(40),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'Read',
          style: TextStyle(
            color: theme.accentColor,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    if (inProgressCount > 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: theme.accentColor.withAlpha(30),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'Reading $readCount/$totalCount',
          style: TextStyle(
            color: theme.accentColor,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorSecondary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'Unread',
        style: TextStyle(
          color: theme.resources.textFillColorSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _ComicActionsButton extends StatelessWidget {
  const _ComicActionsButton({
    required this.text,
    required this.bookmarked,
    required this.onToggleBookmark,
    required this.onCopyTitle,
    required this.onCopyPath,
    required this.onOpenFolder,
  });

  final AppStrings text;
  final bool bookmarked;
  final Future<void> Function() onToggleBookmark;
  final Future<void> Function() onCopyTitle;
  final Future<void> Function() onCopyPath;
  final Future<void> Function() onOpenFolder;

  @override
  Widget build(BuildContext context) {
    return DropDownButton(
      title: const Icon(FluentIcons.more),
      items: [
        MenuFlyoutItem(
          text: Text(bookmarked ? text.removeBookmark : text.addBookmark),
          onPressed: () async => await onToggleBookmark(),
        ),
        MenuFlyoutItem(
          text: Text(text.openFolder),
          onPressed: () async => await onOpenFolder(),
        ),
        MenuFlyoutItem(
          text: Text(text.copyTitle),
          onPressed: () async => await onCopyTitle(),
        ),
        MenuFlyoutItem(
          text: Text(text.copyPath),
          onPressed: () async => await onCopyPath(),
        ),
      ],
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({
    required this.history,
    required this.displayMode,
    required this.controller,
    required this.emptyLabel,
  });

  final AsyncValue<List<bridge.ReadingHistoryEntry>> history;
  final LibraryDisplayMode displayMode;
  final ScrollController controller;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    return history.when(
      data: (items) {
        if (items.isEmpty) {
          return _EmptyState(label: emptyLabel);
        }
        if (displayMode == LibraryDisplayMode.grid) {
          return GridView.builder(
            controller: controller,
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisExtent: 100,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                child: HoverButton(
                  onPressed: () => context.go(
                    '/comic/${encodeRoutePath(item.comicSourcePath)}',
                  ),
                  builder: (context, states) {
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: states.isHovered
                            ? FluentTheme.of(
                                context,
                              ).resources.cardBackgroundFillColorSecondary
                            : null,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(FluentIcons.history, size: 20),
                          const Spacer(),
                          Text(
                            item.comicTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FluentTheme.of(
                              context,
                            ).typography.bodyStrong,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.chapterTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FluentTheme.of(context).typography.caption,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          );
        }
        return ListView.separated(
          controller: controller,
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, index) {
            final item = items[index];
            return HoverButton(
              onPressed: () =>
                  context.go('/comic/${encodeRoutePath(item.comicSourcePath)}'),
              builder: (context, states) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: states.isHovered
                        ? FluentTheme.of(
                            context,
                          ).resources.cardBackgroundFillColorSecondary
                        : null,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Icon(FluentIcons.history, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.comicTitle),
                            Text(
                              item.chapterTitle,
                              style: FluentTheme.of(context).typography.caption,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
      error: (error, _) => _ErrorState(message: error.toString()),
      loading: () =>
          const Align(alignment: Alignment.center, child: ProgressRing()),
    );
  }
}

class _BookmarkList extends StatelessWidget {
  const _BookmarkList({
    required this.bookmarks,
    required this.displayMode,
    required this.controller,
    required this.emptyLabel,
  });

  final AsyncValue<List<bridge.ComicBookmark>> bookmarks;
  final LibraryDisplayMode displayMode;
  final ScrollController controller;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    return bookmarks.when(
      data: (items) {
        if (items.isEmpty) {
          return _EmptyState(label: emptyLabel);
        }
        if (displayMode == LibraryDisplayMode.grid) {
          return GridView.builder(
            controller: controller,
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisExtent: 100,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                child: HoverButton(
                  onPressed: () => context.go(
                    '/comic/${encodeRoutePath(item.comicSourcePath)}',
                  ),
                  builder: (context, states) {
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: states.isHovered
                            ? FluentTheme.of(
                                context,
                              ).resources.cardBackgroundFillColorSecondary
                            : null,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(FluentIcons.bookmarks, size: 20),
                          const Spacer(),
                          Text(
                            item.comicTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: FluentTheme.of(
                              context,
                            ).typography.bodyStrong,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          );
        }
        return ListView.separated(
          controller: controller,
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, index) {
            final item = items[index];
            return HoverButton(
              onPressed: () =>
                  context.go('/comic/${encodeRoutePath(item.comicSourcePath)}'),
              builder: (context, states) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: states.isHovered
                        ? FluentTheme.of(
                            context,
                          ).resources.cardBackgroundFillColorSecondary
                        : null,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Icon(FluentIcons.bookmarks, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.comicTitle),
                            Text(
                              item.comicSourcePath,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: FluentTheme.of(context).typography.caption,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
      error: (error, _) => _ErrorState(message: error.toString()),
      loading: () =>
          const Align(alignment: Alignment.center, child: ProgressRing()),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(label, style: FluentTheme.of(context).typography.bodyStrong),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: TextStyle(color: FluentTheme.of(context).accentColor),
      ),
    );
  }
}
