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
  final window = WindowManager.instance.getCurrent()!;
  window.setSize(const Size(1024, 680).toNative(), false);
  window.minimumSize = const Size(960, 640).toNative();
  window.center();
  window.show();
  window.focus();
  const api = ComicRdApi();
  window.addListener(
    _WindowCloser(window, onClose: () => api.shutdown()).onEvent,
  );
  await api.init();
  runApp(const ProviderScope(child: ComicRdApp()));
}

/// Intercepts the first close request, runs the bounded cleanup, then closes
/// the window again; that second request is let through.
class _WindowCloser {
  _WindowCloser(this.window, {required this.onClose});

  final Window window;
  final Future<void> Function() onClose;
  bool _closing = false;

  void onEvent(WindowEvent event) {
    if (event is! WindowCloseRequestedEvent || _closing) {
      return;
    }
    _closing = true;
    event.request.cancel();
    unawaited(_shutdownAndClose());
  }

  Future<void> _shutdownAndClose() async {
    // Hide the window FIRST so the close feels instant to the user. All
    // cleanup below then happens while an invisible window is being torn
    // down, instead of the user staring at a frozen window.
    window.hide();

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
    window.close();
  }
}
