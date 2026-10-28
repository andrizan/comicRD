import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../bridge_generated.dart' as bridge;
import '../state/api_state.dart';
import '../state/comic_state.dart';
import '../state/library_state.dart';
import '../state/scroll_state.dart';
import '../state/settings_data_state.dart';
import '../state/settings_state.dart';
import '../utils/date_format.dart';
import '../utils/forui_theme.dart';
import '../utils/format_size.dart';
import '../widgets/back_to_top_button.dart';
import '../widgets/soft_ui.dart';

class ComicPage extends ConsumerStatefulWidget {
  const ComicPage({super.key, required this.comicPath});

  final String comicPath;

  @override
  ConsumerState<ComicPage> createState() => _ComicPageState();
}

class _ComicPageState extends ConsumerState<ComicPage> {
  static const double _backToTopThreshold = 320;
  late final ScrollController _scroll;
  late final TextEditingController _search;
  late final FocusNode _focusNode;
  final _headerKey = GlobalKey();
  Timer? _searchDebounce;
  DateTime _lastScrollSave = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastAutoScrollSignature;
  bool _suppressLastOpenedRestore = false;
  bool _showBackToTop = false;

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
    if (savedQuery.isNotEmpty) _search.text = savedQuery;
    _focusNode = FocusNode(debugLabel: 'ComicPage');
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    _updateBackToTopVisibility();
    final now = DateTime.now();
    if (now.difference(_lastScrollSave).inMilliseconds < 200) return;
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
      next.whenData((values) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref
              .read(comicPreferencesProvider.notifier)
              .hydrateFromSettings(widget.comicPath, values);
        });
      });
    });

    final text = stringsFor(ref.watch(appSettingsProvider).localeCode);
    final preferences = ref.watch(
      comicPreferencesProvider.select(
        (state) => state[widget.comicPath] ?? const ComicPreferences(),
      ),
    );
    final chaptersRaw = ref.watch(comicChaptersProvider(widget.comicPath));
    final chapterBookmarks = ref.watch(
      chapterBookmarksProvider(widget.comicPath),
    );
    final chapters = chaptersRaw.whenData(
      (data) => filterAndSortChapters(
        chapters: data,
        chapterBookmarks: chapterBookmarks.asData?.value ?? [],
        preferences: preferences,
      ),
    );
    final stats = ref.watch(comicStatsProvider(widget.comicPath));
    final history = ref.watch(comicReadingHistoryProvider(widget.comicPath));
    final favoritedAsync = ref.watch(comicFavoritedProvider(widget.comicPath));
    final bookmarkedChapterPaths =
        chapterBookmarks.asData?.value.toSet() ?? const <String>{};
    final lastOpened = ref.watch(lastOpenedChapterProvider)[widget.comicPath];
    final currentChapterPath = _currentChapterPath(
      chaptersRaw.asData?.value,
      lastOpened,
    );
    final title = widget.comicPath.split(RegExp(r'[/\\]')).last;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateBackToTopVisibility();
    });

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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 640;
          // Two columns as soon as the 300 px cover and a 480 px info column
          // fit (the design's flex bases); below that the cover sits beside
          // the title so the chapter list still starts above the fold.
          final wide = constraints.maxWidth >= 820;
          final padLeft = narrow ? 16.0 : 24.0;
          final padRight = narrow ? 16.0 : 40.0;
          final actions = _CoverActions(
            text: text,
            continueChapterTitle: stats.continueChapterTitle,
            favorited: favoritedAsync.asData?.value ?? false,
            stacked: !wide,
            onContinueReading: _continueReading,
            onStartFromBeginning: _startFromBeginning,
            onToggleFavorite: _toggleFavorite,
            onOpenFolder: _openContainingFolder,
            onCopyTitle: () => _copy(title),
            onCopyPath: () => _copy(widget.comicPath),
            onRefresh: _refreshChapters,
          );
          final header = _ComicHeader(
            text: text,
            title: title.isEmpty ? text.comic : title,
            comicPath: widget.comicPath,
            stats: stats,
            compact: !wide,
            onCopyPath: () => _copy(widget.comicPath),
          );
          final scrollView = CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  key: _headerKey,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (wide)
                      header
                    else ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: narrow ? 104 : 140,
                            child: _CoverArt(comicPath: widget.comicPath),
                          ),
                          const SizedBox(width: 20),
                          Expanded(child: header),
                        ],
                      ),
                      const SizedBox(height: 20),
                      actions,
                    ],
                    const SizedBox(height: 28),
                    _ProgressCard(text: text, stats: stats, history: history),
                    const SizedBox(height: 28),
                    _ChapterSectionHeader(
                      text: text,
                      preferences: preferences,
                      chapterCount: chaptersRaw.asData?.value.length ?? 0,
                      bookmarkCount: bookmarkedChapterPaths.length,
                      searchController: _search,
                      onSearchChanged: (value) {
                        _searchDebounce?.cancel();
                        _searchDebounce = Timer(
                          const Duration(milliseconds: 300),
                          () => ref
                              .read(comicPreferencesProvider.notifier)
                              .setQuery(widget.comicPath, value),
                        );
                      },
                      onSetSort: _setSort,
                      onSetTab: (tab) => ref
                          .read(comicPreferencesProvider.notifier)
                          .setSelectedTab(widget.comicPath, tab),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              chapters.when(
                data: (items) {
                  _restoreLastOpenedChapter();
                  return _ChapterSliver(
                    text: text,
                    chapters: items,
                    bookmarkedChapterPaths: bookmarkedChapterPaths,
                    currentChapterPath: currentChapterPath,
                    emptyLabel: text.emptyLibrary,
                    onOpen: _openChapter,
                    onToggleBookmark: _toggleBookmark,
                  );
                },
                error: (error, _) => SliverFillRemaining(
                  hasScrollBody: false,
                  child: SoftEmptyState(
                    message: error.toString(),
                    isError: true,
                  ),
                ),
                loading: () => const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: FCircularProgress.loader()),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 56)),
            ],
          );
          final body = wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 300,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 56),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _CoverArt(comicPath: widget.comicPath),
                            const SizedBox(height: 20),
                            actions,
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 40),
                    Expanded(child: scrollView),
                  ],
                )
              : scrollView;
          return Padding(
            padding: EdgeInsets.fromLTRB(padLeft, 20, padRight, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SoftButton(
                  label: text.backToLibrary,
                  icon: AppIcons.chevronLeft,
                  pill: true,
                  onPressed: () => context.go('/'),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(child: body),
                      if (_showBackToTop)
                        Positioned(
                          right: 20,
                          bottom: 20,
                          child: BackToTopButton(
                            key: const ValueKey('chapter-back-to-top-button'),
                            visible: true,
                            tooltip: text.backToTop,
                            onPressed: _scrollToTop,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The chapter the reader would resume: the latest in-progress one, or
  /// the chapter last opened from this page.
  String? _currentChapterPath(
    List<bridge.RawChapter>? items,
    String? lastOpened,
  ) {
    if (items == null) return lastOpened;
    bridge.RawChapter? best;
    for (final chapter in items) {
      if (chapter.isRead || chapter.lastPage <= 0) continue;
      if (best == null || chapter.progressUpdatedAt > best.progressUpdatedAt) {
        best = chapter;
      }
    }
    return best?.sourcePath ?? lastOpened;
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
  }

  Future<void> _refreshChapters() async {
    final api = ref.read(comicRdApiProvider);
    await api.purgeCaches();
    ref.invalidate(comicChaptersProvider(widget.comicPath));
    final _ = await ref.refresh(comicChaptersProvider(widget.comicPath).future);
  }

  Future<void> _setSort(ChapterSortBy sortBy, bridge.SortDir sortDir) async {
    _suppressLastOpenedRestore = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _suppressLastOpenedRestore = false;
    });
    ref
        .read(comicPreferencesProvider.notifier)
        .setSort(widget.comicPath, sortBy, sortDir);
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(0);
        }
      });
    }
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

  Future<void> _toggleBookmark(
    bridge.RawChapter chapter,
    bool isBookmarked,
  ) async {
    final api = ref.read(comicRdApiProvider);
    if (isBookmarked) {
      await api.removeBookmark(chapterSourcePath: chapter.sourcePath);
    } else {
      await api.addBookmark(
        chapterSourcePath: chapter.sourcePath,
        comicSourcePath: widget.comicPath,
      );
    }
    ref.invalidate(chapterBookmarksProvider(widget.comicPath));
  }

  Future<void> _toggleFavorite(bool favorited) async {
    final api = ref.read(comicRdApiProvider);
    if (favorited) {
      await api.removeFavorite(comicSourcePath: widget.comicPath);
    } else {
      await api.addFavorite(comicSourcePath: widget.comicPath);
    }
    ref.invalidate(comicFavoritedProvider(widget.comicPath));
    ref.invalidate(allFavoritesProvider);
  }

  Future<void> _openContainingFolder() async {
    await ref.read(comicRdApiProvider).openContainingFolder(widget.comicPath);
  }

  Future<void> _continueReading() async {
    final items = await ref.read(
      comicChaptersProvider(widget.comicPath).future,
    );
    if (items.isEmpty) return;

    final lastOpened = ref.read(lastOpenedChapterProvider)[widget.comicPath];
    if (lastOpened != null) {
      final match = items.firstWhere(
        (chapter) => chapter.sourcePath == lastOpened,
        orElse: () => items.first,
      );
      await _openChapter(match);
      return;
    }

    bridge.RawChapter? target;
    final chaptersWithProgress = items.where((c) => c.progressUpdatedAt > 0);
    if (chaptersWithProgress.isNotEmpty) {
      target = chaptersWithProgress.reduce(
        (a, b) => a.progressUpdatedAt > b.progressUpdatedAt ? a : b,
      );
    } else {
      for (final chapter in items) {
        if (chapter.lastPage > 0 && !chapter.isRead) {
          target = chapter;
          break;
        }
      }
      target ??= items.firstWhere(
        (chapter) => !chapter.isRead,
        orElse: () => items.first,
      );
    }
    await _openChapter(target);
  }

  Future<void> _startFromBeginning() async {
    final items = await ref.read(
      comicChaptersProvider(widget.comicPath).future,
    );
    if (items.isEmpty) return;
    await _openChapter(items.first);
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

  void _scrollToTop() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _updateBackToTopVisibility() {
    if (!mounted || !_scroll.hasClients) return;
    final showBackToTop = _scroll.offset > _backToTopThreshold;
    if (showBackToTop != _showBackToTop) {
      setState(() => _showBackToTop = showBackToTop);
    }
  }

  Future<void> _openChapter(bridge.RawChapter chapter) async {
    final api = ref.read(comicRdApiProvider);
    final chapterId = await api.openChapterForReading(
      bridge.OpenChapterPayload(
        comicSourcePath: widget.comicPath,
        chapterSourcePath: chapter.sourcePath,
      ),
    );
    final start = chapter.lastPage > 0 ? chapter.lastPage : 0;
    final maxPage = chapter.totalPages > 0
        ? chapter.totalPages
        : chapter.pageCount;
    // Warm tile 0 of the first pages: covers the visible start without an
    // extra tile-layout roundtrip; the reader window prefetches the rest.
    final tiles = [
      for (var index = start; index < maxPage && index < start + 4; index++)
        bridge.PageTile(pageIndex: index, tileIndex: 0),
    ];
    if (tiles.isNotEmpty) {
      await api.prefetchTiles(
        bridge.PrefetchTilesPayload(chapterId: chapterId, tiles: tiles),
      );
    }

    if (mounted) context.go('/reader/$chapterId');
  }

  /// Scroll offset of the first chapter row: everything above the list
  /// scrolls with it, so measure the header instead of assuming a height.
  double _listTopOffset() {
    final box = _headerKey.currentContext?.findRenderObject();
    final headerHeight = box is RenderBox && box.hasSize
        ? box.size.height
        : 0.0;
    return headerHeight + _chapterListInset;
  }

  void _scrollToChapter(String chapterSourcePath) {
    final chaptersRaw = ref.read(comicChaptersProvider(widget.comicPath));
    final chapterBookmarks = ref.read(
      chapterBookmarksProvider(widget.comicPath),
    );
    final prefs = ref
        .read(comicPreferencesProvider.notifier)
        .preferencesFor(widget.comicPath);
    final items = chaptersRaw.asData?.value;
    if (items == null) return;
    final filtered = filterAndSortChapters(
      chapters: items,
      chapterBookmarks: chapterBookmarks.asData?.value ?? [],
      preferences: prefs,
    );
    final index = filtered.indexWhere(
      (chapter) => chapter.sourcePath == chapterSourcePath,
    );
    if (index < 0) return;
    final signature = '$chapterSourcePath|${filtered.length}|$index';
    if (_lastAutoScrollSignature == signature) return;
    _lastAutoScrollSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final offset = _listTopOffset() + index * _chapterListItemExtent;
      _scroll.animateTo(
        offset.clamp(0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _restoreLastOpenedChapter() {
    if (_suppressLastOpenedRestore) {
      return;
    }
    final chapterSourcePath = ref
        .read(lastOpenedChapterProvider.notifier)
        .sourcePathFor(widget.comicPath);
    if (chapterSourcePath == null) return;
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

/// Row height (68) plus the 4 px gap below it.
const double _chapterListItemExtent = 72;

/// Padding inside the chapter list card.
const double _chapterListInset = 8;

bool _isModifiedToday(int secondsSinceEpoch) {
  if (secondsSinceEpoch <= 0) return false;
  final modified = DateTime.fromMillisecondsSinceEpoch(
    secondsSinceEpoch * 1000,
  );
  final now = DateTime.now();
  return modified.year == now.year &&
      modified.month == now.month &&
      modified.day == now.day;
}

// ---------------------------------------------------------------------------
// Cover art and the primary actions
// ---------------------------------------------------------------------------

class _CoverArt extends StatelessWidget {
  const _CoverArt({required this.comicPath});

  final String comicPath;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 2 / 3,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppShape.radiusLarge),
          boxShadow: AppShape.cardShadow(context.appReader),
        ),
        child: CoverThumbnail(
          sourcePath: comicPath,
          radius: AppShape.radiusLarge,
          maxWidth: 260,
          maxHeight: 400,
          fallbackIconSize: 48,
        ),
      ),
    );
  }
}

/// Continue / start / favorite / folder / more. Stacked under the cover in
/// the two-column layout, a wrapping row in the narrow one.
class _CoverActions extends StatelessWidget {
  const _CoverActions({
    required this.text,
    required this.continueChapterTitle,
    required this.favorited,
    required this.stacked,
    required this.onContinueReading,
    required this.onStartFromBeginning,
    required this.onToggleFavorite,
    required this.onOpenFolder,
    required this.onCopyTitle,
    required this.onCopyPath,
    required this.onRefresh,
  });

  final AppStrings text;
  final String? continueChapterTitle;
  final bool favorited;
  final bool stacked;
  final VoidCallback onContinueReading;
  final VoidCallback onStartFromBeginning;
  final void Function(bool favorited) onToggleFavorite;
  final VoidCallback onOpenFolder;
  final VoidCallback onCopyTitle;
  final VoidCallback onCopyPath;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final reader = context.appReader;
    final continueLabel = continueChapterTitle != null
        ? '${text.continueReading} $continueChapterTitle'
        : text.continueReading;
    final continueButton = SoftButton(
      label: continueLabel,
      icon: AppIcons.play,
      variant: SoftButtonVariant.primary,
      height: 52,
      expand: !stacked,
      onPressed: onContinueReading,
    );
    final startButton = SoftButton(
      label: text.startFromBeginning,
      variant: SoftButtonVariant.soft,
      height: stacked ? 52 : 48,
      expand: !stacked,
      onPressed: onStartFromBeginning,
    );
    final favoriteButton = SoftButton(
      label: favorited ? text.removeFavorite : text.addFavorite,
      icon: AppIcons.star,
      iconColor: favorited ? reader.star : null,
      toggled: favorited,
      expand: !stacked,
      onPressed: () => onToggleFavorite(favorited),
    );
    final folderButton = SoftButton(
      label: text.openFolder,
      icon: AppIcons.folderOpen,
      expand: !stacked,
      onPressed: onOpenFolder,
    );
    final moreButton = FPopoverMenu(
      menuAnchor: .topEnd,
      childAnchor: .bottomEnd,
      menu: [
        FItemGroup(
          children: [
            FItem(
              prefix: const Icon(AppIcons.copyTitle, size: 16),
              title: Text(text.copyTitle),
              onPress: onCopyTitle,
            ),
            FItem(
              prefix: const Icon(AppIcons.copyPath, size: 16),
              title: Text(text.copyPath),
              onPress: onCopyPath,
            ),
            FItem(
              prefix: const Icon(AppIcons.refresh, size: 16),
              title: Text(text.refresh),
              onPress: onRefresh,
            ),
          ],
        ),
      ],
      builder: (context, controller, _) => SoftIconButton(
        icon: AppIcons.more,
        tooltip: text.moreActions,
        onPressed: controller.toggle,
      ),
    );
    if (stacked) {
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          continueButton,
          startButton,
          favoriteButton,
          folderButton,
          moreButton,
        ],
      );
    }
    // The 300 px column cannot fit two labelled buttons side by side, so
    // the folder action collapses to an icon there (its label is the
    // tooltip); the favorite keeps its label since it reports state.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        continueButton,
        const SizedBox(height: 10),
        startButton,
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: favoriteButton),
            const SizedBox(width: 10),
            SoftIconButton(
              icon: AppIcons.folderOpen,
              tooltip: text.openFolder,
              onPressed: onOpenFolder,
            ),
            const SizedBox(width: 10),
            moreButton,
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header — title, fact pills, path chip
// ---------------------------------------------------------------------------

class _ComicHeader extends StatelessWidget {
  const _ComicHeader({
    required this.text,
    required this.title,
    required this.comicPath,
    required this.stats,
    required this.compact,
    required this.onCopyPath,
  });

  final AppStrings text;
  final String title;
  final String comicPath;
  final ComicStats stats;
  final bool compact;
  final VoidCallback onCopyPath;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SelectableText(
          title,
          minLines: 1,
          maxLines: 2,
          style: TextStyle(
            fontSize: compact ? 28 : 38,
            height: compact ? 36 / 28 : 46 / 38,
            fontWeight: FontWeight.w800,
            letterSpacing: compact ? -0.84 : -1.14,
            color: colors.foreground,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SoftPill(
              label: text.chaptersCountTemplate.replaceAll(
                '{count}',
                '${stats.chapterCount}',
              ),
            ),
            if (stats.totalSize > 0)
              SoftPill(label: formatBytes(stats.totalSize)),
          ],
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            height: AppShape.controlHeight,
            padding: const EdgeInsets.only(left: 16),
            decoration: BoxDecoration(
              color: colors.muted,
              borderRadius: BorderRadius.circular(AppShape.radiusControl),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    comicPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontFamilyFallback: const [
                        'Menlo',
                        'Consolas',
                        'DejaVu Sans Mono',
                        'Courier New',
                      ],
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: colors.mutedForeground,
                    ),
                  ),
                ),
                SoftIconButton(
                  icon: AppIcons.copyPath,
                  tooltip: text.copyPath,
                  iconSize: 16,
                  outline: false,
                  onPressed: onCopyPath,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Progress card
// ---------------------------------------------------------------------------

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.text,
    required this.stats,
    required this.history,
  });

  final AppStrings text;
  final ComicStats stats;
  final AsyncValue<List<bridge.ReadingHistoryEntry>> history;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final progress = stats.chapterCount > 0
        ? (stats.effectiveReadCount / stats.chapterCount).clamp(0.0, 1.0)
        : 0.0;
    final percent = (progress * 100).round();
    final lastEntry = history.asData?.value.fold<bridge.ReadingHistoryEntry?>(
      null,
      (latest, entry) {
        if (latest == null) return entry;
        return entry.updatedAt > latest.updatedAt ? entry : latest;
      },
    );
    final lastReadText = lastEntry != null
        ? '${lastEntry.chapterTitle} · ${formatModifiedDate(lastEntry.updatedAt.toInt())}'
        : '–';
    final labelStyle = TextStyle(
      fontSize: 13,
      height: 20 / 13,
      fontWeight: FontWeight.w600,
      color: colors.mutedForeground,
    );

    final percentBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text.readingProgress, style: labelStyle),
        Text(
          '$percent%',
          style: TextStyle(
            fontSize: 36,
            height: 44 / 36,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.08,
            color: colors.secondaryForeground,
          ),
        ),
      ],
    );
    final barBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SoftProgressBar(
          value: progress,
          height: 10,
          semanticLabel: text.readingProgress,
        ),
        const SizedBox(height: 10),
        Text(
          text.chaptersDoneTemplate
              .replaceAll('{read}', '${stats.effectiveReadCount}')
              .replaceAll('{total}', '${stats.chapterCount}'),
          style: TextStyle(
            fontSize: 13,
            height: 20 / 13,
            fontWeight: FontWeight.w500,
            color: colors.mutedForeground,
          ),
        ),
      ],
    );
    final lastReadBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text.lastRead, style: labelStyle),
        Text(
          lastReadText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            height: 24 / 15,
            fontWeight: FontWeight.w700,
            color: colors.foreground,
          ),
        ),
      ],
    );

    return SoftCard(
      padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                percentBlock,
                const SizedBox(height: 16),
                barBlock,
                const SizedBox(height: 16),
                lastReadBlock,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 110),
                child: percentBlock,
              ),
              const SizedBox(width: 24),
              Expanded(child: barBlock),
              const SizedBox(width: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: lastReadBlock,
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chapter section header — tabs, search, sort
// ---------------------------------------------------------------------------

class _ChapterSectionHeader extends StatelessWidget {
  const _ChapterSectionHeader({
    required this.text,
    required this.preferences,
    required this.chapterCount,
    required this.bookmarkCount,
    required this.searchController,
    required this.onSearchChanged,
    required this.onSetSort,
    required this.onSetTab,
  });

  final AppStrings text;
  final ComicPreferences preferences;
  final int chapterCount;
  final int bookmarkCount;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final void Function(ChapterSortBy sortBy, bridge.SortDir sortDir) onSetSort;
  final ValueChanged<ChapterTab> onSetTab;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final controls = Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SoftSegmented<ChapterTab>(
          value: preferences.selectedTab,
          onChanged: onSetTab,
          segments: [
            SoftSegment(
              value: ChapterTab.all,
              label: text.all,
              count: chapterCount,
            ),
            SoftSegment(
              value: ChapterTab.bookmarks,
              label: text.bookmarkChapters,
              count: bookmarkCount,
            ),
          ],
        ),
        SoftSearchField(
          controller: searchController,
          hint: text.filterChapters,
          width: 220,
          onChanged: onSearchChanged,
        ),
        SoftSortMenu<ChapterSortBy>(
          prefix: text.sortLabel,
          showPrefix: false,
          value: preferences.sortBy,
          onChanged: (value) => onSetSort(value, preferences.sortDir),
          options: [
            SoftSortOption(
              value: ChapterSortBy.chapterIndex,
              label: text.chapter,
            ),
            SoftSortOption(value: ChapterSortBy.name, label: text.name),
            SoftSortOption(
              value: ChapterSortBy.folderDate,
              label: text.folderDate,
            ),
          ],
          descending: preferences.sortDir == bridge.SortDir.desc,
          onDescendingChanged: (descending) => onSetSort(
            preferences.sortBy,
            descending ? bridge.SortDir.desc : bridge.SortDir.asc,
          ),
          ascendingLabel: text.sortAscending,
          descendingLabel: text.sortDescending,
        ),
      ],
    );
    final heading = Text(
      text.chapter,
      style: TextStyle(
        fontSize: 22,
        height: 30 / 22,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.44,
        color: colors.foreground,
      ),
    );
    // The design's `flex-wrap` + `space-between`: the controls sit on the
    // heading's row, right-aligned, and drop below it only when they no
    // longer fit.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [heading, controls],
    );
  }
}

// ---------------------------------------------------------------------------
// Chapter list
// ---------------------------------------------------------------------------

/// The chapter rows inside one white card; rows stay virtualized because a
/// comic can hold hundreds of chapters.
class _ChapterSliver extends StatelessWidget {
  const _ChapterSliver({
    required this.text,
    required this.chapters,
    required this.bookmarkedChapterPaths,
    required this.currentChapterPath,
    required this.emptyLabel,
    required this.onOpen,
    required this.onToggleBookmark,
  });

  final AppStrings text;
  final List<bridge.RawChapter> chapters;
  final Set<String> bookmarkedChapterPaths;
  final String? currentChapterPath;
  final String emptyLabel;
  final Future<void> Function(bridge.RawChapter chapter) onOpen;
  final Future<void> Function(bridge.RawChapter chapter, bool isBookmarked)
  onToggleBookmark;

  @override
  Widget build(BuildContext context) {
    if (chapters.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: SoftEmptyState(message: emptyLabel, icon: AppIcons.library),
      );
    }
    final colors = context.theme.colors;
    final reader = context.appReader;
    return DecoratedSliver(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(AppShape.radiusLarge),
        boxShadow: AppShape.cardShadow(reader),
      ),
      sliver: SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          _chapterListInset,
          _chapterListInset,
          _chapterListInset,
          _chapterListInset - 4,
        ),
        sliver: SliverFixedExtentList(
          itemExtent: _chapterListItemExtent,
          delegate: SliverChildBuilderDelegate((context, index) {
            final chapter = chapters[index];
            final isBookmarked = bookmarkedChapterPaths.contains(
              chapter.sourcePath,
            );
            return _ChapterRow(
              text: text,
              chapter: chapter,
              isBookmarked: isBookmarked,
              isCurrent: chapter.sourcePath == currentChapterPath,
              onOpen: () => onOpen(chapter),
              onToggleBookmark: () => onToggleBookmark(chapter, isBookmarked),
            );
          }, childCount: chapters.length),
        ),
      ),
    );
  }
}

class _ChapterRow extends StatefulWidget {
  const _ChapterRow({
    required this.text,
    required this.chapter,
    required this.isBookmarked,
    required this.isCurrent,
    required this.onOpen,
    required this.onToggleBookmark,
  });

  final AppStrings text;
  final bridge.RawChapter chapter;
  final bool isBookmarked;

  /// The row the reader would resume; it gets the soft fill and a button.
  final bool isCurrent;
  final VoidCallback onOpen;
  final VoidCallback onToggleBookmark;

  @override
  State<_ChapterRow> createState() => _ChapterRowState();
}

class _ChapterRowState extends State<_ChapterRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final reader = context.appReader;
    final text = widget.text;
    final chapter = widget.chapter;
    final current = widget.isCurrent;
    final inProgress = chapter.lastPage > 0 && !chapter.isRead;
    final total = chapter.totalPages > 0
        ? chapter.totalPages.toInt()
        : chapter.pageCount.toInt();
    final page = total <= 0
        ? 0
        : (chapter.lastPage.toInt() + 1).clamp(1, total);
    final number = chapter.chapterIndex > 0 ? '${chapter.chapterIndex}' : '·';
    final metaParts = <String>[
      if (chapter.pageCount > 0)
        text.pagesCountTemplate.replaceAll('{count}', '${chapter.pageCount}'),
      if (chapter.dateModified > 0)
        formatModifiedDate(chapter.dateModified.toInt()),
      if (chapter.sizeBytes > 0) formatBytes(chapter.sizeBytes.toInt()),
    ];

    final Widget status;
    if (inProgress) {
      status = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text.pageOfTemplate
                    .replaceAll('{page}', '$page')
                    .replaceAll('{total}', '$total'),
                style: TextStyle(
                  fontSize: 13,
                  height: 18 / 13,
                  fontWeight: FontWeight.w700,
                  color: colors.secondaryForeground,
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 96,
                child: SoftProgressBar(
                  value: total <= 0 ? 0 : page / total,
                  trackColor: current ? colors.card : null,
                ),
              ),
            ],
          ),
          if (current) ...[
            const SizedBox(width: 14),
            SoftButton(
              label: text.continueReading,
              variant: SoftButtonVariant.primary,
              onPressed: widget.onOpen,
            ),
          ],
        ],
      );
    } else if (chapter.isRead) {
      status = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.check, size: 16, color: reader.success),
          const SizedBox(width: 6),
          Text(
            text.finished,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: reader.success,
            ),
          ),
        ],
      );
    } else if (_isModifiedToday(chapter.dateModified.toInt())) {
      status = SoftBadge(label: text.newBadge, tone: SoftBadgeTone.amber);
    } else {
      status = Text(
        text.unread,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: colors.mutedForeground,
        ),
      );
    }

    final fill = current
        ? colors.secondary
        : (_hovered || _focused)
        ? colors.muted
        : Colors.transparent;

    return Semantics(
      button: true,
      label: chapter.title,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onOpen();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onOpen,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              height: _chapterListItemExtent - 4,
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(AppShape.radiusMedium),
                border: Border.all(
                  color: _focused ? colors.primary : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: current ? colors.card : colors.muted,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      number,
                      style: TextStyle(
                        fontSize: number.length > 3 ? 12 : 15,
                        fontWeight: FontWeight.w800,
                        color: current
                            ? colors.secondaryForeground
                            : colors.mutedForeground,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          chapter.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            height: 22 / 15,
                            fontWeight: FontWeight.w700,
                            color: colors.foreground,
                          ),
                        ),
                        if (metaParts.isNotEmpty)
                          Text(
                            metaParts.join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 18 / 12.5,
                              fontWeight: FontWeight.w500,
                              color: colors.mutedForeground,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  status,
                  const SizedBox(width: 16),
                  SoftIconButton(
                    icon: AppIcons.bookmark,
                    tooltip: widget.isBookmarked
                        ? text.removeBookmark
                        : text.addBookmark,
                    iconSize: 18,
                    round: true,
                    outline: false,
                    selected: widget.isBookmarked,
                    color: widget.isBookmarked
                        ? reader.star
                        : colors.mutedForeground,
                    onPressed: widget.onToggleBookmark,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
