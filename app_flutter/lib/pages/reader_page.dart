import 'package:flutter/material.dart';

class ReaderPage extends StatelessWidget {
  const ReaderPage({super.key, required this.chapterId});

  final int chapterId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            const Center(
              child: Icon(
                Icons.image_outlined,
                color: Colors.white54,
                size: 56,
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
