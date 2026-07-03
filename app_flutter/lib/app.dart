import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import 'pages/comic_page.dart';
import 'pages/library_page.dart';
import 'pages/reader_page.dart';
import 'state/api_state.dart';
import 'state/library_state.dart';
import 'state/settings_data_state.dart';
import 'state/settings_state.dart';
import 'utils/forui_theme.dart';
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
            final comicPath = state.pathParameters['comicPath'] ?? '';
            return ComicPage(comicPath: comicPath);
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
    final isDark =
        settings.themeMode == ThemeMode.dark ||
        (settings.themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    final fTheme = isDark ? ComicReaderFTheme.dark : ComicReaderFTheme.light;
    return MaterialApp.router(
      title: stringsFor(settings.localeCode).appName,
      debugShowCheckedModeBanner: false,
      locale: const Locale('en'),
      supportedLocales: const [Locale('en')],
      themeMode: settings.themeMode,
      theme: ComicReaderFTheme.light.toApproximateMaterialTheme(),
      darkTheme: ComicReaderFTheme.dark.toApproximateMaterialTheme(),
      routerConfig: _router,
      builder: (context, child) => FTheme(
        data: fTheme,
        child: FToaster(child: FTooltipGroup(child: child!)),
      ),
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          ref.read(appSettingsProvider.notifier).hydrateFromSettings(values);
          ref
              .read(libraryPreferencesProvider.notifier)
              .hydrateFromSettings(values);
          ref.read(readerSettingsProvider.notifier).hydrateFromSettings(values);
        });
      });
    });
    final settings = ref.watch(appSettingsProvider);
    final libraryPreferences = ref.watch(libraryPreferencesProvider);
    final text = stringsFor(settings.localeCode);
    final selectedTab = libraryPreferences.selectedTab;
    return DragToMoveArea(
      child: ColoredBox(
        color: context.theme.colors.background,
        child: Column(
          children: [
            _ShellHeader(
              text: text,
              themeMode: settings.themeMode,
              selectedTab: selectedTab,
              onSelectTab: (tab) => _setSelectedTab(tab),
              onThemeChanged: (mode) async {
                ref.read(appSettingsProvider.notifier).setThemeMode(mode);
                await ref
                    .read(comicRdApiProvider)
                    .setSetting(
                      'app_theme',
                      jsonEncode(themeModeToSetting(mode)),
                    );
              },
              onLocaleChanged: (locale) async {
                ref.read(appSettingsProvider.notifier).setLocale(locale);
                await ref
                    .read(comicRdApiProvider)
                    .setSetting('app_locale', jsonEncode(locale));
              },
              onSettingsPressed: () {
                showFDialog<void>(
                  context: context,
                  builder: (context, style, animation) => const SettingsPanel(),
                );
              },
            ),
            Expanded(child: widget.child),
          ],
        ),
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

class _ShellHeader extends StatelessWidget {
  const _ShellHeader({
    required this.text,
    required this.themeMode,
    required this.selectedTab,
    required this.onSelectTab,
    required this.onThemeChanged,
    required this.onLocaleChanged,
    required this.onSettingsPressed,
  });

  final AppStrings text;
  final ThemeMode themeMode;
  final LibraryTab selectedTab;
  final ValueChanged<LibraryTab> onSelectTab;
  final ValueChanged<ThemeMode> onThemeChanged;
  final ValueChanged<String> onLocaleChanged;
  final VoidCallback onSettingsPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.theme.colors.background,
        border: Border(bottom: BorderSide(color: context.theme.colors.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 16, 8),
          child: Row(
            children: [
              Text(
                text.appName,
                style: const TextStyle(
                  fontFamily: appFontFamily,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _NavButton(
                      icon: AppIcons.library,
                      label: text.library,
                      selected: selectedTab == LibraryTab.library,
                      onPressed: () => onSelectTab(LibraryTab.library),
                    ),
                    const SizedBox(width: 4),
                    _NavButton(
                      icon: AppIcons.history,
                      label: text.history,
                      selected: selectedTab == LibraryTab.history,
                      onPressed: () => onSelectTab(LibraryTab.history),
                    ),
                    const SizedBox(width: 4),
                    _NavButton(
                      icon: AppIcons.bookmark,
                      label: text.bookmarks,
                      selected: selectedTab == LibraryTab.bookmarks,
                      onPressed: () => onSelectTab(LibraryTab.bookmarks),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _ThemeMenuButton(
                text: text,
                themeMode: themeMode,
                onChanged: onThemeChanged,
              ),
              const SizedBox(width: 8),
              _LocaleMenuButton(text: text, onChanged: onLocaleChanged),
              const SizedBox(width: 8),
              FButton.icon(
                variant: .ghost,
                onPress: onSettingsPressed,
                child: const Icon(AppIcons.settings),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FButton(
      variant: .ghost,
      selected: selected,
      onPress: onPressed,
      prefix: Icon(icon),
      child: Text(label),
    );
  }
}

class _ThemeMenuButton extends StatelessWidget {
  const _ThemeMenuButton({
    required this.text,
    required this.themeMode,
    required this.onChanged,
  });

  final AppStrings text;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final icon = switch (themeMode) {
      ThemeMode.dark => AppIcons.moon,
      ThemeMode.light => AppIcons.sun,
      ThemeMode.system => AppIcons.monitor,
    };
    return FPopoverMenu(
      menuAnchor: .bottomEnd,
      childAnchor: .topEnd,
      menu: [
        FItemGroup(
          children: [
            FItem(
              prefix: Icon(
                AppIcons.monitor,
                color: themeMode == ThemeMode.system ? context.appAccent : null,
              ),
              title: Text(text.themeSystem),
              onPress: () => onChanged(ThemeMode.system),
            ),
            FItem(
              prefix: Icon(
                AppIcons.sun,
                color: themeMode == ThemeMode.light ? context.appAccent : null,
              ),
              title: Text(text.themeLight),
              onPress: () => onChanged(ThemeMode.light),
            ),
            FItem(
              prefix: Icon(
                AppIcons.moon,
                color: themeMode == ThemeMode.dark ? context.appAccent : null,
              ),
              title: Text(text.themeDark),
              onPress: () => onChanged(ThemeMode.dark),
            ),
          ],
        ),
      ],
      builder: (_, controller, _) => FButton.icon(
        variant: .ghost,
        onPress: controller.toggle,
        child: Icon(icon),
      ),
    );
  }
}

class _LocaleMenuButton extends StatelessWidget {
  const _LocaleMenuButton({required this.text, required this.onChanged});

  final AppStrings text;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return FPopoverMenu(
      menuAnchor: .bottomEnd,
      childAnchor: .topEnd,
      menu: [
        FItemGroup(
          children: [
            FItem(
              prefix: const Text('🇺🇸'),
              title: Text(text.english),
              onPress: () => onChanged('en'),
            ),
            FItem(
              prefix: const Text('🇮🇩'),
              title: Text(text.indonesian),
              onPress: () => onChanged('id'),
            ),
          ],
        ),
      ],
      builder: (_, controller, _) => FButton.icon(
        variant: .ghost,
        onPress: controller.toggle,
        child: const Icon(AppIcons.languages),
      ),
    );
  }
}
