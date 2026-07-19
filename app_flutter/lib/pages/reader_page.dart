import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' as widgets;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:window_manager/window_manager.dart';
import 'package:go_router/go_router.dart';

import '../api/comicrd_api.dart';
import '../bridge_generated.dart' as bridge;
import '../routes/path_codec.dart';
import '../state/api_state.dart';
import '../state/comic_state.dart';
import '../state/library_state.dart';
import '../state/reader_state.dart';
import '../state/settings_data_state.dart';
import '../state/settings_state.dart';
import '../utils/forui_theme.dart';

/// Standardized page layout for the reader.
///
/// Pages are normalized to a comfortable pixel width on PC screens while
/// preserving their original orientation. Portrait pages use a narrower
/// standard; landscape pages use a wider standard so spreads remain readable.
class _ReaderPageLayout {
  static const double _portraitTargetWidth = 1000.0;
  static const double _landscapeTargetWidth = 1500.0;
  static const double _minDisplayWidth = 240.0;
  static const double _viewportWidthPadding = 24.0;

  static double maxDisplayWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return math.max(width - _viewportWidthPadding, _minDisplayWidth);
  }

  static bool _isLandscape(bridge.PageInfo page) {
    final width = page.width ?? 0;
    final height = page.height ?? 0;
    if (width <= 0 || height <= 0) return false;
    return width > height;
  }

  static double _targetWidth(bridge.PageInfo page) {
    return _isLandscape(page) ? _landscapeTargetWidth : _portraitTargetWidth;
  }

  static double displayWidth(
    bridge.PageInfo page,
    double zoom,
    double maxWidth,
  ) {
    final target = _targetWidth(page) * zoom;
    return target.clamp(_minDisplayWidth, maxWidth);
  }

  static double displayHeight(
    bridge.PageInfo page,
    double zoom,
    double maxWidth,
  ) {
    final width = displayWidth(page, zoom, maxWidth);
    return width / aspectRatio(page);
  }

  static double aspectRatio(bridge.PageInfo page) {
    final width = page.width ?? 900;
    final height = page.height ?? 1300;
    if (width <= 0 || height <= 0) {
      return 900 / 1300;
    }
    return width / height;
  }
}

class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key, required this.chapterId});

  final int chapterId;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  static int _activeInstances = 0;
  static bool _scrollToBottomOnRestore = false;
  static const double _topPadding = 78;
  static const double _bottomChromeHeight = 48;
  late ScrollController _scroll;
  final _focusNode = FocusNode(debugLabel: 'ReaderPage');
  Timer? _progressTimer;
  Timer? _initialScrollTimer;
  int _currentPage = 0;
  int _lastSavedPage = -1;
  bool _ignoreNextScrollUpdate = false;
  bool _restoredProgress = false;
  bool _initialScrollDone = false;
  bool _fullscreen = false;
  bool _toolbarVisible = true;
  late final ComicRdApi _api;
  ReaderData? _lastReaderData;
  int? _lastReaderChapterId;
  Completer<void>? _prefetchQueue;
  int? _prefetchQueuedStart;
  int? _prefetchQueuedEnd;
  bool _wasReset = false;
  int _renderStart = 0;
  int _renderEnd = -1;
  int _readerGeneration = 0;

  @override
  void initState() {
    super.initState();
    _api = ref.read(comicRdApiProvider);
    _activeInstances++;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 64 * 1024 * 1024;
    _scroll = _createScrollController();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _initialScrollTimer?.cancel();
    final data = _lastReaderData;
    final chapterId = _lastReaderChapterId;
    if (data != null && chapterId != null) {
      unawaited(_saveProgressDirect(chapterId: chapterId, data: data));
      unawaited(
        _releaseChapterMemory(
          chapterId: chapterId,
          pageCount: data.pages.length,
          invalidateRenderedPages: false,
        ),
      );
    }
    _activeInstances--;
    if (_activeInstances <= 0) {
      _activeInstances = 0;
      PaintingBinding.instance.imageCache.maximumSizeBytes = 100 * 1024 * 1024;
    }
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _scroll.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ReaderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chapterId == widget.chapterId) {
      return;
    }
    _progressTimer?.cancel();
    _initialScrollTimer?.cancel();
    _initialScrollTimer = null;
    _currentPage = 0;
    _lastSavedPage = -1;
    _ignoreNextScrollUpdate = false;
    _restoredProgress = false;
    _initialScrollDone = false;
    _wasReset = false;
    _renderStart = 0;
    _renderEnd = -1;
    _toolbarVisible = true;
    final oldData = _lastReaderChapterId == oldWidget.chapterId
        ? _lastReaderData
        : null;
    if (_lastReaderChapterId == oldWidget.chapterId) {
      _lastReaderData = null;
      _lastReaderChapterId = null;
    }
    final oldChapterId = oldWidget.chapterId;
    final oldPageCount = oldData?.pages.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.invalidate(readerDataProvider(oldChapterId));
      if (oldPageCount != null) {
        _invalidateRenderedPages(oldChapterId, oldPageCount);
      }
    });
    if (oldData != null) {
      unawaited(
        _releaseChapterMemory(
          chapterId: oldChapterId,
          pageCount: oldData.pages.length,
          invalidateRenderedPages: false,
        ),
      );
    }
    if (_scroll.hasClients) {
      _scroll.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<Map<String, String>>>(settingsMapProvider, (_, next) {
      next.whenData((values) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          ref.read(readerSettingsProvider.notifier).hydrateFromSettings(values);
        });
      });
    });
    final readerSettings = ref.watch(readerSettingsProvider);
    final settings = ref.watch(appSettingsProvider);
    final text = stringsFor(settings.localeCode);
    final reader = ref.watch(readerDataProvider(widget.chapterId));
    final comicPath = reader.asData?.value.context?.comicSourcePath ?? '';
    final chapterSourcePath =
        reader.asData?.value.context?.chapterSourcePath ?? '';
    final favoritePaths = comicPath.isEmpty
        ? const <String>[]
        : ref.watch(chapterFavoritesProvider(comicPath)).asData?.value ??
              const <String>[];
    final isFavorited =
        chapterSourcePath.isNotEmpty &&
        favoritePaths.contains(chapterSourcePath);
    final chapterBookmarksAsync = ref.watch(
      chapterBookmarksProvider(widget.chapterId),
    );
    final chapterBookmarks = chapterBookmarksAsync.asData?.value ?? [];
    final isCurrentPageBookmarked = chapterBookmarks.any(
      (b) => b.page == _currentPage,
    );
    final currentBookmarkId = isCurrentPageBookmarked
        ? chapterBookmarks.firstWhere((b) => b.page == _currentPage).id
        : null;
    return KeyboardListener(
      autofocus: true,
      focusNode: _focusNode,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          _handleKey(event.logicalKey, reader.asData?.value);
        }
      },
      child: ColoredBox(
        color: Colors.black,
        child: reader.when(
          data: (data) {
            _lastReaderData = data;
            _lastReaderChapterId = widget.chapterId;
            _restoreProgress(data);
            return Stack(
              children: [
                Positioned.fill(
                  child: _readerScrollView(data: data, text: text),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 22,
                  child: MouseRegion(
                    onEnter: (_) => _showToolbar(),
                    child: const SizedBox.expand(),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: 48,
                  child: MouseRegion(
                    onEnter: (_) => _showToolbar(),
                    child: const SizedBox.expand(),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedSlide(
                    offset: _toolbarVisible ? Offset.zero : const Offset(0, -1),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: _toolbarVisible ? 1 : 0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      child: IgnorePointer(
                        ignoring: !_toolbarVisible,
                        child: MouseRegion(
                          onEnter: (_) => _showToolbar(),
                          child: _ReferenceReaderToolbar(
                            text: text,
                            data: data,
                            currentPage: _currentPage,
                            pageGap: readerSettings.pageGap,
                            zoom: readerSettings.zoom,
                            fullscreen: _fullscreen,
                            unlimitedScroll: readerSettings.unlimitedScroll,
                            isFavorited: isFavorited,
                            isPageBookmarked: isCurrentPageBookmarked,
                            onClose: () => _close(data),
                            onPreviousPage: () => _jumpBy(-1),
                            onNextPage: () => _jumpBy(1),
                            onPreviousChapter:
                                data.context?.prevChapterId == null
                                ? null
                                : () => _switchChapter(
                                    data.context!.prevChapterId!,
                                  ),
                            onNextChapter: data.context?.nextChapterId == null
                                ? null
                                : () => _switchChapter(
                                    data.context!.nextChapterId!,
                                  ),
                            onGapChanged: (gap) {
                              ref
                                  .read(readerSettingsProvider.notifier)
                                  .setPageGap(gap);
                            },
                            onZoomChanged: (zoom) {
                              ref
                                  .read(readerSettingsProvider.notifier)
                                  .setZoom(zoom);
                            },
                            onToggleFullscreen: _toggleFullscreen,
                            onToggleUnlimitedScroll: () {
                              ref
                                  .read(readerSettingsProvider.notifier)
                                  .setUnlimitedScroll(
                                    !readerSettings.unlimitedScroll,
                                  );
                            },
                            onToggleFavorite: () =>
                                _toggleFavorite(chapterSourcePath, comicPath),
                            onTogglePageBookmark: () =>
                                _togglePageBookmark(currentBookmarkId),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: AnimatedOpacity(
                    opacity: _toolbarVisible ? 0 : 1,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    child: IgnorePointer(
                      ignoring: _toolbarVisible,
                      child: _ReferenceReaderIconButton(
                        tooltip: text.readerControls,
                        icon: AppIcons.settings,
                        onPressed: _showToolbar,
                        compact: true,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: AnimatedSlide(
                    offset: _toolbarVisible ? Offset.zero : const Offset(0, 1),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: _toolbarVisible ? 1 : 0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      child: IgnorePointer(
                        ignoring: !_toolbarVisible,
                        child: MouseRegion(
                          onEnter: (_) => _showToolbar(),
                          child: _ReferencePageIndicator(
                            currentPage: _currentPage,
                            pageCount: data.pages.length,
                            onSelected: _jumpToPage,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
          error: (error, _) => Align(
            alignment: Alignment.center,
            child: Text(
              error.toString(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
          loading: () => const Align(
            alignment: Alignment.center,
            child: FCircularProgress.loader(),
          ),
        ),
      ),
    );
  }

  Widget _readerScrollView({
    required ReaderData data,
    required AppStrings text,
  }) {
    if (data.pages.isEmpty) {
      return Align(
        alignment: Alignment.center,
        child: Text(text.noPages, style: const TextStyle(color: Colors.white)),
      );
    }
    final readerSettings = ref.watch(readerSettingsProvider);
    return widgets.RawScrollbar(
      controller: _scroll,
      thumbVisibility: true,
      trackVisibility: true,
      interactive: true,
      thickness: 12,
      radius: const Radius.circular(999),
      thumbColor: const Color(0xff747474),
      trackColor: const Color(0xff050505),
      trackBorderColor: const Color(0xff050505),
      child: ListView.builder(
        controller: _scroll,
        scrollCacheExtent: const ScrollCacheExtent.pixels(1500),
        itemExtentBuilder: (index, _) {
          if (index < 0 || index >= data.pages.length) {
            return null;
          }
          final pageGap = index == data.pages.length - 1
              ? 0
              : readerSettings.pageGap;
          return _pageDisplayHeight(data.pages[index], readerSettings.zoom) +
              pageGap;
        },
        padding: EdgeInsets.only(
          top: _topPadding,
          bottom: _bottomChromeHeight + readerSettings.pageGap,
        ),
        itemCount: data.pages.length,
        itemBuilder: (context, index) =>
            _readerPageListItem(data, readerSettings, index),
      ),
    );
  }

  Widget _readerPageListItem(
    ReaderData data,
    ReaderSettings readerSettings,
    int index,
  ) {
    final page = data.pages[index];
    return Padding(
      key: ValueKey(page.index),
      padding: EdgeInsets.only(
        bottom: index == data.pages.length - 1 ? 0 : readerSettings.pageGap,
      ),
      child: _ReaderPageItem(
        chapterId: widget.chapterId,
        page: page,
        zoom: readerSettings.zoom,
      ),
    );
  }

  ScrollController _createScrollController([double initialOffset = 0]) {
    return ScrollController(initialScrollOffset: initialOffset)
      ..addListener(_handleScroll);
  }

  void _restoreProgress(ReaderData data) {
    if (_restoredProgress || data.pages.isEmpty) {
      return;
    }
    _restoredProgress = true;
    final chapterId = widget.chapterId;
    final generation = _readerGeneration;
    final scrollToBottom = _scrollToBottomOnRestore;
    _scrollToBottomOnRestore = false;
    final page = scrollToBottom ? data.pages.length - 1 : data.initialPage;
    _currentPage = page;
    _lastSavedPage = page;
    _setRenderWindowAround(page, data.pages.length);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isReaderCurrent(chapterId, generation)) {
        return;
      }
      _jumpToPage(page, persist: false);
      unawaited(_prefetchWindow(_renderStart, _renderEnd));
      _initialScrollTimer?.cancel();
      late final Timer timer;
      timer = Timer(const Duration(milliseconds: 300), () {
        if (identical(_initialScrollTimer, timer)) {
          _initialScrollTimer = null;
        }
        if (_isReaderCurrent(chapterId, generation)) {
          setState(() => _initialScrollDone = true);
          _updateViewportWindow(persistProgress: false);
        }
      });
      _initialScrollTimer = timer;
    });
    unawaited(
      _saveInitialProgress(data, chapterId: chapterId, generation: generation),
    );
  }

  Future<void> _saveInitialProgress(
    ReaderData data, {
    required int chapterId,
    required int generation,
  }) async {
    final progress = data.progress;
    if (progress != null && !progress.isRead) {
      return;
    }
    _wasReset = true;
    await _api.saveProgress(
      bridge.SaveProgressPayload(
        chapterId: chapterId,
        lastPage: 0,
        totalPages: data.pages.length,
        isRead: false,
      ),
    );
    if (!_isReaderCurrent(chapterId, generation)) {
      return;
    }
    _invalidateProgressProviders(data, onClose: false);
  }

  void _handleScroll() {
    if (!_initialScrollDone) {
      return;
    }
    if (!_ignoreNextScrollUpdate) {
      _hideToolbar();
    }
    if (_ignoreNextScrollUpdate) {
      _ignoreNextScrollUpdate = false;
      return;
    }
    _updateViewportWindow();
    _checkAutoAdvanceChapter();
  }

  void _checkAutoAdvanceChapter() {
    final data = ref.read(readerDataProvider(widget.chapterId)).asData?.value;
    if (data == null || data.pages.isEmpty) {
      return;
    }
    final settings = ref.read(readerSettingsProvider);
    if (!settings.unlimitedScroll) {
      return;
    }
    if (!_scroll.hasClients) {
      return;
    }
    final maxExtent = _scroll.position.maxScrollExtent;
    final currentOffset = _scroll.position.pixels;
    final viewportDimension = _scroll.position.viewportDimension;
    final visibleRange = _visiblePageRange(
      pages: data.pages,
      zoom: settings.zoom,
      pageGap: settings.pageGap,
    );

    // Check for next chapter (scroll to end)
    final nextChapterId = data.context?.nextChapterId;
    if (nextChapterId != null) {
      final isAtEnd = currentOffset >= maxExtent - viewportDimension * 0.1;
      if (isAtEnd && visibleRange.last >= data.pages.length - 1) {
        _switchChapter(nextChapterId);
        return;
      }
    }

    // Check for previous chapter (scroll to beginning)
    final prevChapterId = data.context?.prevChapterId;
    if (prevChapterId != null && settings.unlimitedScrollUp) {
      final isAtStart = currentOffset <= viewportDimension * 0.1;
      if (isAtStart && visibleRange.first <= 0) {
        _switchChapter(prevChapterId, scrollToBottom: true);
        return;
      }
    }
  }

  void _updateViewportWindow({bool persistProgress = true}) {
    final data = ref.read(readerDataProvider(widget.chapterId)).asData?.value;
    if (data == null || data.pages.isEmpty || !_scroll.hasClients) {
      return;
    }
    final settings = ref.read(readerSettingsProvider);
    final range = _visiblePageRange(
      pages: data.pages,
      zoom: settings.zoom,
      pageGap: settings.pageGap,
    );
    final page = _pageAtViewportCenter(
      pages: data.pages,
      zoom: settings.zoom,
      pageGap: settings.pageGap,
    );
    final start = math.max(0, range.first - 2);
    final end = math.min(data.pages.length - 1, range.last + 2);
    final pageChanged = page != _currentPage;
    final windowChanged = start != _renderStart || end != _renderEnd;
    if (!pageChanged && !windowChanged) {
      return;
    }
    setState(() {
      _currentPage = page;
      _renderStart = start;
      _renderEnd = end;
    });
    if (pageChanged && persistProgress) {
      _scheduleProgressSave();
    }
    unawaited(_prefetchWindow(start, end));
  }

  int _pageAtViewportCenter({
    required List<bridge.PageInfo> pages,
    required double zoom,
    required double pageGap,
  }) {
    if (!_scroll.hasClients || pages.isEmpty) {
      return _currentPage;
    }
    final viewportCenter =
        _scroll.offset + _scroll.position.viewportDimension / 2;
    return _pageForOffset(
      pages: pages,
      zoom: zoom,
      pageGap: pageGap,
      offset: viewportCenter,
    );
  }

  ({int first, int last}) _visiblePageRange({
    required List<bridge.PageInfo> pages,
    required double zoom,
    required double pageGap,
  }) {
    if (!_scroll.hasClients || pages.isEmpty) {
      return (first: _currentPage, last: _currentPage);
    }
    final visibleTop = _scroll.offset;
    final visibleBottom = visibleTop + _scroll.position.viewportDimension;
    var first = -1;
    var last = -1;
    var top = _topPadding;
    for (var i = 0; i < pages.length; i++) {
      final bottom = top + _pageDisplayHeight(pages[i], zoom);
      if (bottom >= visibleTop && top <= visibleBottom) {
        first = first == -1 ? i : first;
        last = i;
      } else if (top > visibleBottom) {
        break;
      }
      top = bottom + pageGap;
    }
    if (first == -1) {
      final page = _pageForOffset(
        pages: pages,
        zoom: zoom,
        pageGap: pageGap,
        offset: visibleTop,
      );
      return (first: page, last: page);
    }
    return (first: first, last: last);
  }

  int _pageForOffset({
    required List<bridge.PageInfo> pages,
    required double zoom,
    required double pageGap,
    required double offset,
  }) {
    var top = _topPadding;
    for (var i = 0; i < pages.length; i++) {
      final bottom = top + _pageDisplayHeight(pages[i], zoom);
      if (offset <= bottom || i == pages.length - 1) {
        return i;
      }
      top = bottom + pageGap;
    }
    return pages.length - 1;
  }

  void _setRenderWindowAround(int page, int pageCount) {
    if (pageCount <= 0) {
      _renderStart = 0;
      _renderEnd = -1;
      return;
    }
    _renderStart = math.max(0, page - 2);
    _renderEnd = math.min(pageCount - 1, page + 2);
  }

  void _scheduleProgressSave() {
    _progressTimer?.cancel();
    _progressTimer = Timer(const Duration(milliseconds: 450), () {
      _saveProgress(immediate: true);
    });
  }

  Future<void> _saveProgress({required bool immediate}) async {
    final data = ref.read(readerDataProvider(widget.chapterId)).asData?.value;
    _lastReaderData = data;
    if (data == null || data.pages.isEmpty || _currentPage == _lastSavedPage) {
      return;
    }
    final isRead = _currentPage >= data.pages.length - 1;
    if (!_wasReset) {
      final savedLastPage = data.progress?.lastPage ?? 0;
      final savedIsRead = data.progress?.isRead ?? false;
      if (_currentPage <= savedLastPage && !(isRead && !savedIsRead)) {
        _lastSavedPage = _currentPage;
        return;
      }
    }
    _wasReset = false;
    _lastSavedPage = _currentPage;
    await ref
        .read(comicRdApiProvider)
        .saveProgress(
          bridge.SaveProgressPayload(
            chapterId: widget.chapterId,
            lastPage: _currentPage,
            totalPages: data.pages.length,
            isRead: isRead,
          ),
        );
    _invalidateProgressProviders(data, onClose: false);
  }

  Future<void> _saveProgressDirect({int? chapterId, ReaderData? data}) async {
    final targetData = data ?? _lastReaderData;
    final targetChapterId = chapterId ?? _lastReaderChapterId;
    if (targetData == null ||
        targetChapterId == null ||
        targetData.pages.isEmpty) {
      return;
    }
    final isRead = _currentPage >= targetData.pages.length - 1;
    await _api.saveProgress(
      bridge.SaveProgressPayload(
        chapterId: targetChapterId,
        lastPage: _currentPage,
        totalPages: targetData.pages.length,
        isRead: isRead,
      ),
    );
  }

  void _invalidateProgressProviders(ReaderData data, {required bool onClose}) {
    final comicPath = data.context?.comicSourcePath;
    if (onClose) {
      ref.invalidate(comicsWithProgressProvider);
      ref.invalidate(rawLibraryComicsProvider);
      ref.invalidate(libraryComicsProvider);
      ref.invalidate(readingHistoryProvider);
    }
    if (comicPath == null || comicPath.isEmpty) {
      return;
    }
    ref.invalidate(comicChaptersProvider(comicPath));
  }

  Future<void> _prefetchWindow(int start, int end) async {
    final chapterId = widget.chapterId;
    final generation = _readerGeneration;
    if (!_isReaderCurrent(chapterId, generation) || end < start) {
      return;
    }
    if (_prefetchQueue != null && !_prefetchQueue!.isCompleted) {
      _prefetchQueuedStart = start;
      _prefetchQueuedEnd = end;
      return;
    }
    final completer = Completer<void>();
    _prefetchQueue = completer;
    _prefetchQueuedStart = null;
    _prefetchQueuedEnd = null;
    try {
      final api = ref.read(comicRdApiProvider);
      var nextStart = start;
      var nextEnd = end;
      while (true) {
        if (!_isReaderCurrent(chapterId, generation)) {
          return;
        }
        final data = ref.read(readerDataProvider(chapterId)).asData?.value;
        if (data == null || data.pages.isEmpty || nextEnd < nextStart) {
          return;
        }
        final clampedStart = math.max(0, nextStart);
        final clampedEnd = math.min(data.pages.length - 1, nextEnd);
        final keepPages = Uint32List.fromList([
          for (var index = clampedStart; index <= clampedEnd; index++) index,
        ]);
        await api.evictChapterPages(chapterId: chapterId, keepPages: keepPages);
        if (!_isReaderCurrent(chapterId, generation)) {
          return;
        }
        await api.prefetchPages(
          bridge.PrefetchPagesPayload(
            chapterId: chapterId,
            pageIndices: keepPages,
          ),
        );
        if (!_isReaderCurrent(chapterId, generation)) {
          return;
        }
        final queuedStart = _prefetchQueuedStart;
        final queuedEnd = _prefetchQueuedEnd;
        _prefetchQueuedStart = null;
        _prefetchQueuedEnd = null;
        if (queuedStart == null || queuedEnd == null) {
          return;
        }
        nextStart = queuedStart;
        nextEnd = queuedEnd;
      }
    } finally {
      completer.complete();
      if (identical(_prefetchQueue, completer)) {
        _prefetchQueue = null;
      }
    }
  }

  void _handleKey(LogicalKeyboardKey key, ReaderData? data) {
    if (key == LogicalKeyboardKey.escape) {
      if (_fullscreen) {
        _toggleFullscreen();
      } else if (data != null) {
        _close(data);
      } else {
        context.pop();
      }
    } else if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.pageDown) {
      _scrollBy(
        key == LogicalKeyboardKey.pageDown
            ? MediaQuery.sizeOf(context).height * 0.85
            : 520,
      );
    } else if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.pageUp) {
      _scrollBy(
        key == LogicalKeyboardKey.pageUp
            ? -MediaQuery.sizeOf(context).height * 0.85
            : -520,
      );
    } else if (key == LogicalKeyboardKey.arrowRight &&
        data?.context?.nextChapterId != null) {
      _switchChapter(data!.context!.nextChapterId!);
    } else if (key == LogicalKeyboardKey.arrowLeft &&
        data?.context?.prevChapterId != null) {
      _switchChapter(data!.context!.prevChapterId!);
    }
  }

  Future<void> _close(ReaderData data) async {
    final chapterId = widget.chapterId;
    await _saveProgressDirect(chapterId: chapterId, data: data);
    _invalidateProgressProviders(data, onClose: true);
    ref.invalidate(readerDataProvider(chapterId));
    await _releaseChapterMemory(
      chapterId: chapterId,
      pageCount: data.pages.length,
    );
    if (!mounted) {
      return;
    }
    final comicPath = data.context?.comicSourcePath;
    final chapterPath = data.context?.chapterSourcePath;
    if (chapterPath != null &&
        chapterPath.isNotEmpty &&
        comicPath != null &&
        comicPath.isNotEmpty) {
      ref
          .read(lastOpenedChapterProvider.notifier)
          .remember(comicPath, chapterPath);
    }

    // Defer navigation so provider invalidations finish before the comic page
    // is rebuilt. This avoids "setState during build" errors in Riverpod 3.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = comicPath;
      if (target == null || target.isEmpty) {
        context.go('/');
      } else {
        context.go('/comic/${encodeRoutePath(target)}');
      }
    });
  }

  Future<void> _switchChapter(
    int chapterId, {
    bool scrollToBottom = false,
  }) async {
    _scrollToBottomOnRestore = scrollToBottom;
    final currentChapterId = widget.chapterId;
    final data =
        ref.read(readerDataProvider(currentChapterId)).asData?.value ??
        (_lastReaderChapterId == currentChapterId ? _lastReaderData : null);
    await _saveProgressDirect(chapterId: currentChapterId, data: data);
    ref.invalidate(readerDataProvider(currentChapterId));
    await _releaseChapterMemory(
      chapterId: currentChapterId,
      pageCount: data?.pages.length,
    );
    if (mounted) {
      context.go('/reader/$chapterId');
    }
  }

  Future<void> _releaseChapterMemory({
    required int chapterId,
    required int? pageCount,
    bool invalidateRenderedPages = true,
  }) async {
    _readerGeneration++;
    _initialScrollTimer?.cancel();
    _initialScrollTimer = null;
    _prefetchQueuedStart = null;
    _prefetchQueuedEnd = null;
    final pendingPrefetch = _prefetchQueue;
    if (invalidateRenderedPages && pageCount != null) {
      _invalidateRenderedPages(chapterId, pageCount);
    }
    if (_lastReaderChapterId == chapterId) {
      _lastReaderData = null;
      _lastReaderChapterId = null;
    }
    _renderStart = 0;
    _renderEnd = -1;
    if (pendingPrefetch != null && !pendingPrefetch.isCompleted) {
      await pendingPrefetch.future;
    }
    await _api.evictChapterPages(chapterId: chapterId, keepPages: []);
  }

  bool _isReaderCurrent(int chapterId, int generation) {
    return mounted &&
        widget.chapterId == chapterId &&
        _readerGeneration == generation;
  }

  void _invalidateRenderedPages(int chapterId, int pageCount) {
    for (var i = 0; i < pageCount; i++) {
      final provider = renderedPageProvider(
        RenderedPageRequest(chapterId: chapterId, pageIndex: i),
      );
      ref.invalidate(provider);
    }
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  void _jumpBy(int delta) {
    final data = ref.read(readerDataProvider(widget.chapterId)).asData?.value;
    final count = data?.pages.length ?? 0;
    if (count == 0) {
      return;
    }
    _jumpToPage((_currentPage + delta).clamp(0, count - 1));
  }

  void _jumpToPage(int page, {bool persist = true}) {
    final data = ref.read(readerDataProvider(widget.chapterId)).asData?.value;
    final count = data?.pages.length ?? 0;
    if (count == 0) {
      return;
    }
    _setRenderWindowAround(page, count);
    setState(() {
      _currentPage = page;
    });
    if (persist) {
      _scheduleProgressSave();
    } else {
      _lastSavedPage = page;
    }
    unawaited(_prefetchWindow(_renderStart, _renderEnd));
    if (_scroll.hasClients) {
      final estimatedOffset = _scrollOffsetForPageIndex(page, data!.pages);
      final targetOffset = estimatedOffset
          .clamp(0, _scroll.position.maxScrollExtent)
          .toDouble();
      if ((_scroll.position.pixels - targetOffset).abs() > 0.5) {
        _ignoreNextScrollUpdate = _initialScrollDone;
        _scroll.jumpTo(targetOffset);
      } else {
        _ignoreNextScrollUpdate = false;
      }
    }
  }

  void _scrollBy(double delta) {
    if (!_scroll.hasClients) {
      return;
    }
    final position = _scroll.position;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    unawaited(
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  double _scrollOffsetForPageIndex(int page, List<bridge.PageInfo> pages) {
    if (!_scroll.hasClients || pages.isEmpty) {
      return 0;
    }
    final settings = ref.read(readerSettingsProvider);
    final target = page.clamp(0, pages.length - 1);
    var offset = _topPadding;
    for (var i = 0; i < target; i++) {
      offset += _pageDisplayHeight(pages[i], settings.zoom);
      offset += settings.pageGap;
    }
    return offset.clamp(0, _scroll.position.maxScrollExtent).toDouble();
  }

  double _pageDisplayHeight(bridge.PageInfo page, double zoom) {
    return _ReaderPageLayout.displayHeight(
      page,
      zoom,
      _ReaderPageLayout.maxDisplayWidth(context),
    );
  }

  void _showToolbar() {
    if (_toolbarVisible || !mounted) {
      return;
    }
    setState(() => _toolbarVisible = true);
  }

  void _hideToolbar() {
    if (!_toolbarVisible || !mounted) {
      return;
    }
    setState(() => _toolbarVisible = false);
  }

  Future<void> _toggleFullscreen() async {
    _fullscreen = !_fullscreen;
    if (_fullscreen) {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      await windowManager.setFullScreen(true);
    } else {
      await windowManager.setFullScreen(false);
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _toggleFavorite(
    String chapterSourcePath,
    String comicSourcePath,
  ) async {
    if (chapterSourcePath.isEmpty || comicSourcePath.isEmpty) {
      return;
    }
    final api = ref.read(comicRdApiProvider);
    final favorites =
        ref.read(chapterFavoritesProvider(comicSourcePath)).asData?.value ?? [];
    final isFavorited = favorites.contains(chapterSourcePath);
    if (isFavorited) {
      await api.removeChapterFavorite(chapterSourcePath);
    } else {
      await api.addChapterFavorite(
        chapterSourcePath: chapterSourcePath,
        comicSourcePath: comicSourcePath,
      );
    }
    ref.invalidate(chapterFavoritesProvider(comicSourcePath));
  }

  Future<void> _togglePageBookmark(int? bookmarkId) async {
    final api = ref.read(comicRdApiProvider);
    if (bookmarkId != null) {
      await api.removeBookmark(bookmarkId);
    } else {
      await api.addBookmark(
        bridge.SaveBookmarkPayload(
          chapterId: widget.chapterId,
          page: _currentPage,
          note: '',
        ),
      );
    }
    ref.invalidate(chapterBookmarksProvider(widget.chapterId));
  }
}

class _ReaderPageItem extends ConsumerWidget {
  const _ReaderPageItem({
    required this.chapterId,
    required this.page,
    required this.zoom,
  });

  final int chapterId;
  final bridge.PageInfo page;
  final double zoom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final maxWidth = _ReaderPageLayout.maxDisplayWidth(context);
    final displayWidth = _ReaderPageLayout.displayWidth(page, zoom, maxWidth);
    final aspectRatio = _ReaderPageLayout.aspectRatio(page);
    final rendered = ref.watch(
      renderedPageProvider(
        RenderedPageRequest(chapterId: chapterId, pageIndex: page.index),
      ),
    );
    return rendered.when(
      data: (renderedPage) => Center(
        child: SizedBox(
          width: displayWidth,
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: Image.memory(
              renderedPage.bytes,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
      error: (error, _) => _PagePlaceholder(
        aspectRatio: aspectRatio,
        width: displayWidth,
        label: error.toString(),
      ),
      loading: () =>
          _PagePlaceholder(aspectRatio: aspectRatio, width: displayWidth),
    );
  }
}

class _PagePlaceholder extends StatelessWidget {
  const _PagePlaceholder({
    required this.aspectRatio,
    required this.width,
    this.label,
  });

  final double aspectRatio;
  final double width;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: SizedBox(
        width: width,
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: ColoredBox(
            color: const Color(0xff141414),
            child: Align(
              alignment: Alignment.center,
              child: label != null
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        label!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                    )
                  : const SizedBox(),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderGlass extends StatelessWidget {
  const _ReaderGlass({required this.child, this.border});

  final Widget child;
  final Border? border;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xff151922).withValues(alpha: 0.60),
            border: border,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ReferenceReaderToolbar extends StatelessWidget {
  const _ReferenceReaderToolbar({
    required this.text,
    required this.data,
    required this.currentPage,
    required this.pageGap,
    required this.zoom,
    required this.fullscreen,
    required this.unlimitedScroll,
    required this.isFavorited,
    required this.isPageBookmarked,
    required this.onClose,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.onPreviousChapter,
    required this.onNextChapter,
    required this.onGapChanged,
    required this.onZoomChanged,
    required this.onToggleFullscreen,
    required this.onToggleUnlimitedScroll,
    required this.onToggleFavorite,
    required this.onTogglePageBookmark,
  });

  final AppStrings text;
  final ReaderData data;
  final int currentPage;
  final double pageGap;
  final double zoom;
  final bool fullscreen;
  final bool unlimitedScroll;
  final bool isFavorited;
  final bool isPageBookmarked;
  final VoidCallback onClose;
  final VoidCallback onPreviousPage;
  final VoidCallback onNextPage;
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;
  final ValueChanged<double> onGapChanged;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onToggleUnlimitedScroll;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTogglePageBookmark;

  @override
  Widget build(BuildContext context) {
    final contextData = data.context;
    final chapterInfo = contextData != null
        ? '${contextData.title} (${contextData.chapterPosition}/${contextData.chapterTotal})'
        : (contextData?.title ?? text.chapter);
    final subtitle = '$chapterInfo - ${currentPage + 1}/${data.pages.length}';
    return _ReaderGlass(
      border: const Border(bottom: BorderSide(color: Color(0x14ffffff))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 84, vertical: 10),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1748),
            child: Row(
              children: [
                _ReferenceReaderIconButton(
                  tooltip: text.close,
                  icon: AppIcons.close,
                  onPressed: onClose,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        contextData?.comicTitle ?? text.appName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.68),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _ReferenceReaderIconButton(
                      tooltip: text.previousPage,
                      icon: AppIcons.chevronLeft,
                      onPressed: onPreviousPage,
                    ),
                    _ReferenceReaderIconButton(
                      tooltip: text.nextPage,
                      icon: AppIcons.chevronRight,
                      onPressed: onNextPage,
                    ),
                    const SizedBox(width: 4),
                    _ReferenceReaderIconButton(
                      tooltip: text.previousChapter,
                      icon: AppIcons.chevronFirst,
                      onPressed: onPreviousChapter,
                    ),
                    _ReferenceReaderIconButton(
                      tooltip: text.nextChapter,
                      icon: AppIcons.chevronLast,
                      onPressed: onNextChapter,
                    ),
                    _ReferenceReaderIconButton(
                      tooltip: isFavorited
                          ? text.removeFavorite
                          : text.addFavorite,
                      icon: AppIcons.star,
                      active: isFavorited,
                      activeColor: context.appReader.star,
                      onPressed: onToggleFavorite,
                    ),
                    _ReferenceReaderIconButton(
                      tooltip: isPageBookmarked
                          ? text.removeBookmark
                          : text.addBookmark,
                      icon: AppIcons.bookmark,
                      active: isPageBookmarked,
                      activeColor: context.appReader.star,
                      onPressed: onTogglePageBookmark,
                    ),
                    const SizedBox(width: 4),
                    _ReaderControlChip(
                      icon: AppIcons.search,
                      value: '${(zoom * 100).round()}%',
                      tooltip: text.zoom,
                      onDecrease: () =>
                          onZoomChanged((zoom - 0.1).clamp(0.4, 3).toDouble()),
                      onIncrease: () =>
                          onZoomChanged((zoom + 0.1).clamp(0.4, 3).toDouble()),
                      onReset: () => onZoomChanged(1),
                    ),
                    _ReaderControlChip(
                      icon: AppIcons.alignCenter,
                      value: '${pageGap.round()}px',
                      tooltip: text.gap,
                      onDecrease: () =>
                          onGapChanged((pageGap - 5).clamp(0, 80).toDouble()),
                      onIncrease: () =>
                          onGapChanged((pageGap + 5).clamp(0, 80).toDouble()),
                      onReset: () => onGapChanged(20),
                    ),
                    _ReferenceReaderIconButton(
                      tooltip: text.fullscreen,
                      icon: fullscreen ? AppIcons.minimize : AppIcons.maximize,
                      active: fullscreen,
                      onPressed: onToggleFullscreen,
                    ),
                    _ReferenceReaderIconButton(
                      tooltip: text.unlimitedScroll,
                      icon: AppIcons.scroll,
                      active: unlimitedScroll,
                      onPressed: onToggleUnlimitedScroll,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReferenceReaderIconButton extends StatefulWidget {
  const _ReferenceReaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
    this.activeColor,
    this.compact = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool active;
  final Color? activeColor;
  final bool compact;

  @override
  State<_ReferenceReaderIconButton> createState() =>
      _ReferenceReaderIconButtonState();
}

class _ReferenceReaderIconButtonState
    extends State<_ReferenceReaderIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final size = widget.compact ? 38.0 : 40.0;
    final activeColor = widget.activeColor;
    final isActiveColored = widget.active && activeColor != null;
    final fgOpacity = enabled ? 0.78 : 0.28;
    final bgOpacity = (widget.active ? 0.14 : (_hovered && enabled ? 0.10 : 0))
        .toDouble();
    final borderColor = isActiveColored
        ? activeColor.withValues(alpha: 0.60)
        : Colors.white.withValues(alpha: widget.active ? 0.36 : 0.18);
    final iconColor = isActiveColored
        ? activeColor.withValues(alpha: enabled ? 1.0 : 0.40)
        : Colors.white.withValues(alpha: fgOpacity);
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: bgOpacity),
              borderRadius: BorderRadius.circular(widget.compact ? 999 : 8),
              border: Border.all(color: borderColor),
            ),
            child: Icon(
              widget.icon,
              size: widget.compact ? 16 : 18,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderControlChip extends StatefulWidget {
  const _ReaderControlChip({
    required this.icon,
    required this.value,
    required this.tooltip,
    required this.onDecrease,
    required this.onIncrease,
    required this.onReset,
  });

  final IconData icon;
  final String value;
  final String tooltip;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final VoidCallback onReset;

  @override
  State<_ReaderControlChip> createState() => _ReaderControlChipState();
}

class _ReaderControlChipState extends State<_ReaderControlChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _hovered ? 0.12 : 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _chipButton(AppIcons.minus, widget.onDecrease),
              GestureDetector(
                onDoubleTap: widget.onReset,
                child: SizedBox(
                  width: 48,
                  child: Center(
                    child: Text(
                      widget.value,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              _chipButton(AppIcons.plus, widget.onIncrease),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chipButton(IconData icon, VoidCallback onPressed) {
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 32,
        height: 36,
        child: Icon(
          icon,
          size: 14,
          color: Colors.white.withValues(alpha: 0.78),
        ),
      ),
    );
  }
}

class _ReferencePageIndicator extends StatefulWidget {
  const _ReferencePageIndicator({
    required this.currentPage,
    required this.pageCount,
    required this.onSelected,
  });

  final int currentPage;
  final int pageCount;
  final ValueChanged<int> onSelected;

  @override
  State<_ReferencePageIndicator> createState() =>
      _ReferencePageIndicatorState();
}

class _ReferencePageIndicatorState extends State<_ReferencePageIndicator> {
  bool _hovered = false;
  int? _hoveredPage;

  @override
  Widget build(BuildContext context) {
    final count = math.max(1, widget.pageCount);
    final current = widget.currentPage.clamp(0, count - 1);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _hoveredPage = null;
      }),
      child: _ReaderGlass(
        border: const Border(top: BorderSide(color: Color(0x14ffffff))),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: _hovered ? 54 : 34,
          padding: EdgeInsets.symmetric(
            horizontal: _hovered ? 96 : 100,
            vertical: _hovered ? 10 : 7,
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: _hovered ? 36 : 0,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _hovered ? 1 : 0,
                  child: Text(
                    '${current + 1}',
                    overflow: TextOverflow.clip,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final hoveredPage = (_hoveredPage ?? current).clamp(
                      0,
                      count - 1,
                    );
                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      onEnter: (event) => _updateHoveredPage(
                        event.localPosition.dx,
                        constraints.maxWidth,
                        count,
                      ),
                      onHover: (event) => _updateHoveredPage(
                        event.localPosition.dx,
                        constraints.maxWidth,
                        count,
                      ),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) {
                          widget.onSelected(
                            _pageIndexForDx(
                              details.localPosition.dx,
                              constraints.maxWidth,
                              count,
                            ),
                          );
                        },
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _PageIndicatorPainter(
                                  current: current,
                                  pageCount: count,
                                  hovered: _hovered,
                                ),
                              ),
                            ),
                            if (_hoveredPage != null)
                              Positioned(
                                left: _tooltipLeft(
                                  constraints.maxWidth,
                                  count,
                                  hoveredPage,
                                ),
                                top: -10,
                                child: _PageIndicatorTooltip(
                                  label: '${hoveredPage + 1}',
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: _hovered ? 36 : 0,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _hovered ? 1 : 0,
                  child: Text(
                    '$count',
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.clip,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _updateHoveredPage(double dx, double width, int count) {
    final page = _pageIndexForDx(dx, width, count);
    if (_hoveredPage == page) {
      return;
    }
    setState(() => _hoveredPage = page);
  }

  int _pageIndexForDx(double dx, double width, int count) {
    if (count <= 1 || width <= 0) {
      return 0;
    }
    final segmentWidth = width / count;
    return (dx / segmentWidth).floor().clamp(0, count - 1);
  }

  double _tooltipLeft(double width, int count, int page) {
    if (count <= 0 || width <= 0) {
      return 0;
    }
    final segmentWidth = width / count;
    final center = segmentWidth * (page + 0.5);
    const tooltipWidth = _PageIndicatorTooltip.width;
    return (center - tooltipWidth / 2).clamp(0, width - tooltipWidth);
  }
}

class _PageIndicatorTooltip extends StatelessWidget {
  const _PageIndicatorTooltip({required this.label});

  static const double width = 40;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xff222831),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SizedBox(
        width: width,
        height: 22,
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _PageIndicatorPainter extends CustomPainter {
  _PageIndicatorPainter({
    required this.current,
    required this.pageCount,
    required this.hovered,
  });

  final int current;
  final int pageCount;
  final bool hovered;

  @override
  void paint(Canvas canvas, Size size) {
    if (pageCount <= 0) return;
    final segmentWidth = size.width / pageCount;
    final barHeight = hovered ? 12.0 : 4.0;
    final gap = hovered ? 2.0 : 1.0;
    final top = (size.height - barHeight) / 2;
    final filledPaint = Paint()..color = const Color(0xff9aa7b5);
    final emptyPaint = Paint()..color = Colors.white.withValues(alpha: 0.20);
    final radius = Radius.circular(99);

    for (var i = 0; i < pageCount; i++) {
      final left = i * segmentWidth + gap;
      final right = (i + 1) * segmentWidth - gap;
      if (right <= left) continue;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTRB(left, top, right, top + barHeight),
        radius,
      );
      canvas.drawRRect(rect, i <= current ? filledPaint : emptyPaint);
    }
  }

  @override
  bool shouldRepaint(_PageIndicatorPainter oldDelegate) {
    return oldDelegate.current != current ||
        oldDelegate.pageCount != pageCount ||
        oldDelegate.hovered != hovered;
  }
}
