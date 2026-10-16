import 'package:flutter_riverpod/flutter_riverpod.dart';

final scrollOffsetsProvider =
    NotifierProvider<ScrollOffsetsNotifier, Map<String, double>>(
      ScrollOffsetsNotifier.new,
    );

/// Remembers scroll positions so a page can restore them when it is rebuilt.
///
/// The map is updated in place and never watched: positions are only read
/// back with [offsetFor] when a page is created. That also lets a page save
/// its final position from `dispose`, where Riverpod rejects state writes.
class ScrollOffsetsNotifier extends Notifier<Map<String, double>> {
  static const _maxSize = 200;

  @override
  Map<String, double> build() => <String, double>{};

  double offsetFor(String key) => state[key] ?? 0;

  void save(String key, double offset) {
    state[key] = offset;
    while (state.length > _maxSize) {
      state.remove(state.keys.first);
    }
  }
}
