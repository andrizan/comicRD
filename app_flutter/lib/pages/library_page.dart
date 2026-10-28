import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../bridge_generated.dart' as bridge;
import '../routes/path_codec.dart';
import '../state/api_state.dart';
import '../state/library_source_actions.dart';
import '../state/library_state.dart';
import '../state/scroll_state.dart';
import '../state/settings_state.dart';
import '../utils/date_format.dart';
import '../utils/forui_theme.dart';
import '../utils/format_size.dart';
import '../widgets/back_to_top_button.dart';
import '../widgets/soft_ui.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  static const double _backToTopThreshold = 320;
  late final ScrollController _historyScroll;
  late final ScrollController _libraryScroll;
  late final ScrollController _favoritesScroll;
  final _search = TextEditingController();
  final _focusNode = FocusNode(debugLabel: 'LibraryPage');
  Timer? _searchDebounce;
  DateTime _lastScrollSave = DateTime.fromMillisecondsSinceEpoch(0);

  /// The latest offset per tab, kept unthrottled so [dispose] can store the
  /// exact position the 200 ms save throttle may have skipped.
  final _latestOffsets = <String, double>{};
  late final ScrollOffsetsNotifier _offsetStore;
  bool _refreshedOnMount = false;
  bool _showBackToTop = false;
  LibraryComicsState _comicsState = const LibraryComicsState(
    items: [],
    filteredTotal: 0,
    visibleCount: 0,
    hasMore: false,
  );
  HistoryListState _historyState = const HistoryListState(
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
    // Kept in a field: `ref` cannot be read inside dispose().
    _offsetStore = ref.read(scrollOffsetsProvider.notifier);
    _historyScroll = _restoredScrollController('library:history');
    _libraryScroll = _restoredScrollController('library:library');
    _favoritesScroll = _restoredScrollController('library:favorites');
    final savedQuery = ref.read(
      libraryPreferencesProvider.select((p) => p.query),
    );
    if (savedQuery.isNotEmpty) {
      _search.text = savedQuery;
    }
    // Start from what the providers already hold: laid out empty, the first
    // frame would clamp a restored scroll offset to zero.
    _comicsState = ref.read(libraryComicsProvider);
    _historyState = ref.read(historyListProvider);
    _rawComics = ref.read(rawLibraryComicsProvider).asData?.value ?? const [];
    _totalSizeBytes = _sizeOf(_rawComics);
  }

  static int _sizeOf(List<bridge.RawComic> comics) =>
      comics.fold<int>(0, (sum, comic) => sum + comic.sizeBytes.toInt());

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
        ref.listenManual<HistoryListState>(historyListProvider, (prev, next) {
          if (mounted) {
            setState(() {
              _historyState = next;
            });
          }
        }, fireImmediately: true);
        ref.listenManual<AsyncValue<List<bridge.RawComic>>>(
          rawLibraryComicsProvider,
          (prev, next) {
            final comics = next.asData?.value;
            if (comics == null || !mounted) return;
            final total = _sizeOf(comics);
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
    _latestOffsets.forEach(_offsetStore.save);
    _historyScroll.dispose();
    _libraryScroll.dispose();
    _favoritesScroll.dispose();
    _search.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  ScrollController _restoredScrollController(String key) {
    final savedOffset = _offsetStore.offsetFor(key);
    final controller = ScrollController(
      initialScrollOffset: savedOffset > 0 ? savedOffset : 0,
    );
    controller.addListener(() {
      if (controller.hasClients) _latestOffsets[key] = controller.offset;
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
      LibraryTab.favorites => _favoritesScroll,
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
    final comicsState = _comicsState;
    final favorites = ref.watch(allFavoritesProvider);
    final favoritedPaths =
        favorites.asData?.value
            .map((favorite) => favorite.comicSourcePath)
            .toSet() ??
        const <String>{};

    // Sync search controller when tab changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final currentQuery = preferences.query;
      if (_search.text != currentQuery) {
        _search.text = currentQuery;
        _search.selection = TextSelection.fromPosition(
          TextPosition(offset: currentQuery.length),
        );
      }
      _updateBackToTopVisibility(_activeScrollController());
    });

    final status = sourceStatus.asData?.value;
    final firstRun = status != null && !status.configured;

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
          final narrow = constraints.maxWidth < 640;
          final padLeft = narrow ? 16.0 : 24.0;
          final padRight = narrow ? 16.0 : 40.0;
          if (firstRun) {
            return _WelcomeView(
              text: text,
              onPickFolder: _pickLibraryFolder,
              onImportBackup: () => context.go('/settings'),
            );
          }
          final String? sourceError = switch (sourceStatus) {
            AsyncData(:final value) => value.error,
            AsyncError(:final error) => error.toString(),
            _ => null,
          };
          final actions = _CardActions(
            onToggleFavorite: _toggleFavoriteByPath,
            onCopyTitle: (title) =>
                Clipboard.setData(ClipboardData(text: title)),
            onCopyPath: (path) => Clipboard.setData(ClipboardData(text: path)),
            onOpenFolder: (path) =>
                ref.read(comicRdApiProvider).openContainingFolder(path),
          );
          return Padding(
            padding: EdgeInsets.fromLTRB(padLeft, 28, padRight, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PanelHeader(
                  text: text,
                  preferences: preferences,
                  comicsState: comicsState,
                  totalSizeBytes: _totalSizeBytes,
                  favoritesCount: favorites.asData?.value.length ?? 0,
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
                  onSetDisplayMode: _setDisplayMode,
                ),
                if (sourceError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: _SourceErrorBanner(
                      text: text,
                      message: sourceError,
                      onChangeFolder: () => context.go('/settings'),
                    ),
                  ),
                const SizedBox(height: 24),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: switch (preferences.selectedTab) {
                          LibraryTab.history => _HistoryList(
                            text: text,
                            items: _historyState.items,
                            visibleCount: _historyState.visibleCount,
                            hasMore: _historyState.hasMore,
                            onLoadMore: () => ref
                                .read(historyPaginationProvider.notifier)
                                .loadMore(),
                            controller: _historyScroll,
                            emptyLabel: text.emptyLibrary,
                          ),
                          LibraryTab.library => _ComicList(
                            text: text,
                            comics: comicsState.items,
                            allComics: _rawComics,
                            visibleCount: comicsState.visibleCount,
                            hasMore: comicsState.hasMore,
                            onLoadMore: () => ref
                                .read(libraryPaginationProvider.notifier)
                                .loadMore(),
                            displayMode: preferences.displayMode,
                            viewMode: preferences.viewMode,
                            sort: preferences.sort,
                            favoritedPaths: favoritedPaths,
                            controller: _libraryScroll,
                            emptyLabel: text.emptyLibrary,
                            actions: actions,
                            onSetViewMode: _setViewMode,
                            onSetSort: _setSort,
                            onViewHistory: _showHistoryTab,
                          ),
                          LibraryTab.favorites => _FavoritesList(
                            text: text,
                            favorites: favorites,
                            comics: _rawComics,
                            query: preferences.query,
                            sort: preferences.sort,
                            displayMode: preferences.displayMode,
                            controller: _favoritesScroll,
                            emptyLabel: text.emptyLibrary,
                            actions: actions,
                            onSetSort: _setSort,
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
    final controller = _activeScrollController();
    if (controller.hasClients) {
      controller.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (controller.hasClients) {
          controller.jumpTo(0);
        }
      });
    }
    final api = ref.read(comicRdApiProvider);
    final selectedTab = ref.read(libraryPreferencesProvider).selectedTab;
    final prefix = switch (selectedTab) {
      LibraryTab.library => 'library',
      LibraryTab.favorites => 'favorites',
      LibraryTab.history => 'library',
    };
    await api.setSetting('${prefix}_sort_by', jsonEncode(encodeSortBy(sortBy)));
    await api.setSetting(
      '${prefix}_sort_dir',
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
    final api = ref.read(comicRdApiProvider);
    final selectedTab = ref.read(libraryPreferencesProvider).selectedTab;
    final prefix = switch (selectedTab) {
      LibraryTab.library => 'library',
      LibraryTab.favorites => 'favorites',
      LibraryTab.history => 'library',
    };
    await api.setSetting(
      '${prefix}_display_mode',
      jsonEncode(encodeDisplayMode(displayMode)),
    );
  }

  Future<void> _showHistoryTab() async {
    ref
        .read(libraryPreferencesProvider.notifier)
        .setSelectedTab(LibraryTab.history);
    await ref
        .read(comicRdApiProvider)
        .setSetting(
          'library_selected_tab',
          jsonEncode(encodeLibraryTab(LibraryTab.history)),
        );
  }

  Future<void> _refreshLibrary() async {
    final selectedTab = ref.read(libraryPreferencesProvider).selectedTab;
    switch (selectedTab) {
      case LibraryTab.library:
        ref.invalidate(libraryPaginationProvider);
        await Future.wait<void>([
          ref.refresh(librarySourceStatusProvider.future),
          ref.refresh(rawLibraryComicsProvider.future),
          ref.refresh(readingHistoryProvider.future),
        ]);
      case LibraryTab.favorites:
        unawaited(ref.refresh(allFavoritesProvider.future));
      case LibraryTab.history:
        ref.invalidate(historyPaginationProvider);
        unawaited(ref.refresh(readingHistoryProvider.future));
    }
  }

  Future<void> _pickLibraryFolder() async {
    final path = await getDirectoryPath();
    if (path == null || !mounted) return;
    await applyLibrarySource(ref, path);
    if (!mounted) return;
    // The listing is filesystem-first; the scan fills in chapter counts and
    // progress in the background while the shelf is already browsable.
    unawaited(ref.read(comicRdApiProvider).startScanLibraries());
  }

  Future<void> _toggleFavoriteByPath(String sourcePath, bool favorited) async {
    final api = ref.read(comicRdApiProvider);
    if (favorited) {
      await api.removeFavorite(comicSourcePath: sourcePath);
    } else {
      await api.addFavorite(comicSourcePath: sourcePath);
    }
    ref.invalidate(allFavoritesProvider);
  }
}

/// Card callbacks shared by the library grid, list and favorites.
class _CardActions {
  const _CardActions({
    required this.onToggleFavorite,
    required this.onCopyTitle,
    required this.onCopyPath,
    required this.onOpenFolder,
  });

  final Future<void> Function(String sourcePath, bool favorited)
  onToggleFavorite;
  final Future<void> Function(String title) onCopyTitle;
  final Future<void> Function(String path) onCopyPath;
  final Future<void> Function(String path) onOpenFolder;
}

/// What a comic card shows, whether it came from the listing or favorites.
class _CardInfo {
  const _CardInfo({
    required this.title,
    required this.sourcePath,
    required this.chapterCount,
    required this.readCount,
    required this.inProgressCount,
    required this.dateModified,
    required this.sizeBytes,
    required this.favorited,
  });

  factory _CardInfo.fromComic(
    bridge.RawComic comic, {
    required bool favorited,
  }) {
    return _CardInfo(
      title: comic.title,
      sourcePath: comic.sourcePath,
      chapterCount: comic.chapterCount.toInt(),
      readCount: comic.readChapterCount.toInt(),
      inProgressCount: comic.inProgressChapterCount.toInt(),
      dateModified: comic.dateModified.toInt(),
      sizeBytes: comic.sizeBytes.toInt(),
      favorited: favorited,
    );
  }

  factory _CardInfo.fromFavorite(
    bridge.Favorite favorite,
    bridge.RawComic? comic,
  ) {
    return _CardInfo(
      title: favorite.comicTitle,
      sourcePath: favorite.comicSourcePath,
      chapterCount: comic?.chapterCount.toInt() ?? 0,
      readCount: comic?.readChapterCount.toInt() ?? 0,
      inProgressCount: comic?.inProgressChapterCount.toInt() ?? 0,
      dateModified: comic?.dateModified.toInt() ?? 0,
      sizeBytes: comic?.sizeBytes.toInt() ?? 0,
      favorited: true,
    );
  }

  final String title;
  final String sourcePath;
  final int chapterCount;
  final int readCount;
  final int inProgressCount;
  final int dateModified;
  final int sizeBytes;
  final bool favorited;

  bool get isNew {
    if (dateModified <= 0) return false;
    final modified = DateTime.fromMillisecondsSinceEpoch(dateModified * 1000);
    final now = DateTime.now();
    return modified.year == now.year &&
        modified.month == now.month &&
        modified.day == now.day;
  }

  int get touchedCount =>
      (readCount + inProgressCount).clamp(0, math.max(chapterCount, 0));

  bool get hasProgress => chapterCount > 0 && touchedCount > 0;

  double get progress => chapterCount <= 0 ? 0 : touchedCount / chapterCount;

  int get percent => (progress * 100).round();

  /// "26 of 30 chapters" once started, otherwise the plain chapter count.
  String chapterSummary(AppStrings text) {
    if (chapterCount <= 0) return text.unread;
    if (!hasProgress) {
      return text.chaptersCountTemplate.replaceAll('{count}', '$chapterCount');
    }
    return text.chaptersReadTemplate
        .replaceAll('{read}', '$touchedCount')
        .replaceAll('{total}', '$chapterCount');
  }

  String progressLabel(AppStrings text) {
    return text.readingProgressTemplate
        .replaceAll('{percent}', '$percent')
        .replaceAll('{read}', '$touchedCount')
        .replaceAll('{total}', '$chapterCount');
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.text,
    required this.preferences,
    required this.comicsState,
    required this.totalSizeBytes,
    required this.favoritesCount,
    required this.searchController,
    required this.onSearchChanged,
    required this.onRefresh,
    required this.onSetDisplayMode,
  });

  final AppStrings text;
  final LibraryPreferences preferences;
  final LibraryComicsState comicsState;
  final int totalSizeBytes;
  final int favoritesCount;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onRefresh;
  final ValueChanged<LibraryDisplayMode> onSetDisplayMode;

  @override
  Widget build(BuildContext context) {
    final title = switch (preferences.selectedTab) {
      LibraryTab.library => text.library,
      LibraryTab.history => text.history,
      LibraryTab.favorites => text.favorites,
    };
    final subtitle = switch (preferences.selectedTab) {
      LibraryTab.library => _LibrarySubtitle(
        text: text,
        count: comicsState.filteredTotal,
        totalSizeBytes: totalSizeBytes,
      ),
      LibraryTab.history => Text(text.latestReading),
      LibraryTab.favorites => Text(
        text.favoritesSubtitleTemplate.replaceAll('{count}', '$favoritesCount'),
      ),
    };
    final heading = PageHeading(title: title, subtitle: subtitle);

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 840;
        final toolbar = _Toolbar(
          text: text,
          preferences: preferences,
          searchController: searchController,
          searchWidth: stacked
              ? math.max(160.0, math.min(320.0, constraints.maxWidth - 108))
              : 320,
          onSearchChanged: onSearchChanged,
          onRefresh: onRefresh,
          onSetDisplayMode: onSetDisplayMode,
        );
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, const SizedBox(height: 16), toolbar],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: heading),
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
    return Text('$base · ${formatBytes(totalSizeBytes)}');
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.text,
    required this.preferences,
    required this.searchController,
    required this.searchWidth,
    required this.onSearchChanged,
    required this.onRefresh,
    required this.onSetDisplayMode,
  });

  final AppStrings text;
  final LibraryPreferences preferences;
  final TextEditingController searchController;
  final double searchWidth;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onRefresh;
  final ValueChanged<LibraryDisplayMode> onSetDisplayMode;

  @override
  Widget build(BuildContext context) {
    final isHistory = preferences.selectedTab == LibraryTab.history;
    return Material(
      type: MaterialType.transparency,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SoftSearchField(
            controller: searchController,
            hint: '${text.search}…',
            width: searchWidth,
            onChanged: onSearchChanged,
          ),
          SoftIconButton(
            icon: AppIcons.refresh,
            tooltip: text.refresh,
            onPressed: onRefresh,
          ),
          if (!isHistory)
            SoftSegmented<LibraryDisplayMode>(
              value: preferences.displayMode,
              onChanged: onSetDisplayMode,
              segments: [
                SoftSegment(
                  value: LibraryDisplayMode.grid,
                  icon: AppIcons.gridView,
                  tooltip: text.grid,
                ),
                SoftSegment(
                  value: LibraryDisplayMode.list,
                  icon: AppIcons.list,
                  tooltip: text.list,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

typedef _LibrarySort = (bridge.SortBy, bridge.SortDir);

/// "Sort: Name" popover plus the ascending / descending toggle.
Widget _librarySortMenu({
  required AppStrings text,
  required _LibrarySort sort,
  required void Function(bridge.SortBy sortBy, bridge.SortDir sortDir)
  onChanged,
}) {
  final (sortBy, sortDir) = sort;
  return SoftSortMenu<bridge.SortBy>(
    prefix: text.sortLabel,
    value: sortBy,
    onChanged: (value) => onChanged(value, sortDir),
    options: [
      SoftSortOption(value: bridge.SortBy.name, label: text.name),
      SoftSortOption(value: bridge.SortBy.folderDate, label: text.folderDate),
    ],
    descending: sortDir == bridge.SortDir.desc,
    onDescendingChanged: (descending) => onChanged(
      sortBy,
      descending ? bridge.SortDir.desc : bridge.SortDir.asc,
    ),
    ascendingLabel: text.sortAscending,
    descendingLabel: text.sortDescending,
  );
}

/// Shown above the list when the configured folder cannot be read.
class _SourceErrorBanner extends StatelessWidget {
  const _SourceErrorBanner({
    required this.text,
    required this.message,
    required this.onChangeFolder,
  });

  final AppStrings text;
  final String message;
  final VoidCallback onChangeFolder;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final reader = context.appReader;
    return SoftCard(
      radius: AppShape.radiusMedium,
      padding: const EdgeInsets.all(14),
      child: Wrap(
        spacing: 14,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: reader.badgeNew,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              AppIcons.circleAlert,
              size: 20,
              color: reader.badgeNewForeground,
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Text(
              message,
              style: TextStyle(
                fontSize: 14,
                height: 22 / 14,
                fontWeight: FontWeight.w600,
                color: colors.foreground,
              ),
            ),
          ),
          SoftButton(
            label: text.changeFolder,
            icon: AppIcons.folderOpen,
            onPressed: onChangeFolder,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Library tab: continue-reading shelf, filter chips, grid / row cards.
// ---------------------------------------------------------------------------

class _ComicList extends ConsumerWidget {
  const _ComicList({
    required this.text,
    required this.comics,
    required this.allComics,
    required this.visibleCount,
    required this.hasMore,
    required this.onLoadMore,
    required this.displayMode,
    required this.viewMode,
    required this.sort,
    required this.favoritedPaths,
    required this.controller,
    required this.emptyLabel,
    required this.actions,
    required this.onSetViewMode,
    required this.onSetSort,
    required this.onViewHistory,
  });

  final AppStrings text;
  final List<bridge.RawComic> comics;
  final List<bridge.RawComic> allComics;
  final int visibleCount;
  final bool hasMore;
  final VoidCallback onLoadMore;
  final LibraryDisplayMode displayMode;
  final LibraryViewMode viewMode;
  final (bridge.SortBy, bridge.SortDir) sort;
  final Set<String> favoritedPaths;
  final ScrollController controller;
  final String emptyLabel;
  final _CardActions actions;
  final ValueChanged<LibraryViewMode> onSetViewMode;
  final void Function(bridge.SortBy sortBy, bridge.SortDir sortDir) onSetSort;
  final VoidCallback onViewHistory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final raw = ref.watch(rawLibraryComicsProvider);
    final history = ref.watch(readingHistoryProvider).asData?.value;
    final resumable = history == null
        ? const <bridge.ReadingHistoryEntry>[]
        : history.where((entry) => !entry.isRead).toList();
    var readingCount = 0;
    var unreadCount = 0;
    for (final comic in allComics) {
      if (comic.inProgressChapterCount > 0) readingCount++;
      if (comic.readChapterCount == 0 && comic.inProgressChapterCount == 0) {
        unreadCount++;
      }
    }

    return raw.when(
      data: (_) {
        final filterRow = Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SoftChip(
                    label: text.all,
                    count: allComics.length,
                    selected: viewMode == LibraryViewMode.all,
                    onPressed: () => onSetViewMode(LibraryViewMode.all),
                  ),
                  SoftChip(
                    label: text.reading,
                    count: readingCount,
                    selected: viewMode == LibraryViewMode.reading,
                    onPressed: () => onSetViewMode(LibraryViewMode.reading),
                  ),
                  SoftChip(
                    label: text.unread,
                    count: unreadCount,
                    selected: viewMode == LibraryViewMode.unread,
                    onPressed: () => onSetViewMode(LibraryViewMode.unread),
                  ),
                ],
              ),
              _librarySortMenu(text: text, sort: sort, onChanged: onSetSort),
            ],
          ),
        );
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (hasMore &&
                notification.metrics.pixels >=
                    notification.metrics.maxScrollExtent - 200) {
              onLoadMore();
            }
            return false;
          },
          child: CustomScrollView(
            controller: controller,
            slivers: [
              if (resumable.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 32),
                    child: _ContinueShelf(
                      text: text,
                      entries: resumable,
                      onViewHistory: onViewHistory,
                    ),
                  ),
                ),
              SliverToBoxAdapter(child: filterRow),
              if (visibleCount == 0)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: SoftEmptyState(
                    message: emptyLabel,
                    icon: AppIcons.library,
                  ),
                )
              else if (displayMode == LibraryDisplayMode.grid)
                _CoverGrid(
                  itemCount: visibleCount,
                  itemBuilder: (context, index) {
                    final comic = comics[index];
                    return _GridCard(
                      text: text,
                      info: _CardInfo.fromComic(
                        comic,
                        favorited: favoritedPaths.contains(comic.sourcePath),
                      ),
                      actions: actions,
                    );
                  },
                )
              else
                SliverList.separated(
                  itemCount: visibleCount,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final comic = comics[index];
                    return _RowCard(
                      text: text,
                      info: _CardInfo.fromComic(
                        comic,
                        favorited: favoritedPaths.contains(comic.sourcePath),
                      ),
                      actions: actions,
                    );
                  },
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 56)),
            ],
          ),
        );
      },
      error: (error, _) =>
          SoftEmptyState(message: error.toString(), isError: true),
      loading: () => const Align(
        alignment: Alignment.center,
        child: FCircularProgress.loader(),
      ),
    );
  }
}

/// A 2:3 cover grid whose row height follows the column width so the
/// covers keep their aspect ratio at any window size.
class _CoverGrid extends StatelessWidget {
  const _CoverGrid({required this.itemCount, required this.itemBuilder});

  static const double _maxTileWidth = 200;
  static const double _minTileWidth = 150;
  static const double _columnGap = 24;
  static const double _rowGap = 32;

  /// Two title lines (20 each), the gap above them and the caption line.
  static const double _captionHeight = 12 + 40 + 2 + 18;

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        var columns = ((width + _columnGap) / (_maxTileWidth + _columnGap))
            .floor();
        columns = columns.clamp(1, 12);
        var tileWidth = (width - (columns - 1) * _columnGap) / columns;
        if (tileWidth < _minTileWidth && columns > 1) {
          columns -= 1;
          tileWidth = (width - (columns - 1) * _columnGap) / columns;
        }
        final extent = tileWidth * 1.5 + _captionHeight;
        return SliverGrid(
          delegate: SliverChildBuilderDelegate(
            itemBuilder,
            childCount: itemCount,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: _columnGap,
            mainAxisSpacing: _rowGap,
            mainAxisExtent: extent,
          ),
        );
      },
    );
  }
}

class _GridCard extends StatefulWidget {
  const _GridCard({
    required this.text,
    required this.info,
    required this.actions,
  });

  final AppStrings text;
  final _CardInfo info;
  final _CardActions actions;

  @override
  State<_GridCard> createState() => _GridCardState();
}

class _GridCardState extends State<_GridCard> {
  bool _hovered = false;
  bool _focused = false;

  void _open() {
    context.go('/comic/${encodeRoutePath(widget.info.sourcePath)}');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final reader = context.appReader;
    final info = widget.info;
    final text = widget.text;
    final active = _hovered || _focused;
    final showControls = active || info.favorited;

    return Semantics(
      button: true,
      label: info.title,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _open();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _open,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 2 / 3,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  transform: Matrix4.translationValues(0, active ? -2 : 0, 0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppShape.radiusMedium),
                    border: Border.all(
                      color: active ? colors.primary : Colors.transparent,
                      width: 1.5,
                    ),
                    boxShadow: AppShape.cardShadow(reader),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      AppShape.radiusMedium - 1.5,
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CoverThumbnail(sourcePath: info.sourcePath, radius: 0),
                        if (info.isNew)
                          Positioned(
                            top: 12,
                            left: 12,
                            child: SoftBadge(
                              label: text.newBadge,
                              tone: SoftBadgeTone.amber,
                            ),
                          ),
                        if (showControls)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: _CoverStarButton(
                              text: text,
                              favorited: info.favorited,
                              onPressed: () => widget.actions.onToggleFavorite(
                                info.sourcePath,
                                info.favorited,
                              ),
                            ),
                          ),
                        if (active)
                          Positioned(
                            right: 4,
                            bottom: info.hasProgress ? 22 : 4,
                            child: _CardContextMenu(
                              text: text,
                              onCover: true,
                              onCopyTitle: () =>
                                  widget.actions.onCopyTitle(info.title),
                              onCopyPath: () =>
                                  widget.actions.onCopyPath(info.sourcePath),
                              onOpenFolder: () =>
                                  widget.actions.onOpenFolder(info.sourcePath),
                            ),
                          ),
                        if (info.hasProgress)
                          Positioned(
                            left: 14,
                            right: 14,
                            bottom: 14,
                            child: SoftProgressBar(
                              value: info.progress,
                              height: 5,
                              color: Colors.white,
                              trackColor: Colors.white.withValues(alpha: 0.4),
                              semanticLabel: info.progressLabel(text),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 40,
                child: Text(
                  info.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 20 / 14,
                    fontWeight: FontWeight.w700,
                    color: colors.foreground,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                info.chapterSummary(text),
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
      ),
    );
  }
}

/// Amber on the cover scrim is 4.38:1, so the star reads in both themes.
const Color _coverStarColor = Color(0xFFFFC15A);

class _CoverStarButton extends StatelessWidget {
  const _CoverStarButton({
    required this.text,
    required this.favorited,
    required this.onPressed,
  });

  final AppStrings text;
  final bool favorited;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final reader = context.appReader;
    final tooltip = favorited ? text.removeFavorite : text.addFavorite;
    return FTooltip(
      tipBuilder: (context, _) => Text(tooltip),
      child: Semantics(
        button: true,
        toggled: favorited,
        label: tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: reader.scrim,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    AppIcons.star,
                    size: 16,
                    color: favorited ? _coverStarColor : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The row ("Daftar") card: cover 80×120, title + meta, progress, actions.
class _RowCard extends StatelessWidget {
  const _RowCard({
    required this.text,
    required this.info,
    required this.actions,
  });

  final AppStrings text;
  final _CardInfo info;
  final _CardActions actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final reader = context.appReader;
    final metaStyle = TextStyle(
      fontSize: 13,
      height: 20 / 13,
      fontWeight: FontWeight.w500,
      color: colors.mutedForeground,
    );
    final progressBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              info.hasProgress ? '${info.percent}%' : text.unread,
              style: info.hasProgress
                  ? TextStyle(
                      fontSize: 14,
                      height: 20 / 14,
                      fontWeight: FontWeight.w800,
                      color: colors.secondaryForeground,
                    )
                  : TextStyle(
                      fontSize: 13,
                      height: 20 / 13,
                      fontWeight: FontWeight.w600,
                      color: colors.mutedForeground,
                    ),
            ),
            const Spacer(),
            if (info.hasProgress)
              Text(
                info.chapterSummary(text),
                style: TextStyle(
                  fontSize: 12.5,
                  height: 18 / 12.5,
                  fontWeight: FontWeight.w500,
                  color: colors.mutedForeground,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SoftProgressBar(
          value: info.progress,
          semanticLabel: info.progressLabel(text),
        ),
      ],
    );

    return HoverCard(
      padding: const EdgeInsets.all(12),
      semanticLabel: info.title,
      onTap: () => context.go('/comic/${encodeRoutePath(info.sourcePath)}'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          return Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppShape.radiusControl),
                  boxShadow: AppShape.controlShadow(reader),
                ),
                child: CoverThumbnail(
                  sourcePath: info.sourcePath,
                  width: 80,
                  height: 120,
                  radius: AppShape.radiusControl,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            info.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              height: 24 / 16,
                              fontWeight: FontWeight.w700,
                              color: colors.foreground,
                            ),
                          ),
                        ),
                        if (info.isNew) ...[
                          const SizedBox(width: 10),
                          SoftBadge(
                            label: text.newBadge,
                            tone: SoftBadgeTone.amber,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 16,
                      runSpacing: 2,
                      children: [
                        Text(
                          info.chapterCount > 0
                              ? text.chaptersCountTemplate.replaceAll(
                                  '{count}',
                                  '${info.chapterCount}',
                                )
                              : text.unread,
                          style: metaStyle,
                        ),
                        if (info.dateModified > 0)
                          Text(
                            formatModifiedDate(info.dateModified),
                            style: metaStyle,
                          ),
                        if (info.sizeBytes > 0)
                          Text(formatBytes(info.sizeBytes), style: metaStyle),
                      ],
                    ),
                    if (!wide) ...[const SizedBox(height: 12), progressBlock],
                  ],
                ),
              ),
              if (wide) ...[
                const SizedBox(width: 24),
                SizedBox(width: 280, child: progressBlock),
              ],
              const SizedBox(width: 12),
              SoftIconButton(
                icon: AppIcons.star,
                tooltip: info.favorited
                    ? text.removeFavorite
                    : text.addFavorite,
                iconSize: 20,
                round: true,
                outline: false,
                selected: info.favorited,
                color: info.favorited ? reader.star : colors.mutedForeground,
                onPressed: () =>
                    actions.onToggleFavorite(info.sourcePath, info.favorited),
              ),
              const SizedBox(width: 4),
              _CardContextMenu(
                text: text,
                onCover: false,
                onCopyTitle: () => actions.onCopyTitle(info.title),
                onCopyPath: () => actions.onCopyPath(info.sourcePath),
                onOpenFolder: () => actions.onOpenFolder(info.sourcePath),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// "Continue Reading": the last unfinished chapters, one row of cards.
class _ContinueShelf extends StatelessWidget {
  const _ContinueShelf({
    required this.text,
    required this.entries,
    required this.onViewHistory,
  });

  final AppStrings text;
  final List<bridge.ReadingHistoryEntry> entries;
  final VoidCallback onViewHistory;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: SectionHeading(title: text.continueReadingSection)),
            SoftButton(
              label: text.viewHistory,
              icon: AppIcons.chevronRight,
              variant: SoftButtonVariant.text,
              onPressed: onViewHistory,
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            const minCardWidth = 300.0;
            const gap = 16.0;
            final columns =
                ((constraints.maxWidth + gap) / (minCardWidth + gap))
                    .floor()
                    .clamp(1, 4);
            final shown = entries.take(columns).toList();
            return Row(
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0) const SizedBox(width: gap),
                  Expanded(
                    child: _ContinueCard(text: text, entry: shown[i]),
                  ),
                ],
                for (var i = shown.length; i < columns; i++) ...[
                  const SizedBox(width: gap),
                  const Expanded(child: SizedBox.shrink()),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.text, required this.entry});

  final AppStrings text;
  final bridge.ReadingHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final total = entry.totalPages.toInt();
    final page = total <= 0 ? 0 : (entry.lastPage.toInt() + 1).clamp(1, total);
    final progress = total <= 0 ? 0.0 : page / total;
    final meta = total <= 0
        ? entry.chapterTitle
        : text.chapterPageTemplate
              .replaceAll('{chapter}', entry.chapterTitle)
              .replaceAll('{page}', '$page')
              .replaceAll('{total}', '$total');
    return HoverCard(
      padding: const EdgeInsets.all(14),
      semanticLabel: '${entry.comicTitle}. $meta',
      onTap: () =>
          context.go('/comic/${encodeRoutePath(entry.comicSourcePath)}'),
      child: Row(
        children: [
          CoverThumbnail(
            sourcePath: entry.comicSourcePath,
            width: 64,
            height: 92,
            radius: 14,
            fallbackIconSize: 20,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.comicTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    height: 22 / 15,
                    fontWeight: FontWeight.w700,
                    color: colors.foreground,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 20 / 13,
                    fontWeight: FontWeight.w500,
                    color: colors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 10),
                SoftProgressBar(value: progress),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SoftIconButton(
            icon: AppIcons.play,
            tooltip: '${text.continueReading}: ${entry.comicTitle}',
            primary: true,
            round: true,
            onPressed: () => context.go('/reader/${entry.chapterId}'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// History tab.
// ---------------------------------------------------------------------------

class _HistoryList extends ConsumerWidget {
  const _HistoryList({
    required this.text,
    required this.items,
    required this.visibleCount,
    required this.hasMore,
    required this.onLoadMore,
    required this.controller,
    required this.emptyLabel,
  });

  final AppStrings text;
  final List<bridge.ReadingHistoryEntry> items;
  final int visibleCount;
  final bool hasMore;
  final VoidCallback onLoadMore;
  final ScrollController controller;
  final String emptyLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(readingHistoryProvider);
    return history.when(
      data: (entries) {
        if (entries.isEmpty || visibleCount == 0) {
          return SoftEmptyState(message: emptyLabel, icon: AppIcons.clock);
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
          child: ListView.separated(
            controller: controller,
            padding: const EdgeInsets.only(bottom: 56),
            itemCount: visibleCount,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              return _HistoryRow(text: text, item: items[index]);
            },
          ),
        );
      },
      error: (error, _) =>
          SoftEmptyState(message: error.toString(), isError: true),
      loading: () => const Align(
        alignment: Alignment.center,
        child: FCircularProgress.loader(),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.text, required this.item});

  final AppStrings text;
  final bridge.ReadingHistoryEntry item;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final reader = context.appReader;
    final total = item.totalPages.toInt();
    final finished = item.isRead;
    final page = total <= 0
        ? 0
        : finished
        ? total
        : (item.lastPage.toInt() + 1).clamp(1, total);
    final progress = finished ? 1.0 : (total <= 0 ? 0.0 : page / total);
    final lastRead = item.updatedAt > 0
        ? formatModifiedDate(item.updatedAt.toInt())
        : '';

    final progressBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              finished ? text.finished : '${(progress * 100).round()}%',
              style: TextStyle(
                fontSize: 14,
                height: 20 / 14,
                fontWeight: FontWeight.w800,
                color: finished ? reader.success : colors.secondaryForeground,
              ),
            ),
            const SizedBox(width: 12),
            if (total > 0)
              Expanded(
                child: Text(
                  text.pageOfTemplate
                      .replaceAll('{page}', '$page')
                      .replaceAll('{total}', '$total'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 18 / 12.5,
                    fontWeight: FontWeight.w500,
                    color: colors.mutedForeground,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SoftProgressBar(
          value: progress,
          color: finished ? reader.success : null,
          semanticLabel: text.readingProgress,
        ),
      ],
    );
    final action = SoftButton(
      label: finished ? text.readAgain : text.continueReading,
      icon: finished ? AppIcons.restart : AppIcons.play,
      variant: finished ? SoftButtonVariant.outline : SoftButtonVariant.soft,
      onPressed: () => context.go('/reader/${item.chapterId}'),
    );

    return HoverCard(
      padding: const EdgeInsets.all(12),
      semanticLabel: '${item.comicTitle}. ${item.chapterTitle}',
      onTap: () =>
          context.go('/comic/${encodeRoutePath(item.comicSourcePath)}'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          return Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppShape.radiusControl),
                  boxShadow: AppShape.controlShadow(reader),
                ),
                child: CoverThumbnail(
                  sourcePath: item.comicSourcePath,
                  width: 80,
                  height: 120,
                  radius: AppShape.radiusControl,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.comicTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        height: 24 / 16,
                        fontWeight: FontWeight.w700,
                        color: colors.foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.chapterTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        height: 22 / 14,
                        fontWeight: FontWeight.w600,
                        color: colors.foreground,
                      ),
                    ),
                    if (lastRead.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${text.lastRead}: $lastRead',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 18 / 12.5,
                          fontWeight: FontWeight.w500,
                          color: colors.mutedForeground,
                        ),
                      ),
                    ],
                    if (!wide) ...[
                      const SizedBox(height: 12),
                      progressBlock,
                      const SizedBox(height: 12),
                      Align(alignment: Alignment.centerRight, child: action),
                    ],
                  ],
                ),
              ),
              if (wide) ...[
                const SizedBox(width: 24),
                SizedBox(width: 260, child: progressBlock),
                const SizedBox(width: 20),
                action,
                const SizedBox(width: 4),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Favorites tab.
// ---------------------------------------------------------------------------

class _FavoritesList extends StatelessWidget {
  const _FavoritesList({
    required this.text,
    required this.favorites,
    required this.comics,
    required this.query,
    required this.sort,
    required this.displayMode,
    required this.controller,
    required this.emptyLabel,
    required this.actions,
    required this.onSetSort,
  });

  final AppStrings text;
  final AsyncValue<List<bridge.Favorite>> favorites;
  final List<bridge.RawComic> comics;
  final String query;
  final (bridge.SortBy, bridge.SortDir) sort;
  final LibraryDisplayMode displayMode;
  final ScrollController controller;
  final String emptyLabel;
  final _CardActions actions;
  final void Function(bridge.SortBy sortBy, bridge.SortDir sortDir) onSetSort;

  @override
  Widget build(BuildContext context) {
    final comicByPath = <String, bridge.RawComic>{};
    for (final c in comics) {
      comicByPath[c.sourcePath] = c;
    }
    final (sortBy, sortDir) = sort;
    return favorites.when(
      data: (items) {
        final sorted = List<bridge.Favorite>.from(items);
        sorted.sort((a, b) {
          final cmp = switch (sortBy) {
            bridge.SortBy.name => a.comicTitle.toLowerCase().compareTo(
              b.comicTitle.toLowerCase(),
            ),
            bridge.SortBy.folderDate =>
              (comicByPath[a.comicSourcePath]?.dateModified ?? 0).compareTo(
                comicByPath[b.comicSourcePath]?.dateModified ?? 0,
              ),
          };
          return sortDir == bridge.SortDir.asc ? cmp : -cmp;
        });
        final filteredQuery = query.trim().toLowerCase();
        final filtered = filteredQuery.isEmpty
            ? sorted
            : sorted
                  .where(
                    (item) =>
                        item.comicTitle.toLowerCase().contains(filteredQuery) ||
                        item.comicSourcePath.toLowerCase().contains(
                          filteredQuery,
                        ),
                  )
                  .toList();
        return CustomScrollView(
          controller: controller,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _librarySortMenu(
                    text: text,
                    sort: sort,
                    onChanged: onSetSort,
                  ),
                ),
              ),
            ),
            if (filtered.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: SoftEmptyState(message: emptyLabel, icon: AppIcons.star),
              )
            else if (displayMode == LibraryDisplayMode.grid)
              _CoverGrid(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final item = filtered[index];
                  return _GridCard(
                    text: text,
                    info: _CardInfo.fromFavorite(
                      item,
                      comicByPath[item.comicSourcePath],
                    ),
                    actions: actions,
                  );
                },
              )
            else
              SliverList.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = filtered[index];
                  return _RowCard(
                    text: text,
                    info: _CardInfo.fromFavorite(
                      item,
                      comicByPath[item.comicSourcePath],
                    ),
                    actions: actions,
                  );
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 56)),
          ],
        );
      },
      error: (error, _) =>
          SoftEmptyState(message: error.toString(), isError: true),
      loading: () => const Align(
        alignment: Alignment.center,
        child: FCircularProgress.loader(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits.
// ---------------------------------------------------------------------------

class _CardContextMenu extends StatelessWidget {
  const _CardContextMenu({
    required this.text,
    required this.onCover,
    required this.onCopyTitle,
    required this.onCopyPath,
    required this.onOpenFolder,
  });

  final AppStrings text;

  /// Drawn over cover art (scrim circle) instead of on a surface.
  final bool onCover;
  final VoidCallback onCopyTitle;
  final VoidCallback onCopyPath;
  final VoidCallback onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final reader = context.appReader;
    return FPopoverMenu(
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
              prefix: const Icon(AppIcons.folderOpen, size: 16),
              title: Text(text.openFolder),
              onPress: onOpenFolder,
            ),
          ],
        ),
      ],
      builder: (context, controller, _) {
        if (!onCover) {
          return SoftIconButton(
            icon: AppIcons.more,
            tooltip: text.menu,
            iconSize: 20,
            round: true,
            outline: false,
            onPressed: controller.toggle,
          );
        }
        return FTooltip(
          tipBuilder: (context, _) => Text(text.menu),
          child: Semantics(
            button: true,
            label: text.menu,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: controller.toggle,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: reader.scrim,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        AppIcons.more,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// First run: no library folder configured yet.
// ---------------------------------------------------------------------------

class _WelcomeView extends StatelessWidget {
  const _WelcomeView({
    required this.text,
    required this.onPickFolder,
    required this.onImportBackup,
  });

  final AppStrings text;
  final VoidCallback onPickFolder;
  final VoidCallback onImportBackup;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1000;
        final narrow = constraints.maxWidth < 640;
        final pad = narrow ? 16.0 : 48.0;
        final intro = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 36,
              padding: const EdgeInsets.fromLTRB(12, 0, 14, 0),
              decoration: BoxDecoration(
                color: colors.secondary,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    AppIcons.offline,
                    size: 16,
                    color: colors.secondaryForeground,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    text.worksOffline,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.secondaryForeground,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              text.welcomeTitle,
              style: TextStyle(
                fontSize: narrow ? 34 : 46,
                height: narrow ? 42 / 34 : 54 / 46,
                fontWeight: FontWeight.w800,
                letterSpacing: narrow ? -1.0 : -1.6,
                color: colors.foreground,
              ),
            ),
            const SizedBox(height: 24),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(
                text.welcomeBody,
                style: TextStyle(
                  fontSize: 17,
                  height: 28 / 17,
                  fontWeight: FontWeight.w500,
                  color: colors.mutedForeground,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SoftButton(
                  label: text.pickComicFolder,
                  icon: AppIcons.folderOpen,
                  variant: SoftButtonVariant.primary,
                  height: 56,
                  onPressed: onPickFolder,
                ),
                SoftButton(
                  label: text.haveBackupImport,
                  variant: SoftButtonVariant.text,
                  onPressed: onImportBackup,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    text.supported,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.mutedForeground,
                    ),
                  ),
                ),
                for (final format in [
                  text.imageFolder,
                  'CBZ',
                  'ZIP',
                  'CBR',
                  'RAR',
                ])
                  SoftPill(label: format),
              ],
            ),
          ],
        );
        final example = _FolderStructureCard(text: text);
        final content = wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(flex: 11, child: intro),
                  const SizedBox(width: 56),
                  Expanded(flex: 9, child: example),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [intro, const SizedBox(height: 40), example],
              );
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(pad, 40, pad, 72),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: content,
            ),
          ),
        );
      },
    );
  }
}

class _FolderStructureCard extends StatelessWidget {
  const _FolderStructureCard({required this.text});

  final AppStrings text;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final reader = context.appReader;
    return SoftCard(
      radius: 32,
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text.folderStructureTitle,
            style: TextStyle(
              fontSize: 16,
              height: 24 / 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.16,
              color: colors.foreground,
            ),
          ),
          const SizedBox(height: 20),
          _TreeRow(
            depth: 0,
            icon: AppIcons.folder,
            iconColor: colors.secondaryForeground,
            label: text.library,
            bold: true,
            highlighted: true,
            tag: SoftBadge(label: text.libraryFolderTag),
          ),
          _TreeRow(
            depth: 1,
            icon: AppIcons.folder,
            iconColor: colors.secondaryForeground,
            label: 'Penjaga Senja',
            tag: SoftBadge(label: text.oneTitleTag, tone: SoftBadgeTone.accent),
          ),
          _TreeRow(
            depth: 2,
            icon: AppIcons.folder,
            iconColor: reader.badgeNewForeground,
            label: 'Chapter 01',
            tag: SoftBadge(label: text.chapterTag, tone: SoftBadgeTone.amber),
          ),
          _TreeRow(
            depth: 2,
            icon: AppIcons.folder,
            iconColor: reader.badgeNewForeground,
            label: 'Chapter 02',
            tag: SoftBadge(label: text.chapterTag, tone: SoftBadgeTone.amber),
          ),
          _TreeRow(
            depth: 2,
            icon: AppIcons.fileArchive,
            iconColor: reader.badgeNewForeground,
            label: 'Chapter 03.cbz',
            tag: SoftBadge(label: text.chapterTag, tone: SoftBadgeTone.amber),
          ),
          _TreeRow(
            depth: 1,
            icon: AppIcons.fileArchive,
            iconColor: colors.secondaryForeground,
            label: 'Kota di Bawah Hujan.cbz',
            tag: SoftBadge(label: text.oneTitleTag, tone: SoftBadgeTone.accent),
          ),
          const SizedBox(height: 20),
          Text(
            text.folderStructureNote,
            style: TextStyle(
              fontSize: 13,
              height: 20 / 13,
              fontWeight: FontWeight.w500,
              color: colors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}

class _TreeRow extends StatelessWidget {
  const _TreeRow({
    required this.depth,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.tag,
    this.bold = false,
    this.highlighted = false,
  });

  final int depth;
  final IconData icon;
  final Color iconColor;
  final String label;
  final Widget tag;
  final bool bold;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      margin: const EdgeInsets.only(bottom: 4),
      padding: EdgeInsets.fromLTRB(12 + depth * 24.0, 6, 12, 6),
      decoration: BoxDecoration(
        color: highlighted ? colors.muted : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                color: colors.foreground,
              ),
            ),
          ),
          const SizedBox(width: 12),
          tag,
        ],
      ),
    );
  }
}
