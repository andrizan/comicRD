import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../bridge_generated.dart' as bridge;
import '../routes/path_codec.dart';
import '../state/library_state.dart';
import '../state/scroll_state.dart';
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
    final text = stringsFor(ref.watch(appSettingsProvider).localeCode);
    final preferences = ref.watch(libraryPreferencesProvider);
    final sourceStatus = ref.watch(librarySourceStatusProvider);
    final history = ref.watch(readingHistoryProvider);
    final comics = ref.watch(libraryComicsProvider);
    final bookmarks = ref.watch(allBookmarksProvider);
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
                onSelectionChanged: (selection) {
                  ref
                      .read(libraryPreferencesProvider.notifier)
                      .setDisplayMode(selection.single);
                },
              ),
            ],
          ),
        ),
        sourceStatus.when(
          data: (status) {
            if (!status.configured || status.error == null) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  status.error!,
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
                controller: _libraryScroll,
                emptyLabel: text.emptyLibrary,
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
}

class _ComicList extends StatelessWidget {
  const _ComicList({
    required this.comics,
    required this.controller,
    required this.emptyLabel,
  });

  final AsyncValue<List<bridge.RawComic>> comics;
  final ScrollController controller;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    return comics.when(
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
            final comic = items[index];
            return ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(comic.title),
              subtitle: Text(
                comic.sourcePath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(comic.sourceType.toUpperCase()),
              onTap: () =>
                  context.go('/comic/${encodeRoutePath(comic.sourcePath)}'),
            );
          },
        );
      },
      error: (error, _) => _ErrorState(message: error.toString()),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}

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
