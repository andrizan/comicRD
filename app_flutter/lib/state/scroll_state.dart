import 'package:flutter_riverpod/flutter_riverpod.dart';

final scrollOffsetsProvider =
    NotifierProvider<ScrollOffsetsNotifier, Map<String, double>>(
      ScrollOffsetsNotifier.new,
    );

class ScrollOffsetsNotifier extends Notifier<Map<String, double>> {
  static const _maxSize = 200;

  @override
  Map<String, double> build() => const {};

  double offsetFor(String key) => state[key] ?? 0;

  void save(String key, double offset) {
    if (state[key] == offset) {
      return;
    }
    final updated = {...state, key: offset};
    if (updated.length > _maxSize) {
      final keys = updated.keys.toList();
      for (var i = 0; i < keys.length - _maxSize; i++) {
        updated.remove(keys[i]);
      }
    }
    state = updated;
  }
}
