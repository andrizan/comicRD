import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../bridge_generated.dart' as bridge;
import '../routes/path_codec.dart';
import '../state/api_state.dart';
import '../state/library_state.dart';
import '../state/scroll_state.dart';
import '../state/settings_state.dart';
import '../utils/date_format.dart';
import '../utils/forui_theme.dart';
import '../utils/format_size.dart';
import '../widgets/back_to_top_button.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  static const double _backToTopThreshold = 320;
  late final ScrollController _historyScroll;
  late final ScrollController _libraryScroll;
  late final ScrollController _bookmarksScroll;
  final _search = TextEditingController();
  final _focusNode = FocusNode(debugLabel: 'LibraryPage');
  Timer? _searchDebounce;
  DateTime _lastScrollSave = DateTime.fromMillisecondsSinceEpoch(0);
  bool _refreshedOnMount = false;
  bool _showBackToTop = false;
  LibraryComicsState _comicsState = const LibraryComicsState(
    items: [],
    filteredTotal: 0,
    visibleCount: 0,
    hasMore: false,
  );
  List<bridge.RawComic> _rawComics = const [];
  int _totalSizeBytes = 0;

  @override
  void initState() {
    super.initState();
    _historyScroll = _restoredScrollController('library:history');
    _libraryScroll = _restoredScrollController('library:library');
    _bookmarksScroll = _restoredScrollController('library:bookmarks');
    final savedQuery = ref.read(
      libraryPreferencesProvider.select((p) => p.query),
    );
    if (savedQuery.isNotEmpty) {
      _search.text = savedQuery;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_refreshedOnMount) {
      _refreshedOnMount = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.listenManual<LibraryComicsState>(libraryComicsProvider, (
          prev,
          next,
        ) {
          if (mounted) {
            setState(() {
              _comicsState = next;
            });
          }
        }, fireImmediately: true);
        ref.listenManual<AsyncValue<List<bridge.RawComic>>>(
          rawLibraryComicsProvider,
          (prev, next) {
            final comics = next.asData?.value;
            if (comics == null || !mounted) return;
            final total = comics.fold<int>(
              0,
              (sum, comic) => sum + comic.sizeBytes.toInt(),
            );
            final needsComicsUpdate = !identical(comics, _rawComics);
            final needsTotalUpdate = total != _totalSizeBytes;
            if (needsComicsUpdate || needsTotalUpdate) {
              setState(() {
                if (needsComicsUpdate) _rawComics = comics;
                if (needsTotalUpdate) _totalSizeBytes = total;
              });
            }
          },
          fireImmediately: true,
        );
        unawaited(ref.refresh(rawLibraryComicsProvider.future));
        unawaited(ref.refresh(comicsWithProgressProvider.future));
        unawaited(ref.refresh(readingHistoryProvider.future));
      });
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _saveScrollOffset('library:history', _historyScroll);
    _saveScrollOffset('library:library', _libraryScroll);
    _saveScrollOffset('library:bookmarks', _bookmarksScroll);
    _historyScroll.dispose();
    _libraryScroll.dispose();
    _bookmarksScroll.dispose();
    _search.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  ScrollController _restoredScrollController(String key) {
    final offsets = ref.read(scrollOffsetsProvider.notifier);
    final savedOffset = offsets.offsetFor(key);
    final controller = ScrollController(
      initialScrollOffset: savedOffset > 0 ? savedOffset : 0,
    );
    controller.addListener(() {
      _saveScrollOffset(key, controller);
      if (identical(controller, _activeScrollController())) {
        _updateBackToTopVisibility(controller);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (controller.hasClients) {
        final maxExtent = controller.position.maxScrollExtent;
        if (controller.offset > maxExtent && maxExtent >= 0) {
          controller.jumpTo(maxExtent);
        }
      }
    });
    return controller;
  }

  void _saveScrollOffset(String key, ScrollController controller) {
    if (!controller.hasClients) {
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastScrollSave).inMilliseconds < 200) {
      return;
    }
    _lastScrollSave = now;
    ref.read(scrollOffsetsProvider.notifier).save(key, controller.offset);
  }

  ScrollController _activeScrollController() {
    final tab = ref.read(libraryPreferencesProvider).selectedTab;
    return switch (tab) {
      LibraryTab.history => _historyScroll,
      LibraryTab.library => _libraryScroll,
      LibraryTab.bookmarks => _bookmarksScroll,
    };
  }

  void _updateBackToTopVisibility(ScrollController controller) {
    if (!mounted || !controller.hasClients) {
      return;
    }
    final next = controller.offset > _backToTopThreshold;
    if (next != _showBackToTop) {
      setState(() => _showBackToTop = next);
    }
  }

  void _scrollActiveToTop() {
    final controller = _activeScrollController();
    if (!controller.hasClients) {
      return;
    }
    controller.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _handleKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowDown) {
      _scrollBy(300);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _scrollBy(-300);
    }
  }

  void _scrollBy(double delta) {
    final controller = _activeScrollController();
    if (!controller.hasClients) return;
    final target = (controller.offset + delta).clamp(
      0.0,
      controller.position.maxScrollExtent,
    );
    controller.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = stringsFor(ref.watch(appSettingsProvider).localeCode);
    final preferences = ref.watch(libraryPreferencesProvider);
    final sourceStatus = ref.watch(librarySourceStatusProvider);
    final history = ref.watch(readingHistoryProvider);
    final comicsState = _comicsState;
    final bookmarks = ref.watch(allBookmarksProvider);
    final bookmarkedPaths =
        bookmarks.asData?.value
            .map((bookmark) => bookmark.comicSourcePath)
            .toSet() ??
        const <String>{};
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateBackToTopVisibility(_activeScrollController());
        ref
            .read(libraryCountProvider.notifier)
            .update(comicsState.items.length);
      }
    });

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          _handleKey(event.logicalKey);
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final hPad = constraints.maxWidth < 600
              ? 16.0
              : constraints.maxWidth < 900
              ? 32.0
              : 48.0;
          return Padding(
            padding: EdgeInsets.fromLTRB(hPad, 32, hPad, 0),
            child: Column(
              children: [
                _PanelHeader(
                  text: text,
                  preferences: preferences,
                  comicsState: comicsState,
                  totalSizeBytes: _totalSizeBytes,
                  historyCount: history.asData?.value.length ?? 0,
                  bookmarksCount: bookmarks.asData?.value.length ?? 0,
                  searchController: _search,
                  onSearchChanged: (value) {
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(
                      const Duration(milliseconds: 300),
                      () => ref
                          .read(libraryPreferencesProvider.notifier)
                          .setQuery(value),
                    );
                  },
                  onRefresh: _refreshLibrary,
                  onSetViewMode: _setViewMode,
                  onSetSort: _setSort,
                  onSetDisplayMode: _setDisplayMode,
                ),
                const SizedBox(height: 8),
                sourceStatus.when(
                  data: (status) {
                    if (status.configured && status.error == null) {
                      return const SizedBox.shrink();
                    }
                    final message = status.configured
                        ? status.error!
                        : text.noLibrarySource;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          message,
                          style: TextStyle(color: context.appAccent),
                        ),
                      ),
                    );
                  },
                  error: (error, _) => Padding(
                    padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        error.toString(),
                        style: TextStyle(color: context.appAccent),
                      ),
                    ),
                  ),
                  loading: () => const SizedBox.shrink(),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: switch (preferences.selectedTab) {
                          LibraryTab.history => _HistoryList(
                            text: text,
                            history: history,
                            controller: _historyScroll,
                            emptyLabel: text.emptyLibrary,
                          ),
                          LibraryTab.library => _ComicList(
                            text: text,
                            comics: comicsState.items,
                            visibleCount: comicsState.visibleCount,
                            hasMore: comicsState.hasMore,
                            onLoadMore: () => ref
                                .read(libraryPaginationProvider.notifier)
                                .loadMore(),
                            displayMode: preferences.displayMode,
                            bookmarkedPaths: bookmarkedPaths,
                            controller: _libraryScroll,
                            emptyLabel: text.emptyLibrary,
                            onToggleBookmark: _toggleComicBookmark,
                            onCopyTitle: _copyComicTitle,
                            onCopyPath: _copyComicPath,
                            onOpenFolder: _openContainingFolder,
                          ),
                          LibraryTab.bookmarks => _BookmarkList(
                            text: text,
                            bookmarks: bookmarks,
                            comics: _rawComics,
                            displayMode: preferences.displayMode,
                            controller: _bookmarksScroll,
                            emptyLabel: text.emptyLibrary,
                            onToggleBookmark: _toggleBookmarkBookmark,
                            onCopyTitle: _copyBookmarkTitle,
                            onCopyPath: _copyBookmarkPath,
                            onOpenFolder: _openBookmarkContainingFolder,
                          ),
                        },
                      ),
                      if (_showBackToTop)
                        Positioned(
                          right: 24,
                          bottom: 24,
                          child: BackToTopButton(
                            key: const ValueKey('library-back-to-top-button'),
                            visible: true,
                            tooltip: text.backToTop,
                            onPressed: _scrollActiveToTop,
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

  Future<void> _setSort(bridge.SortBy sortBy, bridge.SortDir sortDir) async {
    ref.read(libraryPreferencesProvider.notifier).setSort(sortBy, sortDir);
    final api = ref.read(comicRdApiProvider);
    await api.setSetting('library_sort_by', jsonEncode(encodeSortBy(sortBy)));
    await api.setSetting(
      'library_sort_dir',
      jsonEncode(encodeSortDir(sortDir)),
    );
    if (_libraryScroll.hasClients) {
      _libraryScroll.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
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

  Future<void> _refreshLibrary() async {
    ref.invalidate(libraryPaginationProvider);
    await Future.wait<void>([
      ref.refresh(librarySourceStatusProvider.future),
      ref.refresh(rawLibraryComicsProvider.future),
    ]);
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

  Future<void> _toggleBookmarkBookmark(
    bridge.ComicBookmark bookmark,
    bool bookmarked,
  ) async {
    await ref
        .read(comicRdApiProvider)
        .removeComicBookmark(bookmark.comicSourcePath);
    ref.invalidate(allBookmarksProvider);
  }

  Future<void> _copyBookmarkTitle(bridge.ComicBookmark bookmark) async {
    await Clipboard.setData(ClipboardData(text: bookmark.comicTitle));
  }

  Future<void> _copyBookmarkPath(bridge.ComicBookmark bookmark) async {
    await Clipboard.setData(ClipboardData(text: bookmark.comicSourcePath));
  }

  Future<void> _openBookmarkContainingFolder(
    bridge.ComicBookmark bookmark,
  ) async {
    await ref
        .read(comicRdApiProvider)
        .openContainingFolder(bookmark.comicSourcePath);
  }
}

class _PanelHeader extends ConsumerWidget {
  const _PanelHeader({
    required this.text,
    required this.preferences,
    required this.comicsState,
    required this.totalSizeBytes,
    required this.historyCount,
    required this.bookmarksCount,
    required this.searchController,
    required this.onSearchChanged,
    required this.onRefresh,
    required this.onSetViewMode,
    required this.onSetSort,
    required this.onSetDisplayMode,
  });

  final AppStrings text;
  final LibraryPreferences preferences;
  final LibraryComicsState comicsState;
  final int totalSizeBytes;
  final int historyCount;
  final int bookmarksCount;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onRefresh;
  final ValueChanged<LibraryViewMode> onSetViewMode;
  final void Function(bridge.SortBy sortBy, bridge.SortDir sortDir) onSetSort;
  final ValueChanged<LibraryDisplayMode> onSetDisplayMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    final title = switch (preferences.selectedTab) {
      LibraryTab.library => text.library,
      LibraryTab.history => text.history,
      LibraryTab.bookmarks => text.bookmarks,
    };
    final subtitle = switch (preferences.selectedTab) {
      LibraryTab.library => _LibrarySubtitle(
        text: text,
        count: comicsState.filteredTotal,
        totalSizeBytes: totalSizeBytes,
      ),
      LibraryTab.history => Text(text.latestReading),
      LibraryTab.bookmarks => Text(
        text.bookmarksSubtitleTemplate.replaceAll('{count}', '$bookmarksCount'),
      ),
    };

    final toolbar = _Toolbar(
      text: text,
      preferences: preferences,
      searchController: searchController,
      onSearchChanged: onSearchChanged,
      onRefresh: onRefresh,
      onSetViewMode: onSetViewMode,
      onSetSort: onSetSort,
      onSetDisplayMode: onSetDisplayMode,
    );
    final titleColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: appFontFamily,
            fontSize: 24,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.01,
            color: colors.foreground,
          ),
        ),
        const SizedBox(height: 4),
        DefaultTextStyle(
          style: TextStyle(fontSize: 14, color: colors.mutedForeground),
          child: subtitle,
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 800) {
          return Wrap(
            spacing: 24,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: [titleColumn, toolbar],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleColumn),
            const SizedBox(width: 24),
            toolbar,
          ],
        );
      },
    );
  }
}

class _LibrarySubtitle extends StatelessWidget {
  const _LibrarySubtitle({
    required this.text,
    required this.count,
    required this.totalSizeBytes,
  });

  final AppStrings text;
  final int count;
  final int totalSizeBytes;

  @override
  Widget build(BuildContext context) {
    final base = text.librarySubtitleTemplate.replaceAll('{count}', '$count');
    if (totalSizeBytes <= 0) {
      return Text(base);
    }
    return Text('$base · ${text.totalSize}: ${formatBytes(totalSizeBytes)}');
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.text,
    required this.preferences,
    required this.searchController,
    required this.onSearchChanged,
    required this.onRefresh,
    required this.onSetViewMode,
    required this.onSetSort,
    required this.onSetDisplayMode,
  });

  final AppStrings text;
  final LibraryPreferences preferences;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onRefresh;
  final ValueChanged<LibraryViewMode> onSetViewMode;
  final void Function(bridge.SortBy sortBy, bridge.SortDir sortDir) onSetSort;
  final ValueChanged<LibraryDisplayMode> onSetDisplayMode;

  @override
  Widget build(BuildContext context) {
    final isLibrary = preferences.selectedTab == LibraryTab.library;
    final isBookmarks = preferences.selectedTab == LibraryTab.bookmarks;
    final isHistory = preferences.selectedTab == LibraryTab.history;

    return Material(
      type: MaterialType.transparency,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _SearchBox(
            controller: searchController,
            hint: '${text.search}...',
            onChanged: onSearchChanged,
          ),
          if (isLibrary)
            _FilterSelect<LibraryViewMode>(
              value: preferences.viewMode,
              items: {
                text.all: LibraryViewMode.all,
                text.unread: LibraryViewMode.unread,
                text.progress: LibraryViewMode.reading,
              },
              onChanged: onSetViewMode,
            ),
          if (!isHistory)
            _ViewToggles(
              text: text,
              displayMode: preferences.displayMode,
              onChanged: onSetDisplayMode,
            ),
          FTooltip(
            tipBuilder: (context, _) => Text(text.refresh),
            child: FButton.icon(
              variant: .outline,
              onPress: onRefresh,
              child: const Icon(AppIcons.refresh),
            ),
          ),
          if (isLibrary || isBookmarks) ...[
            Container(
              width: 1,
              height: 24,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: context.theme.colors.border,
            ),
            _FilterSelect<bridge.SortBy>(
              value: preferences.sortBy,
              items: {
                text.name: bridge.SortBy.name,
                text.folderDate: bridge.SortBy.folderDate,
              },
              onChanged: (sortBy) => onSetSort(sortBy, preferences.sortDir),
            ),
            _SortDirToggle(
              text: text,
              sortDir: preferences.sortDir,
              onChanged: (sortDir) => onSetSort(preferences.sortBy, sortDir),
            ),
          ],
        ],
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({
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
    return Container(
      width: 240,
      height: 38,
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
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
    );
  }
}

class _FilterSelect<T> extends StatelessWidget {
  const _FilterSelect({
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
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
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
          borderRadius: BorderRadius.circular(8),
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

class _ViewToggles extends StatelessWidget {
  const _ViewToggles({
    required this.text,
    required this.displayMode,
    required this.onChanged,
  });

  final AppStrings text;
  final LibraryDisplayMode displayMode;
  final ValueChanged<LibraryDisplayMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Container(
      height: 38,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _ViewToggleButton(
            icon: AppIcons.gridView,
            selected: displayMode == LibraryDisplayMode.grid,
            tooltip: text.grid,
            onTap: () => onChanged(LibraryDisplayMode.grid),
          ),
          _ViewToggleButton(
            icon: AppIcons.list,
            selected: displayMode == LibraryDisplayMode.list,
            tooltip: text.list,
            onTap: () => onChanged(LibraryDisplayMode.list),
          ),
        ],
      ),
    );
  }
}

class _SortDirToggle extends StatelessWidget {
  const _SortDirToggle({
    required this.text,
    required this.sortDir,
    required this.onChanged,
  });

  final AppStrings text;
  final bridge.SortDir sortDir;
  final ValueChanged<bridge.SortDir> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final isAsc = sortDir == bridge.SortDir.asc;
    return Tooltip(
      message: text.sortDirection,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () =>
              onChanged(isAsc ? bridge.SortDir.desc : bridge.SortDir.asc),
          child: Container(
            height: 38,
            width: 38,
            decoration: BoxDecoration(
              color: colors.card,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isAsc ? AppIcons.sortUp : AppIcons.sortDown,
              size: 16,
              color: colors.foreground,
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewToggleButton extends StatelessWidget {
  const _ViewToggleButton({
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 34,
            height: 30,
            decoration: BoxDecoration(
              color: selected ? colors.secondary : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              icon,
              size: 18,
              color: selected ? colors.primary : colors.mutedForeground,
            ),
          ),
        ),
      ),
    );
  }
}

class _ComicList extends StatelessWidget {
  const _ComicList({
    required this.text,
    required this.comics,
    required this.visibleCount,
    required this.hasMore,
    required this.onLoadMore,
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
  final List<bridge.RawComic> comics;
  final int visibleCount;
  final bool hasMore;
  final VoidCallback onLoadMore;
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
    if (visibleCount == 0) {
      return _EmptyState(label: emptyLabel);
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (hasMore &&
            notification.metrics.pixels >=
                notification.metrics.maxScrollExtent - 200) {
          onLoadMore();
        }
        return false;
      },
      child: displayMode == LibraryDisplayMode.grid
          ? GridView.builder(
              controller: controller,
              padding: const EdgeInsets.symmetric(vertical: 16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisExtent: 290,
                crossAxisSpacing: 20,
                mainAxisSpacing: 20,
              ),
              itemCount: visibleCount,
              itemBuilder: (context, index) {
                final comic = comics[index];
                final bookmarked = bookmarkedPaths.contains(comic.sourcePath);
                return _ComicCard(
                  text: text,
                  comic: comic,
                  bookmarked: bookmarked,
                  displayMode: LibraryDisplayMode.grid,
                  onOpen: () =>
                      context.go('/comic/${encodeRoutePath(comic.sourcePath)}'),
                  onToggleBookmark: () => onToggleBookmark(comic, bookmarked),
                  onCopyTitle: () => onCopyTitle(comic),
                  onCopyPath: () => onCopyPath(comic),
                  onOpenFolder: () => onOpenFolder(comic),
                );
              },
            )
          : ListView.separated(
              controller: controller,
              padding: const EdgeInsets.symmetric(vertical: 16),
              itemCount: visibleCount,
              separatorBuilder: (_, _) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final comic = comics[index];
                final bookmarked = bookmarkedPaths.contains(comic.sourcePath);
                return _ComicCard(
                  text: text,
                  comic: comic,
                  bookmarked: bookmarked,
                  displayMode: LibraryDisplayMode.list,
                  onOpen: () =>
                      context.go('/comic/${encodeRoutePath(comic.sourcePath)}'),
                  onToggleBookmark: () => onToggleBookmark(comic, bookmarked),
                  onCopyTitle: () => onCopyTitle(comic),
                  onCopyPath: () => onCopyPath(comic),
                  onOpenFolder: () => onOpenFolder(comic),
                );
              },
            ),
    );
  }
}

class _HoverCard extends StatefulWidget {
  const _HoverCard({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: colors.card,
            border: Border.all(
              color: _hovered ? colors.primary : colors.border,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: colors.foreground.withValues(
                  alpha: _hovered ? 0.1 : 0.04,
                ),
                blurRadius: _hovered ? 20 : 12,
                offset: Offset(0, _hovered ? 8 : 4),
              ),
            ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _ComicCard extends StatelessWidget {
  const _ComicCard({
    required this.text,
    required this.comic,
    required this.bookmarked,
    required this.displayMode,
    required this.onOpen,
    required this.onToggleBookmark,
    required this.onCopyTitle,
    required this.onCopyPath,
    required this.onOpenFolder,
  });

  final AppStrings text;
  final bridge.RawComic comic;
  final bool bookmarked;
  final LibraryDisplayMode displayMode;
  final VoidCallback onOpen;
  final VoidCallback onToggleBookmark;
  final VoidCallback onCopyTitle;
  final VoidCallback onCopyPath;
  final VoidCallback onOpenFolder;

  bool get _isNew {
    if (comic.dateModified <= 0) return false;
    final modified = DateTime.fromMillisecondsSinceEpoch(
      comic.dateModified.toInt() * 1000,
    );
    final now = DateTime.now();
    return modified.year == now.year &&
        modified.month == now.month &&
        modified.day == now.day;
  }

  double get _progress {
    if (comic.chapterCount <= 0) return 0;
    final completed = comic.readChapterCount + comic.inProgressChapterCount;
    return (completed / comic.chapterCount).clamp(0.0, 1.0);
  }

  String get _chapterLabel {
    if (comic.chapterCount <= 0) return text.unread;
    return '${text.chapterCountLabel} ${comic.chapterCount}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final isGrid = displayMode == LibraryDisplayMode.grid;

    Widget cardContent = isGrid
        ? _buildGridContent(context, colors)
        : _buildListContent(context, colors);

    return _HoverCard(onTap: onOpen, child: cardContent);
  }

  Widget _buildGridContent(BuildContext context, FColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _CoverArea(
            text: text,
            sourcePath: comic.sourcePath,
            isGrid: true,
            isNew: _isNew,
            bookmarked: bookmarked,
            onToggleBookmark: onToggleBookmark,
            contextMenu: _CardContextMenu(
              text: text,
              onCopyTitle: onCopyTitle,
              onCopyPath: onCopyPath,
              onOpenFolder: onOpenFolder,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                comic.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.foreground,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _chapterLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: _isNew ? colors.primary : colors.mutedForeground,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    comic.dateModified > 0
                        ? formatModifiedDate(comic.dateModified.toInt())
                        : '',
                    style: TextStyle(
                      fontSize: 10,
                      color: colors.mutedForeground,
                    ),
                  ),
                  Text(
                    formatBytes(comic.sizeBytes.toInt()),
                    style: TextStyle(
                      fontSize: 10,
                      color: colors.mutedForeground,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _ProgressBar(progress: _progress),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildListContent(BuildContext context, FColors colors) {
    return SizedBox(
      height: 136,
      child: Row(
        children: [
          _CoverArea(
            text: text,
            sourcePath: comic.sourcePath,
            isGrid: false,
            isNew: _isNew,
            bookmarked: bookmarked,
            onToggleBookmark: onToggleBookmark,
            showBookmark: false,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    comic.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colors.foreground,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        _chapterLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: _isNew
                              ? colors.primary
                              : colors.mutedForeground,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        comic.dateModified > 0
                            ? formatModifiedDate(comic.dateModified.toInt())
                            : '',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.mutedForeground,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        formatBytes(comic.sizeBytes.toInt()),
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ProgressBar(progress: _progress),
                ],
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _BookmarkButton(
                    bookmarked: bookmarked,
                    onToggle: onToggleBookmark,
                    isGrid: false,
                    tooltip: bookmarked
                        ? text.removeBookmark
                        : text.addBookmark,
                  ),
                  const SizedBox(width: 4),
                  _CardContextMenu(
                    text: text,
                    onCopyTitle: onCopyTitle,
                    onCopyPath: onCopyPath,
                    onOpenFolder: onOpenFolder,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverArea extends ConsumerWidget {
  const _CoverArea({
    required this.text,
    required this.sourcePath,
    required this.isGrid,
    required this.isNew,
    required this.bookmarked,
    required this.onToggleBookmark,
    this.showBookmark = true,
    this.contextMenu,
  });

  final AppStrings text;
  final String sourcePath;
  final bool isGrid;
  final bool isNew;
  final bool bookmarked;
  final VoidCallback onToggleBookmark;
  final bool showBookmark;
  final Widget? contextMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    final thumbnail = ref.watch(
      comicThumbnailProvider((
        sourcePath: sourcePath,
        maxWidth: 200,
        maxHeight: 300,
      )),
    );
    final borderRadius = isGrid
        ? const BorderRadius.vertical(top: Radius.circular(14))
        : const BorderRadius.horizontal(left: Radius.circular(14));
    final cover = Container(
      width: isGrid ? double.infinity : 110,
      height: isGrid ? double.infinity : 136,
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: borderRadius,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          thumbnail.when(
            data: (bytes) {
              if (bytes == null) {
                return Icon(
                  AppIcons.library,
                  size: 28,
                  color: colors.mutedForeground,
                );
              }
              return Positioned.fill(
                child: ClipRRect(
                  borderRadius: borderRadius,
                  child: Image.memory(bytes, fit: BoxFit.cover),
                ),
              );
            },
            loading: () =>
                Icon(AppIcons.library, size: 28, color: colors.mutedForeground),
            error: (_, _) =>
                Icon(AppIcons.library, size: 28, color: colors.mutedForeground),
          ),
          if (isNew)
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: context.appReader.progress,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  text.newBadge.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: colors.primaryForeground,
                  ),
                ),
              ),
            ),
          if (showBookmark)
            Positioned(
              top: isGrid ? 8 : null,
              right: isGrid ? 8 : 12,
              bottom: isGrid ? null : 12,
              child: _BookmarkButton(
                bookmarked: bookmarked,
                onToggle: onToggleBookmark,
                isGrid: isGrid,
                tooltip: bookmarked ? text.removeBookmark : text.addBookmark,
              ),
            ),
          if (contextMenu != null && isGrid)
            Positioned(right: 8, bottom: 8, child: contextMenu!),
        ],
      ),
    );
    return cover;
  }
}

class _BookmarkButton extends StatelessWidget {
  const _BookmarkButton({
    required this.bookmarked,
    required this.onToggle,
    required this.isGrid,
    required this.tooltip,
  });

  final bool bookmarked;
  final VoidCallback onToggle;
  final bool isGrid;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onToggle,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isGrid
                  ? Colors.black.withValues(alpha: 0.35)
                  : colors.secondary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              AppIcons.bookmark,
              size: 14,
              color: bookmarked
                  ? context.appReader.star
                  : (isGrid
                        ? Colors.white.withValues(alpha: 0.9)
                        : colors.mutedForeground),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 5,
      decoration: BoxDecoration(
        color: context.appReader.progressTrack,
        borderRadius: BorderRadius.circular(5),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress,
        child: Container(
          decoration: BoxDecoration(
            color: context.appReader.progress,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({
    required this.text,
    required this.history,
    required this.controller,
    required this.emptyLabel,
  });

  final AppStrings text;
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
          padding: const EdgeInsets.symmetric(vertical: 16),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final item = items[index];
            return _HistoryItem(
              text: text,
              item: item,
              onOpen: () =>
                  context.go('/comic/${encodeRoutePath(item.comicSourcePath)}'),
            );
          },
        );
      },
      error: (error, _) => _ErrorState(message: error.toString()),
      loading: () => const Align(
        alignment: Alignment.center,
        child: FCircularProgress.loader(),
      ),
    );
  }
}

class _HistoryItem extends StatelessWidget {
  const _HistoryItem({
    required this.text,
    required this.item,
    required this.onOpen,
  });

  final AppStrings text;
  final bridge.ReadingHistoryEntry item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final cover = _HistoryCover(sourcePath: item.comicSourcePath);
    final textColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.comicTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: colors.foreground,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          item.chapterTitle,
          style: TextStyle(fontSize: 13, color: colors.mutedForeground),
        ),
      ],
    );
    final continueButton = OutlinedButton(
      onPressed: () => context.go('/reader/${item.chapterId}'),
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.primary,
        side: BorderSide(color: colors.primary),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      child: Text(text.continueReading),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.card,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: colors.foreground.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 380) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    cover,
                    const SizedBox(height: 12),
                    textColumn,
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: continueButton,
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  cover,
                  const SizedBox(width: 16),
                  Expanded(child: textColumn),
                  const SizedBox(width: 16),
                  continueButton,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HistoryCover extends ConsumerWidget {
  const _HistoryCover({required this.sourcePath});

  final String sourcePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    final thumbnail = ref.watch(
      comicThumbnailProvider((
        sourcePath: sourcePath,
        maxWidth: 100,
        maxHeight: 140,
      )),
    );

    return Container(
      width: 60,
      height: 80,
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: thumbnail.when(
        data: (bytes) {
          if (bytes == null) {
            return Icon(
              AppIcons.library,
              size: 24,
              color: colors.mutedForeground,
            );
          }
          return Image.memory(bytes, fit: BoxFit.cover);
        },
        loading: () =>
            Icon(AppIcons.library, size: 24, color: colors.mutedForeground),
        error: (_, _) =>
            Icon(AppIcons.library, size: 24, color: colors.mutedForeground),
      ),
    );
  }
}

class _BookmarkList extends StatelessWidget {
  const _BookmarkList({
    required this.text,
    required this.bookmarks,
    required this.comics,
    required this.displayMode,
    required this.controller,
    required this.emptyLabel,
    required this.onToggleBookmark,
    required this.onCopyTitle,
    required this.onCopyPath,
    required this.onOpenFolder,
  });

  final AppStrings text;
  final AsyncValue<List<bridge.ComicBookmark>> bookmarks;
  final List<bridge.RawComic> comics;
  final LibraryDisplayMode displayMode;
  final ScrollController controller;
  final String emptyLabel;
  final Future<void> Function(bridge.ComicBookmark bookmark, bool bookmarked)
  onToggleBookmark;
  final Future<void> Function(bridge.ComicBookmark bookmark) onCopyTitle;
  final Future<void> Function(bridge.ComicBookmark bookmark) onCopyPath;
  final Future<void> Function(bridge.ComicBookmark bookmark) onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final comicByPath = <String, bridge.RawComic>{};
    for (final c in comics) {
      comicByPath[c.sourcePath] = c;
    }
    return bookmarks.when(
      data: (items) {
        if (items.isEmpty) {
          return _EmptyState(label: emptyLabel);
        }
        return NotificationListener<ScrollNotification>(
          onNotification: (_) => false,
          child: displayMode == LibraryDisplayMode.grid
              ? GridView.builder(
                  controller: controller,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisExtent: 290,
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 20,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _BookmarkCard(
                      text: text,
                      bookmark: item,
                      comic: comicByPath[item.comicSourcePath],
                      displayMode: LibraryDisplayMode.grid,
                      onOpen: () => context.go(
                        '/comic/${encodeRoutePath(item.comicSourcePath)}',
                      ),
                      onToggleBookmark: () => onToggleBookmark(item, true),
                      onCopyTitle: () => onCopyTitle(item),
                      onCopyPath: () => onCopyPath(item),
                      onOpenFolder: () => onOpenFolder(item),
                    );
                  },
                )
              : ListView.separated(
                  controller: controller,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _BookmarkCard(
                      text: text,
                      bookmark: item,
                      comic: comicByPath[item.comicSourcePath],
                      displayMode: LibraryDisplayMode.list,
                      onOpen: () => context.go(
                        '/comic/${encodeRoutePath(item.comicSourcePath)}',
                      ),
                      onToggleBookmark: () => onToggleBookmark(item, true),
                      onCopyTitle: () => onCopyTitle(item),
                      onCopyPath: () => onCopyPath(item),
                      onOpenFolder: () => onOpenFolder(item),
                    );
                  },
                ),
        );
      },
      error: (error, _) => _ErrorState(message: error.toString()),
      loading: () => const Align(
        alignment: Alignment.center,
        child: FCircularProgress.loader(),
      ),
    );
  }
}

class _BookmarkCard extends StatelessWidget {
  const _BookmarkCard({
    required this.text,
    required this.bookmark,
    this.comic,
    required this.displayMode,
    required this.onOpen,
    required this.onToggleBookmark,
    required this.onCopyTitle,
    required this.onCopyPath,
    required this.onOpenFolder,
  });

  final AppStrings text;
  final bridge.ComicBookmark bookmark;
  final bridge.RawComic? comic;
  final LibraryDisplayMode displayMode;
  final VoidCallback onOpen;
  final VoidCallback onToggleBookmark;
  final VoidCallback onCopyTitle;
  final VoidCallback onCopyPath;
  final VoidCallback onOpenFolder;

  double get _progress {
    if (comic == null || comic!.chapterCount <= 0) return 0;
    final completed = comic!.readChapterCount + comic!.inProgressChapterCount;
    return (completed / comic!.chapterCount).clamp(0.0, 1.0);
  }

  String get _chapterLabel {
    if (comic == null || comic!.chapterCount <= 0) return text.unread;
    return '${text.chapterCountLabel} ${comic!.chapterCount}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final isGrid = displayMode == LibraryDisplayMode.grid;

    Widget cardContent = isGrid
        ? _buildGridContent(context, colors)
        : _buildListContent(context, colors);

    return _HoverCard(onTap: onOpen, child: cardContent);
  }

  Widget _buildGridContent(BuildContext context, FColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _CoverArea(
            text: text,
            sourcePath: bookmark.comicSourcePath,
            isGrid: true,
            isNew: false,
            bookmarked: true,
            onToggleBookmark: onToggleBookmark,
            showBookmark: true,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                bookmark.comicTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.foreground,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _chapterLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: colors.mutedForeground,
                ),
              ),
              if (comic != null) ...[
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      comic!.dateModified > 0
                          ? formatModifiedDate(comic!.dateModified.toInt())
                          : '',
                      style: TextStyle(
                        fontSize: 10,
                        color: colors.mutedForeground,
                      ),
                    ),
                    Text(
                      formatBytes(comic!.sizeBytes.toInt()),
                      style: TextStyle(
                        fontSize: 10,
                        color: colors.mutedForeground,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _ProgressBar(progress: _progress),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildListContent(BuildContext context, FColors colors) {
    return SizedBox(
      height: 136,
      child: Row(
        children: [
          _CoverArea(
            text: text,
            sourcePath: bookmark.comicSourcePath,
            isGrid: false,
            isNew: false,
            bookmarked: true,
            onToggleBookmark: onToggleBookmark,
            showBookmark: false,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    bookmark.comicTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colors.foreground,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        _chapterLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: colors.mutedForeground,
                        ),
                      ),
                      if (comic != null) ...[
                        const SizedBox(width: 12),
                        Text(
                          comic!.dateModified > 0
                              ? formatModifiedDate(comic!.dateModified.toInt())
                              : '',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.mutedForeground,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          formatBytes(comic!.sizeBytes.toInt()),
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.mutedForeground,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (comic != null) ...[
                    const SizedBox(height: 12),
                    _ProgressBar(progress: _progress),
                  ],
                ],
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: _BookmarkButton(
                bookmarked: true,
                onToggle: onToggleBookmark,
                isGrid: false,
                tooltip: text.removeBookmark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardContextMenu extends StatelessWidget {
  const _CardContextMenu({
    required this.text,
    required this.onCopyTitle,
    required this.onCopyPath,
    required this.onOpenFolder,
  });

  final AppStrings text;
  final VoidCallback onCopyTitle;
  final VoidCallback onCopyPath;
  final VoidCallback onOpenFolder;

  @override
  Widget build(BuildContext context) {
    return FPopoverMenu(
      menuAnchor: .bottomEnd,
      childAnchor: .topEnd,
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
              prefix: const Icon(AppIcons.folderOpen, size: 16),
              title: Text(text.openFolder),
              onPress: onOpenFolder,
            ),
          ],
        ),
      ],
      builder: (_, controller, _) => Tooltip(
        message: text.menu,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: controller.toggle,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
              child: const Icon(AppIcons.more, size: 14, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(label, style: context.appBodyStrongStyle));
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(message, style: TextStyle(color: context.appAccent)),
    );
  }
}
