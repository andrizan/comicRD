import 'dart:typed_data';

import 'package:comicrd_flutter/widgets/comic_thumbnail_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// 1x1 transparent PNG.
final Uint8List _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

ComicThumbnailImage _cover(String sourcePath, {int width = 200}) {
  // A fresh Uint8List per call, like the thumbnail provider hands out.
  return ComicThumbnailImage(
    sourcePath: sourcePath,
    maxWidth: width,
    maxHeight: 300,
    bytes: Uint8List.fromList(_png),
  );
}

void main() {
  test('key is the comic path and requested size, not the byte instance', () {
    expect(_cover('/library/a'), equals(_cover('/library/a')));
    expect(_cover('/library/a').hashCode, _cover('/library/a').hashCode);
    expect(_cover('/library/a'), isNot(equals(_cover('/library/b'))));
    expect(
      _cover('/library/a'),
      isNot(equals(_cover('/library/a', width: 260))),
    );
  });

  testWidgets('cards for the same comic share one image cache entry', (
    tester,
  ) async {
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
    addTearDown(() {
      cache.clear();
      cache.clearLiveImages();
    });

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            Image(image: _cover('/library/a'), width: 10, height: 10),
            Image(image: _cover('/library/a'), width: 10, height: 10),
            Image(image: _cover('/library/b'), width: 10, height: 10),
          ],
        ),
      ),
    );

    // Two distinct keys for three widgets: the duplicate comic resolved to
    // the entry already in the cache instead of decoding its bytes again.
    expect(cache.liveImageCount, 2);
    expect(cache.statusForKey(_cover('/library/a')).untracked, isFalse);
    expect(cache.statusForKey(_cover('/library/b')).untracked, isFalse);
  });
}
