import 'dart:convert';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'pages/comic_page.dart';
import 'pages/library_page.dart';
import 'pages/reader_page.dart';
import 'routes/path_codec.dart';
import 'state/api_state.dart';
import 'state/library_state.dart';
import 'state/settings_data_state.dart';
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
    return FluentApp.router(
      title: stringsFor(settings.localeCode).appName,
      debugShowCheckedModeBanner: false,
      locale: const Locale('en'),
      supportedLocales: const [Locale('en')],
      themeMode: settings.themeMode,
      theme: FluentThemeData(
        brightness: Brightness.light,
        accentColor: Colors.blue,
        fontFamily: 'DM Sans',
      ),
      darkTheme: FluentThemeData(
        brightness: Brightness.dark,
        accentColor: Colors.blue,
        fontFamily: 'DM Sans',
      ),
      routerConfig: _router,
    );
  }
}

class ComicRdShell extends ConsumerStatefulWidget {
  const ComicRdShell({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ComicRdShell> createState() => _ComicRdShellState();
}

class _ComicRdShellState extends ConsumerState<ComicRdShell> {
  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<Map<String, String>>>(settingsMapProvider, (_, next) {
      next.whenData((values) {
        ref.read(appSettingsProvider.notifier).hydrateFromSettings(values);
        ref
            .read(libraryPreferencesProvider.notifier)
            .hydrateFromSettings(values);
      });
    });
    final settings = ref.watch(appSettingsProvider);
    final libraryPreferences = ref.watch(libraryPreferencesProvider);
    final text = stringsFor(settings.localeCode);
    return NavigationView(
      titleBar: TitleBar(
        title: Text(
          text.appName,
          style: const TextStyle(
            fontFamily: 'Syne',
            fontWeight: FontWeight.w700,
          ),
        ),
        endHeader: Row(
          children: [
            Tooltip(
              message: text.theme,
              child: DropDownButton(
                title: Icon(
                  settings.themeMode == ThemeMode.dark
                      ? FluentIcons.clear_night
                      : settings.themeMode == ThemeMode.light
                      ? FluentIcons.sunny
                      : FluentIcons.screen,
                ),
                items: [
                  MenuFlyoutItem(
                    text: Text(text.themeSystem),
                    leading: Icon(
                      FluentIcons.screen,
                      color: settings.themeMode == ThemeMode.system
                          ? FluentTheme.of(context).accentColor
                          : null,
                    ),
                    onPressed: () async {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setThemeMode(ThemeMode.system);
                      await ref
                          .read(comicRdApiProvider)
                          .setSetting(
                            'app_theme',
                            jsonEncode(themeModeToSetting(ThemeMode.system)),
                          );
                    },
                  ),
                  MenuFlyoutItem(
                    text: Text(text.themeLight),
                    leading: Icon(
                      FluentIcons.sunny,
                      color: settings.themeMode == ThemeMode.light
                          ? FluentTheme.of(context).accentColor
                          : null,
                    ),
                    onPressed: () async {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setThemeMode(ThemeMode.light);
                      await ref
                          .read(comicRdApiProvider)
                          .setSetting(
                            'app_theme',
                            jsonEncode(themeModeToSetting(ThemeMode.light)),
                          );
                    },
                  ),
                  MenuFlyoutItem(
                    text: Text(text.themeDark),
                    leading: Icon(
                      FluentIcons.clear_night,
                      color: settings.themeMode == ThemeMode.dark
                          ? FluentTheme.of(context).accentColor
                          : null,
                    ),
                    onPressed: () async {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setThemeMode(ThemeMode.dark);
                      await ref
                          .read(comicRdApiProvider)
                          .setSetting(
                            'app_theme',
                            jsonEncode(themeModeToSetting(ThemeMode.dark)),
                          );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: text.locale,
              child: DropDownButton(
                title: const Icon(FluentIcons.locale_language),
                items: [
                  MenuFlyoutItem(
                    text: Text(text.english),
                    leading: Text(
                      '🇺🇸',
                      style: FluentTheme.of(context).typography.body,
                    ),
                    onPressed: () async {
                      ref.read(appSettingsProvider.notifier).setLocale('en');
                      await ref
                          .read(comicRdApiProvider)
                          .setSetting('app_locale', jsonEncode('en'));
                    },
                  ),
                  MenuFlyoutItem(
                    text: Text(text.indonesian),
                    leading: Text(
                      '🇮🇩',
                      style: FluentTheme.of(context).typography.body,
                    ),
                    onPressed: () async {
                      ref.read(appSettingsProvider.notifier).setLocale('id');
                      await ref
                          .read(comicRdApiProvider)
                          .setSetting('app_locale', jsonEncode('id'));
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: text.settings,
              child: IconButton(
                icon: const Icon(FluentIcons.settings),
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (_) => const SettingsPanel(),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
      pane: NavigationPane(
        selected: _paneIndexForTab(libraryPreferences.selectedTab),
        onChanged: (index) => _setSelectedTab(_tabForPaneIndex(index)),
        displayMode: PaneDisplayMode.top,
        items: [
          PaneItem(
            icon: const Icon(FluentIcons.library),
            title: Text(text.library),
            body: widget.child,
          ),
          PaneItem(
            icon: const Icon(FluentIcons.history),
            title: Text(text.history),
            body: widget.child,
          ),
          PaneItem(
            icon: const Icon(FluentIcons.single_bookmark_solid),
            title: Text(text.bookmarks),
            body: widget.child,
          ),
        ],
      ),
    );
  }

  Future<void> _setSelectedTab(LibraryTab selectedTab) async {
    ref.read(libraryPreferencesProvider.notifier).setSelectedTab(selectedTab);
    await ref
        .read(comicRdApiProvider)
        .setSetting(
          'library_selected_tab',
          jsonEncode(encodeLibraryTab(selectedTab)),
        );
    if (mounted) {
      context.go('/');
    }
  }
}

int _paneIndexForTab(LibraryTab tab) {
  return switch (tab) {
    LibraryTab.library => 0,
    LibraryTab.history => 1,
    LibraryTab.bookmarks => 2,
  };
}

LibraryTab _tabForPaneIndex(int index) {
  return switch (index) {
    1 => LibraryTab.history,
    2 => LibraryTab.bookmarks,
    _ => LibraryTab.library,
  };
}
