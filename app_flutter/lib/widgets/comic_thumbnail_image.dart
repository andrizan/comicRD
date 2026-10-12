import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Decodes comic cover bytes under a key that is stable across fetches.
///
/// `Image.memory` keys the image cache by the identity of its `Uint8List`,
/// and the thumbnail provider hands out a fresh list every time a card
/// re-enters the viewport, so each scroll-back decoded the JPEG again and
/// left the previous decode as an orphan in the cache. Keying by
/// (source path, requested size) instead lets Flutter's bounded image
/// cache serve the existing decode and evict by its own LRU.
class ComicThumbnailImage extends ImageProvider<ComicThumbnailImage> {
  const ComicThumbnailImage({
    required this.sourcePath,
    required this.maxWidth,
    required this.maxHeight,
    required this.bytes,
  });

  final String sourcePath;
  final int maxWidth;
  final int maxHeight;
  final Uint8List bytes;

  @override
  Future<ComicThumbnailImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<ComicThumbnailImage>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    ComicThumbnailImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      debugLabel: 'ComicThumbnailImage(${key.sourcePath})',
    );
  }

  Future<ui.Codec> _loadAsync(
    ComicThumbnailImage key,
    ImageDecoderCallback decode,
  ) async {
    return decode(await ui.ImmutableBuffer.fromUint8List(key.bytes));
  }

  @override
  bool operator ==(Object other) {
    return other is ComicThumbnailImage &&
        other.sourcePath == sourcePath &&
        other.maxWidth == maxWidth &&
        other.maxHeight == maxHeight;
  }

  @override
  int get hashCode => Object.hash(sourcePath, maxWidth, maxHeight);
}
