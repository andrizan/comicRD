import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart'
    show ItemExtentBuilder, RenderSliverVariedExtentList, ScrollCacheExtent;
import 'package:flutter/services.dart';
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
    super.findChildIndexCallback,
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
    ChildIndexGetter? findChildIndex,
  }) : super(
         delegate: _ExactTotalChildDelegate(
           itemBuilder,
           childCount: itemCount,
           exactTotal: exactTotal,
           findChildIndexCallback: findChildIndex,
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

/// A slice of one chapter's tiles, as chapter-local tile indices.
typedef _WindowSegment = ({int chapterId, int start, int end});

class _ReaderPageState extends ConsumerState<ReaderPage> {
  static int _activeInstances = 0;

  /// Floating top toolbar: 20 px inset + 56 px pill, plus a 2 px breath.
  static const double _topPadding = 78;

  /// Floating page bar: 56 px pill + 24 px inset.
  static const double _bottomChromeHeight = 80;

  /// The "finished / next chapter" header drawn above the first page of every
  /// chapter that follows another one in the strip.
  static const double _transitionExtent = 168;

  /// A neighbouring chapter starts loading once the viewport is this many
  /// viewport heights from that end of the strip.
  static const double _preloadViewports = 3;

  late ScrollController _scroll;
  final _focusNode = FocusNode(debugLabel: 'ReaderPage');
  _TileLayout? _tileLayout;
  Timer? _progressTimer;
  Timer? _initialScrollTimer;

  /// The chapters chained into the scroll view. Null until the opened chapter
  /// has loaded; with unlimited scroll off it only ever holds that chapter.
  ReaderStrip? _strip;

  /// Slot (in [_strip]) of the chapter being read, and the page within it.
  int _activeSlot = 0;
  int _currentPage = 0;

  /// Last page persisted per chapter, so a repeat is not written twice.
  final Map<int, int> _savedPages = {};
  final Map<int, Set<int>> _pageMarks = {};
  final Set<int> _loadingMarks = {};

  /// Keeps the provider of a chained chapter (other than the opened one,
  /// which `build` watches) alive for as long as it is in the strip.
  final Map<int, ProviderSubscription<AsyncValue<ReaderData>>> _chapterHolds =
      {};
  final Set<int> _loadingChapters = {};
  final Set<int> _failedChapters = {};

  /// Chapters whose raw pages were already released because the window left
  /// them, so the eviction is not repeated on every scroll event.
  final Set<int> _idleChapters = {};
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
  Completer<void>? _prefetchQueue;
  List<_WindowSegment>? _prefetchQueued;

  /// Prefetch window as strip-wide tile indices (`_renderEnd < _renderStart`
  /// means none yet).
  int _renderStart = 0;
  int _renderEnd = -1;
  int _readerGeneration = 0;

  StripChapter? get _activeChapter {
    final strip = _strip;
    if (strip == null || strip.chapters.isEmpty) {
      return null;
    }
    return strip.chapters[_activeSlot.clamp(0, strip.chapters.length - 1)];
  }

  Set<int> get _activeMarks {
    final chapter = _activeChapter;
    return chapter == null
        ? const <int>{}
        : _pageMarks[chapter.chapterId] ?? const <int>{};
  }

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
    final strip = _strip;
    final active = _activeChapter;
    if (active != null) {
      unawaited(_saveProgressDirect(active));
    }
    if (strip != null) {
      unawaited(_releaseStripMemory(strip, invalidateRenderedPages: false));
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
    _readerGeneration++;
    _activeSlot = 0;
    _currentPage = 0;
    _ignoreNextScrollUpdate = false;
    _restoredProgress = false;
    _initialScrollDone = false;
    _renderStart = 0;
    _renderEnd = -1;
    // Per-chapter state must not leak into the new chapter.
    _savedPages.clear();
    _pageMarks.clear();
    _loadingMarks.clear();
    _loadingChapters.clear();
    _failedChapters.clear();
    _idleChapters.clear();
    _toolbarVisible = true;
    _openPanel = _ReaderPanel.none;
    _refreshOverlay();
    final oldStrip = _strip;
    _strip = null;
    final oldChapters = oldStrip?.chapters ?? const <StripChapter>[];
    final oldIds = oldStrip == null
        ? [oldWidget.chapterId]
        : [for (final chapter in oldChapters) chapter.chapterId];
    _closeHolds();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      for (final id in oldIds) {
        ref.invalidate(readerDataProvider(id));
      }
      for (final chapter in oldChapters) {
        _invalidateRenderedTiles(chapter.chapterId, chapter.data.pages);
      }
    });
    if (oldStrip != null) {
      unawaited(_releaseStripMemory(oldStrip, invalidateRenderedPages: false));
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
    // One comic per strip, so the opened chapter names it for every slot.
    final comicPath = reader.asData?.value.context?.comicSourcePath ?? '';
    final bookmarkedChapterPaths = comicPath.isEmpty
        ? const <String>[]
        : ref.watch(chapterBookmarksProvider(comicPath)).asData?.value ??
              const <String>[];
    final isFavorited =
        ref.watch(comicFavoritedProvider(comicPath)).asData?.value ?? false;
    return KeyboardListener(
      autofocus: true,
      focusNode: _focusNode,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          _handleKey(
            event.logicalKey,
            _activeChapter?.data ?? reader.asData?.value,
          );
        }
      },
      child: ColoredBox(
        color: context.appReader.canvas,
        child: reader.when(
          data: (data) {
            final strip = _ensureStrip(data);
            _restoreProgress(data);
            if (!_pageMarks.containsKey(widget.chapterId)) {
              unawaited(_loadPageMarks(widget.chapterId));
            }
            return Stack(
              children: [
                Positioned.fill(
                  child: _readerScrollView(strip: strip, text: text),
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
                    builder: (_, _, _) {
                      // The chapter in view changes as the strip scrolls, so
                      // everything that names it is read here, not in build.
                      final activeData = _activeChapter?.data ?? data;
                      final chapterSourcePath =
                          activeData.context?.chapterSourcePath ?? '';
                      final isBookmarked =
                          chapterSourcePath.isNotEmpty &&
                          bookmarkedChapterPaths.contains(chapterSourcePath);
                      return Stack(
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
                                      data: activeData,
                                      fullscreen: _fullscreen,
                                      openPanel: _openPanel,
                                      hasMarks:
                                          isBookmarked ||
                                          isFavorited ||
                                          _activeMarks.contains(_currentPage),
                                      onClose: () => _close(activeData),
                                      onTogglePanel: _togglePanel,
                                      onToggleFullscreen: _toggleFullscreen,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (_toolbarVisible &&
                              _openPanel != _ReaderPanel.none)
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
                                        data: activeData,
                                        currentPage: _currentPage,
                                        isPageBookmarked: _activeMarks.contains(
                                          _currentPage,
                                        ),
                                        isChapterBookmarked: isBookmarked,
                                        isFavorited: isFavorited,
                                        onTogglePageBookmark:
                                            _togglePageBookmark,
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
                                pageCount: activeData.pages.length,
                                pageBookmarkedPages: _activeMarks,
                                expanded: _toolbarVisible,
                                onSelected: _jumpToPage,
                                onPreviousPage: () => _jumpBy(-1),
                                onNextPage: () => _jumpBy(1),
                                onPreviousChapter:
                                    activeData.context?.prevChapterId == null
                                    ? null
                                    : () => _switchChapter(
                                        activeData.context!.prevChapterId!,
                                      ),
                                onNextChapter:
                                    activeData.context?.nextChapterId == null
                                    ? null
                                    : () => _switchChapter(
                                        activeData.context!.nextChapterId!,
                                      ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
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

  /// The strip always starts as the chapter the route opened.
  ReaderStrip _ensureStrip(ReaderData data) {
    final existing = _strip;
    if (existing != null) {
      return existing;
    }
    final strip = ReaderStrip([StripChapter(widget.chapterId, data)]);
    _strip = strip;
    _activeSlot = 0;
    return strip;
  }

  Widget _readerScrollView({
    required ReaderStrip strip,
    required AppStrings text,
  }) {
    if (strip.tileCount == 0) {
      return Align(
        alignment: Alignment.center,
        child: Text(text.noPages, style: const TextStyle(color: Colors.white)),
      );
    }
    final readerSettings = ref.watch(readerSettingsProvider);
    final maxWidth = _ReaderPageLayout.maxDisplayWidth(context);
    // Exact total scroll extent (single source of truth with the per-item
    // builder below). Reported to the framework via _ExactTotalChildDelegate
    // so maxScrollExtent never wobbles from average-based estimation.
    final layout = _layoutFor(
      strip,
      zoom: readerSettings.zoom,
      maxWidth: maxWidth,
      pageGap: readerSettings.pageGap,
      forcePortrait: readerSettings.forcePortrait,
    );
    return Stack(
      children: [
        Positioned.fill(
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
                      _readerTileListItem(strip, readerSettings, index, text),
                  itemExtentBuilder: (index, _) =>
                      index < 0 || index >= strip.tileCount
                      ? null
                      : layout.extents[index],
                  findChildIndex: (key) => _indexOfItemKey(strip, key),
                  itemCount: strip.tileCount,
                  exactTotal: layout.totalExtent,
                ),
              ),
            ],
          ),
        ),
        // Scoped to the chapter in view, so it starts over with each chapter
        // the way a scrollbar over a single chapter would.
        Positioned(
          top: 0,
          right: 0,
          bottom: 0,
          width: _ChapterScrollbar.width,
          child: _ChapterScrollbar(controller: _scroll, layout: layout),
        ),
      ],
    );
  }

  /// Strip-wide index of the item a [ValueKey] (chapter, page, tile) names,
  /// so items keep their state when a chapter is prepended above them.
  int? _indexOfItemKey(ReaderStrip strip, Key key) {
    if (key is! ValueKey<(int, int, int)>) {
      return null;
    }
    final (chapterId, page, tile) = key.value;
    final slot = strip.slotOfChapter(chapterId);
    if (slot < 0) {
      return null;
    }
    final tiles = strip.chapters[slot].data.tiles;
    final local = firstTileOfPage(tiles, page) + tile;
    return local < tiles.length ? strip.globalTile(slot, local) : null;
  }

  /// Prefix-summed geometry for the current strip and layout inputs, built
  /// once and reused until any input changes (a chapter joins the strip,
  /// zoom, window width, gap). Every per-scroll lookup goes through this
  /// instead of re-measuring all tiles.
  _TileLayout _layoutFor(
    ReaderStrip strip, {
    required double zoom,
    required double maxWidth,
    required double pageGap,
    required bool forcePortrait,
  }) {
    final cached = _tileLayout;
    if (cached != null &&
        cached.matches(strip, zoom, maxWidth, pageGap, forcePortrait)) {
      return cached;
    }
    final count = strip.tileCount;
    final tops = List<double>.filled(count, 0);
    final contentTops = List<double>.filled(count, 0);
    final bottoms = List<double>.filled(count, 0);
    final extents = List<double>.filled(count, 0);
    var top = _topPadding;
    var total = _topPadding + _bottomChromeHeight + pageGap;
    var index = 0;
    for (var slot = 0; slot < strip.chapters.length; slot++) {
      final data = strip.chapters[slot].data;
      for (var local = 0; local < data.tiles.length; local++, index++) {
        final tile = data.tiles[local];
        final layout = _tilePages(data.pages, tile);
        // The first page of a chapter that follows another carries the
        // "finished / next" header above it.
        final header = slot > 0 && local == 0 ? _transitionExtent : 0.0;
        final height = _tileDisplayHeight(
          tile: tile,
          page: layout.page,
          zoom: zoom,
          maxWidth: maxWidth,
          prevPage: layout.prevPage,
          forcePortrait: forcePortrait,
        );
        final gap = _tileGap(data.tiles, local, pageGap);
        tops[index] = top;
        contentTops[index] = top + header;
        bottoms[index] = top + header + height;
        extents[index] = header + height + gap;
        total += header + height + gap;
        top = bottoms[index] + gap;
      }
    }
    final built = _TileLayout(
      strip: strip,
      zoom: zoom,
      maxWidth: maxWidth,
      pageGap: pageGap,
      forcePortrait: forcePortrait,
      tops: tops,
      contentTops: contentTops,
      bottoms: bottoms,
      extents: extents,
      totalExtent: total,
    );
    _tileLayout = built;
    return built;
  }

  _TileLayout _currentLayout(ReaderStrip strip) {
    final settings = ref.read(readerSettingsProvider);
    return _layoutFor(
      strip,
      zoom: settings.zoom,
      maxWidth: _ReaderPageLayout.maxDisplayWidth(context),
      pageGap: settings.pageGap,
      forcePortrait: settings.forcePortrait,
    );
  }

  Widget _readerTileListItem(
    ReaderStrip strip,
    ReaderSettings readerSettings,
    int index,
    AppStrings text,
  ) {
    final at = strip.locate(index);
    final chapter = strip.chapters[at.slot];
    final data = chapter.data;
    final tile = data.tiles[at.local];
    final layout = _tilePages(data.pages, tile);
    final item = _ReaderPageItem(
      chapterId: chapter.chapterId,
      page: layout.page,
      tileIndex: tile.tileIndex,
      tilePixelHeight: tile.pixelHeight,
      zoom: readerSettings.zoom,
      prevPage: layout.prevPage,
      forcePortrait: readerSettings.forcePortrait,
    );
    final startsFollowingChapter = at.slot > 0 && at.local == 0;
    return Padding(
      key: ValueKey((chapter.chapterId, tile.pageIndex, tile.tileIndex)),
      // Gap only between pages, never between tiles of one page (seams).
      padding: EdgeInsets.only(
        bottom: _tileGap(data.tiles, at.local, readerSettings.pageGap),
      ),
      child: startsFollowingChapter
          ? Column(
              children: [
                SizedBox(
                  height: _transitionExtent,
                  child: _ChapterTransition(
                    text: text,
                    finishedTitle: _chapterTitle(strip.chapters[at.slot - 1]),
                    next: data,
                  ),
                ),
                Expanded(child: item),
              ],
            )
          : item,
    );
  }

  String _chapterTitle(StripChapter chapter) =>
      chapter.data.context?.title ?? '';

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
    final page = data.initialPage;
    _currentPage = page;
    _savedPages[chapterId] = page;
    final strip = _strip!;
    _setRenderWindowAroundTile(
      strip.globalTile(0, _firstTileOfPage(data.tiles, page)),
      strip.tileCount,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isCurrent(generation)) {
        return;
      }
      _jumpToChapterPage(0, page, persist: false);
      unawaited(_prefetchWindow(_renderStart, _renderEnd));
      _initialScrollTimer?.cancel();
      late final Timer timer;
      timer = Timer(const Duration(milliseconds: 300), () {
        if (identical(_initialScrollTimer, timer)) {
          _initialScrollTimer = null;
        }
        if (_isCurrent(generation)) {
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
    if (!_isCurrent(generation)) {
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
  }

  void _updateViewportWindow({bool persistProgress = true}) {
    final strip = _strip;
    if (strip == null || strip.tileCount == 0 || !_scroll.hasClients) {
      return;
    }
    final layout = _currentLayout(strip);
    final range = _visibleTileRange(layout);
    final center = layout.tileForOffset(
      _scroll.offset + _scroll.position.viewportDimension / 2,
    );
    final located = strip.locate(center);
    final page =
        strip.chapters[located.slot].data.tiles[located.local].pageIndex;
    final start = math.max(0, range.first - 2);
    final end = math.min(strip.tileCount - 1, range.last + 2);
    final slotChanged = located.slot != _activeSlot;
    final pageChanged = page != _currentPage;
    final windowChanged = start != _renderStart || end != _renderEnd;
    if (slotChanged) {
      _changeActiveChapter(
        located.slot,
        page,
        persist: persistProgress,
        finishedPrevious: located.slot == _activeSlot + 1,
      );
    } else if (pageChanged) {
      _currentPage = page;
      _refreshOverlay();
      if (persistProgress) {
        _scheduleProgressSave();
      }
    }
    if (windowChanged) {
      _renderStart = start;
      _renderEnd = end;
      unawaited(_prefetchWindow(start, end));
    }
    _maybeLoadAdjacent();
  }

  /// Makes [slot] the chapter being read: the top bar, page indicator and
  /// marks follow it at once, and both chapters' progress is written now
  /// rather than after the scroll-save debounce.
  void _changeActiveChapter(
    int slot,
    int page, {
    required bool persist,
    required bool finishedPrevious,
  }) {
    final strip = _strip;
    final previous = _activeChapter;
    if (strip == null || previous == null) {
      return;
    }
    _progressTimer?.cancel();
    final leftPage = finishedPrevious
        ? previous.data.pages.length - 1
        : _currentPage;
    _activeSlot = slot;
    _currentPage = page;
    final active = strip.chapters[slot];
    _refreshOverlay();
    if (persist) {
      // Scrolling on into the next chapter means the previous one was read to
      // its end, even if a fast scroll skipped past its last page.
      unawaited(_persistProgress(previous, leftPage));
      unawaited(_persistProgress(active, page));
      _rememberLastOpened(active);
    } else {
      _savedPages[active.chapterId] = page;
    }
  }

  void _rememberLastOpened(StripChapter chapter) {
    final comicPath = chapter.data.context?.comicSourcePath;
    final chapterPath = chapter.data.context?.chapterSourcePath;
    if (comicPath == null ||
        comicPath.isEmpty ||
        chapterPath == null ||
        chapterPath.isEmpty) {
      return;
    }
    ref
        .read(lastOpenedChapterProvider.notifier)
        .remember(comicPath, chapterPath);
  }

  ({int first, int last}) _visibleTileRange(_TileLayout layout) {
    final visibleTop = _scroll.offset;
    final visibleBottom = visibleTop + _scroll.position.viewportDimension;
    final range = layout.visibleRange(visibleTop, visibleBottom);
    if (range == null) {
      final tile = layout.tileForOffset(visibleTop);
      return (first: tile, last: tile);
    }
    return range;
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

  // -------------------------------------------------------------------------
  // Chaining neighbouring chapters into the strip
  // -------------------------------------------------------------------------

  /// Starts loading the chapter before / after the strip once the viewport is
  /// close to that end, so crossing into it never waits on a load.
  void _maybeLoadAdjacent() {
    final strip = _strip;
    if (strip == null || !_initialScrollDone || !_scroll.hasClients) {
      return;
    }
    final settings = ref.read(readerSettingsProvider);
    if (!settings.unlimitedScroll) {
      return;
    }
    final position = _scroll.position;
    final lookahead = position.viewportDimension * _preloadViewports;
    final nextId = strip.chapters.last.data.context?.nextChapterId;
    if (nextId != null &&
        position.maxScrollExtent - position.pixels <= lookahead) {
      unawaited(_extendStrip(nextId, forward: true));
    }
    final prevId = strip.chapters.first.data.context?.prevChapterId;
    if (prevId != null &&
        position.pixels - position.minScrollExtent <= lookahead) {
      unawaited(_extendStrip(prevId, forward: false));
    }
  }

  Future<void> _extendStrip(int chapterId, {required bool forward}) async {
    final strip = _strip;
    if (strip == null ||
        strip.slotOfChapter(chapterId) >= 0 ||
        _loadingChapters.contains(chapterId) ||
        _failedChapters.contains(chapterId)) {
      return;
    }
    final generation = _readerGeneration;
    _loadingChapters.add(chapterId);
    final hold = ref.listenManual(readerDataProvider(chapterId), (_, _) {});
    var kept = false;
    try {
      final data = await ref.read(readerDataProvider(chapterId).future);
      if (!_isCurrent(generation)) {
        return;
      }
      if (data.pages.isEmpty) {
        _failedChapters.add(chapterId);
        return;
      }
      if (!forward) {
        await _whenScrollSettled();
        if (!_isCurrent(generation)) {
          return;
        }
      }
      final current = _strip;
      final edge = forward
          ? current?.chapters.last.data.context?.nextChapterId
          : current?.chapters.first.data.context?.prevChapterId;
      if (current == null || edge != chapterId) {
        return;
      }
      final chapter = StripChapter(chapterId, data);
      _chapterHolds[chapterId] = hold;
      kept = true;
      final progress = data.progress;
      _savedPages[chapterId] = progress != null && !progress.isRead
          ? progress.lastPage.toInt()
          : -1;
      if (forward) {
        _setStrip(current.appended(chapter));
      } else {
        _prependChapter(current, chapter);
      }
      unawaited(_loadPageMarks(chapterId));
    } catch (_) {
      _failedChapters.add(chapterId);
    } finally {
      _loadingChapters.remove(chapterId);
      if (!kept) {
        hold.close();
      }
    }
  }

  /// A prepend moves every existing item down, which a running scroll
  /// animation would undo; wait for it so the correction below sticks.
  Future<void> _whenScrollSettled() async {
    if (!_scroll.hasClients) {
      return;
    }
    final scrolling = _scroll.position.isScrollingNotifier;
    if (!scrolling.value) {
      return;
    }
    final settled = Completer<void>();
    void listener() {
      if (!scrolling.value && !settled.isCompleted) {
        settled.complete();
      }
    }

    scrolling.addListener(listener);
    try {
      await settled.future;
    } finally {
      scrolling.removeListener(listener);
    }
  }

  void _setStrip(ReaderStrip next) {
    setState(() => _strip = next);
    // New tiles are only prefetched once the window is recomputed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateViewportWindow(persistProgress: false);
      }
    });
  }

  /// Puts [chapter] above the strip without moving what is on screen: the
  /// scroll offset grows by exactly how far the content in view was pushed.
  void _prependChapter(ReaderStrip current, StripChapter chapter) {
    final next = current.prepended(chapter);
    final added = chapter.data.tiles.length;
    if (!_scroll.hasClients) {
      setState(() {
        _strip = next;
        _activeSlot += 1;
      });
      return;
    }
    final before = _currentLayout(current);
    final anchor = _visibleTileRange(before).first;
    final shift =
        _currentLayout(next).contentTops[anchor + added] -
        before.contentTops[anchor];
    setState(() {
      _strip = next;
      _activeSlot += 1;
    });
    _scroll.position.correctBy(shift);
    if (_renderEnd >= _renderStart) {
      _renderStart += added;
      _renderEnd += added;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateViewportWindow(persistProgress: false);
      }
    });
  }

  void _closeHolds() {
    for (final hold in _chapterHolds.values) {
      hold.close();
    }
    _chapterHolds.clear();
  }

  // -------------------------------------------------------------------------
  // Progress
  // -------------------------------------------------------------------------

  void _scheduleProgressSave() {
    _progressTimer?.cancel();
    _progressTimer = Timer(const Duration(milliseconds: 450), () {
      final active = _activeChapter;
      if (active != null) {
        unawaited(_persistProgress(active, _currentPage));
      }
    });
  }

  /// Writes [page] as the chapter's progress unless it is already stored.
  /// Reaching the last page marks the chapter read.
  Future<void> _persistProgress(StripChapter chapter, int page) async {
    final count = chapter.data.pages.length;
    if (count == 0) {
      return;
    }
    final clamped = page.clamp(0, count - 1);
    if (_savedPages[chapter.chapterId] == clamped) {
      return;
    }
    _savedPages[chapter.chapterId] = clamped;
    await _api.saveProgress(
      bridge.SaveProgressPayload(
        chapterId: chapter.chapterId,
        lastPage: clamped,
        totalPages: count,
        isRead: clamped >= count - 1,
      ),
    );
    ReaderSaveGuard.track(chapter.chapterId, clamped, count);
    if (mounted) {
      _invalidateProgressProviders(chapter.data, onClose: false);
    }
  }

  /// Saves [chapter]'s current page without the "already stored" shortcut;
  /// used where the app is about to leave the reader.
  Future<void> _saveProgressDirect(StripChapter chapter) async {
    final count = chapter.data.pages.length;
    if (count == 0) {
      return;
    }
    final isActive = identical(chapter, _activeChapter);
    final page = (isActive ? _currentPage : _savedPages[chapter.chapterId] ?? 0)
        .clamp(0, count - 1);
    await _api.saveProgress(
      bridge.SaveProgressPayload(
        chapterId: chapter.chapterId,
        lastPage: page,
        totalPages: count,
        isRead: page >= count - 1,
      ),
    );
    ReaderSaveGuard.track(chapter.chapterId, page, count);
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

  // -------------------------------------------------------------------------
  // Prefetch
  // -------------------------------------------------------------------------

  /// The part of strip window [start]..[end] that falls inside each chapter.
  List<_WindowSegment> _segmentsFor(ReaderStrip strip, int start, int end) {
    final segments = <_WindowSegment>[];
    if (strip.tileCount == 0 || end < start) {
      return segments;
    }
    final first = strip.locate(math.max(0, start));
    final last = strip.locate(math.min(strip.tileCount - 1, end));
    for (var slot = first.slot; slot <= last.slot; slot++) {
      final chapter = strip.chapters[slot];
      segments.add((
        chapterId: chapter.chapterId,
        start: slot == first.slot ? first.local : 0,
        end: slot == last.slot ? last.local : chapter.data.tiles.length - 1,
      ));
    }
    return segments;
  }

  Future<void> _prefetchWindow(int start, int end) async {
    final generation = _readerGeneration;
    final strip = _strip;
    if (strip == null || !_isCurrent(generation) || end < start) {
      return;
    }
    final segments = _segmentsFor(strip, start, end);
    if (_prefetchQueue != null && !_prefetchQueue!.isCompleted) {
      _prefetchQueued = segments;
      return;
    }
    final completer = Completer<void>();
    _prefetchQueue = completer;
    _prefetchQueued = null;
    try {
      var next = segments;
      while (true) {
        if (!_isCurrent(generation)) {
          return;
        }
        await _prefetchSegments(next, generation);
        if (!_isCurrent(generation)) {
          return;
        }
        final queued = _prefetchQueued;
        _prefetchQueued = null;
        if (queued == null) {
          return;
        }
        next = queued;
      }
    } finally {
      completer.complete();
      if (identical(_prefetchQueue, completer)) {
        _prefetchQueue = null;
      }
    }
  }

  Future<void> _prefetchSegments(
    List<_WindowSegment> segments,
    int generation,
  ) async {
    final inWindow = {for (final segment in segments) segment.chapterId};
    // Chapters the window has moved away from give their raw pages back, once.
    for (final chapter in [...?_strip?.chapters]) {
      if (inWindow.contains(chapter.chapterId)) {
        _idleChapters.remove(chapter.chapterId);
      } else if (_idleChapters.add(chapter.chapterId)) {
        await _api.evictChapterPages(
          chapterId: chapter.chapterId,
          keepPages: [],
        );
        if (!_isCurrent(generation)) {
          return;
        }
      }
    }
    for (final segment in segments) {
      final strip = _strip;
      final slot = strip?.slotOfChapter(segment.chapterId) ?? -1;
      if (strip == null || slot < 0) {
        continue;
      }
      final tiles = strip.chapters[slot].data.tiles;
      if (tiles.isEmpty) {
        continue;
      }
      final clampedStart = math.max(0, segment.start);
      final clampedEnd = math.min(tiles.length - 1, segment.end);
      if (clampedEnd < clampedStart) {
        continue;
      }
      final windowTiles = [
        for (var index = clampedStart; index <= clampedEnd; index++)
          tiles[index],
      ];
      // evictChapterPages stays page-based; Rust drops all tiles of
      // pages outside the window.
      final keepPages = <int>{
        for (final tile in windowTiles) tile.pageIndex,
      }.toList()..sort();
      await _api.evictChapterPages(
        chapterId: segment.chapterId,
        keepPages: keepPages,
      );
      if (!_isCurrent(generation)) {
        return;
      }
      await _api.prefetchTiles(
        bridge.PrefetchTilesPayload(
          chapterId: segment.chapterId,
          tiles: [
            for (final tile in windowTiles)
              bridge.PageTile(
                pageIndex: tile.pageIndex,
                tileIndex: tile.tileIndex,
              ),
          ],
        ),
      );
      if (!_isCurrent(generation)) {
        return;
      }
    }
  }

  // -------------------------------------------------------------------------
  // Keys, closing and switching chapters
  // -------------------------------------------------------------------------

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
    } else if (key == LogicalKeyboardKey.digit0 ||
        key == LogicalKeyboardKey.numpad0 ||
        key == LogicalKeyboardKey.home) {
      // "0" (and Home) rewinds the chapter to its first page.
      _jumpToPage(0);
    }
  }

  Future<void> _close(ReaderData fallback) async {
    final strip = _strip;
    final active = _activeChapter ?? StripChapter(widget.chapterId, fallback);
    final data = active.data;
    await _saveProgressDirect(active);
    _invalidateProgressProviders(data, onClose: true);
    for (final chapter in strip?.chapters ?? [active]) {
      ref.invalidate(readerDataProvider(chapter.chapterId));
    }
    await _releaseStripMemory(strip);
    if (!mounted) {
      return;
    }
    final comicPath = data.context?.comicSourcePath;
    _rememberLastOpened(active);

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

  Future<void> _switchChapter(int chapterId) async {
    final strip = _strip;
    final slot = strip?.slotOfChapter(chapterId) ?? -1;
    if (strip != null && slot >= 0) {
      // Already chained in: go there without reloading anything.
      _jumpToChapterPage(slot, strip.chapters[slot].data.initialPage);
      return;
    }
    final active = _activeChapter;
    if (active != null) {
      await _saveProgressDirect(active);
    }

    // Update last opened chapter immediately so the comic page shows the
    // correct "continue reading" target even if the app is killed right after.
    final comicPath = active?.data.context?.comicSourcePath;
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

    for (final chapter in strip?.chapters ?? const <StripChapter>[]) {
      ref.invalidate(readerDataProvider(chapter.chapterId));
    }
    ref.invalidate(readerDataProvider(widget.chapterId));
    await _releaseStripMemory(strip);
    if (mounted) {
      context.go('/reader/$chapterId');
    }
  }

  /// Gives back every chapter of [strip]: pending prefetch finishes first,
  /// then the Rust side drops the raw pages of each chapter.
  Future<void> _releaseStripMemory(
    ReaderStrip? strip, {
    bool invalidateRenderedPages = true,
  }) async {
    _readerGeneration++;
    _initialScrollTimer?.cancel();
    _initialScrollTimer = null;
    _prefetchQueued = null;
    final pendingPrefetch = _prefetchQueue;
    if (invalidateRenderedPages && strip != null) {
      for (final chapter in strip.chapters) {
        _invalidateRenderedTiles(chapter.chapterId, chapter.data.pages);
      }
    }
    if (identical(_strip, strip)) {
      _strip = null;
    }
    _closeHolds();
    _renderStart = 0;
    _renderEnd = -1;
    _idleChapters.clear();
    if (pendingPrefetch != null && !pendingPrefetch.isCompleted) {
      await pendingPrefetch.future;
    }
    for (final chapter in strip?.chapters ?? const <StripChapter>[]) {
      await _api.evictChapterPages(chapterId: chapter.chapterId, keepPages: []);
    }
  }

  bool _isCurrent(int generation) {
    return mounted && _readerGeneration == generation;
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

  // -------------------------------------------------------------------------
  // Jumping
  // -------------------------------------------------------------------------

  /// Steps [delta] pages within the chapter in view, rolling over into the
  /// neighbouring chapter when it is already part of the strip.
  void _jumpBy(int delta) {
    final strip = _strip;
    final active = _activeChapter;
    if (strip == null || active == null || active.data.pages.isEmpty) {
      return;
    }
    final target = _currentPage + delta;
    if (target >= active.data.pages.length &&
        _activeSlot + 1 < strip.chapters.length) {
      _jumpToChapterPage(_activeSlot + 1, 0);
    } else if (target < 0 && _activeSlot > 0) {
      final previous = strip.chapters[_activeSlot - 1];
      _jumpToChapterPage(_activeSlot - 1, previous.data.pages.length - 1);
    } else {
      _jumpToPage(target.clamp(0, active.data.pages.length - 1));
    }
  }

  void _jumpToPage(int page, {bool persist = true}) {
    _jumpToChapterPage(_activeSlot, page, persist: persist);
  }

  void _jumpToChapterPage(int slot, int page, {bool persist = true}) {
    final strip = _strip;
    if (strip == null || slot < 0 || slot >= strip.chapters.length) {
      return;
    }
    final chapter = strip.chapters[slot];
    if (chapter.data.pages.isEmpty) {
      return;
    }
    final clampedPage = page.clamp(0, chapter.data.pages.length - 1);
    final tile = strip.globalTile(
      slot,
      _firstTileOfPage(chapter.data.tiles, clampedPage),
    );
    _setRenderWindowAroundTile(tile, strip.tileCount);
    if (slot != _activeSlot) {
      _changeActiveChapter(
        slot,
        clampedPage,
        persist: persist,
        finishedPrevious: false,
      );
    } else if (clampedPage != _currentPage) {
      _currentPage = clampedPage;
      _refreshOverlay();
      if (persist) {
        _scheduleProgressSave();
      }
    }
    if (!persist) {
      _savedPages[chapter.chapterId] = clampedPage;
    }
    unawaited(_prefetchWindow(_renderStart, _renderEnd));
    if (_scroll.hasClients) {
      final targetOffset = _currentLayout(
        strip,
      ).contentTops[tile].clamp(0, _scroll.position.maxScrollExtent).toDouble();
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

  Future<void> _loadPageMarks(int chapterId) async {
    if (!_loadingMarks.add(chapterId)) {
      return;
    }
    try {
      final bookmarks = await _api.listPageBookmarks(chapterId: chapterId);
      if (!mounted) return;
      _pageMarks[chapterId] = {...bookmarks.map((b) => b.page.toInt())};
      _refreshOverlay();
    } catch (_) {
      // Marks are cosmetic; the chapter still reads fine without them.
    } finally {
      _loadingMarks.remove(chapterId);
    }
  }

  Future<void> _togglePageBookmark() async {
    final active = _activeChapter;
    if (active == null || active.data.pages.isEmpty) return;
    final pageIndex = _currentPage;
    if (pageIndex < 0 || pageIndex >= active.data.pages.length) return;
    final chapterId = active.chapterId;
    final marks = _pageMarks.putIfAbsent(chapterId, () => <int>{});

    if (marks.contains(pageIndex)) {
      // Find and remove the bookmark
      try {
        final bookmarks = await _api.listPageBookmarks(chapterId: chapterId);
        final match = bookmarks.where((b) => b.page.toInt() == pageIndex);
        if (match.isNotEmpty) {
          await _api.removePageBookmark(bookmarkId: match.first.id);
        }
      } catch (_) {}
      if (mounted) {
        marks.remove(pageIndex);
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
        marks.add(pageIndex);
        _refreshOverlay();
      }
    }
  }
}

/// Prefix-summed tile geometry for one (strip, zoom, width, gap) state.
///
/// Built once in O(n); the lookups the scroll handler needs on every scroll
/// event (visible range, tile under an offset, item extents, total extent)
/// are then O(log n) or O(1) instead of a walk over every tile per event.
/// Tiles are indexed across the whole strip.
class _TileLayout {
  const _TileLayout({
    required this.strip,
    required this.zoom,
    required this.maxWidth,
    required this.pageGap,
    required this.forcePortrait,
    required this.tops,
    required this.contentTops,
    required this.bottoms,
    required this.extents,
    required this.totalExtent,
  });

  final ReaderStrip strip;
  final double zoom;
  final double maxWidth;
  final double pageGap;
  final bool forcePortrait;

  /// Top edge of each item, including the reader's top padding and, for the
  /// first page of a chapter that follows another, its transition header.
  final List<double> tops;

  /// Top edge of each tile's image, below any transition header.
  final List<double> contentTops;

  /// Bottom edge of each tile (image bottom, no gap).
  final List<double> bottoms;

  /// Sliver item extent of each tile: header + display height + the gap
  /// after it.
  final List<double> extents;
  final double totalExtent;

  int get tileCount => tops.length;

  bool matches(
    ReaderStrip strip,
    double zoom,
    double maxWidth,
    double pageGap,
    bool forcePortrait,
  ) {
    return identical(this.strip, strip) &&
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
    if (first >= tileCount || last < first) {
      return null;
    }
    return (first: first, last: last);
  }

  /// First tile whose bottom edge is at or below [offset], else the last.
  int tileForOffset(double offset) {
    final index = lowerBoundIndex(bottoms, offset);
    return index < tileCount ? index : tileCount - 1;
  }
}

/// Vertical scrollbar scoped to the chapter under the viewport centre.
///
/// The strip chains chapters into one scroll view, so a stock scrollbar would
/// span all of them and its thumb would never start over. This one measures
/// only the active chapter's stretch of the strip: its thumb restarts at the
/// top when the next chapter begins, and dragging it moves within that chapter.
class _ChapterScrollbar extends StatefulWidget {
  const _ChapterScrollbar({required this.controller, required this.layout});

  static const double width = 16;

  final ScrollController controller;
  final _TileLayout layout;

  @override
  State<_ChapterScrollbar> createState() => _ChapterScrollbarState();
}

class _ChapterScrollbarState extends State<_ChapterScrollbar> {
  static const double _thickness = 12;
  static const double _minThumb = 36;

  /// Pointer distance from the thumb's top while it is being dragged.
  double _grab = 0;

  @override
  void initState() {
    super.initState();
    // The controller only has a position after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  /// Where the active chapter starts and ends along the scroll axis.
  ({double top, double bottom}) _region(double offset, double viewport) {
    final layout = widget.layout;
    final strip = layout.strip;
    final center = layout.tileForOffset(offset + viewport / 2);
    final slot = strip.locate(center).slot;
    final top = slot == 0 ? 0.0 : layout.tops[strip.tileStart(slot)];
    final bottom = slot == strip.chapters.length - 1
        ? layout.totalExtent
        : layout.tops[strip.tileStart(slot + 1)];
    return (top: top, bottom: bottom);
  }

  ({double top, double thumb, double region, double range})? _measure(
    double track,
  ) {
    final controller = widget.controller;
    if (!controller.hasClients || track <= 0) {
      return null;
    }
    final position = controller.position;
    final viewport = position.viewportDimension;
    final region = _region(position.pixels, viewport);
    final length = math.max(region.bottom - region.top, viewport);
    final range = length - viewport;
    final progress = range <= 0
        ? 0.0
        : ((position.pixels - region.top) / range).clamp(0.0, 1.0);
    final thumb = (track * viewport / length).clamp(_minThumb, track);
    return (
      top: (track - thumb) * progress,
      thumb: thumb.toDouble(),
      region: region.top,
      range: range,
    );
  }

  void _seek(double thumbTop, double track) {
    final measured = _measure(track);
    if (measured == null || measured.range <= 0) {
      return;
    }
    final free = track - measured.thumb;
    final progress = free <= 0 ? 0.0 : (thumbTop / free).clamp(0.0, 1.0);
    final position = widget.controller.position;
    widget.controller.jumpTo(
      (measured.region + progress * measured.range).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final track = constraints.maxHeight;
        return AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            final measured = _measure(track);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) {
                final m = _measure(track);
                if (m != null) {
                  _seek(details.localPosition.dy - m.thumb / 2, track);
                }
              },
              onVerticalDragStart: (details) {
                final m = _measure(track);
                if (m == null) {
                  return;
                }
                final dy = details.localPosition.dy;
                final onThumb = dy >= m.top && dy <= m.top + m.thumb;
                _grab = onThumb ? dy - m.top : m.thumb / 2;
                if (!onThumb) {
                  _seek(dy - _grab, track);
                }
              },
              onVerticalDragUpdate: (details) =>
                  _seek(details.localPosition.dy - _grab, track),
              child: Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: _thickness,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(color: Color(0xff0e0d13)),
                    child: Stack(
                      children: [
                        if (measured != null)
                          Positioned(
                            key: const ValueKey('reader-scrollbar-thumb'),
                            top: measured.top,
                            left: 0,
                            right: 0,
                            height: measured.thumb,
                            child: const DecoratedBox(
                              decoration: BoxDecoration(
                                color: Color(0xff5b5670),
                                borderRadius: BorderRadius.all(
                                  Radius.circular(999),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// The separator between two chapters of the strip: what was just finished
/// and what comes next, with where it sits in the comic.
class _ChapterTransition extends StatelessWidget {
  const _ChapterTransition({
    required this.text,
    required this.finishedTitle,
    required this.next,
  });

  final AppStrings text;
  final String finishedTitle;
  final ReaderData next;

  @override
  Widget build(BuildContext context) {
    final chapterContext = next.context;
    final facts = [
      if (chapterContext != null && chapterContext.chapterTotal > 0)
        '${chapterContext.chapterPosition}/${chapterContext.chapterTotal}',
      text.pagesCountTemplate.replaceAll('{count}', '${next.pages.length}'),
    ].join(' · ');
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(AppIcons.check, size: 16, color: _chromeAccent),
                  const SizedBox(width: 6),
                  Text(
                    text.finished,
                    style: const TextStyle(
                      color: _chromeAccentInk,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                finishedTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _chromeMuted,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Container(
                width: 120,
                height: 1,
                margin: const EdgeInsets.symmetric(vertical: 16),
                color: _chromeLine,
              ),
              Text(
                text.nextChapter,
                style: const TextStyle(
                  color: _chromeMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                next.context?.title ?? text.chapter,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _chromeText,
                  fontSize: 17,
                  height: 24 / 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                facts,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _chromeMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
    final subtitle = contextData?.title ?? text.chapter;
    // Kept out of the ellipsised title so a long chapter name never hides
    // where the chapter sits in the comic.
    final position = contextData != null
        ? ' (${contextData.chapterPosition}/${contextData.chapterTotal})'
        : null;
    const subtitleStyle = TextStyle(
      color: _chromeMuted,
      fontSize: 12.5,
      height: 18 / 12.5,
      fontWeight: FontWeight.w500,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showLabels = constraints.maxWidth >= 760;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title pill hugs the left edge; the controls pill sits at the
              // right edge (space-between), whatever the title width.
              Expanded(
                child: Align(
                  alignment: Alignment.topLeft,
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
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        subtitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: subtitleStyle,
                                      ),
                                    ),
                                    if (position != null)
                                      Text(
                                        position,
                                        maxLines: 1,
                                        softWrap: false,
                                        style: subtitleStyle,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
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
    required this.onForcePortraitChanged,
  });

  final AppStrings text;
  final ReaderSettings settings;
  final ValueChanged<double> onZoomChanged;
  final ValueChanged<double> onGapChanged;
  final ValueChanged<bool> onUnlimitedScrollChanged;
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
                _KeyHint(keys: '0', label: text.keyFirstPage),
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
