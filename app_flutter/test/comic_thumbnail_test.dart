import 'dart:typed_data';

import 'package:comicrd_flutter/api/comicrd_api.dart';
import 'package:comicrd_flutter/state/api_state.dart';
import 'package:comicrd_flutter/state/library_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('thumbnail provider returns null silently for empty bytes', () async {
    final container = ProviderContainer(
      overrides: [
        comicRdApiProvider.overrideWithValue(const _EmptyThumbnailApi()),
      ],
    );
    addTearDown(container.dispose);

    final result = await container.read(
      comicThumbnailProvider((
        sourcePath: '/library/empty',
        maxWidth: 200,
        maxHeight: 300,
      )).future,
    );

    expect(result, isNull);
  });

  test('thumbnail provider returns null silently on error', () async {
    final container = ProviderContainer(
      overrides: [
        comicRdApiProvider.overrideWithValue(const _ThrowingThumbnailApi()),
      ],
    );
    addTearDown(container.dispose);

    final result = await container.read(
      comicThumbnailProvider((
        sourcePath: '/library/missing',
        maxWidth: 200,
        maxHeight: 300,
      )).future,
    );

    expect(result, isNull);
  });
}

class _EmptyThumbnailApi extends ComicRdApi {
  const _EmptyThumbnailApi();

  @override
  Future<Uint8List> getComicThumbnail(
    String sourcePath, {
    int maxWidth = 200,
    int maxHeight = 300,
  }) async {
    return Uint8List(0);
  }
}

class _ThrowingThumbnailApi extends ComicRdApi {
  const _ThrowingThumbnailApi();

  @override
  Future<Uint8List> getComicThumbnail(
    String sourcePath, {
    int maxWidth = 200,
    int maxHeight = 300,
  }) async {
    throw Exception('no cover image or chapter found in comic folder');
  }
}
