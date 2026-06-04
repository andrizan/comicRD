import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'pages/comic_page.dart';
import 'pages/library_page.dart';
import 'pages/reader_page.dart';
import 'routes/path_codec.dart';
import 'state/api_state.dart';
import 'state/settings_state.dart';
import 'widgets/settings_panel.dart';

final _router = GoRouter(
  routes: [
    ShellRoute(
      builder: (context, state, child) => ComicRdShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (context, state) => const LibraryPage()),
        GoRoute(
          path: '/comic/:comicPath',
          builder: (context, state) {
            final encodedPath = state.pathParameters['comicPath'] ?? '';
            return ComicPage(comicPath: decodeRoutePath(encodedPath));
          },
        ),
      ],
    ),
    GoRoute(
      path: '/reader/:chapterId',
      builder: (context, state) {
        final chapterId = int.tryParse(state.pathParameters['chapterId'] ?? '');
        return ReaderPage(chapterId: chapterId ?? 0);
      },
    ),
  ],
);

class ComicRdApp extends ConsumerWidget {
  const ComicRdApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    return MaterialApp.router(
      title: 'ComicRD',
      debugShowCheckedModeBanner: false,
      locale: const Locale('en'),
      supportedLocales: const [Locale('en')],
      themeMode: settings.themeMode,
      theme: buildComicRdTheme(Brightness.light),
      darkTheme: buildComicRdTheme(Brightness.dark),
      routerConfig: _router,
    );
  }
}

ThemeData buildComicRdTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xff2563eb),
        brightness: brightness,
      ).copyWith(
        surface: dark ? const Color(0xff111318) : const Color(0xfff7f8fb),
        primary: dark ? const Color(0xff8ab4ff) : const Color(0xff1d4ed8),
        secondary: dark ? const Color(0xff4fd1c5) : const Color(0xff0f766e),
        tertiary: dark ? const Color(0xfff7c948) : const Color(0xffa16207),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      elevation: 0,
      centerTitle: false,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        fixedSize: const Size.square(40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    ),
  );
}

class ComicRdShell extends ConsumerWidget {
  const ComicRdShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final text = stringsFor(settings.localeCode);
    return Scaffold(
      appBar: AppBar(
        title: const Text('ComicRD'),
        actions: [
          Tooltip(
            message: text.home,
            child: IconButton(
              onPressed: () => context.go('/'),
              icon: const Icon(Icons.home_outlined),
            ),
          ),
          Tooltip(
            message: text.theme,
            child: IconButton(
              onPressed: () async {
                final nextMode = settings.themeMode == ThemeMode.dark
                    ? ThemeMode.light
                    : ThemeMode.dark;
                ref.read(appSettingsProvider.notifier).setThemeMode(nextMode);
                await ref
                    .read(comicRdApiProvider)
                    .setSetting(
                      'app_theme',
                      jsonEncode(themeModeToSetting(nextMode)),
                    );
              },
              icon: Icon(
                settings.themeMode == ThemeMode.dark
                    ? Icons.dark_mode_outlined
                    : Icons.light_mode_outlined,
              ),
            ),
          ),
          Tooltip(
            message: text.locale,
            child: IconButton(
              onPressed: () async {
                final nextLocale = settings.localeCode == 'en' ? 'id' : 'en';
                ref.read(appSettingsProvider.notifier).setLocale(nextLocale);
                await ref
                    .read(comicRdApiProvider)
                    .setSetting('app_locale', jsonEncode(nextLocale));
              },
              icon: const Icon(Icons.translate_outlined),
            ),
          ),
          Tooltip(
            message: text.settings,
            child: IconButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (_) => const SettingsPanel(),
                );
              },
              icon: const Icon(Icons.tune_outlined),
            ),
          ),
        ],
      ),
      body: child,
    );
  }
}
