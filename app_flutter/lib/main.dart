import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/comicrd_api.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await const ComicRdApi().init();
  runApp(const ProviderScope(child: ComicRdApp()));
}
