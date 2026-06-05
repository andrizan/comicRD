import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' as widgets;
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key, required this.chapterId});

  final int chapterId;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  late ScrollController _scroll;
  final _focusNode = FocusNode(debugLabel: 'ReaderPage');
  final _pageKeys = <int, GlobalKey>{};
  Timer? _progressTimer;
  int _currentPage = 0;
  int _lastSavedPage = -1;
  int _jumpGeneration = 0;
  bool _ignoreNextScrollUpdate = false;
  bool _restoredProgress = false;
  bool _initialScrollDone = false;
  bool _fullscreen = false;
  bool _toolbarVisible = true;
  late final ComicRdApi _api;
  ReaderData? _lastReaderData;

  @override
  void initState() {
    super.initState();
    _api = ref.read(comicRdApiProvider);
    PaintingBinding.instance.imageCache.maximumSizeBytes = 64 * 1024 * 1024;
    _scroll = _createScrollController();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    unawaited(_saveProgressDirect());
    PaintingBinding.instance.imageCache.maximumSizeBytes = 100 * 1024 * 1024;
    PaintingBinding.instance.imageCache.clear();
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
    _currentPage = 0;
    _lastSavedPage = -1;
    _jumpGeneration++;
    _ignoreNextScrollUpdate = false;
    _restoredProgress = false;
    _initialScrollDone = false;
    _pageKeys.clear();
    _toolbarVisible = true;
    if (_scroll.hasClients) {
      _scroll.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<Map<String, String>>>(settingsMapProvider, (_, next) {
      next.whenData((values) {
        ref.read(readerSettingsProvider.notifier).hydrateFromSettings(values);
      });
    });
    final readerSettings = ref.watch(readerSettingsProvider);
    final settings = ref.watch(appSettingsProvider);
    final text = stringsFor(settings.localeCode);
    final reader = ref.watch(readerDataProvider(widget.chapterId));
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
                        icon: FluentIcons.settings,
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
          loading: () =>
              const Align(alignment: Alignment.center, child: ProgressRing()),
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
        padding: EdgeInsets.only(top: 78, bottom: 48 + readerSettings.pageGap),
        itemCount: data.pages.length,
        itemBuilder: (context, index) {
          final page = data.pages[index];
          return Padding(
            key: _pageKeys.putIfAbsent(index, GlobalKey.new),
            padding: EdgeInsets.only(
              bottom: index == data.pages.length - 1
                  ? 0
                  : readerSettings.pageGap,
            ),
            child: _ReaderPageItem(
              chapterId: widget.chapterId,
              page: page,
              zoom: readerSettings.zoom,
            ),
          );
        },
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
    final page = data.initialPage;
    _currentPage = page;
    _lastSavedPage = page;
    final initialOffset = _estimatedOffsetForPage(
      page,
      data,
      ref.read(readerSettingsProvider),
    );
    if (!_scroll.hasClients && initialOffset > 0) {
      _scroll.dispose();
      _scroll = _createScrollController(initialOffset);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_prefetchAround(page));
      if (_scroll.hasClients) {
        _jumpToPage(page, persist: false);
      }
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() => _initialScrollDone = true);
        }
      });
    });
  }

  void _handleScroll() {
    if (!_initialScrollDone) {
      return;
    }
    _hideToolbar();
    if (_ignoreNextScrollUpdate) {
      _ignoreNextScrollUpdate = false;
      return;
    }
    final page = _pageAtViewportCenter();
    if (page == _currentPage) {
      return;
    }
    setState(() => _currentPage = page);
    _scheduleProgressSave();
    unawaited(_prefetchAround(page));
    if (page % 2 == 0) {
      PaintingBinding.instance.imageCache.clearLiveImages();
    }
  }

  int _pageAtViewportCenter() {
    if (!_scroll.hasClients) {
      return _currentPage;
    }
    final viewportHeight = _scroll.position.viewportDimension;
    final viewportCenter = viewportHeight / 2;
    var bestPage = _currentPage;
    var bestDistance = double.infinity;
    for (final entry in _pageKeys.entries) {
      final renderObject = entry.value.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) {
        continue;
      }
      final position = renderObject.localToGlobal(Offset.zero);
      final top = position.dy;
      final bottom = top + renderObject.size.height;
      if (bottom <= 0 || top >= viewportHeight) {
        continue;
      }
      final visibleTop = top.clamp(0.0, viewportHeight);
      final visibleBottom = bottom.clamp(0.0, viewportHeight);
      final visibleCenter = (visibleTop + visibleBottom) / 2;
      final distance = (visibleCenter - viewportCenter).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestPage = entry.key;
      }
    }
    return bestPage;
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
    await ref
        .read(comicRdApiProvider)
        .saveProgress(
          bridge.SaveProgressPayload(
            chapterId: widget.chapterId,
            lastPage: _currentPage,
            totalPages: data.pages.length,
            isRead: _currentPage >= data.pages.length - 1,
          ),
        );
    _invalidateProgressProviders(data);
  }

  Future<void> _saveProgressDirect() async {
    final data = _lastReaderData;
    if (data == null || data.pages.isEmpty || _currentPage == _lastSavedPage) {
      return;
    }
    _lastSavedPage = _currentPage;
    await _api.saveProgress(
      bridge.SaveProgressPayload(
        chapterId: widget.chapterId,
        lastPage: _currentPage,
        totalPages: data.pages.length,
        isRead: _currentPage >= data.pages.length - 1,
      ),
    );
  }

  void _invalidateProgressProviders(ReaderData data) {
    final comicPath = data.context?.comicSourcePath;
    ref.invalidate(comicsWithProgressProvider);
    ref.invalidate(rawLibraryComicsProvider);
    ref.invalidate(libraryComicsProvider);
    ref.invalidate(readingHistoryProvider);
    if (comicPath == null || comicPath.isEmpty) {
      return;
    }
    ref.invalidate(comicChaptersProvider(comicPath));
    ref.invalidate(filteredComicChaptersProvider(comicPath));
  }

  Future<void> _prefetchAround(int page) async {
    final data = ref.read(readerDataProvider(widget.chapterId)).asData?.value;
    if (data == null || data.pages.isEmpty) {
      return;
    }
    final start = math.max(0, page - 2);
    final end = math.min(data.pages.length - 1, page + 2);
    final api = ref.read(comicRdApiProvider);
    await api.prefetchPages(
      bridge.PrefetchPagesPayload(
        chapterId: widget.chapterId,
        pageIndices: Uint32List.fromList([
          for (var index = start; index <= end; index++) index,
        ]),
      ),
    );
    await api.evictChapterPages(
      chapterId: widget.chapterId,
      keepPages: Uint32List.fromList([
        for (var index = start; index <= end; index++) index,
      ]),
    );
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
    await _saveProgress(immediate: true);
    _invalidateProgressProviders(data);
    if (!mounted) {
      return;
    }
    final comicPath = data.context?.comicSourcePath;
    if (comicPath == null || comicPath.isEmpty) {
      context.go('/');
    } else {
      context.go('/comic/${encodeRoutePath(comicPath)}');
    }
  }

  Future<void> _switchChapter(int chapterId) async {
    await _saveProgress(immediate: true);
    if (mounted) {
      context.go('/reader/$chapterId');
    }
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
    final generation = ++_jumpGeneration;
    setState(() => _currentPage = page);
    if (persist) {
      _scheduleProgressSave();
    } else {
      _lastSavedPage = page;
    }
    unawaited(_prefetchAround(page));
    if (_scroll.hasClients) {
      final data = ref.read(readerDataProvider(widget.chapterId)).asData?.value;
      final estimatedOffset = _scrollOffsetForPageIndex(
        page,
        data?.pages.length ?? 0,
      );
      final targetOffset = estimatedOffset.clamp(
        0,
        _scroll.position.maxScrollExtent,
      ).toDouble();
      if ((_scroll.position.pixels - targetOffset).abs() > 0.5) {
        _ignoreNextScrollUpdate = _initialScrollDone;
        _scroll.jumpTo(targetOffset);
      } else {
        _ignoreNextScrollUpdate = false;
      }
      _alignPageAfterLayout(page, generation);
    }
  }

  void _alignPageAfterLayout(int page, int generation) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _jumpGeneration != generation) {
        return;
      }
      final pageContext = _pageKeys[page]?.currentContext;
      if (pageContext == null) {
        return;
      }
      Scrollable.ensureVisible(
        pageContext,
        duration: Duration.zero,
        alignment: 0,
      );
    });
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

  double _estimatedOffsetForPage(
    int page,
    ReaderData data,
    ReaderSettings settings,
  ) {
    const topPadding = 78.0;
    var offset = topPadding;
    final target = page.clamp(0, data.pages.length - 1);
    for (var index = 0; index < target; index++) {
      offset += _estimatedPageHeight(data.pages[index], settings.zoom);
      offset += settings.pageGap;
    }
    return offset;
  }

  double _estimatedPageHeight(bridge.PageInfo page, double zoom) {
    final width = (page.width ?? 900).toDouble();
    final height = (page.height ?? 1300).toDouble();
    if (width <= 0 || height <= 0) {
      return 1300 * zoom;
    }
    return height * zoom;
  }

  double _scrollOffsetForPageIndex(int page, int pageCount) {
    if (!_scroll.hasClients || pageCount <= 1) {
      return 0;
    }
    final lastPage = pageCount - 1;
    final targetPage = page.clamp(0, lastPage).toDouble();
    return _scroll.position.maxScrollExtent * (targetPage / lastPage);
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
    final aspectRatio = _aspectRatio(page);
    final displayWidth = _displayWidth(page, zoom);
    final rendered = ref.watch(
      renderedPageProvider(
        RenderedPageRequest(chapterId: chapterId, pageIndex: page.index),
      ),
    );
    return rendered.when(
      data: (page) => Center(
        child: SizedBox(
          width: page.width == 0 ? null : page.width.toDouble() * zoom,
          child: Image.memory(
            page.bytes,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            fit: BoxFit.contain,
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

  double _displayWidth(bridge.PageInfo page, double zoom) {
    final width = page.width ?? 900;
    if (width <= 0) {
      return 900 * zoom;
    }
    return width * zoom;
  }

  double _aspectRatio(bridge.PageInfo page) {
    final width = page.width ?? 900;
    final height = page.height ?? 1300;
    if (width <= 0 || height <= 0) {
      return 900 / 1300;
    }
    return width / height;
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
                  : const ProgressRing(),
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
    required this.onClose,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.onPreviousChapter,
    required this.onNextChapter,
    required this.onGapChanged,
    required this.onZoomChanged,
    required this.onToggleFullscreen,
  });

  final AppStrings text;
  final ReaderData data;
  final int currentPage;
  final double pageGap;
  final double zoom;
  final bool fullscreen;
  final VoidCallback onClose;
  final VoidCallback onPreviousPage;
  final VoidCallback onNextPage;
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;
  final ValueChanged<double> onGapChanged;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onToggleFullscreen;

  @override
  Widget build(BuildContext context) {
    final contextData = data.context;
    final subtitle =
        '${contextData?.title ?? text.chapter} - '
        '${currentPage + 1}/${data.pages.length}';
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
                  icon: FluentIcons.cancel,
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
                      icon: FluentIcons.chevron_left,
                      onPressed: onPreviousPage,
                    ),
                    _ReferenceReaderIconButton(
                      tooltip: text.nextPage,
                      icon: FluentIcons.chevron_right,
                      onPressed: onNextPage,
                    ),
                    const SizedBox(width: 4),
                    _ReferenceReaderIconButton(
                      tooltip: text.previousChapter,
                      icon: FluentIcons.previous,
                      onPressed: onPreviousChapter,
                    ),
                    _ReferenceReaderIconButton(
                      tooltip: text.nextChapter,
                      icon: FluentIcons.next,
                      onPressed: onNextChapter,
                    ),
                    const SizedBox(width: 4),
                    _ReaderControlChip(
                      icon: FluentIcons.search,
                      value: '${(zoom * 100).round()}%',
                      tooltip: text.zoom,
                      onDecrease: () =>
                          onZoomChanged((zoom - 0.1).clamp(0.4, 3).toDouble()),
                      onIncrease: () =>
                          onZoomChanged((zoom + 0.1).clamp(0.4, 3).toDouble()),
                      onReset: () => onZoomChanged(1),
                    ),
                    _ReaderControlChip(
                      icon: FluentIcons.align_horizontal_center,
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
                      icon: fullscreen
                          ? FluentIcons.back_to_window
                          : FluentIcons.full_screen,
                      active: fullscreen,
                      onPressed: onToggleFullscreen,
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
    this.compact = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool active;
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
    final fgOpacity = enabled ? 0.78 : 0.28;
    final bgOpacity = (widget.active ? 0.14 : (_hovered && enabled ? 0.10 : 0))
        .toDouble();
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
              border: Border.all(
                color: Colors.white.withValues(
                  alpha: widget.active ? 0.36 : 0.18,
                ),
              ),
            ),
            child: Icon(
              widget.icon,
              size: widget.compact ? 16 : 18,
              color: Colors.white.withValues(alpha: fgOpacity),
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
              _chipButton(FluentIcons.remove, widget.onDecrease),
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
              _chipButton(FluentIcons.add, widget.onIncrease),
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
        child: Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.78)),
      ),
    );
  }
}

// ignore: unused_element
class _ReaderToolbar extends StatelessWidget {
  const _ReaderToolbar({
    required this.text,
    required this.data,
    required this.currentPage,
    required this.pageGap,
    required this.zoom,
    required this.fullscreen,
    required this.onClose,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.onPreviousChapter,
    required this.onNextChapter,
    required this.onGapChanged,
    required this.onZoomChanged,
    required this.onToggleFullscreen,
  });

  final AppStrings text;
  final ReaderData data;
  final int currentPage;
  final double pageGap;
  final double zoom;
  final bool fullscreen;
  final VoidCallback onClose;
  final VoidCallback onPreviousPage;
  final VoidCallback onNextPage;
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;
  final ValueChanged<double> onGapChanged;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onToggleFullscreen;

  @override
  Widget build(BuildContext context) {
    final contextData = data.context;
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.82),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 900;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Tooltip(
                  message: text.close,
                  child: IconButton(
                    onPressed: onClose,
                    icon: const Icon(FluentIcons.cancel, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        contextData?.comicTitle ?? text.appName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white),
                      ),
                      Text(
                        '${contextData?.title ?? text.chapter} - '
                        '${currentPage + 1}/${data.pages.length}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: text.previousChapter,
                  child: IconButton(
                    onPressed: onPreviousChapter,
                    icon: const Icon(FluentIcons.previous, color: Colors.white),
                  ),
                ),
                Tooltip(
                  message: text.previousPage,
                  child: IconButton(
                    onPressed: onPreviousPage,
                    icon: const Icon(FluentIcons.up, color: Colors.white),
                  ),
                ),
                Tooltip(
                  message: text.nextPage,
                  child: IconButton(
                    onPressed: onNextPage,
                    icon: const Icon(FluentIcons.down, color: Colors.white),
                  ),
                ),
                Tooltip(
                  message: text.nextChapter,
                  child: IconButton(
                    onPressed: onNextChapter,
                    icon: const Icon(FluentIcons.next, color: Colors.white),
                  ),
                ),
                if (compact)
                  Tooltip(
                    message: text.readerControls,
                    child: IconButton(
                      onPressed: () => _showReaderControls(context),
                      icon: const Icon(
                        FluentIcons.settings,
                        color: Colors.white,
                      ),
                    ),
                  )
                else ...[
                  _ValueButton(
                    tooltip: text.gap,
                    icon: FluentIcons.align_vertical_center,
                    label: '${pageGap.round()}px',
                    onDecrease: () => onGapChanged((pageGap - 5).clamp(0, 80)),
                    onIncrease: () => onGapChanged((pageGap + 5).clamp(0, 80)),
                  ),
                  _ValueButton(
                    tooltip: text.zoom,
                    icon: FluentIcons.search,
                    label: '${(zoom * 100).round()}%',
                    onDecrease: () => onZoomChanged((zoom - 0.1).clamp(0.5, 3)),
                    onIncrease: () => onZoomChanged((zoom + 0.1).clamp(0.5, 3)),
                  ),
                ],
                Tooltip(
                  message: text.fullscreen,
                  child: IconButton(
                    onPressed: onToggleFullscreen,
                    icon: Icon(
                      fullscreen
                          ? FluentIcons.back_to_window
                          : FluentIcons.full_screen,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showReaderControls(BuildContext context) {
    var sheetGap = pageGap;
    var sheetZoom = zoom;
    return showDialog<void>(
      context: context,
      builder: (context) {
        return ContentDialog(
          title: Text(text.readerControls),
          content: StatefulBuilder(
            builder: (context, setSheetState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SheetValueControl(
                    label: text.gap,
                    value: sheetGap,
                    decimals: 0,
                    unit: 'px',
                    onDecrease: () {
                      final v = (sheetGap - 5).clamp(0, 80).toDouble();
                      setSheetState(() => sheetGap = v);
                      onGapChanged(v);
                    },
                    onIncrease: () {
                      final v = (sheetGap + 5).clamp(0, 80).toDouble();
                      setSheetState(() => sheetGap = v);
                      onGapChanged(v);
                    },
                  ),
                  _SheetValueControl(
                    label: text.zoom,
                    value: sheetZoom * 100,
                    decimals: 0,
                    unit: '%',
                    onDecrease: () {
                      final v = (sheetZoom - 0.1).clamp(0.5, 3).toDouble();
                      setSheetState(() => sheetZoom = v);
                      onZoomChanged(v);
                    },
                    onIncrease: () {
                      final v = (sheetZoom + 0.1).clamp(0.5, 3).toDouble();
                      setSheetState(() => sheetZoom = v);
                      onZoomChanged(v);
                    },
                  ),
                ],
              );
            },
          ),
          actions: [
            Button(
              child: Text(text.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }
}

class _ValueButton extends StatelessWidget {
  const _ValueButton({
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.onDecrease,
    required this.onIncrease,
  });

  final String tooltip;
  final IconData icon;
  final String label;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 16),
        const SizedBox(width: 2),
        _iconBtn(FluentIcons.remove, onDecrease),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
        _iconBtn(FluentIcons.add, onIncrease),
      ],
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onPressed) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onPressed,
      ),
    );
  }
}

class _SheetValueControl extends StatelessWidget {
  const _SheetValueControl({
    required this.label,
    required this.value,
    required this.decimals,
    required this.unit,
    required this.onDecrease,
    required this.onIncrease,
  });

  final String label;
  final double value;
  final int decimals;
  final String unit;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(label, style: const TextStyle(color: Colors.white)),
        ),
        IconButton(
          icon: const Icon(FluentIcons.remove, color: Colors.white),
          onPressed: onDecrease,
        ),
        SizedBox(
          width: 56,
          child: Text(
            value.toStringAsFixed(decimals) + unit,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ),
        IconButton(
          icon: const Icon(FluentIcons.add, color: Colors.white),
          onPressed: onIncrease,
        ),
      ],
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

  @override
  Widget build(BuildContext context) {
    final count = math.max(1, widget.pageCount);
    final current = widget.currentPage.clamp(0, count - 1);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
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
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) {
                          final width = constraints.maxWidth;
                          if (width <= 0) {
                            return;
                          }
                          final fraction = (details.localPosition.dx / width)
                              .clamp(0.0, 0.999999);
                          widget.onSelected((fraction * count).floor());
                        },
                        child: Row(
                          children: [
                            for (var index = 0; index < count; index++)
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: _hovered ? 2 : 1,
                                  ),
                                  child: Tooltip(
                                    message: '${index + 1}',
                                    child: SizedBox.expand(
                                      key: ValueKey(
                                        'reader-page-indicator-$index',
                                      ),
                                      child: Center(
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 150,
                                          ),
                                          curve: Curves.easeOutCubic,
                                          height: _hovered ? 12 : 4,
                                          width: double.infinity,
                                          decoration: BoxDecoration(
                                            color: index <= current
                                                ? const Color(0xff9aa7b5)
                                                : Colors.white.withValues(
                                                    alpha: 0.20,
                                                  ),
                                            borderRadius: BorderRadius.circular(
                                              99,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
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
}

// ignore: unused_element
class _PageIndicator extends StatelessWidget {
  const _PageIndicator({
    required this.currentPage,
    required this.pageCount,
    required this.onSelected,
  });

  final int currentPage;
  final int pageCount;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.82),
      child: SizedBox(
        height: 58,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: pageCount,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (context, index) {
            final selected = index == currentPage;
            return ToggleButton(
              checked: selected,
              onChanged: (_) => onSelected(index),
              child: Text('${index + 1}'),
            );
          },
        ),
      ),
    );
  }
}
