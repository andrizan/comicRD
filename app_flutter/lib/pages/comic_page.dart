import 'dart:convert';
import 'dart:typed_data';

import 'package:fluent_ui/fluent_ui.dart';
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
                Tooltip(
                  message: text.home,
                  child: IconButton(
                    onPressed: () => context.go('/'),
                    icon: const Icon(FluentIcons.back),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title.isEmpty ? text.comic : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FluentTheme.of(context).typography.title,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
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
                        .read(comicPreferencesProvider.notifier)
                        .setQuery(widget.comicPath, value),
                  ),
                ),
                const SizedBox(width: 12),
                ToggleButton(
                  checked: preferences.displayMode == ChapterDisplayMode.grid,
                  onChanged: (value) => ref
                      .read(comicPreferencesProvider.notifier)
                      .setDisplayMode(
                        widget.comicPath,
                        value
                            ? ChapterDisplayMode.grid
                            : ChapterDisplayMode.list,
                      ),
                  child: const Icon(FluentIcons.grid_view_medium),
                ),
                const SizedBox(width: 4),
                ToggleButton(
                  checked: preferences.displayMode == ChapterDisplayMode.list,
                  onChanged: (value) => ref
                      .read(comicPreferencesProvider.notifier)
                      .setDisplayMode(
                        widget.comicPath,
                        value
                            ? ChapterDisplayMode.list
                            : ChapterDisplayMode.grid,
                      ),
                  child: const Icon(FluentIcons.list),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ToggleButton(
                  checked: preferences.favoritesOnly,
                  onChanged: (value) => ref
                      .read(comicPreferencesProvider.notifier)
                      .setFavoritesOnly(widget.comicPath, value),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(FluentIcons.favorite_star, size: 18),
                      const SizedBox(width: 4),
                      Text(text.favorites),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ComboBox<ChapterSortBy>(
                  value: preferences.sortBy,
                  items: [
                    ComboBoxItem(
                      value: ChapterSortBy.chapterIndex,
                      child: Text(text.chapter),
                    ),
                    ComboBoxItem(
                      value: ChapterSortBy.name,
                      child: Text(text.name),
                    ),
                    ComboBoxItem(
                      value: ChapterSortBy.folderDate,
                      child: Text(text.folderDate),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      _setSort(value, preferences.sortDir);
                    }
                  },
                ),
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
            const SizedBox(height: 16),
            Expanded(
              child: chapters.when(
                data: (items) {
                  _scrollToLastOpened(items, preferences.displayMode);
                  return _ChapterList(
                    text: text,
                    chapters: items,
                    favorites: favoritePaths,
                    displayMode: preferences.displayMode,
                    controller: _scroll,
                    emptyLabel: text.emptyLibrary,
                    onOpen: _openChapter,
                    onToggleFavorite: _toggleFavorite,
                    onOpenFolder: _openChapterFolder,
                  );
                },
                error: (error, _) => Align(
                  alignment: Alignment.center,
                  child: Text(
                    error.toString(),
                    style: TextStyle(
                      color: FluentTheme.of(context).accentColor,
                    ),
                  ),
                ),
                loading: () => const Align(
                  alignment: Alignment.center,
                  child: ProgressRing(),
                ),
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

  Future<void> _openChapterFolder(bridge.RawChapter chapter) async {
    await ref.read(comicRdApiProvider).openContainingFolder(chapter.sourcePath);
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
    required this.text,
    required this.chapters,
    required this.favorites,
    required this.displayMode,
    required this.controller,
    required this.emptyLabel,
    required this.onOpen,
    required this.onToggleFavorite,
    required this.onOpenFolder,
  });

  final AppStrings text;
  final List<bridge.RawChapter> chapters;
  final Set<String> favorites;
  final ChapterDisplayMode displayMode;
  final ScrollController controller;
  final String emptyLabel;
  final Future<void> Function(bridge.RawChapter chapter) onOpen;
  final Future<void> Function(bridge.RawChapter chapter, bool favorite)
  onToggleFavorite;
  final Future<void> Function(bridge.RawChapter chapter) onOpenFolder;

  @override
  Widget build(BuildContext context) {
    if (chapters.isEmpty) {
      return Align(
        alignment: Alignment.center,
        child: Text(
          emptyLabel,
          style: FluentTheme.of(context).typography.bodyStrong,
        ),
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
            text: text,
            chapter: chapter,
            favorite: favorite,
            onOpen: () {
              onOpen(chapter);
            },
            onToggleFavorite: () {
              onToggleFavorite(chapter, favorite);
            },
            onOpenFolder: () {
              onOpenFolder(chapter);
            },
          );
        },
      );
    }
    return ListView.separated(
      controller: controller,
      itemCount: chapters.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, index) {
        final chapter = chapters[index];
        final favorite = favorites.contains(chapter.sourcePath);
        return HoverButton(
          onPressed: () => onOpen(chapter),
          builder: (context, states) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                  IconButton(
                    icon: Icon(
                      favorite
                          ? FluentIcons.favorite_star_fill
                          : FluentIcons.favorite_star,
                      color: favorite
                          ? FluentTheme.of(context).accentColor
                          : null,
                    ),
                    onPressed: () => onToggleFavorite(chapter, favorite),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(chapter.title),
                        Text(
                          _chapterStatus(chapter, text),
                          style: FluentTheme.of(context).typography.caption,
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(FluentIcons.folder_open, size: 20),
                        onPressed: () => onOpenFolder(chapter),
                      ),
                      Icon(
                        chapter.isRead
                            ? FluentIcons.check_mark
                            : FluentIcons.chevron_right,
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ChapterGridTile extends StatelessWidget {
  const _ChapterGridTile({
    required this.text,
    required this.chapter,
    required this.favorite,
    required this.onOpen,
    required this.onToggleFavorite,
    required this.onOpenFolder,
  });

  final AppStrings text;
  final bridge.RawChapter chapter;
  final bool favorite;
  final VoidCallback onOpen;
  final VoidCallback onToggleFavorite;
  final VoidCallback onOpenFolder;

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
                      chapter.isRead
                          ? FluentIcons.check_mark
                          : FluentIcons.reading_mode,
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(FluentIcons.folder_open, size: 20),
                      onPressed: onOpenFolder,
                    ),
                    IconButton(
                      icon: Icon(
                        favorite
                            ? FluentIcons.favorite_star_fill
                            : FluentIcons.favorite_star,
                        color: favorite
                            ? FluentTheme.of(context).accentColor
                            : null,
                      ),
                      onPressed: onToggleFavorite,
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  chapter.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: FluentTheme.of(context).typography.bodyStrong,
                ),
                const SizedBox(height: 6),
                Text(
                  _chapterStatus(chapter, text),
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
  }
}

String _chapterStatus(bridge.RawChapter chapter, AppStrings text) {
  if (chapter.isRead) {
    return text.read;
  }
  if (chapter.lastPage > 0) {
    final total = chapter.totalPages > 0
        ? chapter.totalPages
        : chapter.pageCount;
    return '${text.reading} ${chapter.lastPage + 1}/$total';
  }
  final unit = chapter.pageCount == 1 ? text.page : text.pages;
  return '${text.unread} - ${chapter.pageCount} $unit';
}
