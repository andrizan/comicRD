import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'api.dart' as bridge;
import 'api/comicrd_api.dart';
import 'app.dart';
import 'state/api_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1024, 680),
    center: true,
    minimumSize: Size(960, 640),
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  const api = ComicRdApi();
  windowManager.setPreventClose(true);
  windowManager.addListener(_WindowListener(onClose: () => api.shutdown()));
  await api.init();
  runApp(const ProviderScope(child: ComicRdApp()));
}

class _WindowListener extends WindowListener {
  _WindowListener({required this.onClose});

  final Future<void> Function() onClose;

  @override
  void onWindowClose() async {
    // Hide the window FIRST so the close feels instant to the user. All
    // cleanup below then happens while an invisible window is being torn
    // down, instead of the user staring at a frozen window.
    unawaited(windowManager.hide());

    // Bounded cleanup so window close on Windows doesn't freeze
    // for seconds (WAL TRUNCATE + FRB dispose are slow on NTFS/Defender).
    final chapterId = ReaderSaveGuard.chapterId;
    if (chapterId != null) {
      try {
        await bridge
            .saveProgress(
              payload: bridge.SaveProgressPayload(
                chapterId: chapterId,
                lastPage: ReaderSaveGuard.lastPage,
                totalPages: ReaderSaveGuard.totalPages,
                isRead:
                    ReaderSaveGuard.lastPage >= ReaderSaveGuard.totalPages - 1,
              ),
            )
            .timeout(const Duration(milliseconds: 400));
      } catch (_) {}
    }
    try {
      await onClose().timeout(const Duration(milliseconds: 800));
    } catch (_) {
      // Timeout or error: still destroy window. The original
      // onClose future keeps running in background (timeout doesn't cancel it).
    }
    unawaited(windowManager.destroy());
  }
}
