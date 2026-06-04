import 'package:flutter_riverpod/flutter_riverpod.dart';

final scrollOffsetsProvider =
    NotifierProvider<ScrollOffsetsNotifier, Map<String, double>>(
      ScrollOffsetsNotifier.new,
    );

class ScrollOffsetsNotifier extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() => const {};

  double offsetFor(String key) => state[key] ?? 0;

  void save(String key, double offset) {
    if (state[key] == offset) {
      return;
    }
    state = {...state, key: offset};
  }
}
