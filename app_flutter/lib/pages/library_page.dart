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
        // ignore: unused_result
        ref.refresh(rawLibraryComicsProvider.future);
        // ignore: unused_result
        ref.refresh(comicsWithProgressProvider.future);
        // ignore: unused_result
        ref.refresh(readingHistoryProvider.future);
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: FTextField(
                    control: .managed(
                      controller: _search,
                      onChange: (value) {
                        _searchDebounce?.cancel();
                        _searchDebounce = Timer(
                          const Duration(milliseconds: 300),
                          () => ref
                              .read(libraryPreferencesProvider.notifier)
                              .setQuery(value.text),
                        );
                      },
                    ),
                    hint: text.search,
                    prefixBuilder: (context, style, variants) => Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Icon(
                        AppIcons.search,
                        size: 16,
                        color: context.appMutedText,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FTooltip(
                  tipBuilder: (context, _) => Text(text.refresh),
                  child: FButton.icon(
                    variant: .outline,
                    onPress: _refreshLibrary,
                    child: const Icon(AppIcons.refresh),
                  ),
                ),
                const SizedBox(width: 8),
                FButton(
                  variant: .outline,
                  selected: preferences.displayMode == LibraryDisplayMode.grid,
                  onPress: () => _setDisplayMode(LibraryDisplayMode.grid),
                  child: const Icon(AppIcons.gridView),
                ),
                const SizedBox(width: 4),
                FButton(
                  variant: .outline,
                  selected: preferences.displayMode == LibraryDisplayMode.list,
                  onPress: () => _setDisplayMode(LibraryDisplayMode.list),
                  child: const Icon(AppIcons.list),
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
                        FButton(
                          variant: .outline,
                          selected: preferences.viewMode == LibraryViewMode.all,
                          onPress: () => _setViewMode(LibraryViewMode.all),
                          child: Text(text.all),
                        ),
                        const SizedBox(width: 4),
                        FButton(
                          variant: .outline,
                          selected:
                              preferences.viewMode == LibraryViewMode.unread,
                          onPress: () => _setViewMode(LibraryViewMode.unread),
                          child: Text(text.unread),
                        ),
                        const SizedBox(width: 4),
                        FButton(
                          variant: .outline,
                          selected:
                              preferences.viewMode == LibraryViewMode.reading,
                          onPress: () => _setViewMode(LibraryViewMode.reading),
                          child: Text(text.progress),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 180,
                          height: 38,
                          child: FSelect<bridge.SortBy>(
                            hint: text.name,
                            items: {
                              text.name: bridge.SortBy.name,
                              text.folderDate: bridge.SortBy.folderDate,
                            },
                            control: .managed(
                              initial: preferences.sortBy,
                              onChange: (value) {
                                if (value != null) {
                                  _setSort(value, preferences.sortDir);
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FButton(
                          variant: .outline,
                          selected: preferences.sortDir == bridge.SortDir.asc,
                          onPress: () => _setSort(
                            preferences.sortBy,
                            preferences.sortDir == bridge.SortDir.asc
                                ? bridge.SortDir.desc
                                : bridge.SortDir.asc,
                          ),
                          prefix: Icon(
                            preferences.sortDir == bridge.SortDir.asc
                                ? AppIcons.sortUp
                                : AppIcons.sortDown,
                            size: 16,
                          ),
                          child: Text(
                            preferences.sortDir == bridge.SortDir.asc
                                ? text.ascending
                                : text.descending,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _TabCountLabel(
                  text: text,
                  selectedTab: preferences.selectedTab,
                  visibleComics: comicsState.visibleCount,
                  totalComics: comicsState.filteredTotal,
                  historyCount: history.asData?.value.length ?? 0,
                  bookmarksCount: bookmarks.asData?.value.length ?? 0,
                ),
              ],
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
                        history: history,
                        displayMode: preferences.displayMode,
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
                        bookmarks: bookmarks,
                        displayMode: preferences.displayMode,
                        controller: _bookmarksScroll,
                        emptyLabel: text.emptyLibrary,
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
}

class _TabCountLabel extends StatelessWidget {
  const _TabCountLabel({
    required this.text,
    required this.selectedTab,
    required this.visibleComics,
    required this.totalComics,
    required this.historyCount,
    required this.bookmarksCount,
  });

  final AppStrings text;
  final LibraryTab selectedTab;
  final int visibleComics;
  final int totalComics;
  final int historyCount;
  final int bookmarksCount;

  @override
  Widget build(BuildContext context) {
    final label = switch (selectedTab) {
      LibraryTab.history => '${text.totalComics}: $historyCount',
      LibraryTab.library when visibleComics != totalComics =>
        '${text.showingComics} $visibleComics/$totalComics',
      LibraryTab.library => '${text.totalComics}: $totalComics',
      LibraryTab.bookmarks => '${text.totalComics}: $bookmarksCount',
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: context.appCaptionStyle.copyWith(
            color: context.appMutedText,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (selectedTab == LibraryTab.library) _StorageSuffix(text: text),
      ],
    );
  }
}

class _StorageSuffix extends ConsumerWidget {
  const _StorageSuffix({required this.text});

  final AppStrings text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(comicRdApiProvider);
    return FutureBuilder<bridge.LibraryStorageStats>(
      future: api.getLibraryStorageStats(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final total = snapshot.data!.totalSizeBytes;
        if (total <= 0) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Text(
            '  •  Storage: ${formatBytes(total)}',
            style: context.appCaptionStyle.copyWith(
              color: context.appMutedText,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      },
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
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisExtent: 220,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: visibleCount,
              itemBuilder: (context, index) {
                final comic = comics[index];
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
            )
          : ListView.separated(
              controller: controller,
              padding: const EdgeInsets.all(16),
              itemCount: visibleCount,
              separatorBuilder: (_, _) => const FDivider(),
              itemBuilder: (context, index) {
                final comic = comics[index];
                final bookmarked = bookmarkedPaths.contains(comic.sourcePath);
                return _ComicListItem(
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
            ),
    );
  }
}

class _ComicListItem extends StatelessWidget {
  const _ComicListItem({
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
  final VoidCallback onToggleBookmark;
  final VoidCallback onCopyTitle;
  final VoidCallback onCopyPath;
  final VoidCallback onOpenFolder;

  @override
  Widget build(BuildContext context) {
    return FTappable(
      onPress: onOpen,
      builder: (context, states, child) => DecoratedBox(
        decoration: BoxDecoration(
          color: states.contains(FTappableVariant.hovered)
              ? context.appSecondarySurface
              : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(AppIcons.folderOpen, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(comic.title, style: context.appBodyStrongStyle),
                    Text(
                      comic.sourcePath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.appCaptionStyle,
                    ),
                    if (comic.dateModified > 0)
                      Text(
                        formatModifiedDate(comic.dateModified),
                        style: context.appCaptionStyle.copyWith(
                          color: context.appMutedText,
                        ),
                      ),
                  ],
                ),
              ),
              _ReadStatusBadge(
                text: text,
                readCount: comic.readChapterCount,
                totalCount: comic.chapterCount,
                inProgressCount: comic.inProgressChapterCount,
              ),
              if (comic.sizeBytes > 0) ...[
                const SizedBox(width: 6),
                _SizeBadge(sizeBytes: comic.sizeBytes),
              ],
              const SizedBox(width: 8),
              if (bookmarked) ...[
                _BookmarkMarker(text: text),
                const SizedBox(width: 8),
              ],
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
        ),
      ),
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
  final VoidCallback onToggleBookmark;
  final VoidCallback onCopyTitle;
  final VoidCallback onCopyPath;
  final VoidCallback onOpenFolder;

  @override
  Widget build(BuildContext context) {
    return FCard.raw(
      child: FTappable(
        onPress: onOpen,
        builder: (context, states, child) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: states.contains(FTappableVariant.hovered)
                ? context.appSecondarySurface
                : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(AppIcons.folderOpen, size: 20),
                  const Spacer(),
                  if (bookmarked) ...[
                    _BookmarkMarker(text: text),
                    const SizedBox(width: 4),
                  ],
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
              const SizedBox(height: 6),
              _ReadStatusBadge(
                text: text,
                readCount: comic.readChapterCount,
                totalCount: comic.chapterCount,
                inProgressCount: comic.inProgressChapterCount,
              ),
              if (comic.sizeBytes > 0) ...[
                const SizedBox(height: 4),
                _SizeBadge(sizeBytes: comic.sizeBytes),
              ],
              const Spacer(),
              Text(
                comic.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.appBodyStrongStyle,
              ),
              const SizedBox(height: 6),
              Text(
                comic.sourcePath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.appCaptionStyle,
              ),
              if (comic.dateModified > 0)
                Text(
                  formatModifiedDate(comic.dateModified),
                  style: context.appCaptionStyle.copyWith(
                    color: context.appMutedText,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadStatusBadge extends StatelessWidget {
  const _ReadStatusBadge({
    required this.text,
    required this.readCount,
    required this.totalCount,
    required this.inProgressCount,
  });

  final AppStrings text;
  final int readCount;
  final int totalCount;
  final int inProgressCount;

  @override
  Widget build(BuildContext context) {
    if (totalCount == 0) {
      return const SizedBox.shrink();
    }
    if (readCount >= totalCount) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: context.appAccent.withAlpha(40),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '${text.read} $readCount/$totalCount',
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.appAccent,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    if (readCount > 0 || inProgressCount > 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: context.appAccent.withAlpha(30),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '${text.reading} $readCount/$totalCount',
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.appAccent,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: context.appSecondarySurface,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text.unread,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: context.appMutedText,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _SizeBadge extends StatelessWidget {
  const _SizeBadge({required this.sizeBytes});

  final int sizeBytes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: context.appSecondarySurface,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        formatBytes(sizeBytes),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: context.appMutedText,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _BookmarkMarker extends StatelessWidget {
  const _BookmarkMarker({required this.text});

  final AppStrings text;

  @override
  Widget build(BuildContext context) {
    return FTooltip(
      tipBuilder: (context, _) => Text(text.bookmarks),
      child: Icon(AppIcons.bookmark, size: 16, color: context.appAccent),
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
  final VoidCallback onToggleBookmark;
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
              title: Text(bookmarked ? text.removeBookmark : text.addBookmark),
              onPress: onToggleBookmark,
            ),
            FItem(title: Text(text.openFolder), onPress: onOpenFolder),
            FItem(title: Text(text.copyTitle), onPress: onCopyTitle),
            FItem(title: Text(text.copyPath), onPress: onCopyPath),
          ],
        ),
      ],
      builder: (_, controller, _) => FButton.icon(
        variant: .ghost,
        onPress: controller.toggle,
        child: const Icon(AppIcons.more),
      ),
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
              mainAxisExtent: 120,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return _HistoryGridTile(
                item: item,
                onOpen: () => context.go(
                  '/comic/${encodeRoutePath(item.comicSourcePath)}',
                ),
              );
            },
          );
        }
        return ListView.separated(
          controller: controller,
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, _) => const FDivider(),
          itemBuilder: (context, index) {
            final item = items[index];
            return _HistoryListItem(
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

class _HistoryListItem extends StatelessWidget {
  const _HistoryListItem({required this.item, required this.onOpen});

  final bridge.ReadingHistoryEntry item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return FTappable(
      onPress: onOpen,
      builder: (context, states, child) => DecoratedBox(
        decoration: BoxDecoration(
          color: states.contains(FTappableVariant.hovered)
              ? context.appSecondarySurface
              : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(AppIcons.history, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.comicTitle),
                    Text(item.chapterTitle, style: context.appCaptionStyle),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryGridTile extends StatelessWidget {
  const _HistoryGridTile({required this.item, required this.onOpen});

  final bridge.ReadingHistoryEntry item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return FCard.raw(
      child: FTappable(
        onPress: onOpen,
        builder: (context, states, child) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: states.contains(FTappableVariant.hovered)
                ? context.appSecondarySurface
                : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(AppIcons.history, size: 20),
              const Spacer(),
              Text(
                item.comicTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.appBodyStrongStyle,
              ),
              const SizedBox(height: 4),
              Text(
                item.chapterTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.appCaptionStyle,
              ),
            ],
          ),
        ),
      ),
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
              mainAxisExtent: 120,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return _BookmarkGridTile(
                item: item,
                onOpen: () => context.go(
                  '/comic/${encodeRoutePath(item.comicSourcePath)}',
                ),
              );
            },
          );
        }
        return ListView.separated(
          controller: controller,
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, _) => const FDivider(),
          itemBuilder: (context, index) {
            final item = items[index];
            return _BookmarkListItem(
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

class _BookmarkListItem extends StatelessWidget {
  const _BookmarkListItem({required this.item, required this.onOpen});

  final bridge.ComicBookmark item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return FTappable(
      onPress: onOpen,
      builder: (context, states, child) => DecoratedBox(
        decoration: BoxDecoration(
          color: states.contains(FTappableVariant.hovered)
              ? context.appSecondarySurface
              : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(AppIcons.bookmark, size: 20),
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
                      style: context.appCaptionStyle,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookmarkGridTile extends StatelessWidget {
  const _BookmarkGridTile({required this.item, required this.onOpen});

  final bridge.ComicBookmark item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return FCard.raw(
      child: FTappable(
        onPress: onOpen,
        builder: (context, states, child) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: states.contains(FTappableVariant.hovered)
                ? context.appSecondarySurface
                : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(AppIcons.bookmark, size: 20),
              const Spacer(),
              Text(
                item.comicTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.appBodyStrongStyle,
              ),
            ],
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
