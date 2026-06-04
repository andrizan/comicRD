import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/reader_state.dart';

class ReaderPage extends ConsumerWidget {
  const ReaderPage({super.key, required this.chapterId});

  final int chapterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reader = ref.watch(readerDataProvider(chapterId));
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: reader.when(
                data: (data) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.image_outlined,
                      color: Colors.white54,
                      size: 56,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      data.context?.title ?? 'Chapter $chapterId',
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${data.pages.length} pages',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
                error: (error, _) => Text(
                  error.toString(),
                  style: const TextStyle(color: Colors.white70),
                ),
                loading: () => const CircularProgressIndicator(),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: Tooltip(
                message: 'Close',
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
