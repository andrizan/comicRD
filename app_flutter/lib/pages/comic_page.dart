import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../bridge_generated.dart' as bridge;
import '../state/comic_state.dart';
import '../state/scroll_state.dart';
import '../state/settings_state.dart';

class ComicPage extends ConsumerStatefulWidget {
  const ComicPage({super.key, required this.comicPath});

  final String comicPath;

  @override
  ConsumerState<ComicPage> createState() => _ComicPageState();
}

class _ComicPageState extends ConsumerState<ComicPage> {
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    final key = ref.read(comicScrollKeyProvider(widget.comicPath));
    final offsets = ref.read(scrollOffsetsProvider.notifier);
    _scroll = ScrollController(initialScrollOffset: offsets.offsetFor(key));
    _scroll.addListener(() {
      ref.read(scrollOffsetsProvider.notifier).save(key, _scroll.offset);
    });
  }

  @override
  void dispose() {
    if (_scroll.hasClients) {
      final key = ref.read(comicScrollKeyProvider(widget.comicPath));
      ref.read(scrollOffsetsProvider.notifier).save(key, _scroll.offset);
    }
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = stringsFor(ref.watch(appSettingsProvider).localeCode);
    final chapters = ref.watch(comicChaptersProvider(widget.comicPath));
    final favorites = ref.watch(chapterFavoritesProvider(widget.comicPath));
    final title = widget.comicPath.split(RegExp(r'[/\\]')).last;
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
            child: chapters.when(
              data: (items) => _ChapterList(
                chapters: items,
                favorites: favorites.asData?.value ?? const [],
                controller: _scroll,
                emptyLabel: text.emptyLibrary,
              ),
              error: (error, _) => Center(
                child: Text(
                  error.toString(),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChapterList extends StatelessWidget {
  const _ChapterList({
    required this.chapters,
    required this.favorites,
    required this.controller,
    required this.emptyLabel,
  });

  final List<bridge.RawChapter> chapters;
  final List<String> favorites;
  final ScrollController controller;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (chapters.isEmpty) {
      return Center(
        child: Text(emptyLabel, style: Theme.of(context).textTheme.titleMedium),
      );
    }
    return ListView.separated(
      controller: controller,
      itemCount: chapters.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final chapter = chapters[index];
        final favorite = favorites.contains(chapter.sourcePath);
        return ListTile(
          leading: Icon(
            favorite ? Icons.star : Icons.article_outlined,
            color: favorite ? Theme.of(context).colorScheme.tertiary : null,
          ),
          title: Text(chapter.title),
          subtitle: Text('${chapter.pageCount} pages'),
          trailing: chapter.isRead
              ? const Icon(Icons.done_all_outlined)
              : const Icon(Icons.chevron_right),
          onTap: () => context.go('/reader/${chapter.chapterIndex}'),
        );
      },
    );
  }
}
