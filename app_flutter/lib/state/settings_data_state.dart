import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge_generated.dart' as bridge;
import 'api_state.dart';

final settingsEntriesProvider = FutureProvider<List<bridge.SettingEntry>>((
  ref,
) {
  return ref.watch(comicRdApiProvider).listSettings();
});

final settingsMapProvider = FutureProvider<Map<String, String>>((ref) async {
  final entries = await ref.watch(settingsEntriesProvider.future);
  return {for (final entry in entries) entry.key: entry.valueJson};
});
