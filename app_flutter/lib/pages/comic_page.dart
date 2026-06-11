import 'dart:async';
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
import '../utils/date_format.dart';

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
  Timer? _searchDebounce;
  DateTime _lastScrollSave = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastAutoScrollSignature;

  @override
  void initState() {
    super.initState();
    final key = ref.read(comicScrollKeyProvider(widget.comicPath));
    final offsets = ref.read(scrollOffsetsProvider.notifier);
    _scroll = ScrollController(initialScrollOffset: offsets.offsetFor(key));
    _scroll.addListener(_onScroll);
    _search = TextEditingController();
    final savedQuery = ref.read(
      comicPreferencesProvider.select(
        (state) => state[widget.comicPath]?.query ?? '',
      ),
    );
    if (savedQuery.isNotEmpty) {
      _search.text = savedQuery;
    }
    _focusNode = FocusNode(debugLabel: 'ComicPage');
  }

  void _onScroll() {
    if (!_scroll.hasClients) {
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastScrollSave).inMilliseconds < 200) {
      return;
    }
    _lastScrollSave = now;
    final key = ref.read(comicScrollKeyProvider(widget.comicPath));
    ref.read(scrollOffsetsProvider.notifier).save(key, _scroll.offset);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
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

    ref.listen(lastOpenedChapterProvider, (prev, next) {
      final prevChapter = prev?[widget.comicPath];
      final nextChapter = next[widget.comicPath];
      if (nextChapter != null && nextChapter != prevChapter) {
        _scrollToChapter(nextChapter);
      }
    });

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is! KeyDownEvent) return;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          context.go('/');
        } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _scrollBy(300);
        } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _scrollBy(-300);
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
                  child: SizedBox(
                    height: 38,
                    child: TextBox(
                      controller: _search,
                      prefix: const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(FluentIcons.search, size: 16),
                      ),
                      placeholder: text.search,
                      onChanged: (value) {
                        _searchDebounce?.cancel();
                        _searchDebounce = Timer(
                          const Duration(milliseconds: 300),
                          () => ref
                              .read(comicPreferencesProvider.notifier)
                              .setQuery(widget.comicPath, value),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 38,
                  child: ToggleButton(
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
                ),
                const SizedBox(width: 4),
                SizedBox(
                  height: 38,
                  child: ToggleButton(
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
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        SizedBox(
                          height: 38,
                          child: ToggleButton(
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
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          height: 38,
                          child: ComboBox<ChapterSortBy>(
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
                        ),
                        SizedBox(
                          height: 38,
                          child: ToggleButton(
                            checked: preferences.sortDir == bridge.SortDir.asc,
                            onChanged: (value) => _setSort(
                              preferences.sortBy,
                              value ? bridge.SortDir.asc : bridge.SortDir.desc,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  preferences.sortDir == bridge.SortDir.asc
                                      ? FluentIcons.sort_up
                                      : FluentIcons.sort_down,
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  preferences.sortDir == bridge.SortDir.asc
                                      ? text.ascending
                                      : text.descending,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                chapters.when(
                  data: (items) => Text(
                    '${items.length} ${text.totalChapters}',
                    style: FluentTheme.of(context).typography.caption?.copyWith(
                      color: FluentTheme.of(
                        context,
                      ).resources.textFillColorSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  error: (_, _) => const SizedBox.shrink(),
                  loading: () => const SizedBox.shrink(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: chapters.when(
                data: (items) {
                  _restoreLastOpenedChapter();
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
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
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

  void _scrollBy(double delta) {
    if (!_scroll.hasClients) return;
    final target = (_scroll.offset + delta).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
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
      await api.prefetchPages(
        bridge.PrefetchPagesPayload(
          chapterId: chapterId,
          pageIndices: Uint32List.fromList(pages.cast<int>()),
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

  void _scrollToChapter(String chapterSourcePath) {
    final chapters = ref.read(filteredComicChaptersProvider(widget.comicPath));
    final preferences = ref.read(
      comicPreferencesProvider.select(
        (state) => state[widget.comicPath] ?? const ComicPreferences(),
      ),
    );
    final items = chapters.asData?.value;
    if (items == null) return;
    final index = items.indexWhere(
      (chapter) => chapter.sourcePath == chapterSourcePath,
    );
    if (index < 0) return;
    final signature = [
      chapterSourcePath,
      preferences.displayMode.name,
      preferences.sortBy.name,
      preferences.sortDir.name,
      preferences.query,
      preferences.favoritesOnly,
      items.length,
      index,
    ].join('|');
    if (_lastAutoScrollSignature == signature) {
      return;
    }
    _lastAutoScrollSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final offset = _chapterScrollOffset(
        index: index,
        itemCount: items.length,
        displayMode: preferences.displayMode,
      );
      _scroll.animateTo(
        offset.clamp(0, _scroll.position.maxScrollExtent).toDouble(),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  double _chapterScrollOffset({
    required int index,
    required int itemCount,
    required ChapterDisplayMode displayMode,
  }) {
    final position = _scroll.position;
    final totalExtent = position.maxScrollExtent + position.viewportDimension;
    if (itemCount <= 0 || totalExtent <= 0) {
      return 0;
    }
    if (displayMode == ChapterDisplayMode.list) {
      return index * _chapterListItemExtent;
    }

    final estimatedRows =
        ((totalExtent + _chapterGridMainAxisSpacing) /
                (_chapterGridMainAxisExtent + _chapterGridMainAxisSpacing))
            .round()
            .clamp(1, itemCount);
    final columns = (itemCount / estimatedRows).ceil().clamp(1, itemCount);
    final row = index ~/ columns;
    return row * (totalExtent / estimatedRows);
  }

  void _restoreLastOpenedChapter() {
    final chapterSourcePath = ref
        .read(lastOpenedChapterProvider.notifier)
        .sourcePathFor(widget.comicPath);
    if (chapterSourcePath == null) {
      return;
    }
    _scrollToChapter(chapterSourcePath);
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
          mainAxisExtent: 160,
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
    return ListView.builder(
      controller: controller,
      itemExtent: _chapterListItemExtent,
      itemCount: chapters.length,
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
                border: Border(
                  bottom: BorderSide(
                    color: FluentTheme.of(
                      context,
                    ).resources.dividerStrokeColorDefault,
                  ),
                ),
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
                        if (chapter.dateModified > 0)
                          Text(
                            formatModifiedDate(chapter.dateModified),
                            style: FluentTheme.of(context).typography.caption
                                ?.copyWith(
                                  color: FluentTheme.of(
                                    context,
                                  ).resources.textFillColorSecondary,
                                ),
                          ),
                      ],
                    ),
                  ),
                  _ChapterStatusBadge(text: text, chapter: chapter),
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(FluentIcons.folder_open, size: 20),
                        onPressed: () => onOpenFolder(chapter),
                      ),
                      const Icon(FluentIcons.chevron_right),
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

const double _chapterListItemExtent = 66;
const double _chapterGridMainAxisExtent = 160;
const double _chapterGridMainAxisSpacing = 12;

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
                _ChapterStatusBadge(text: text, chapter: chapter),
                if (chapter.dateModified > 0)
                  Text(
                    formatModifiedDate(chapter.dateModified),
                    style: FluentTheme.of(context).typography.caption?.copyWith(
                      color: FluentTheme.of(
                        context,
                      ).resources.textFillColorSecondary,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ChapterStatusBadge extends StatelessWidget {
  const _ChapterStatusBadge({required this.text, required this.chapter});

  final AppStrings text;
  final bridge.RawChapter chapter;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    if (chapter.isRead) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: theme.accentColor.withAlpha(40),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text.read,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: theme.accentColor,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    if (chapter.lastPage > 0) {
      final total = chapter.totalPages > 0
          ? chapter.totalPages
          : chapter.pageCount;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: theme.accentColor.withAlpha(30),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '${text.reading} ${chapter.lastPage + 1}/$total',
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: theme.accentColor,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    final unit = chapter.pageCount == 1 ? text.page : text.pages;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorSecondary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${text.unread} - ${chapter.pageCount} $unit',
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: theme.resources.textFillColorSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
