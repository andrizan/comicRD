import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart'
    show ItemExtentBuilder, RenderSliverVariedExtentList, ScrollCacheExtent;
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
  static const double _landscapeAspectThreshold = 1.5;
  static const double _landscapeSizeRatio = 1.5;

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

  /// Landscape layout is reserved for spreads. A page is treated as
  /// landscape only when:
  ///   1. its aspect ratio is clearly wider than tall (> 1.5), and
  ///   2. its width is more than 1.5x the previous page's longer side.
  /// Anything that doesn't satisfy both follows the previous page's
  /// target width so the column stays visually consistent.
  ///
  /// When [forcePortrait] is true, every page is sized to the portrait
  /// target width regardless of aspect ratio or surrounding pages.
  static double _effectiveTargetWidth(
    bridge.PageInfo page,
    bridge.PageInfo? prevPage, {
    bool forcePortrait = false,
  }) {
    if (forcePortrait) {
      return _portraitTargetWidth;
    }
    if (!_isLandscape(page)) {
      return _portraitTargetWidth;
    }
    if (aspectRatio(page) <= _landscapeAspectThreshold) {
      return prevPage != null ? _targetWidth(prevPage) : _portraitTargetWidth;
    }
    if (prevPage == null) {
      return _targetWidth(page);
    }
    final curWidth = page.width ?? 0;
    final prevLargerDim = math.max(prevPage.width ?? 0, prevPage.height ?? 0);
    if (curWidth > 0 &&
        prevLargerDim > 0 &&
        curWidth > prevLargerDim * _landscapeSizeRatio) {
      return _targetWidth(page);
    }
    return _targetWidth(prevPage);
  }

  static double displayWidth(
    bridge.PageInfo page,
    double zoom,
    double maxWidth, {
    bridge.PageInfo? prevPage,
    bool forcePortrait = false,
  }) {
    final target =
        _effectiveTargetWidth(page, prevPage, forcePortrait: forcePortrait) *
        zoom;
    return target.clamp(_minDisplayWidth, maxWidth);
  }

  static double displayHeight(
    bridge.PageInfo page,
    double zoom,
    double maxWidth, {
    bridge.PageInfo? prevPage,
    bool forcePortrait = false,
  }) {
    final width = displayWidth(
      page,
      zoom,
      maxWidth,
      prevPage: prevPage,
      forcePortrait: forcePortrait,
    );
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

/// Child delegate that reports the exact total scroll extent instead of
/// letting the framework extrapolate it from laid-out children.
///
/// `RenderSliverVariedExtentList` only lays out children near the viewport
/// and estimates the rest from their average, so `maxScrollExtent` wobbles
/// every frame while scrolling (visible as a jumping scrollbar thumb).
/// Our extents are pure math over Rust-provided tile heights, so the exact
/// total is cheap to precompute and always wins the `min()` in layout.
class _ExactTotalChildDelegate extends SliverChildBuilderDelegate {
  _ExactTotalChildDelegate(
    super.builder, {
    required this.exactTotal,
    super.childCount,
  });

  final double exactTotal;

  @override
  double? estimateMaxScrollOffset(
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) => exactTotal;
}

/// `SliverVariedExtentList` twin that accepts a custom child delegate.
/// Behavior (laziness, keep-alives, repaint boundaries, semantics) matches
/// `ListView.builder` defaults; only the extent estimation differs.
class _ExactTotalSliverList extends SliverMultiBoxAdaptorWidget {
  _ExactTotalSliverList({
    required NullableIndexedWidgetBuilder itemBuilder,
    required this.itemExtentBuilder,
    required this.exactTotal,
    required int itemCount,
  }) : super(
         delegate: _ExactTotalChildDelegate(
           itemBuilder,
           childCount: itemCount,
           exactTotal: exactTotal,
         ),
       );

  final ItemExtentBuilder itemExtentBuilder;
  final double exactTotal;

  @override
  RenderSliverVariedExtentList createRenderObject(BuildContext context) {
    final element = context as SliverMultiBoxAdaptorElement;
    return RenderSliverVariedExtentList(
      childManager: element,
      itemExtentBuilder: itemExtentBuilder,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSliverVariedExtentList renderObject,
  ) {
    renderObject.itemExtentBuilder = itemExtentBuilder;
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

  /// Floating top toolbar: 20 px inset + 56 px pill, plus a 2 px breath.
  static const double _topPadding = 78;

  /// Floating page bar: 56 px pill + 24 px inset.
  static const double _bottomChromeHeight = 80;
  late ScrollController _scroll;
  final _focusNode = FocusNode(debugLabel: 'ReaderPage');
  _TileLayout? _tileLayout;
  Timer? _progressTimer;
  Timer? _initialScrollTimer;
  int _currentPage = 0;
  int _lastSavedPage = -1;
  bool _ignoreNextScrollUpdate = false;
  bool _restoredProgress = false;
  bool _initialScrollDone = false;
  bool _fullscreen = false;
  bool _toolbarVisible = true;
  _ReaderPanel _openPanel = _ReaderPanel.none;
  // Overlay-only version counter (toolbar + page indicator). Bumped instead
  // of calling setState so scroll/page/toolbar updates don't rebuild the
  // page list, and overlay changes don't rebuild it either.
  final ValueNotifier<int> _overlayVersion = ValueNotifier(0);
  late final ComicRdApi _api;
  ReaderData? _lastReaderData;
  int? _lastReaderChapterId;
  Completer<void>? _prefetchQueue;
  int? _prefetchQueuedStart;
  int? _prefetchQueuedEnd;
  int _renderStart = 0;
  int _renderEnd = -1;
  int _readerGeneration = 0;
  final Set<int> _pageBookmarkedPages = {};

  @override
  void initState() {
    super.initState();
    _api = ref.read(comicRdApiProvider);
    _activeInstances++;
    // Sized for downscaled page variants (~3-12MB decoded each) so the
    // prefetch window survives without constant evict/re-decode churn.
    PaintingBinding.instance.imageCache.maximumSizeBytes = 128 * 1024 * 1024;
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
          pages: data.pages,
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
    _overlayVersion.dispose();
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
    _renderStart = 0;
    _renderEnd = -1;
    // Per-chapter state: the bookmark set must not leak into the new
    // chapter (the loader below only fetches when this is empty).
    _pageBookmarkedPages.clear();
    _toolbarVisible = true;
    _openPanel = _ReaderPanel.none;
    _refreshOverlay();
    final oldData = _lastReaderChapterId == oldWidget.chapterId
        ? _lastReaderData
        : null;
    if (_lastReaderChapterId == oldWidget.chapterId) {
      _lastReaderData = null;
      _lastReaderChapterId = null;
    }
    final oldChapterId = oldWidget.chapterId;
    final oldPages = oldData?.pages;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.invalidate(readerDataProvider(oldChapterId));
      if (oldPages != null) {
        _invalidateRenderedTiles(oldChapterId, oldPages);
      }
    });
    if (oldData != null) {
      unawaited(
        _releaseChapterMemory(
          chapterId: oldChapterId,
          pages: oldData.pages,
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
    final bookmarkedChapterPaths = comicPath.isEmpty
        ? const <String>[]
        : ref.watch(chapterBookmarksProvider(comicPath)).asData?.value ??
              const <String>[];
    final isBookmarked =
        chapterSourcePath.isNotEmpty &&
        bookmarkedChapterPaths.contains(chapterSourcePath);
    final isFavorited =
        ref.watch(comicFavoritedProvider(comicPath)).asData?.value ?? false;
    return KeyboardListener(
      autofocus: true,
      focusNode: _focusNode,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          _handleKey(event.logicalKey, reader.asData?.value);
        }
      },
      child: ColoredBox(
        color: context.appReader.canvas,
        child: reader.when(
          data: (data) {
            _lastReaderData = data;
            _lastReaderChapterId = widget.chapterId;
            _restoreProgress(data);
            if (_pageBookmarkedPages.isEmpty) {
              unawaited(_loadPageBookmarks(widget.chapterId));
            }
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
                Positioned.fill(
                  child: ValueListenableBuilder<int>(
                    valueListenable: _overlayVersion,
                    builder: (_, _, _) => Stack(
                      children: [
                        // Click-away target: an open panel closes when the
                        // pages behind it are tapped.
                        if (_openPanel != _ReaderPanel.none)
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: () => _setPanel(_ReaderPanel.none),
                            ),
                          ),
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: AnimatedSlide(
                            offset: _toolbarVisible
                                ? Offset.zero
                                : const Offset(0, -1),
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
                                  child: _ReaderTopBar(
                                    text: text,
                                    data: data,
                                    fullscreen: _fullscreen,
                                    openPanel: _openPanel,
                                    hasMarks:
                                        isBookmarked ||
                                        isFavorited ||
                                        _pageBookmarkedPages.contains(
                                          _currentPage,
                                        ),
                                    onClose: () => _close(data),
                                    onTogglePanel: _togglePanel,
                                    onToggleFullscreen: _toggleFullscreen,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (_toolbarVisible && _openPanel != _ReaderPanel.none)
                          Positioned(
                            top: 92,
                            right: 24,
                            child: MouseRegion(
                              onEnter: (_) => _showToolbar(),
                              child: _openPanel == _ReaderPanel.display
                                  ? _ReaderDisplayPanel(
                                      text: text,
                                      settings: readerSettings,
                                      onGapChanged: (gap) {
                                        ref
                                            .read(
                                              readerSettingsProvider.notifier,
                                            )
                                            .setPageGap(gap);
                                      },
                                      onZoomChanged: (zoom) {
                                        ref
                                            .read(
                                              readerSettingsProvider.notifier,
                                            )
                                            .setZoom(zoom);
                                      },
                                      onUnlimitedScrollChanged: (value) {
                                        ref
                                            .read(
                                              readerSettingsProvider.notifier,
                                            )
                                            .setUnlimitedScroll(value);
                                      },
                                      onUnlimitedScrollUpChanged: (value) {
                                        ref
                                            .read(
                                              readerSettingsProvider.notifier,
                                            )
                                            .setUnlimitedScrollUp(value);
                                      },
                                      onForcePortraitChanged: (value) {
                                        ref
                                            .read(
                                              readerSettingsProvider.notifier,
                                            )
                                            .setForcePortrait(value);
                                      },
                                    )
                                  : _ReaderMarkPanel(
                                      text: text,
                                      data: data,
                                      currentPage: _currentPage,
                                      isPageBookmarked: _pageBookmarkedPages
                                          .contains(_currentPage),
                                      isChapterBookmarked: isBookmarked,
                                      isFavorited: isFavorited,
                                      onTogglePageBookmark: _togglePageBookmark,
                                      onToggleChapterBookmark: () =>
                                          _toggleBookmark(
                                            chapterSourcePath,
                                            comicPath,
                                          ),
                                      onToggleFavorite: () =>
                                          _toggleFavorite(comicPath),
                                    ),
                            ),
                          ),
                        Positioned(
                          top: 20,
                          right: 24,
                          child: AnimatedOpacity(
                            opacity: _toolbarVisible ? 0 : 1,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            child: IgnorePointer(
                              ignoring: _toolbarVisible,
                              child: _ReaderGlass(
                                radius: 999,
                                child: _ReaderIconButton(
                                  tooltip: text.readerControls,
                                  icon: AppIcons.sliders,
                                  onPressed: _showToolbar,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          // Page bar stays visible while scrolling: only
                          // shrinks to its compact look instead of hiding
                          // with the toolbar.
                          child: MouseRegion(
                            onEnter: (_) => _showToolbar(),
                            child: _ReaderPageBar(
                              text: text,
                              currentPage: _currentPage,
                              pageCount: data.pages.length,
                              pageBookmarkedPages: _pageBookmarkedPages,
                              expanded: _toolbarVisible,
                              onSelected: _jumpToPage,
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
                            ),
                          ),
                        ),
                      ],
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
    // Flattened tile list: one sliver item per tile. The grid depends
    // only on Rust-provided tile_heights, never on zoom or display size.
    final tiles = data.tiles;
    final maxWidth = _ReaderPageLayout.maxDisplayWidth(context);
    // Exact total scroll extent (single source of truth with the per-item
    // builder below). Reported to the framework via _ExactTotalChildDelegate
    // so maxScrollExtent never wobbles from average-based estimation.
    final totalExtent = _totalTilesExtent(
      tiles,
      data.pages,
      readerSettings,
      maxWidth,
    );
    return widgets.RawScrollbar(
      controller: _scroll,
      thumbVisibility: true,
      trackVisibility: true,
      interactive: true,
      thickness: 12,
      radius: const Radius.circular(999),
      thumbColor: const Color(0xff5b5670),
      trackColor: const Color(0xff0e0d13),
      trackBorderColor: const Color(0xff0e0d13),
      child: CustomScrollView(
        controller: _scroll,
        scrollCacheExtent: const ScrollCacheExtent.pixels(1500),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.only(
              top: _topPadding,
              bottom: _bottomChromeHeight + readerSettings.pageGap,
            ),
            sliver: _ExactTotalSliverList(
              itemBuilder: (context, index) =>
                  _readerTileListItem(data, tiles, readerSettings, index),
              itemExtentBuilder: (index, _) => _tileExtentAt(
                tiles,
                data.pages,
                readerSettings,
                maxWidth,
                index,
              ),
              itemCount: tiles.length,
              exactTotal: totalExtent,
            ),
          ),
        ],
      ),
    );
  }

  /// Display extent of one tile item, or null beyond the list.
  /// Single source of truth shared by the item builder and the exact total.
  double? _tileExtentAt(
    List<TileItem> tiles,
    List<bridge.PageInfo> pages,
    ReaderSettings readerSettings,
    double maxWidth,
    int index,
  ) {
    if (index < 0 || index >= tiles.length) {
      return null;
    }
    return _layoutFor(
      tiles,
      pages,
      zoom: readerSettings.zoom,
      maxWidth: maxWidth,
      pageGap: readerSettings.pageGap,
      forcePortrait: readerSettings.forcePortrait,
    ).extents[index];
  }

  double _totalTilesExtent(
    List<TileItem> tiles,
    List<bridge.PageInfo> pages,
    ReaderSettings readerSettings,
    double maxWidth,
  ) {
    return _layoutFor(
      tiles,
      pages,
      zoom: readerSettings.zoom,
      maxWidth: maxWidth,
      pageGap: readerSettings.pageGap,
      forcePortrait: readerSettings.forcePortrait,
    ).totalExtent;
  }

  /// Prefix-summed geometry for the current tiles and layout inputs, built
  /// once and reused until any input changes (new chapter, zoom, window
  /// width, gap). Every per-scroll lookup goes through this instead of
  /// re-measuring all tiles.
  _TileLayout _layoutFor(
    List<TileItem> tiles,
    List<bridge.PageInfo> pages, {
    required double zoom,
    required double maxWidth,
    required double pageGap,
    required bool forcePortrait,
  }) {
    final cached = _tileLayout;
    if (cached != null &&
        cached.matches(tiles, zoom, maxWidth, pageGap, forcePortrait)) {
      return cached;
    }
    final tops = List<double>.filled(tiles.length, 0);
    final bottoms = List<double>.filled(tiles.length, 0);
    final extents = List<double>.filled(tiles.length, 0);
    var top = _topPadding;
    var total = _topPadding + _bottomChromeHeight + pageGap;
    for (var i = 0; i < tiles.length; i++) {
      final layout = _tilePages(pages, tiles[i]);
      final height = _tileDisplayHeight(
        tile: tiles[i],
        page: layout.page,
        zoom: zoom,
        maxWidth: maxWidth,
        prevPage: layout.prevPage,
        forcePortrait: forcePortrait,
      );
      final gap = _tileGap(tiles, i, pageGap);
      tops[i] = top;
      bottoms[i] = top + height;
      extents[i] = height + gap;
      total += height + gap;
      top = bottoms[i] + gap;
    }
    final built = _TileLayout(
      tiles: tiles,
      zoom: zoom,
      maxWidth: maxWidth,
      pageGap: pageGap,
      forcePortrait: forcePortrait,
      tops: tops,
      bottoms: bottoms,
      extents: extents,
      totalExtent: total,
    );
    _tileLayout = built;
    return built;
  }

  Widget _readerTileListItem(
    ReaderData data,
    List<TileItem> tiles,
    ReaderSettings readerSettings,
    int index,
  ) {
    final tile = tiles[index];
    final layout = _tilePages(data.pages, tile);
    return Padding(
      key: ValueKey('p${tile.pageIndex}t${tile.tileIndex}'),
      // Gap only between pages, never between tiles of one page (seams).
      padding: EdgeInsets.only(
        bottom: _tileGap(tiles, index, readerSettings.pageGap),
      ),
      child: _ReaderPageItem(
        chapterId: widget.chapterId,
        page: layout.page,
        tileIndex: tile.tileIndex,
        tilePixelHeight: tile.pixelHeight,
        zoom: readerSettings.zoom,
        prevPage: layout.prevPage,
        forcePortrait: readerSettings.forcePortrait,
      ),
    );
  }

  /// Page (+ previous page for landscape rules) owning a tile.
  /// `pageIndex` equals the page position (Rust enumerates in order).
  ({bridge.PageInfo page, bridge.PageInfo? prevPage}) _tilePages(
    List<bridge.PageInfo> pages,
    TileItem tile,
  ) {
    final pos = tile.pageIndex.clamp(0, pages.length - 1);
    return (page: pages[pos], prevPage: pos > 0 ? pages[pos - 1] : null);
  }

  /// Display gap after a tile: pageGap after the last tile of a page,
  /// zero between tiles of one page and after the final tile.
  double _tileGap(List<TileItem> tiles, int tilePos, double pageGap) {
    return tileGapAfter(tiles, tilePos, pageGap);
  }

  double _tileDisplayHeight({
    required TileItem tile,
    required bridge.PageInfo page,
    required double zoom,
    required double maxWidth,
    bridge.PageInfo? prevPage,
    bool forcePortrait = false,
  }) {
    final displayWidth = _ReaderPageLayout.displayWidth(
      page,
      zoom,
      maxWidth,
      prevPage: prevPage,
      forcePortrait: forcePortrait,
    );
    if (tile.pixelHeight <= 0) {
      // Unknown dimensions: fall back to whole-page aspect (old behavior).
      return _ReaderPageLayout.displayHeight(
        page,
        zoom,
        maxWidth,
        prevPage: prevPage,
        forcePortrait: forcePortrait,
      );
    }
    return tile.pixelHeight * displayWidth / fittedPageWidth(page);
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
    final tiles = data.tiles;
    _setRenderWindowAroundTile(_firstTileOfPage(tiles, page), tiles.length);
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
          _initialScrollDone = true;
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
    final tiles = data.tiles;
    final visibleRange = _visibleTileRange(
      tiles: tiles,
      pages: data.pages,
      zoom: settings.zoom,
      pageGap: settings.pageGap,
      forcePortrait: settings.forcePortrait,
    );

    // Check for next chapter (scroll to end)
    final nextChapterId = data.context?.nextChapterId;
    if (nextChapterId != null) {
      final isAtEnd = currentOffset >= maxExtent - viewportDimension * 0.1;
      if (isAtEnd &&
          tiles[visibleRange.last].pageIndex >= data.pages.length - 1) {
        _switchChapter(nextChapterId);
        return;
      }
    }

    // Check for previous chapter (scroll to beginning)
    final prevChapterId = data.context?.prevChapterId;
    if (prevChapterId != null && settings.unlimitedScrollUp) {
      final isAtStart = currentOffset <= viewportDimension * 0.1;
      if (isAtStart && tiles[visibleRange.first].pageIndex <= 0) {
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
    final tiles = data.tiles;
    if (tiles.isEmpty) {
      return;
    }
    final range = _visibleTileRange(
      tiles: tiles,
      pages: data.pages,
      zoom: settings.zoom,
      pageGap: settings.pageGap,
      forcePortrait: settings.forcePortrait,
    );
    final centerTile = _tileAtViewportCenter(
      tiles: tiles,
      pages: data.pages,
      zoom: settings.zoom,
      pageGap: settings.pageGap,
      forcePortrait: settings.forcePortrait,
    );
    final page = tiles[centerTile].pageIndex;
    final start = math.max(0, range.first - 2);
    final end = math.min(tiles.length - 1, range.last + 2);
    final pageChanged = page != _currentPage;
    final windowChanged = start != _renderStart || end != _renderEnd;
    if (!pageChanged && !windowChanged) {
      return;
    }
    _currentPage = page;
    _renderStart = start;
    _renderEnd = end;
    if (pageChanged) {
      _refreshOverlay();
    }
    if (pageChanged && persistProgress) {
      _scheduleProgressSave();
    }
    unawaited(_prefetchWindow(start, end));
  }

  int _tileAtViewportCenter({
    required List<TileItem> tiles,
    required List<bridge.PageInfo> pages,
    required double zoom,
    required double pageGap,
    bool forcePortrait = false,
  }) {
    if (!_scroll.hasClients || tiles.isEmpty) {
      return _firstTileOfPage(tiles, _currentPage);
    }
    final viewportCenter =
        _scroll.offset + _scroll.position.viewportDimension / 2;
    return _tileForOffset(
      tiles: tiles,
      pages: pages,
      zoom: zoom,
      pageGap: pageGap,
      offset: viewportCenter,
      forcePortrait: forcePortrait,
    );
  }

  ({int first, int last}) _visibleTileRange({
    required List<TileItem> tiles,
    required List<bridge.PageInfo> pages,
    required double zoom,
    required double pageGap,
    bool forcePortrait = false,
  }) {
    if (!_scroll.hasClients || tiles.isEmpty) {
      final tile = _firstTileOfPage(tiles, _currentPage);
      return (first: tile, last: tile);
    }
    final layout = _layoutFor(
      tiles,
      pages,
      zoom: zoom,
      maxWidth: _ReaderPageLayout.maxDisplayWidth(context),
      pageGap: pageGap,
      forcePortrait: forcePortrait,
    );
    final visibleTop = _scroll.offset;
    final visibleBottom = visibleTop + _scroll.position.viewportDimension;
    final range = layout.visibleRange(visibleTop, visibleBottom);
    if (range == null) {
      final tile = layout.tileForOffset(visibleTop);
      return (first: tile, last: tile);
    }
    return range;
  }

  int _tileForOffset({
    required List<TileItem> tiles,
    required List<bridge.PageInfo> pages,
    required double zoom,
    required double pageGap,
    required double offset,
    bool forcePortrait = false,
  }) {
    if (tiles.isEmpty) {
      return 0;
    }
    return _layoutFor(
      tiles,
      pages,
      zoom: zoom,
      maxWidth: _ReaderPageLayout.maxDisplayWidth(context),
      pageGap: pageGap,
      forcePortrait: forcePortrait,
    ).tileForOffset(offset);
  }

  /// First tile position of a page (binary search; pages are ordered).
  int _firstTileOfPage(List<TileItem> tiles, int page) {
    return firstTileOfPage(tiles, page);
  }

  void _setRenderWindowAroundTile(int tilePos, int tileCount) {
    if (tileCount <= 0) {
      _renderStart = 0;
      _renderEnd = -1;
      return;
    }
    _renderStart = math.max(0, tilePos - 2);
    _renderEnd = math.min(tileCount - 1, tilePos + 2);
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
    _lastSavedPage = _currentPage;
    final isRead = _currentPage >= data.pages.length - 1;
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
    ReaderSaveGuard.track(widget.chapterId, _currentPage, data.pages.length);
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
    ReaderSaveGuard.track(
      targetChapterId,
      _currentPage,
      targetData.pages.length,
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
        final tiles = data.tiles;
        if (tiles.isEmpty) {
          return;
        }
        final clampedStart = math.max(0, nextStart);
        final clampedEnd = math.min(tiles.length - 1, nextEnd);
        final windowTiles = [
          for (var index = clampedStart; index <= clampedEnd; index++)
            tiles[index],
        ];
        // evictChapterPages stays page-based; Rust drops all tiles of
        // pages outside the window.
        final keepPages = <int>{
          for (final tile in windowTiles) tile.pageIndex,
        }.toList()..sort();
        await api.evictChapterPages(chapterId: chapterId, keepPages: keepPages);
        if (!_isReaderCurrent(chapterId, generation)) {
          return;
        }
        await api.prefetchTiles(
          bridge.PrefetchTilesPayload(
            chapterId: chapterId,
            tiles: [
              for (final tile in windowTiles)
                bridge.PageTile(
                  pageIndex: tile.pageIndex,
                  tileIndex: tile.tileIndex,
                ),
            ],
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
      if (_openPanel != _ReaderPanel.none) {
        _setPanel(_ReaderPanel.none);
      } else if (_fullscreen) {
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
    await _releaseChapterMemory(chapterId: chapterId, pages: data.pages);
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

    // Update last opened chapter immediately so the comic page shows the
    // correct "continue reading" target even if the app is killed right after.
    final comicPath = data?.context?.comicSourcePath;
    if (comicPath != null && comicPath.isNotEmpty) {
      try {
        final newCtx = await _api.getChapterContext(chapterId);
        final newChapterPath = newCtx?.chapterSourcePath ?? '';
        if (newChapterPath.isNotEmpty) {
          ref
              .read(lastOpenedChapterProvider.notifier)
              .remember(comicPath, newChapterPath);
        }
      } catch (_) {
        // Non-critical: worst case the old chapter stays as "last opened".
      }
    }

    ref.invalidate(readerDataProvider(currentChapterId));
    await _releaseChapterMemory(
      chapterId: currentChapterId,
      pages: data?.pages,
    );
    if (mounted) {
      context.go('/reader/$chapterId');
    }
  }

  Future<void> _releaseChapterMemory({
    required int chapterId,
    required List<bridge.PageInfo>? pages,
    bool invalidateRenderedPages = true,
  }) async {
    _readerGeneration++;
    _initialScrollTimer?.cancel();
    _initialScrollTimer = null;
    _prefetchQueuedStart = null;
    _prefetchQueuedEnd = null;
    final pendingPrefetch = _prefetchQueue;
    if (invalidateRenderedPages && pages != null) {
      _invalidateRenderedTiles(chapterId, pages);
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

  void _invalidateRenderedTiles(int chapterId, List<bridge.PageInfo> pages) {
    for (final tile in flattenTiles(pages)) {
      ref.invalidate(
        renderedTileProvider(
          TileRequest(
            chapterId: chapterId,
            pageIndex: tile.pageIndex,
            tileIndex: tile.tileIndex,
          ),
        ),
      );
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
    final pages = data?.pages ?? const [];
    if (pages.isEmpty) {
      return;
    }
    final tiles = flattenTiles(pages);
    _setRenderWindowAroundTile(_firstTileOfPage(tiles, page), tiles.length);
    if (page != _currentPage) {
      _currentPage = page;
      _refreshOverlay();
    }
    if (persist) {
      _scheduleProgressSave();
    } else {
      _lastSavedPage = page;
    }
    unawaited(_prefetchWindow(_renderStart, _renderEnd));
    if (_scroll.hasClients) {
      final estimatedOffset = _scrollOffsetForPageIndex(page, pages);
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
    final tiles = flattenTiles(pages);
    final target = _firstTileOfPage(tiles, page.clamp(0, pages.length - 1));
    final maxWidth = _ReaderPageLayout.maxDisplayWidth(context);
    var offset = _topPadding;
    for (var i = 0; i < target; i++) {
      final layout = _tilePages(pages, tiles[i]);
      offset += _tileDisplayHeight(
        tile: tiles[i],
        page: layout.page,
        zoom: settings.zoom,
        maxWidth: maxWidth,
        prevPage: layout.prevPage,
        forcePortrait: settings.forcePortrait,
      );
      offset += _tileGap(tiles, i, settings.pageGap);
    }
    return offset.clamp(0, _scroll.position.maxScrollExtent).toDouble();
  }

  void _refreshOverlay() {
    if (!mounted) {
      return;
    }
    _overlayVersion.value++;
  }

  void _showToolbar() {
    if (_toolbarVisible || !mounted) {
      return;
    }
    _toolbarVisible = true;
    _refreshOverlay();
  }

  void _hideToolbar() {
    if (!_toolbarVisible || !mounted) {
      return;
    }
    _toolbarVisible = false;
    _openPanel = _ReaderPanel.none;
    _refreshOverlay();
  }

  void _setPanel(_ReaderPanel panel) {
    if (_openPanel == panel || !mounted) {
      return;
    }
    _openPanel = panel;
    _refreshOverlay();
  }

  void _togglePanel(_ReaderPanel panel) {
    _setPanel(_openPanel == panel ? _ReaderPanel.none : panel);
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
      _refreshOverlay();
    }
  }

  Future<void> _toggleBookmark(
    String chapterSourcePath,
    String comicSourcePath,
  ) async {
    if (chapterSourcePath.isEmpty || comicSourcePath.isEmpty) {
      return;
    }
    final api = ref.read(comicRdApiProvider);
    final chapterBookmarks =
        ref.read(chapterBookmarksProvider(comicSourcePath)).asData?.value ?? [];
    final isBookmarked = chapterBookmarks.contains(chapterSourcePath);
    if (isBookmarked) {
      await api.removeBookmark(chapterSourcePath: chapterSourcePath);
    } else {
      await api.addBookmark(
        chapterSourcePath: chapterSourcePath,
        comicSourcePath: comicSourcePath,
      );
    }
    ref.invalidate(chapterBookmarksProvider(comicSourcePath));
  }

  Future<void> _toggleFavorite(String comicPath) async {
    if (comicPath.isEmpty) return;
    final api = ref.read(comicRdApiProvider);
    final favorited =
        ref.read(comicFavoritedProvider(comicPath)).asData?.value ?? false;
    if (favorited) {
      await api.removeFavorite(comicSourcePath: comicPath);
    } else {
      await api.addFavorite(comicSourcePath: comicPath);
    }
    ref.invalidate(comicFavoritedProvider(comicPath));
    ref.invalidate(allFavoritesProvider);
  }

  Future<void> _loadPageBookmarks(int chapterId) async {
    try {
      final bookmarks = await _api.listPageBookmarks(chapterId: chapterId);
      if (!mounted) return;
      _pageBookmarkedPages
        ..clear()
        ..addAll(bookmarks.map((b) => b.page.toInt()));
      _refreshOverlay();
    } catch (_) {}
  }

  Future<void> _togglePageBookmark() async {
    final data = _lastReaderData;
    if (data == null || data.pages.isEmpty) return;
    final pageIndex = _currentPage;
    if (pageIndex < 0 || pageIndex >= data.pages.length) return;
    final chapterId = widget.chapterId;

    if (_pageBookmarkedPages.contains(pageIndex)) {
      // Find and remove the bookmark
      try {
        final bookmarks = await _api.listPageBookmarks(chapterId: chapterId);
        final match = bookmarks.where((b) => b.page.toInt() == pageIndex);
        if (match.isNotEmpty) {
          await _api.removePageBookmark(bookmarkId: match.first.id);
        }
      } catch (_) {}
      if (mounted) {
        _pageBookmarkedPages.remove(pageIndex);
        _refreshOverlay();
      }
    } else {
      try {
        await _api.addPageBookmark(
          bridge.SavePageBookmarkPayload(
            chapterId: chapterId,
            page: pageIndex,
            note: '',
          ),
        );
      } catch (_) {}
      if (mounted) {
        _pageBookmarkedPages.add(pageIndex);
        _refreshOverlay();
      }
    }
  }
}

/// Prefix-summed tile geometry for one (tiles, zoom, width, gap) state.
///
/// Built once in O(n); the lookups the scroll handler needs on every scroll
/// event (visible range, tile under an offset, item extents, total extent)
/// are then O(log n) or O(1) instead of a walk over every tile per event.
class _TileLayout {
  const _TileLayout({
    required this.tiles,
    required this.zoom,
    required this.maxWidth,
    required this.pageGap,
    required this.forcePortrait,
    required this.tops,
    required this.bottoms,
    required this.extents,
    required this.totalExtent,
  });

  final List<TileItem> tiles;
  final double zoom;
  final double maxWidth;
  final double pageGap;
  final bool forcePortrait;

  /// Top edge of each tile, including the reader's top padding.
  final List<double> tops;

  /// Bottom edge of each tile (top + display height, no gap).
  final List<double> bottoms;

  /// Sliver item extent of each tile: display height + the gap after it.
  final List<double> extents;
  final double totalExtent;

  bool matches(
    List<TileItem> tiles,
    double zoom,
    double maxWidth,
    double pageGap,
    bool forcePortrait,
  ) {
    return identical(this.tiles, tiles) &&
        this.zoom == zoom &&
        this.maxWidth == maxWidth &&
        this.pageGap == pageGap &&
        this.forcePortrait == forcePortrait;
  }

  /// Tiles overlapping [top, bottom], or null when none does (viewport
  /// entirely inside a gap or past the end).
  ({int first, int last})? visibleRange(double top, double bottom) {
    final first = lowerBoundIndex(bottoms, top);
    final last = upperBoundIndex(tops, bottom);
    if (first >= tiles.length || last < first) {
      return null;
    }
    return (first: first, last: last);
  }

  /// First tile whose bottom edge is at or below [offset], else the last.
  int tileForOffset(double offset) {
    final index = lowerBoundIndex(bottoms, offset);
    return index < tiles.length ? index : tiles.length - 1;
  }
}

class _ReaderPageItem extends ConsumerWidget {
  const _ReaderPageItem({
    required this.chapterId,
    required this.page,
    required this.tileIndex,
    required this.tilePixelHeight,
    required this.zoom,
    this.prevPage,
    this.forcePortrait = false,
  });

  final int chapterId;
  final bridge.PageInfo page;
  final int tileIndex;
  final int tilePixelHeight;
  final double zoom;
  final bridge.PageInfo? prevPage;
  final bool forcePortrait;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final maxWidth = _ReaderPageLayout.maxDisplayWidth(context);
    final displayWidth = _ReaderPageLayout.displayWidth(
      page,
      zoom,
      maxWidth,
      prevPage: prevPage,
      forcePortrait: forcePortrait,
    );
    final aspectRatio = tilePixelHeight > 0
        ? fittedPageWidth(page) / tilePixelHeight
        : _ReaderPageLayout.aspectRatio(page);
    final decodeWidth = decodeWidthFor(
      fittedWidth: fittedPageWidth(page),
      displayWidth: displayWidth,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    final rendered = ref.watch(
      renderedTileProvider(
        TileRequest(
          chapterId: chapterId,
          pageIndex: page.index,
          tileIndex: tileIndex,
        ),
      ),
    );
    return RepaintBoundary(
      child: rendered.when(
        data: (renderedPage) => Center(
          child: SizedBox(
            width: displayWidth,
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: Image.memory(
                renderedPage.bytes,
                // Decode at the size the tile is drawn at (zoom included):
                // a 2048px tile on a 1000px column is a quarter of the
                // decoded memory and a cheaper, DCT-scaled JPEG decode.
                // Texture and display scale match, so bilinear is enough
                // (no mipmap chain to build and hold).
                cacheWidth: decodeWidth,
                gaplessPlayback: true,
                filterQuality: FilterQuality.low,
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
      ),
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

// ---------------------------------------------------------------------------
// Reader chrome: floating glass pills over an always-dark canvas. The
// palette is fixed (it never follows the app theme) so pages keep the same
// surround in light and dark mode.
// ---------------------------------------------------------------------------

enum _ReaderPanel { none, display, mark }

const Color _chromeText = Color(0xFFF2EFFA);
const Color _chromeMuted = Color(0xFFB4AFC6);
const Color _chromeAccent = Color(0xFFA294FF);
const Color _chromeAccentInk = Color(0xFFCFC7FF);
const Color _chromeAccentSoft = Color(0x33A294FF);
const Color _chromeAmber = Color(0xFFFFC15A);
const Color _chromeAmberInk = Color(0xFF2A1D00);
const Color _chromeAmberSoft = Color(0x24FFC15A);
const Color _chromeAmberBox = Color(0x38FFC15A);
const Color _chromeGlass = Color(0xE0181620);
const Color _chromePanel = Color(0xF51C1926);
const Color _chromeLine = Color(0x17FFFFFF);
const Color _chromeFill = Color(0x14FFFFFF);
const Color _chromeTrack = Color(0x33FFFFFF);
const Color _chromeRing = Color(0x4DFFFFFF);

class _ReaderGlass extends StatelessWidget {
  const _ReaderGlass({
    required this.child,
    this.radius = 26,
    this.padding = EdgeInsets.zero,
    this.color = _chromeGlass,
    this.elevated = false,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color color;

  /// The deeper shadow used by the panels.
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    // NOTE: intentionally no BackdropFilter blur here. A fullscreen backdrop
    // blur is re-computed every frame while scrolling and saturates the GPU.
    // A more opaque fill keeps the same look for a fraction of the cost.
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: _chromeLine),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: elevated ? 0.75 : 0.6),
            blurRadius: elevated ? 70 : 40,
            spreadRadius: elevated ? -16 : -12,
            offset: Offset(0, elevated ? 28 : 16),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// A 44 px round icon button on glass.
class _ReaderIconButton extends StatefulWidget {
  const _ReaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.filled = false,
    this.active = false,
    this.iconSize = 18,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  /// Subtle white fill (back / chapter buttons).
  final bool filled;
  final bool active;
  final double iconSize;

  @override
  State<_ReaderIconButton> createState() => _ReaderIconButtonState();
}

class _ReaderIconButtonState extends State<_ReaderIconButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final Color background;
    if (widget.active) {
      background = _chromeAccentSoft;
    } else if (widget.filled) {
      background = _hovered && enabled ? const Color(0x24FFFFFF) : _chromeFill;
    } else {
      background = _hovered && enabled ? _chromeFill : Colors.transparent;
    }
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        child: FocusableActionDetector(
          enabled: enabled,
          mouseCursor: enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onShowHoverHighlight: (value) => setState(() => _hovered = value),
          onShowFocusHighlight: (value) => setState(() => _focused = value),
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onPressed?.call();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: background,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _focused ? _chromeAccent : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Icon(
                widget.icon,
                size: widget.iconSize,
                color: widget.active
                    ? _chromeAccentInk
                    : _chromeText.withValues(alpha: enabled ? 1 : 0.35),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 44 px labelled toggle on glass (the "Mark" / "Display" buttons).
class _ReaderTextButton extends StatefulWidget {
  const _ReaderTextButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.onPressed,
    this.showLabel = true,
    this.dot = false,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onPressed;
  final bool showLabel;

  /// Amber dot on the icon: something on this page is already marked.
  final bool dot;

  @override
  State<_ReaderTextButton> createState() => _ReaderTextButtonState();
}

class _ReaderTextButtonState extends State<_ReaderTextButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final fg = widget.active ? _chromeAccentInk : _chromeText;
    final icon = Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(widget.icon, size: 18, color: fg),
        if (widget.dot)
          Positioned(
            top: -3,
            right: -4,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: _chromeAmber,
                shape: BoxShape.circle,
                border: Border.all(color: _chromeGlass, width: 2),
              ),
            ),
          ),
      ],
    );
    final body = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      height: 44,
      padding: EdgeInsets.symmetric(horizontal: widget.showLabel ? 16 : 13),
      decoration: BoxDecoration(
        color: widget.active
            ? _chromeAccentSoft
            : _hovered
            ? _chromeFill
            : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _focused ? _chromeAccent : Colors.transparent,
          width: 2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          if (widget.showLabel) ...[
            const SizedBox(width: 8),
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ],
        ],
      ),
    );
    final pressable = Semantics(
      button: true,
      toggled: widget.active,
      label: widget.label,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: body,
        ),
      ),
    );
    if (widget.showLabel) return pressable;
    return Tooltip(message: widget.label, child: pressable);
  }
}

/// Top chrome: back + titles on the left, Mark / Display / fullscreen on the
/// right.
class _ReaderTopBar extends StatelessWidget {
  const _ReaderTopBar({
    required this.text,
    required this.data,
    required this.fullscreen,
    required this.openPanel,
    required this.hasMarks,
    required this.onClose,
    required this.onTogglePanel,
    required this.onToggleFullscreen,
  });

  final AppStrings text;
  final ReaderData data;
  final bool fullscreen;
  final _ReaderPanel openPanel;
  final bool hasMarks;
  final VoidCallback onClose;
  final ValueChanged<_ReaderPanel> onTogglePanel;
  final VoidCallback onToggleFullscreen;

  @override
  Widget build(BuildContext context) {
    final contextData = data.context;
    final subtitle = contextData != null
        ? '${contextData.title} (${contextData.chapterPosition}/${contextData.chapterTotal})'
        : text.chapter;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showLabels = constraints.maxWidth >= 760;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 540),
                  child: _ReaderGlass(
                    padding: const EdgeInsets.fromLTRB(6, 6, 22, 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ReaderIconButton(
                          tooltip: text.close,
                          icon: AppIcons.chevronLeft,
                          iconSize: 20,
                          filled: true,
                          onPressed: onClose,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                contextData?.comicTitle ?? text.appName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _chromeText,
                                  fontSize: 14,
                                  height: 20 / 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _chromeMuted,
                                  fontSize: 12.5,
                                  height: 18 / 12.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              _ReaderGlass(
                padding: const EdgeInsets.all(6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ReaderTextButton(
                      label: text.markPanel,
                      icon: AppIcons.bookmark,
                      active: openPanel == _ReaderPanel.mark,
                      showLabel: showLabels,
                      dot: hasMarks,
                      onPressed: () => onTogglePanel(_ReaderPanel.mark),
                    ),
                    const SizedBox(width: 4),
                    _ReaderTextButton(
                      label: text.displayPanel,
                      icon: AppIcons.sliders,
                      active: openPanel == _ReaderPanel.display,
                      showLabel: showLabels,
                      onPressed: () => onTogglePanel(_ReaderPanel.display),
                    ),
                    Container(
                      width: 1,
                      height: 24,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      color: const Color(0x24FFFFFF),
                    ),
                    _ReaderIconButton(
                      tooltip: text.fullscreen,
                      icon: fullscreen ? AppIcons.minimize : AppIcons.maximize,
                      active: fullscreen,
                      onPressed: onToggleFullscreen,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The "Display" panel: zoom, page gap, scroll behaviour, key hints.
class _ReaderDisplayPanel extends StatelessWidget {
  const _ReaderDisplayPanel({
    required this.text,
    required this.settings,
    required this.onZoomChanged,
    required this.onGapChanged,
    required this.onUnlimitedScrollChanged,
    required this.onUnlimitedScrollUpChanged,
    required this.onForcePortraitChanged,
  });

  final AppStrings text;
  final ReaderSettings settings;
  final ValueChanged<double> onZoomChanged;
  final ValueChanged<double> onGapChanged;
  final ValueChanged<bool> onUnlimitedScrollChanged;
  final ValueChanged<bool> onUnlimitedScrollUpChanged;
  final ValueChanged<bool> onForcePortraitChanged;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width - 48;
    return _ReaderGlass(
      radius: 28,
      color: _chromePanel,
      elevated: true,
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        width: math.min(356, maxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text.displayPanel, style: _panelTitleStyle),
            const SizedBox(height: 14),
            _ReaderSlider(
              label: text.zoom,
              valueLabel: '${(settings.zoom * 100).round()}%',
              value: settings.zoom,
              min: 0.2,
              max: 1.5,
              divisions: 26,
              onChanged: (value) => onZoomChanged((value * 20).round() / 20),
            ),
            _ReaderSlider(
              label: text.pageGap,
              valueLabel: '${settings.pageGap.round()} px',
              value: settings.pageGap,
              min: 0,
              max: 80,
              divisions: 16,
              onChanged: (value) => onGapChanged((value / 5).round() * 5),
            ),
            const _PanelDivider(),
            _ReaderSwitchRow(
              title: text.unlimitedScroll,
              description: text.unlimitedScrollDescription,
              value: settings.unlimitedScroll,
              onChanged: onUnlimitedScrollChanged,
            ),
            _ReaderSwitchRow(
              title: text.unlimitedScrollUp,
              description: text.unlimitedScrollUpDescription,
              value: settings.unlimitedScrollUp,
              onChanged: onUnlimitedScrollUpChanged,
            ),
            _ReaderSwitchRow(
              title: text.forcePortrait,
              description: text.forcePortraitDescription,
              value: settings.forcePortrait,
              onChanged: onForcePortraitChanged,
            ),
            const _PanelDivider(),
            Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                _KeyHint(keys: 'Esc', label: text.keyExit),
                _KeyHint(keys: '↑ ↓', label: text.keyScroll),
                _KeyHint(keys: '← →', label: text.keySwitchChapter),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

const TextStyle _panelTitleStyle = TextStyle(
  color: _chromeText,
  fontSize: 16,
  height: 24 / 16,
  fontWeight: FontWeight.w800,
  letterSpacing: -0.16,
);

class _PanelDivider extends StatelessWidget {
  const _PanelDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 14),
      color: _chromeLine,
    );
  }
}

class _ReaderSlider extends StatelessWidget {
  const _ReaderSlider({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: _chromeText,
                  fontSize: 14,
                  height: 22 / 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              valueLabel,
              style: const TextStyle(
                color: _chromeMuted,
                fontSize: 14,
                height: 22 / 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Material(
          type: MaterialType.transparency,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 6,
              activeTrackColor: _chromeAccent,
              inactiveTrackColor: _chromeTrack,
              thumbColor: _chromeText,
              overlayColor: _chromeAccent.withValues(alpha: 0.24),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              activeTickMarkColor: Colors.transparent,
              inactiveTickMarkColor: Colors.transparent,
              trackShape: const RoundedRectSliderTrackShape(),
            ),
            child: SizedBox(
              height: 44,
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                divisions: divisions,
                label: valueLabel,
                semanticFormatterCallback: (_) => '$label $valueLabel',
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReaderSwitchRow extends StatelessWidget {
  const _ReaderSwitchRow({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: title,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(!value),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: _chromeText,
                          fontSize: 14,
                          height: 22 / 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        description,
                        style: const TextStyle(
                          color: _chromeMuted,
                          fontSize: 12.5,
                          height: 18 / 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _ReaderSwitch(value: value),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The 48×28 toggle drawn on glass (the row above handles the tap).
class _ReaderSwitch extends StatelessWidget {
  const _ReaderSwitch({required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        width: 48,
        height: 28,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? _chromeAccent : _chromeTrack,
          borderRadius: BorderRadius.circular(999),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: value ? const Color(0xFF1A1530) : _chromeText,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class _KeyHint extends StatelessWidget {
  const _KeyHint({required this.keys, required this.label});

  final String keys;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          decoration: BoxDecoration(
            color: const Color(0x1AFFFFFF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            keys,
            style: const TextStyle(
              color: _chromeText,
              fontSize: 12,
              height: 18 / 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: _chromeMuted,
            fontSize: 12.5,
            height: 20 / 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// The "Mark" panel: page bookmark, chapter bookmark, favorite.
class _ReaderMarkPanel extends StatelessWidget {
  const _ReaderMarkPanel({
    required this.text,
    required this.data,
    required this.currentPage,
    required this.isPageBookmarked,
    required this.isChapterBookmarked,
    required this.isFavorited,
    required this.onTogglePageBookmark,
    required this.onToggleChapterBookmark,
    required this.onToggleFavorite,
  });

  final AppStrings text;
  final ReaderData data;
  final int currentPage;
  final bool isPageBookmarked;
  final bool isChapterBookmarked;
  final bool isFavorited;
  final VoidCallback onTogglePageBookmark;
  final VoidCallback onToggleChapterBookmark;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width - 48;
    final page = '${currentPage + 1}';
    final total = '${data.pages.length}';
    final chapterTitle = data.context?.title ?? text.chapter;
    final comicTitle = data.context?.comicTitle ?? text.comic;
    return _ReaderGlass(
      radius: 28,
      color: _chromePanel,
      elevated: true,
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        width: math.min(372, maxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(child: Text(text.markPanel, style: _panelTitleStyle)),
                Text(
                  text.pageOfTemplate
                      .replaceAll('{page}', page)
                      .replaceAll('{total}', total),
                  style: const TextStyle(
                    color: _chromeMuted,
                    fontSize: 12.5,
                    height: 18 / 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _MarkRow(
              icon: AppIcons.bookmark,
              title: isPageBookmarked
                  ? text.removePageBookmark
                  : text.addPageBookmark,
              subtitle:
                  (isPageBookmarked
                          ? text.pageBookmarkedTemplate
                          : text.pageNotBookmarkedTemplate)
                      .replaceAll('{page}', page),
              active: isPageBookmarked,
              onPressed: onTogglePageBookmark,
            ),
            const SizedBox(height: 6),
            _MarkRow(
              icon: AppIcons.folderBookmark,
              title: isChapterBookmarked
                  ? text.removeBookmark
                  : text.addBookmark,
              subtitle:
                  (isChapterBookmarked
                          ? text.chapterBookmarkedTemplate
                          : text.chapterNotBookmarkedTemplate)
                      .replaceAll('{chapter}', chapterTitle),
              active: isChapterBookmarked,
              onPressed: onToggleChapterBookmark,
            ),
            const SizedBox(height: 6),
            _MarkRow(
              icon: AppIcons.star,
              title: isFavorited ? text.removeFavorite : text.addFavorite,
              subtitle:
                  (isFavorited
                          ? text.inFavoritesTemplate
                          : text.notInFavoritesTemplate)
                      .replaceAll('{comic}', comicTitle),
              active: isFavorited,
              onPressed: onToggleFavorite,
            ),
          ],
        ),
      ),
    );
  }
}

class _MarkRow extends StatefulWidget {
  const _MarkRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.active,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool active;
  final VoidCallback onPressed;

  @override
  State<_MarkRow> createState() => _MarkRowState();
}

class _MarkRowState extends State<_MarkRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    return Semantics(
      button: true,
      toggled: active,
      label: '${widget.title}. ${widget.subtitle}',
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 68),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: active
                  ? _chromeAmberSoft
                  : _hovered
                  ? _chromeFill
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _focused ? _chromeAccent : Colors.transparent,
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: active ? _chromeAmberBox : _chromeFill,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    widget.icon,
                    size: 20,
                    color: active ? _chromeAmber : _chromeText,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _chromeText,
                          fontSize: 14,
                          height: 22 / 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _chromeMuted,
                          fontSize: 12.5,
                          height: 18 / 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: active ? _chromeAmber : Colors.transparent,
                    shape: BoxShape.circle,
                    border: active
                        ? null
                        : Border.all(color: _chromeRing, width: 2),
                  ),
                  child: active
                      ? const Icon(
                          AppIcons.check,
                          size: 16,
                          color: _chromeAmberInk,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom chrome: chapter / page buttons around the segmented page track.
/// Collapses to the bare track while the toolbar is hidden.
class _ReaderPageBar extends StatefulWidget {
  const _ReaderPageBar({
    required this.text,
    required this.currentPage,
    required this.pageCount,
    required this.pageBookmarkedPages,
    required this.expanded,
    required this.onSelected,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.onPreviousChapter,
    required this.onNextChapter,
  });

  final AppStrings text;
  final int currentPage;
  final int pageCount;
  final Set<int> pageBookmarkedPages;
  final bool expanded;
  final ValueChanged<int> onSelected;
  final VoidCallback onPreviousPage;
  final VoidCallback onNextPage;
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;

  @override
  State<_ReaderPageBar> createState() => _ReaderPageBarState();
}

class _ReaderPageBarState extends State<_ReaderPageBar> {
  int? _hoveredPage;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final count = math.max(1, widget.pageCount);
    final current = widget.currentPage.clamp(0, count - 1);
    final expanded = widget.expanded;
    const numberStyle = TextStyle(
      color: _chromeText,
      fontSize: 14,
      fontWeight: FontWeight.w800,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    final track = _buildTrack(count, current, expanded);
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, expanded ? 24 : 16),
      child: Center(
        child: AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: expanded ? 680 : 420),
            child: _ReaderGlass(
              radius: expanded ? 26 : 14,
              padding: EdgeInsets.all(expanded ? 6 : 4),
              child: expanded
                  ? Row(
                      children: [
                        _ReaderIconButton(
                          tooltip: text.previousChapter,
                          icon: AppIcons.chevronsLeft,
                          filled: true,
                          onPressed: widget.onPreviousChapter,
                        ),
                        const SizedBox(width: 2),
                        _ReaderIconButton(
                          tooltip: text.previousPage,
                          icon: AppIcons.chevronLeft,
                          onPressed: widget.onPreviousPage,
                        ),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 24),
                          child: Text(
                            '${current + 1}',
                            textAlign: TextAlign.right,
                            style: numberStyle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: track),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 24),
                          child: Text(
                            '$count',
                            style: numberStyle.copyWith(
                              color: _chromeMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _ReaderIconButton(
                          tooltip: text.nextPage,
                          icon: AppIcons.chevronRight,
                          onPressed: widget.onNextPage,
                        ),
                        const SizedBox(width: 2),
                        _ReaderIconButton(
                          tooltip: text.nextChapter,
                          icon: AppIcons.chevronsRight,
                          filled: true,
                          onPressed: widget.onNextChapter,
                        ),
                      ],
                    )
                  : track,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrack(int count, int current, bool expanded) {
    final hoveredPage = (_hoveredPage ?? current).clamp(0, count - 1);
    String pageLabel(int page) => widget.text.pageOfTemplate
        .replaceAll('{page}', '${page + 1}')
        .replaceAll('{total}', '$count');
    return SizedBox(
      height: expanded ? 44 : 20,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Semantics(
            slider: true,
            value: pageLabel(current),
            increasedValue: pageLabel(math.min(current + 1, count - 1)),
            decreasedValue: pageLabel(math.max(current - 1, 0)),
            onIncrease: widget.onNextPage,
            onDecrease: widget.onPreviousPage,
            child: FocusableActionDetector(
              onShowFocusHighlight: (value) => setState(() => _focused = value),
              mouseCursor: SystemMouseCursors.click,
              shortcuts: const <ShortcutActivator, Intent>{
                SingleActivator(LogicalKeyboardKey.arrowRight): _PageStepIntent(
                  1,
                ),
                SingleActivator(LogicalKeyboardKey.arrowLeft): _PageStepIntent(
                  -1,
                ),
              },
              actions: <Type, Action<Intent>>{
                _PageStepIntent: CallbackAction<_PageStepIntent>(
                  onInvoke: (intent) {
                    if (intent.delta > 0) {
                      widget.onNextPage();
                    } else {
                      widget.onPreviousPage();
                    }
                    return null;
                  },
                ),
              },
              child: MouseRegion(
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
                onExit: (_) => setState(() => _hoveredPage = null),
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
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _focused
                                  ? _chromeAccent
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: CustomPaint(
                            painter: _PageIndicatorPainter(
                              current: current,
                              pageCount: count,
                              hovered: expanded,
                              pageBookmarkedPages: widget.pageBookmarkedPages,
                            ),
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
                          top: -(_PageIndicatorTooltip.height + 8),
                          child: _PageIndicatorTooltip(
                            label: '${hoveredPage + 1}',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
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

class _PageStepIntent extends Intent {
  const _PageStepIntent(this.delta);

  final int delta;
}

class _PageIndicatorTooltip extends StatelessWidget {
  const _PageIndicatorTooltip({required this.label});

  static const double width = 40;
  static const double height = 22;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xff222831),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _chromeLine),
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
        height: height,
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: const TextStyle(
              color: _chromeText,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// One segment per page: read pages in accent, bookmarked pages amber and
/// taller (so they read without relying on hue), the current page ringed.
class _PageIndicatorPainter extends CustomPainter {
  _PageIndicatorPainter({
    required this.current,
    required this.pageCount,
    required this.hovered,
    required this.pageBookmarkedPages,
  });

  final int current;
  final int pageCount;
  final bool hovered;
  final Set<int> pageBookmarkedPages;

  @override
  void paint(Canvas canvas, Size size) {
    if (pageCount <= 0) return;
    final segmentWidth = size.width / pageCount;
    final barHeight = hovered ? 8.0 : 4.0;
    final markedHeight = hovered ? 18.0 : 8.0;
    final gap = math.min(hovered ? 1.0 : 0.5, segmentWidth * 0.2);
    final filledPaint = Paint()..color = _chromeAccent;
    final emptyPaint = Paint()..color = _chromeTrack;
    final bookmarkPaint = Paint()..color = _chromeAmber;
    final ringPaint = Paint()
      ..color = _chromeText
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    const radius = Radius.circular(99);

    for (var i = 0; i < pageCount; i++) {
      final left = i * segmentWidth + gap;
      final right = (i + 1) * segmentWidth - gap;
      if (right <= left) continue;
      final marked = pageBookmarkedPages.contains(i);
      final height = marked ? markedHeight : barHeight;
      final top = (size.height - height) / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTRB(left, top, right, top + height),
        radius,
      );
      if (marked) {
        canvas.drawRRect(rect, bookmarkPaint);
      } else {
        canvas.drawRRect(rect, i <= current ? filledPaint : emptyPaint);
      }
      if (i == current && hovered) {
        canvas.drawRRect(rect.inflate(1.5), ringPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_PageIndicatorPainter oldDelegate) {
    return oldDelegate.current != current ||
        oldDelegate.pageCount != pageCount ||
        oldDelegate.hovered != hovered ||
        oldDelegate.pageBookmarkedPages != pageBookmarkedPages;
  }
}
