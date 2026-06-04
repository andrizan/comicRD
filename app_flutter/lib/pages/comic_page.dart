import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../bridge_generated.dart' as bridge;
import '../state/api_state.dart';
import '../state/comic_state.dart';
import '../state/scroll_state.dart';
import '../state/settings_data_state.dart';
import '../state/settings_state.dart';

class ComicPage extends ConsumerStatefulWidget {
  const ComicPage({super.key, required this.comicPath});

  final String comicPath;

  @override
  ConsumerState<ComicPage> createState() => _ComicPageState();
}

class _ComicPageState extends ConsumerState<ComicPage> {
  late final ScrollController _scroll;
  late final TextEditingController _search;
  late final FocusNode _focusNode;
  bool _didScrollToLastOpened = false;

  @override
  void initState() {
    super.initState();
    final key = ref.read(comicScrollKeyProvider(widget.comicPath));
    final offsets = ref.read(scrollOffsetsProvider.notifier);
    _scroll = ScrollController(initialScrollOffset: offsets.offsetFor(key));
    _scroll.addListener(() {
      ref.read(scrollOffsetsProvider.notifier).save(key, _scroll.offset);
    });
    _search = TextEditingController();
    _search.addListener(() {
      ref
          .read(comicPreferencesProvider.notifier)
          .setQuery(widget.comicPath, _search.text);
    });
    _focusNode = FocusNode(debugLabel: 'ComicPage');
  }

  @override
  void dispose() {
    if (_scroll.hasClients) {
      final key = ref.read(comicScrollKeyProvider(widget.comicPath));
      ref.read(scrollOffsetsProvider.notifier).save(key, _scroll.offset);
    }
    _focusNode.dispose();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<Map<String, String>>>(settingsMapProvider, (_, next) {
      next.whenData(
        (values) => ref
            .read(comicPreferencesProvider.notifier)
            .hydrateFromSettings(widget.comicPath, values),
      );
    });

    final text = stringsFor(ref.watch(appSettingsProvider).localeCode);
    final preferences = ref.watch(
      comicPreferencesProvider.select(
        (state) => state[widget.comicPath] ?? const ComicPreferences(),
      ),
    );
    final chapters = ref.watch(filteredComicChaptersProvider(widget.comicPath));
    final favorites = ref.watch(chapterFavoritesProvider(widget.comicPath));
    final favoritePaths = favorites.asData?.value.toSet() ?? const <String>{};
    final title = widget.comicPath.split(RegExp(r'[/\\]')).last;

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          context.go('/');
        }
      },
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: text.home,
                  onPressed: () => context.go('/'),
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title.isEmpty ? text.comic : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SearchBar(
                    controller: _search,
                    leading: const Icon(Icons.search),
                    hintText: text.search,
                    constraints: const BoxConstraints(minHeight: 44),
                    onChanged: (value) => ref
                        .read(comicPreferencesProvider.notifier)
                        .setQuery(widget.comicPath, value),
                  ),
                ),
                const SizedBox(width: 12),
                SegmentedButton<ChapterDisplayMode>(
                  segments: const [
                    ButtonSegment(
                      value: ChapterDisplayMode.grid,
                      icon: Icon(Icons.grid_view_outlined),
                    ),
                    ButtonSegment(
                      value: ChapterDisplayMode.list,
                      icon: Icon(Icons.view_list_outlined),
                    ),
                  ],
                  selected: {preferences.displayMode},
                  onSelectionChanged: (selection) => ref
                      .read(comicPreferencesProvider.notifier)
                      .setDisplayMode(widget.comicPath, selection.single),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilterChip(
                  selected: preferences.favoritesOnly,
                  avatar: const Icon(Icons.star_outline, size: 18),
                  label: const Text('Favorites'),
                  onSelected: (value) => ref
                      .read(comicPreferencesProvider.notifier)
                      .setFavoritesOnly(widget.comicPath, value),
                ),
                const SizedBox(width: 12),
                DropdownButton<ChapterSortBy>(
                  value: preferences.sortBy,
                  items: const [
                    DropdownMenuItem(
                      value: ChapterSortBy.chapterIndex,
                      child: Text('Chapter'),
                    ),
                    DropdownMenuItem(
                      value: ChapterSortBy.name,
                      child: Text('Name'),
                    ),
                    DropdownMenuItem(
                      value: ChapterSortBy.folderDate,
                      child: Text('Folder date'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      _setSort(value, preferences.sortDir);
                    }
                  },
                ),
                IconButton(
                  tooltip: preferences.sortDir == bridge.SortDir.asc
                      ? 'Ascending'
                      : 'Descending',
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
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: chapters.when(
                data: (items) {
                  _scrollToLastOpened(items, preferences.displayMode);
                  return _ChapterList(
                    chapters: items,
                    favorites: favoritePaths,
                    displayMode: preferences.displayMode,
                    controller: _scroll,
                    emptyLabel: text.emptyLibrary,
                    onOpen: _openChapter,
                    onToggleFavorite: _toggleFavorite,
                  );
                },
                error: (error, _) => Center(
                  child: Text(
                    error.toString(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setSort(ChapterSortBy sortBy, bridge.SortDir sortDir) async {
    ref
        .read(comicPreferencesProvider.notifier)
        .setSort(widget.comicPath, sortBy, sortDir);
    final api = ref.read(comicRdApiProvider);
    await api.setSetting(
      'chapter_sort_by',
      jsonEncode(_encodeChapterSortBy(sortBy)),
    );
    await api.setSetting(
      'chapter_sort_dir',
      jsonEncode(sortDir == bridge.SortDir.asc ? 'asc' : 'desc'),
    );
  }

  Future<void> _toggleFavorite(bridge.RawChapter chapter, bool favorite) async {
    final api = ref.read(comicRdApiProvider);
    if (favorite) {
      await api.removeChapterFavorite(chapter.sourcePath);
    } else {
      await api.addChapterFavorite(
        chapterSourcePath: chapter.sourcePath,
        comicSourcePath: widget.comicPath,
      );
    }
    ref.invalidate(chapterFavoritesProvider(widget.comicPath));
    ref.invalidate(filteredComicChaptersProvider(widget.comicPath));
  }

  Future<void> _openChapter(bridge.RawChapter chapter) async {
    final api = ref.read(comicRdApiProvider);
    final chapterId = await api.openChapterForReading(
      bridge.OpenChapterPayload(
        comicSourcePath: widget.comicPath,
        chapterSourcePath: chapter.sourcePath,
      ),
    );
    ref
        .read(lastOpenedChapterProvider.notifier)
        .remember(widget.comicPath, chapter.sourcePath);

    final start = chapter.lastPage > 0 ? chapter.lastPage : 0;
    final maxPage = chapter.totalPages > 0
        ? chapter.totalPages
        : chapter.pageCount;
    final pages = [
      for (var index = start; index < maxPage && index < start + 4; index++)
        index,
    ];
    if (pages.isNotEmpty) {
      await api.prefetchPageVariants(
        bridge.PrefetchPageVariantsPayload(
          chapterId: chapterId,
          pageIndices: Uint32List.fromList(pages.cast<int>()),
          targetWidth: 1024,
          profile: bridge.ImageVariantProfile.balanced,
        ),
      );
    }

    if (mounted) {
      context.go('/reader/$chapterId');
    }
  }

  void _scrollToLastOpened(
    List<bridge.RawChapter> chapters,
    ChapterDisplayMode displayMode,
  ) {
    if (_didScrollToLastOpened || _scroll.initialScrollOffset > 0) {
      return;
    }
    final lastSourcePath = ref
        .read(lastOpenedChapterProvider.notifier)
        .sourcePathFor(widget.comicPath);
    if (lastSourcePath == null) {
      return;
    }
    final index = chapters.indexWhere(
      (chapter) => chapter.sourcePath == lastSourcePath,
    );
    if (index < 0) {
      return;
    }
    _didScrollToLastOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) {
        return;
      }
      final row = displayMode == ChapterDisplayMode.grid ? index ~/ 3 : index;
      final offset =
          row * (displayMode == ChapterDisplayMode.grid ? 152.0 : 73.0);
      _scroll.animateTo(
        offset.clamp(0, _scroll.position.maxScrollExtent).toDouble(),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }
}

String _encodeChapterSortBy(ChapterSortBy sortBy) {
  return switch (sortBy) {
    ChapterSortBy.name => 'name',
    ChapterSortBy.folderDate => 'folder_date',
    ChapterSortBy.chapterIndex => 'chapter_index',
  };
}

class _ChapterList extends StatelessWidget {
  const _ChapterList({
    required this.chapters,
    required this.favorites,
    required this.displayMode,
    required this.controller,
    required this.emptyLabel,
    required this.onOpen,
    required this.onToggleFavorite,
  });

  final List<bridge.RawChapter> chapters;
  final Set<String> favorites;
  final ChapterDisplayMode displayMode;
  final ScrollController controller;
  final String emptyLabel;
  final Future<void> Function(bridge.RawChapter chapter) onOpen;
  final Future<void> Function(bridge.RawChapter chapter, bool favorite)
  onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    if (chapters.isEmpty) {
      return Center(
        child: Text(emptyLabel, style: Theme.of(context).textTheme.titleMedium),
      );
    }
    if (displayMode == ChapterDisplayMode.grid) {
      return GridView.builder(
        controller: controller,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 240,
          mainAxisExtent: 140,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: chapters.length,
        itemBuilder: (context, index) {
          final chapter = chapters[index];
          final favorite = favorites.contains(chapter.sourcePath);
          return _ChapterGridTile(
            chapter: chapter,
            favorite: favorite,
            onOpen: () {
              onOpen(chapter);
            },
            onToggleFavorite: () {
              onToggleFavorite(chapter, favorite);
            },
          );
        },
      );
    }
    return ListView.separated(
      controller: controller,
      itemCount: chapters.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final chapter = chapters[index];
        final favorite = favorites.contains(chapter.sourcePath);
        return ListTile(
          leading: IconButton(
            tooltip: favorite ? 'Remove favorite' : 'Add favorite',
            onPressed: () => onToggleFavorite(chapter, favorite),
            icon: Icon(
              favorite ? Icons.star : Icons.star_border,
              color: favorite ? Theme.of(context).colorScheme.tertiary : null,
            ),
          ),
          title: Text(chapter.title),
          subtitle: Text(_chapterStatus(chapter)),
          trailing: chapter.isRead
              ? const Icon(Icons.done_all_outlined)
              : const Icon(Icons.chevron_right),
          onTap: () => onOpen(chapter),
        );
      },
    );
  }
}

class _ChapterGridTile extends StatelessWidget {
  const _ChapterGridTile({
    required this.chapter,
    required this.favorite,
    required this.onOpen,
    required this.onToggleFavorite,
  });

  final bridge.RawChapter chapter;
  final bool favorite;
  final VoidCallback onOpen;
  final VoidCallback onToggleFavorite;

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
                    chapter.isRead
                        ? Icons.done_all_outlined
                        : Icons.article_outlined,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: favorite ? 'Remove favorite' : 'Add favorite',
                    onPressed: onToggleFavorite,
                    icon: Icon(
                      favorite ? Icons.star : Icons.star_border,
                      color: favorite
                          ? Theme.of(context).colorScheme.tertiary
                          : null,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                chapter.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                _chapterStatus(chapter),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _chapterStatus(bridge.RawChapter chapter) {
  if (chapter.isRead) {
    return 'Read';
  }
  if (chapter.lastPage > 0) {
    final total = chapter.totalPages > 0
        ? chapter.totalPages
        : chapter.pageCount;
    return 'Reading ${chapter.lastPage + 1}/$total';
  }
  final pages = chapter.pageCount == 1 ? 'page' : 'pages';
  return 'Unread - ${chapter.pageCount} $pages';
}
