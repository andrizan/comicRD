import 'dart:convert';

import 'package:flutter/material.dart';
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

class _LibraryPageState extends ConsumerState<LibraryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final ScrollController _historyScroll;
  late final ScrollController _libraryScroll;
  late final ScrollController _bookmarksScroll;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
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
    _tabs.dispose();
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
          child: Row(
            children: [
              Expanded(
                child: SearchBar(
                  controller: _search,
                  leading: const Icon(Icons.search),
                  hintText: text.search,
                  constraints: const BoxConstraints(minHeight: 44),
                  onChanged: (value) => ref
                      .read(libraryPreferencesProvider.notifier)
                      .setQuery(value),
                ),
              ),
              const SizedBox(width: 12),
              SegmentedButton<LibraryDisplayMode>(
                segments: const [
                  ButtonSegment(
                    value: LibraryDisplayMode.grid,
                    icon: Icon(Icons.grid_view_outlined),
                  ),
                  ButtonSegment(
                    value: LibraryDisplayMode.list,
                    icon: Icon(Icons.view_list_outlined),
                  ),
                ],
                selected: {preferences.displayMode},
                onSelectionChanged: (selection) =>
                    _setDisplayMode(selection.single),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Row(
            children: [
              SegmentedButton<LibraryViewMode>(
                segments: const [
                  ButtonSegment(value: LibraryViewMode.all, label: Text('All')),
                  ButtonSegment(
                    value: LibraryViewMode.unread,
                    label: Text('Unread'),
                  ),
                  ButtonSegment(
                    value: LibraryViewMode.reading,
                    label: Text('Progress'),
                  ),
                ],
                selected: {preferences.viewMode},
                onSelectionChanged: (selection) =>
                    _setViewMode(selection.single),
              ),
              const SizedBox(width: 12),
              DropdownButton<bridge.SortBy>(
                value: preferences.sortBy,
                items: const [
                  DropdownMenuItem(
                    value: bridge.SortBy.name,
                    child: Text('Name'),
                  ),
                  DropdownMenuItem(
                    value: bridge.SortBy.folderDate,
                    child: Text('Folder date'),
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
                    ? 'Ascending'
                    : 'Descending',
                child: IconButton(
                  onPressed: () => _setSort(
                    preferences.sortBy,
                    preferences.sortDir == bridge.SortDir.asc
                        ? bridge.SortDir.desc
                        : bridge.SortDir.asc,
                  ),
                  icon: Icon(
                    preferences.sortDir == bridge.SortDir.asc
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
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
                : 'No library source configured';
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
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
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
          loading: () => const SizedBox.shrink(),
        ),
        TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: text.history, icon: const Icon(Icons.history_outlined)),
            Tab(text: text.library, icon: const Icon(Icons.book_outlined)),
            Tab(
              text: text.bookmarks,
              icon: const Icon(Icons.bookmark_border_outlined),
            ),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _HistoryList(
                history: history,
                controller: _historyScroll,
                emptyLabel: text.emptyLibrary,
              ),
              _ComicList(
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
                controller: _bookmarksScroll,
                emptyLabel: text.emptyLibrary,
              ),
            ],
          ),
        ),
      ],
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
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final comic = items[index];
            final bookmarked = bookmarkedPaths.contains(comic.sourcePath);
            return ListTile(
              leading: Icon(
                bookmarked ? Icons.bookmark_outlined : Icons.menu_book_outlined,
              ),
              title: Text(comic.title),
              subtitle: Text(
                comic.sourcePath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () =>
                  context.go('/comic/${encodeRoutePath(comic.sourcePath)}'),
              onLongPress: () => onToggleBookmark(comic, bookmarked),
              contentPadding: const EdgeInsets.only(left: 16, right: 4),
              minLeadingWidth: 24,
              horizontalTitleGap: 12,
              mouseCursor: SystemMouseCursors.click,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              hoverColor: Theme.of(context).colorScheme.surfaceContainerHigh,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(comic.sourceType.toUpperCase()),
                  _ComicActionsButton(
                    bookmarked: bookmarked,
                    onToggleBookmark: () => onToggleBookmark(comic, bookmarked),
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
      error: (error, _) => _ErrorState(message: error.toString()),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}

class _ComicGridTile extends StatelessWidget {
  const _ComicGridTile({
    required this.comic,
    required this.bookmarked,
    required this.onOpen,
    required this.onToggleBookmark,
    required this.onCopyTitle,
    required this.onCopyPath,
    required this.onOpenFolder,
  });

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
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    bookmarked
                        ? Icons.bookmark_outlined
                        : Icons.menu_book_outlined,
                  ),
                  const Spacer(),
                  _ComicActionsButton(
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
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                comic.sourceType.toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComicActionsButton extends StatelessWidget {
  const _ComicActionsButton({
    required this.bookmarked,
    required this.onToggleBookmark,
    required this.onCopyTitle,
    required this.onCopyPath,
    required this.onOpenFolder,
  });

  final bool bookmarked;
  final Future<void> Function() onToggleBookmark;
  final Future<void> Function() onCopyTitle;
  final Future<void> Function() onCopyPath;
  final Future<void> Function() onOpenFolder;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_ComicAction>(
      tooltip: 'Comic actions',
      icon: const Icon(Icons.more_vert),
      onSelected: (action) async {
        switch (action) {
          case _ComicAction.toggleBookmark:
            await onToggleBookmark();
          case _ComicAction.copyTitle:
            await onCopyTitle();
          case _ComicAction.copyPath:
            await onCopyPath();
          case _ComicAction.openFolder:
            await onOpenFolder();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _ComicAction.toggleBookmark,
          child: Text(bookmarked ? 'Remove bookmark' : 'Add bookmark'),
        ),
        const PopupMenuItem(
          value: _ComicAction.openFolder,
          child: Text('Open folder'),
        ),
        const PopupMenuItem(
          value: _ComicAction.copyTitle,
          child: Text('Copy title'),
        ),
        const PopupMenuItem(
          value: _ComicAction.copyPath,
          child: Text('Copy path'),
        ),
      ],
    );
  }
}

enum _ComicAction { toggleBookmark, openFolder, copyTitle, copyPath }

class _HistoryList extends StatelessWidget {
  const _HistoryList({
    required this.history,
    required this.controller,
    required this.emptyLabel,
  });

  final AsyncValue<List<bridge.ReadingHistoryEntry>> history;
  final ScrollController controller;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    return history.when(
      data: (items) {
        if (items.isEmpty) {
          return _EmptyState(label: emptyLabel);
        }
        return ListView.separated(
          controller: controller,
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = items[index];
            return ListTile(
              leading: const Icon(Icons.history_outlined),
              title: Text(item.comicTitle),
              subtitle: Text(item.chapterTitle),
              onTap: () =>
                  context.go('/comic/${encodeRoutePath(item.comicSourcePath)}'),
            );
          },
        );
      },
      error: (error, _) => _ErrorState(message: error.toString()),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}

class _BookmarkList extends StatelessWidget {
  const _BookmarkList({
    required this.bookmarks,
    required this.controller,
    required this.emptyLabel,
  });

  final AsyncValue<List<bridge.ComicBookmark>> bookmarks;
  final ScrollController controller;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    return bookmarks.when(
      data: (items) {
        if (items.isEmpty) {
          return _EmptyState(label: emptyLabel);
        }
        return ListView.separated(
          controller: controller,
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = items[index];
            return ListTile(
              leading: const Icon(Icons.bookmark_border_outlined),
              title: Text(item.comicTitle),
              subtitle: Text(
                item.comicSourcePath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () =>
                  context.go('/comic/${encodeRoutePath(item.comicSourcePath)}'),
            );
          },
        );
      },
      error: (error, _) => _ErrorState(message: error.toString()),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(label, style: Theme.of(context).textTheme.titleMedium),
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
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}
