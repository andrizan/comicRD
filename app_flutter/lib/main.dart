import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'api/comicrd_api.dart';
import 'app.dart';

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

  final VoidCallback onClose;

  @override
  void onWindowClose() async {
    onClose();
    await windowManager.destroy();
  }
}
