import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/settings_state.dart';

class ComicPage extends ConsumerWidget {
  const ComicPage({super.key, required this.comicPath});

  final String comicPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = stringsFor(ref.watch(appSettingsProvider).localeCode);
    final title = comicPath.split(RegExp(r'[/\\]')).last;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.isEmpty ? text.comic : title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          SearchBar(
            leading: const Icon(Icons.search),
            hintText: text.search,
            constraints: const BoxConstraints(minHeight: 44),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Center(
              child: Text(
                text.emptyLibrary,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
