import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../bridge_generated.dart' as bridge;
import '../state/api_state.dart';
import '../state/comic_state.dart';
import '../state/scroll_state.dart';
import '../state/settings_data_state.dart';
import '../state/settings_state.dart';
import '../utils/date_format.dart';
import '../utils/forui_theme.dart';
import '../utils/format_size.dart';
import '../widgets/back_to_top_button.dart';

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
  Timer? _searchDebounce;
  DateTime _lastScrollSave = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastAutoScrollSignature;
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
    final favorites = ref.watch(chapterFavoritesProvider(widget.comicPath));
    final chapters = chaptersRaw.whenData((data) => filterAndSortChapters(
      chapters: data,
      favorites: favorites.asData?.value ?? [],
      preferences: preferences,
    ));
    final stats = ref.watch(comicStatsProvider(widget.comicPath));
    final history = ref.watch(comicReadingHistoryProvider(widget.comicPath));
    final bookmarkedAsync = ref.watch(
      comicBookmarkedProvider(widget.comicPath),
    );
    final favoritePaths = favorites.asData?.value.toSet() ?? const <String>{};
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(48, 32, 48, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BackButton(text: text, onBack: () => context.go('/')),
            const SizedBox(height: 20),
            _ComicHero(
              text: text,
              comicPath: widget.comicPath,
              title: title.isEmpty ? text.comic : title,
              stats: stats,
              history: history,
              bookmarked: bookmarkedAsync.asData?.value ?? false,
              onContinueReading: _continueReading,
              onStartFromBeginning: _startFromBeginning,
              onToggleBookmark: _toggleComicBookmark,
            ),
            const SizedBox(height: 24),
            _ChapterSectionHeader(
              text: text,
              preferences: preferences,
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
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: chapters.when(
                      data: (items) {
                        _restoreLastOpenedChapter();
                        return _ChapterList(
                          text: text,
                          chapters: items,
                          favorites: favoritePaths,
                          controller: _scroll,
                          emptyLabel: text.emptyLibrary,
                          onOpen: _openChapter,
                          onToggleFavorite: _toggleFavorite,
                        );
                      },
                      error: (error, _) => Align(
                        alignment: Alignment.center,
                        child: Text(
                          error.toString(),
                          style: TextStyle(color: context.appAccent),
                        ),
                      ),
                      loading: () => const Align(
                        alignment: Alignment.center,
                        child: FCircularProgress.loader(),
                      ),
                    ),
                  ),
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
  }

  Future<void> _toggleComicBookmark(bool bookmarked) async {
    final api = ref.read(comicRdApiProvider);
    if (bookmarked) {
      await api.removeComicBookmark(widget.comicPath);
    } else {
      await api.addComicBookmark(widget.comicPath);
    }
    ref.invalidate(comicBookmarkedProvider(widget.comicPath));
  }

  Future<void> _continueReading() async {
    final chapters = ref.read(comicChaptersProvider(widget.comicPath));
    final items = chapters.asData?.value;
    if (items == null || items.isEmpty) return;
    bridge.RawChapter? target;
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
    await _openChapter(target);
  }

  Future<void> _startFromBeginning() async {
    final chapters = ref.read(comicChaptersProvider(widget.comicPath));
    final items = chapters.asData?.value;
    if (items == null || items.isEmpty) return;
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

    if (mounted) context.go('/reader/$chapterId');
  }

  void _scrollToChapter(String chapterSourcePath) {
    final chaptersRaw = ref.read(comicChaptersProvider(widget.comicPath));
    final favs = ref.read(chapterFavoritesProvider(widget.comicPath));
    final prefs = ref.read(comicPreferencesProvider.notifier).preferencesFor(widget.comicPath);
    final items = chaptersRaw.asData?.value;
    if (items == null) return;
    final filtered = filterAndSortChapters(
      chapters: items,
      favorites: favs.asData?.value ?? [],
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
      final offset = (index * _chapterListItemExtent).toDouble();
      _scroll.animateTo(
        offset.clamp(0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _restoreLastOpenedChapter() {
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

const double _chapterListItemExtent = 64;

// ---------------------------------------------------------------------------
// Back button
// ---------------------------------------------------------------------------

class _BackButton extends StatelessWidget {
  const _BackButton({required this.text, required this.onBack});

  final AppStrings text;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onBack,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AppIcons.back, size: 16, color: colors.foreground),
              const SizedBox(width: 8),
              Text(
                text.backToLibrary,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: colors.foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Comic hero — cover, title, info, metadata, actions
// ---------------------------------------------------------------------------

class _ComicHero extends StatelessWidget {
  const _ComicHero({
    required this.text,
    required this.comicPath,
    required this.title,
    required this.stats,
    required this.history,
    required this.bookmarked,
    required this.onContinueReading,
    required this.onStartFromBeginning,
    required this.onToggleBookmark,
  });

  final AppStrings text;
  final String comicPath;
  final String title;
  final ComicStats stats;
  final AsyncValue<List<bridge.ReadingHistoryEntry>> history;
  final bool bookmarked;
  final VoidCallback onContinueReading;
  final VoidCallback onStartFromBeginning;
  final void Function(bool bookmarked) onToggleBookmark;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final progressPercent = stats.chapterCount > 0
        ? ((stats.effectiveReadCount / stats.chapterCount) * 100).round()
        : 0;

    final lastEntry = history.asData?.value.fold<bridge.ReadingHistoryEntry?>(
      null,
      (latest, entry) {
        if (latest == null) return entry;
        return entry.updatedAt > latest.updatedAt ? entry : latest;
      },
    );
    final lastReadText = lastEntry != null
        ? text.lastReadTemplate
              .replaceAll('{chapter}', lastEntry.chapterTitle)
              .replaceAll(
                '{date}',
                formatModifiedDate(lastEntry.updatedAt.toInt()),
              )
        : '-';

    final continueLabel = stats.continueChapterTitle != null
        ? '${text.continueReading} ${stats.continueChapterTitle}'
        : text.continueReading;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CoverPlaceholder(),
        const SizedBox(width: 28),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: appFontFamily,
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.02,
                  color: colors.foreground,
                ),
              ),
              const SizedBox(height: 16),
              _InfoBar(
                text: text,
                totalSize: stats.totalSize,
                chapterCount: stats.chapterCount,
              ),
              const SizedBox(height: 20),
              _MetadataRow(label: '${text.directoryPath}:', value: comicPath),
              const SizedBox(height: 10),
              _MetadataRow(label: '${text.lastRead}:', value: lastReadText),
              const SizedBox(height: 10),
              _MetadataRow(
                label: '${text.readingProgress}:',
                value: text.readingProgressTemplate
                    .replaceAll('{percent}', '$progressPercent')
                    .replaceAll('{read}', '${stats.effectiveReadCount}')
                    .replaceAll('{total}', '${stats.chapterCount}'),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _PrimaryActionButton(
                    label: continueLabel,
                    onPressed: onContinueReading,
                  ),
                  _OutlineActionButton(
                    label: text.startFromBeginning,
                    onPressed: onStartFromBeginning,
                  ),
                  _OutlineActionButton(
                    label: bookmarked ? text.bookmarked : text.bookmark,
                    icon: AppIcons.bookmark,
                    onPressed: () => onToggleBookmark(bookmarked),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Container(
      width: 220,
      height: 300,
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(AppIcons.image, size: 48, color: colors.mutedForeground),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: colors.primary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.primaryForeground,
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlineActionButton extends StatelessWidget {
  const _OutlineActionButton({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: colors.card,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: colors.mutedForeground),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBar extends StatelessWidget {
  const _InfoBar({
    required this.text,
    required this.totalSize,
    required this.chapterCount,
  });

  final AppStrings text;
  final int totalSize;
  final int chapterCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 20,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _InfoItem(icon: AppIcons.folderOpen, value: formatBytes(totalSize)),
          _InfoItem(
            icon: AppIcons.download,
            value: '$chapterCount ${text.totalChapters}',
          ),
        ],
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  const _InfoItem({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: colors.mutedForeground),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colors.foreground,
          ),
        ),
      ],
    );
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: TextStyle(fontSize: 14, color: colors.foreground),
        children: [
          TextSpan(
            text: label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const TextSpan(text: ' '),
          TextSpan(
            text: value,
            style: TextStyle(color: colors.mutedForeground),
          ),
        ],
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
    required this.searchController,
    required this.onSearchChanged,
    required this.onSetSort,
    required this.onSetTab,
  });

  final AppStrings text;
  final ComicPreferences preferences;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final void Function(ChapterSortBy sortBy, bridge.SortDir sortDir) onSetSort;
  final ValueChanged<ChapterTab> onSetTab;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final filterControls = <Widget>[
      _SortSelect<ChapterSortBy>(
        value: preferences.sortBy,
        items: {
          text.chapter: ChapterSortBy.chapterIndex,
          text.name: ChapterSortBy.name,
          text.folderDate: ChapterSortBy.folderDate,
        },
        onChanged: (sortBy) => onSetSort(sortBy, preferences.sortDir),
      ),
      const SizedBox(width: 8),
      _SortDirToggle(
        sortDir: preferences.sortDir,
        onChanged: (sortDir) => onSetSort(preferences.sortBy, sortDir),
      ),
      const SizedBox(width: 8),
      Container(width: 1, height: 24, color: colors.border),
      const SizedBox(width: 8),
      _ChapterSearchBox(
        controller: searchController,
        hint: text.filterChapters,
        onChanged: onSearchChanged,
      ),
    ];

    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 700;
            if (isCompact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ChapterTabs(
                    text: text,
                    selectedTab: preferences.selectedTab,
                    onSetTab: onSetTab,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: filterControls,
                  ),
                ],
              );
            }
            return Row(
              children: [
                _ChapterTabs(
                  text: text,
                  selectedTab: preferences.selectedTab,
                  onSetTab: onSetTab,
                ),
                const Spacer(),
                ...filterControls,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ChapterTabs extends StatelessWidget {
  const _ChapterTabs({
    required this.text,
    required this.selectedTab,
    required this.onSetTab,
  });

  final AppStrings text;
  final ChapterTab selectedTab;
  final ValueChanged<ChapterTab> onSetTab;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ChapterTab(
          label: text.allChapters,
          selected: selectedTab == ChapterTab.all,
          onTap: () => onSetTab(ChapterTab.all),
        ),
        const SizedBox(width: 20),
        _ChapterTab(
          label: text.favoriteChapters,
          selected: selectedTab == ChapterTab.favorites,
          onTap: () => onSetTab(ChapterTab.favorites),
        ),
      ],
    );
  }
}

class _ChapterTab extends StatefulWidget {
  const _ChapterTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ChapterTab> createState() => _ChapterTabState();
}

class _ChapterTabState extends State<_ChapterTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: widget.selected
                    ? colors.foreground
                    : colors.mutedForeground,
              ),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 3,
              width: 24,
              decoration: BoxDecoration(
                color: widget.selected || _hovered
                    ? colors.primary
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapterSearchBox extends StatelessWidget {
  const _ChapterSearchBox({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: 220,
        height: 38,
        decoration: BoxDecoration(
          color: colors.background,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          style: TextStyle(fontSize: 13, color: colors.foreground),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(fontSize: 13, color: colors.mutedForeground),
            prefixIcon: Icon(
              AppIcons.search,
              size: 18,
              color: colors.mutedForeground,
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
        ),
      ),
    );
  }
}

class _SortSelect<T> extends StatelessWidget {
  const _SortSelect({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final Map<String, T> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          icon: Icon(
            AppIcons.chevronDown,
            size: 14,
            color: colors.mutedForeground,
          ),
          dropdownColor: colors.card,
          style: TextStyle(fontSize: 13, color: colors.foreground),
          borderRadius: BorderRadius.circular(10),
          items: items.entries
              .map(
                (entry) => DropdownMenuItem<T>(
                  value: entry.value,
                  child: Text(
                    entry.key,
                    style: TextStyle(fontSize: 13, color: colors.foreground),
                  ),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    );
  }
}

class _SortDirToggle extends StatelessWidget {
  const _SortDirToggle({required this.sortDir, required this.onChanged});

  final bridge.SortDir sortDir;
  final ValueChanged<bridge.SortDir> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final isAsc = sortDir == bridge.SortDir.asc;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () =>
            onChanged(isAsc ? bridge.SortDir.desc : bridge.SortDir.asc),
        child: Container(
          height: 38,
          width: 38,
          decoration: BoxDecoration(
            color: colors.background,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isAsc ? AppIcons.sortUp : AppIcons.sortDown,
            size: 16,
            color: colors.foreground,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chapter list
// ---------------------------------------------------------------------------

class _ChapterList extends StatelessWidget {
  const _ChapterList({
    required this.text,
    required this.chapters,
    required this.favorites,
    required this.controller,
    required this.emptyLabel,
    required this.onOpen,
    required this.onToggleFavorite,
  });

  final AppStrings text;
  final List<bridge.RawChapter> chapters;
  final Set<String> favorites;
  final ScrollController controller;
  final String emptyLabel;
  final Future<void> Function(bridge.RawChapter chapter) onOpen;
  final Future<void> Function(bridge.RawChapter chapter, bool favorite)
  onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    if (chapters.isEmpty) {
      return Align(
        alignment: Alignment.center,
        child: Text(emptyLabel, style: context.appBodyStrongStyle),
      );
    }
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.only(bottom: 32),
      itemExtent: _chapterListItemExtent,
      itemCount: chapters.length,
      itemBuilder: (context, index) {
        final chapter = chapters[index];
        final favorite = favorites.contains(chapter.sourcePath);
        return _ChapterListRow(
          chapter: chapter,
          favorite: favorite,
          text: text,
          onOpen: () => onOpen(chapter),
          onToggleFavorite: () => onToggleFavorite(chapter, favorite),
        );
      },
    );
  }
}

class _ChapterListRow extends StatefulWidget {
  const _ChapterListRow({
    required this.chapter,
    required this.favorite,
    required this.text,
    required this.onOpen,
    required this.onToggleFavorite,
  });

  final bridge.RawChapter chapter;
  final bool favorite;
  final AppStrings text;
  final VoidCallback onOpen;
  final VoidCallback onToggleFavorite;

  @override
  State<_ChapterListRow> createState() => _ChapterListRowState();
}

class _ChapterListRowState extends State<_ChapterListRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onOpen,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: _chapterListItemExtent,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _hovered ? colors.card : Colors.transparent,
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _statusColor(context),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.chapter.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.foreground,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.text.downloaded}: ${formatModifiedDate(widget.chapter.dateModified.toInt())}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.chapter.isRead)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Icon(
                      AppIcons.check,
                      size: 18,
                      color: context.appAccent,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onToggleFavorite,
                      child: Icon(
                        AppIcons.star,
                        size: 16,
                        color: widget.favorite
                            ? context.appReader.star
                            : colors.mutedForeground.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),
                Text(
                  formatBytes(widget.chapter.sizeBytes.toInt()),
                  style: TextStyle(fontSize: 13, color: colors.mutedForeground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _statusColor(BuildContext context) {
    if (widget.chapter.isRead) {
      return context.theme.colors.mutedForeground.withValues(alpha: 0.4);
    }
    if (widget.chapter.lastPage > 0) {
      return context.appAccent.withValues(alpha: 0.6);
    }
    return context.appAccent;
  }
}
