import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../bridge_generated.dart' as bridge;
import '../routes/path_codec.dart';
import '../state/api_state.dart';
import '../state/reader_state.dart';
import '../state/settings_data_state.dart';

class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key, required this.chapterId});

  final int chapterId;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  final _scroll = ScrollController();
  final _focusNode = FocusNode(debugLabel: 'ReaderPage');
  final _pageKeys = <int, GlobalKey>{};
  Timer? _progressTimer;
  int _currentPage = 0;
  int _lastSavedPage = -1;
  bool _restoredProgress = false;
  bool _fullscreen = false;
  double _zoom = 1;
  double _pageGap = 10;
  bridge.ImageVariantProfile _profile = bridge.ImageVariantProfile.balanced;

  @override
  void initState() {
    super.initState();
    PaintingBinding.instance.imageCache.maximumSizeBytes = 128 * 1024 * 1024;
    _scroll.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    unawaited(_saveProgress(immediate: true));
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
    _restoredProgress = false;
    _pageKeys.clear();
    if (_scroll.hasClients) {
      _scroll.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<Map<String, String>>>(settingsMapProvider, (_, next) {
      next.whenData(_applySettings);
    });
    final reader = ref.watch(readerDataProvider(widget.chapterId));
    return Scaffold(
      backgroundColor: Colors.black,
      body: KeyboardListener(
        autofocus: true,
        focusNode: _focusNode,
        onKeyEvent: (event) {
          if (event is KeyDownEvent) {
            _handleKey(event.logicalKey, reader.asData?.value);
          }
        },
        child: SafeArea(
          child: reader.when(
            data: (data) {
              _restoreProgress(data);
              return Stack(
                children: [
                  Positioned.fill(child: _readerScrollView(data: data)),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _ReaderToolbar(
                      data: data,
                      currentPage: _currentPage,
                      pageGap: _pageGap,
                      zoom: _zoom,
                      fullscreen: _fullscreen,
                      onClose: () => _close(data),
                      onPreviousPage: () => _jumpBy(-1),
                      onNextPage: () => _jumpBy(1),
                      onPreviousChapter: data.context?.prevChapterId == null
                          ? null
                          : () => _switchChapter(data.context!.prevChapterId!),
                      onNextChapter: data.context?.nextChapterId == null
                          ? null
                          : () => _switchChapter(data.context!.nextChapterId!),
                      onGapChanged: (gap) => setState(() => _pageGap = gap),
                      onZoomChanged: (zoom) => setState(() => _zoom = zoom),
                      onToggleFullscreen: _toggleFullscreen,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _PageIndicator(
                      currentPage: _currentPage,
                      pageCount: data.pages.length,
                      onSelected: _jumpToPage,
                    ),
                  ),
                ],
              );
            },
            error: (error, _) => Center(
              child: Text(
                error.toString(),
                style: const TextStyle(color: Colors.white70),
              ),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
          ),
        ),
      ),
    );
  }

  Widget _readerScrollView({required ReaderData data}) {
    if (data.pages.isEmpty) {
      return const Center(
        child: Text('No pages', style: TextStyle(color: Colors.white70)),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: EdgeInsets.only(top: 72, bottom: 74 + _pageGap),
      itemCount: data.pages.length,
      itemBuilder: (context, index) {
        final page = data.pages[index];
        final active = _isActivePage(index);
        final key = _pageKeys.putIfAbsent(index, GlobalKey.new);
        return Padding(
          key: key,
          padding: EdgeInsets.only(bottom: _pageGap),
          child: _ReaderPageItem(
            active: active,
            chapterId: widget.chapterId,
            page: page,
            targetWidth: _targetWidth(context),
            zoom: _zoom,
            profile: _profile,
          ),
        );
      },
    );
  }

  bool _isActivePage(int index) {
    final policy = _profilePolicy(_profile);
    return index >= _currentPage - policy.backward - 1 &&
        index <= _currentPage + policy.forward + 1;
  }

  int _targetWidth(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final policy = _profilePolicy(_profile);
    final width = (size.width * math.min(dpr, policy.maxDpr) * _zoom).round();
    return width.clamp(320, policy.maxWidth);
  }

  void _applySettings(Map<String, String> values) {
    final zoom = _decodeNumber(values['default_zoom'], 1);
    final gap = _decodeNumber(values['page_gap'], 10);
    final profile = _decodeProfile(values['image_pipeline_profile']);
    if (zoom == _zoom && gap == _pageGap && profile == _profile) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _zoom = zoom.clamp(0.5, 3);
      _pageGap = gap.clamp(0, 80);
      _profile = profile;
    });
  }

  double _decodeNumber(String? raw, double fallback) {
    if (raw == null) {
      return fallback;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is num) {
        return decoded.toDouble();
      }
      if (decoded is String) {
        return num.tryParse(decoded)?.toDouble() ?? fallback;
      }
    } on FormatException {
      return num.tryParse(raw)?.toDouble() ?? fallback;
    }
    return fallback;
  }

  bridge.ImageVariantProfile _decodeProfile(String? raw) {
    if (raw == null) {
      return bridge.ImageVariantProfile.balanced;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return _profileFromValue(raw);
    }
    final value = decoded is String ? decoded : raw.replaceAll('"', '');
    return _profileFromValue(value);
  }

  bridge.ImageVariantProfile _profileFromValue(String value) {
    return switch (value) {
      'performance' => bridge.ImageVariantProfile.performance,
      'quality' => bridge.ImageVariantProfile.quality,
      _ => bridge.ImageVariantProfile.balanced,
    };
  }

  void _restoreProgress(ReaderData data) {
    if (_restoredProgress || data.pages.isEmpty) {
      return;
    }
    _restoredProgress = true;
    final page = (data.progress?.lastPage ?? 0).clamp(0, data.pages.length - 1);
    _currentPage = page;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpToPage(page);
      unawaited(_prefetchAround(page));
    });
  }

  void _handleScroll() {
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
    if (_pageKeys.isEmpty) {
      return _currentPage;
    }
    final viewportCenter = MediaQuery.sizeOf(context).height / 2;
    var bestPage = _currentPage;
    var bestDistance = double.infinity;
    for (final entry in _pageKeys.entries) {
      final renderObject = entry.value.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) {
        continue;
      }
      final position = renderObject.localToGlobal(Offset.zero);
      final center = position.dy + renderObject.size.height / 2;
      final distance = (center - viewportCenter).abs();
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
            mode: 'webtoon',
            isRead: _currentPage >= data.pages.length - 1,
          ),
        );
  }

  Future<void> _prefetchAround(int page) async {
    final data = ref.read(readerDataProvider(widget.chapterId)).asData?.value;
    if (data == null || data.pages.isEmpty) {
      return;
    }
    final policy = _profilePolicy(_profile);
    final start = math.max(0, page - policy.backward);
    final end = math.min(data.pages.length - 1, page + policy.forward);
    await ref
        .read(comicRdApiProvider)
        .prefetchPageVariants(
          bridge.PrefetchPageVariantsPayload(
            chapterId: widget.chapterId,
            pageIndices: Uint32List.fromList([
              for (var index = start; index <= end; index++) index,
            ]),
            targetWidth: policy.maxWidth,
            profile: _profile,
          ),
        );
  }

  void _handleKey(LogicalKeyboardKey key, ReaderData? data) {
    if (key == LogicalKeyboardKey.escape) {
      if (data != null) {
        _close(data);
      } else {
        context.pop();
      }
    } else if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.pageDown) {
      _jumpBy(1);
    } else if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.pageUp) {
      _jumpBy(-1);
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

  void _jumpToPage(int page) {
    final keyContext = _pageKeys[page]?.currentContext;
    if (keyContext != null) {
      Scrollable.ensureVisible(
        keyContext,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: 0,
      );
    }
    setState(() => _currentPage = page);
    _scheduleProgressSave();
  }

  Future<void> _toggleFullscreen() async {
    _fullscreen = !_fullscreen;
    await SystemChrome.setEnabledSystemUIMode(
      _fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    if (mounted) {
      setState(() {});
    }
  }
}

class _ReaderPageItem extends ConsumerWidget {
  const _ReaderPageItem({
    required this.active,
    required this.chapterId,
    required this.page,
    required this.targetWidth,
    required this.zoom,
    required this.profile,
  });

  final bool active;
  final int chapterId;
  final bridge.PageInfo page;
  final int targetWidth;
  final double zoom;
  final bridge.ImageVariantProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aspectRatio = _aspectRatio(page);
    if (!active) {
      return _PagePlaceholder(aspectRatio: aspectRatio);
    }
    final rendered = ref.watch(
      renderedPageProvider(
        RenderedPageRequest(
          chapterId: chapterId,
          pageIndex: page.index,
          targetWidth: targetWidth,
          profile: profile,
        ),
      ),
    );
    return rendered.when(
      data: (page) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: targetWidth / zoom),
          child: Image.memory(
            page.bytes,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            fit: BoxFit.contain,
            width: page.width == 0 ? null : page.width.toDouble() / zoom,
          ),
        ),
      ),
      error: (error, _) =>
          _PagePlaceholder(aspectRatio: aspectRatio, label: error.toString()),
      loading: () => _PagePlaceholder(aspectRatio: aspectRatio),
    );
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
  const _PagePlaceholder({required this.aspectRatio, this.label});

  final double aspectRatio;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: ColoredBox(
          color: const Color(0xff141414),
          child: Center(
            child: label == null
                ? const CircularProgressIndicator()
                : Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      label!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _ReaderToolbar extends StatelessWidget {
  const _ReaderToolbar({
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
                IconButton(
                  tooltip: 'Close',
                  onPressed: onClose,
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        contextData?.comicTitle ?? 'ComicRD',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white),
                      ),
                      Text(
                        '${contextData?.title ?? 'Chapter'} - '
                        '${currentPage + 1}/${data.pages.length}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Previous chapter',
                  onPressed: onPreviousChapter,
                  icon: const Icon(Icons.skip_previous, color: Colors.white),
                ),
                IconButton(
                  tooltip: 'Previous page',
                  onPressed: onPreviousPage,
                  icon: const Icon(
                    Icons.keyboard_arrow_up,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  tooltip: 'Next page',
                  onPressed: onNextPage,
                  icon: const Icon(
                    Icons.keyboard_arrow_down,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  tooltip: 'Next chapter',
                  onPressed: onNextChapter,
                  icon: const Icon(Icons.skip_next, color: Colors.white),
                ),
                if (compact)
                  IconButton(
                    tooltip: 'Reader controls',
                    onPressed: () => _showReaderControls(context),
                    icon: const Icon(Icons.tune, color: Colors.white),
                  )
                else ...[
                  _MiniSlider(
                    tooltip: 'Gap',
                    icon: Icons.vertical_align_center,
                    value: pageGap,
                    min: 0,
                    max: 80,
                    onChanged: onGapChanged,
                  ),
                  _MiniSlider(
                    tooltip: 'Zoom',
                    icon: Icons.zoom_in,
                    value: zoom,
                    min: 0.5,
                    max: 3,
                    onChanged: onZoomChanged,
                  ),
                ],
                IconButton(
                  tooltip: 'Fullscreen',
                  onPressed: onToggleFullscreen,
                  icon: Icon(
                    fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    color: Colors.white,
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
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xff171717),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SheetSlider(
                      label: 'Gap',
                      value: sheetGap,
                      min: 0,
                      max: 80,
                      onChanged: (value) {
                        setSheetState(() => sheetGap = value);
                        onGapChanged(value);
                      },
                    ),
                    _SheetSlider(
                      label: 'Zoom',
                      value: sheetZoom,
                      min: 0.5,
                      max: 3,
                      onChanged: (value) {
                        setSheetState(() => sheetZoom = value);
                        onZoomChanged(value);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _MiniSlider extends StatelessWidget {
  const _MiniSlider({
    required this.tooltip,
    required this.icon,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String tooltip;
  final IconData icon;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 132,
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            Expanded(
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetSlider extends StatelessWidget {
  const _SheetSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(label, style: const TextStyle(color: Colors.white70)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            value.toStringAsFixed(1),
            textAlign: TextAlign.end,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      ],
    );
  }
}

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
            return ChoiceChip(
              selected: selected,
              label: Text('${index + 1}'),
              onSelected: (_) => onSelected(index),
            );
          },
        ),
      ),
    );
  }
}

_ProfilePolicy _profilePolicy(bridge.ImageVariantProfile profile) {
  return switch (profile) {
    bridge.ImageVariantProfile.performance => const _ProfilePolicy(
      maxWidth: 1280,
      maxDpr: 1,
      forward: 6,
      backward: 1,
    ),
    bridge.ImageVariantProfile.quality => const _ProfilePolicy(
      maxWidth: 2400,
      maxDpr: 1.75,
      forward: 4,
      backward: 2,
    ),
    bridge.ImageVariantProfile.balanced => const _ProfilePolicy(
      maxWidth: 1600,
      maxDpr: 1.25,
      forward: 5,
      backward: 1,
    ),
  };
}

class _ProfilePolicy {
  const _ProfilePolicy({
    required this.maxWidth,
    required this.maxDpr,
    required this.forward,
    required this.backward,
  });

  final int maxWidth;
  final double maxDpr;
  final int forward;
  final int backward;
}
