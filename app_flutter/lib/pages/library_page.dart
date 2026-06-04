import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/settings_state.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = stringsFor(ref.watch(appSettingsProvider).localeCode);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
          child: Row(
            children: [
              Expanded(
                child: SearchBar(
                  controller: _search,
                  leading: const Icon(Icons.search),
                  hintText: text.search,
                  constraints: const BoxConstraints(minHeight: 44),
                ),
              ),
              const SizedBox(width: 12),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'grid',
                    icon: const Icon(Icons.grid_view_outlined),
                    tooltip: text.library,
                  ),
                  ButtonSegment(
                    value: 'list',
                    icon: const Icon(Icons.view_list_outlined),
                    tooltip: text.library,
                  ),
                ],
                selected: const {'grid'},
                onSelectionChanged: (_) {},
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: text.history, icon: const Icon(Icons.history_outlined)),
            Tab(text: text.library, icon: const Icon(Icons.book_outlined)),
            Tab(
              text: text.bookmarks,
              icon: const Icon(Icons.bookmark_border_outlined),
            ),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _EmptyLibraryState(label: text.emptyLibrary),
              _EmptyLibraryState(label: text.emptyLibrary),
              _EmptyLibraryState(label: text.emptyLibrary),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyLibraryState extends StatelessWidget {
  const _EmptyLibraryState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(label, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
