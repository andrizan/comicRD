import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_state.dart';
import 'library_state.dart';
import 'settings_data_state.dart';

/// Drops every provider that caches library or settings data so the next
/// read goes back to Rust (after a source change, scan, import or optimize).
void invalidateLibraryData(WidgetRef ref) {
  ref.invalidate(settingsEntriesProvider);
  ref.invalidate(settingsMapProvider);
  ref.invalidate(librarySourceStatusProvider);
  ref.invalidate(rawLibraryComicsProvider);
  ref.invalidate(libraryComicsProvider);
  ref.invalidate(comicsWithProgressProvider);
  ref.invalidate(readingHistoryProvider);
  ref.invalidate(allFavoritesProvider);
}

/// Stores [path] as the library root, registers it, and refreshes the data
/// providers. An empty path only clears the stored input.
Future<void> applyLibrarySource(WidgetRef ref, String path) async {
  final api = ref.read(comicRdApiProvider);
  final trimmed = path.trim();
  await api.setSetting('library_source_input', jsonEncode(trimmed));
  if (trimmed.isNotEmpty) {
    await api.addLibrary(trimmed);
  }
  invalidateLibraryData(ref);
}
