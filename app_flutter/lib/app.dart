import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import 'pages/comic_page.dart';
import 'pages/library_page.dart';
import 'pages/reader_page.dart';
import 'pages/settings_page.dart';
import 'routes/path_codec.dart';
import 'state/api_state.dart';
import 'state/library_state.dart';
import 'state/settings_data_state.dart';
import 'state/settings_state.dart';
import 'utils/forui_theme.dart';

final _router = GoRouter(
  routes: [
    ShellRoute(
      builder: (context, state, child) => ComicRdShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (context, state) => const LibraryPage()),
        GoRoute(
          path: '/comic/:comicPath',
          builder: (context, state) {
            final comicPath = decodeRoutePath(
              state.pathParameters['comicPath'] ?? '',
            );
            return ComicPage(comicPath: comicPath);
          },
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsPage(),
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

enum SidebarTab { library, history, favorites, settings }

final sidebarTabProvider = NotifierProvider<SidebarTabNotifier, SidebarTab>(
  SidebarTabNotifier.new,
);

class SidebarTabNotifier extends Notifier<SidebarTab> {
  @override
  SidebarTab build() => SidebarTab.library;

  void set(SidebarTab tab) {
    state = tab;
  }
}

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
      locale: Locale(settings.localeCode),
      supportedLocales: const [Locale('en'), Locale('id')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      themeMode: settings.themeMode,
      theme: _materialTheme(ComicReaderFTheme.light, ComicReaderColors.light),
      darkTheme: _materialTheme(ComicReaderFTheme.dark, ComicReaderColors.dark),
      routerConfig: _router,
      builder: (context, child) => FTheme(
        data: fTheme,
        child: FToaster(
          child: FTooltipGroup(
            // Bridges the modern material_ui theme down to legacy SDK
            // Material for dependencies (forui) that still import
            // package:flutter/material.dart. Remove once they migrate.
            // ignore: deprecated_member_use
            child: MaterialUiCompatibilityBridge(child: child!),
          ),
        ),
      ),
    );
  }
}

/// Mirrors forui's `FThemeData.toApproximateMaterialTheme` with modern
/// `material_ui` types so the root theme and the [ComicReaderColors]
/// extension share one type universe.
ThemeData _materialTheme(FThemeData f, ComicReaderColors readerColors) {
  return ThemeData(
    colorScheme: ColorScheme(
      brightness: f.colors.brightness,
      primary: f.colors.primary,
      onPrimary: f.colors.primaryForeground,
      secondary: f.colors.secondary,
      onSecondary: f.colors.secondaryForeground,
      error: f.colors.error,
      onError: f.colors.errorForeground,
      surface: f.colors.background,
      onSurface: f.colors.foreground,
      secondaryContainer: f.colors.secondary,
      onSecondaryContainer: f.colors.secondaryForeground,
    ),
    fontFamily: appFontFamily,
    extensions: [readerColors],
  );
}

class ComicRdShell extends ConsumerStatefulWidget {
  const ComicRdShell({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ComicRdShell> createState() => _ComicRdShellState();
}

class _ComicRdShellState extends ConsumerState<ComicRdShell> {
  bool _sidebarCollapsed = false;
  int _libraryCount = 0;
  int _favoriteCount = 0;
  bool _countsHooked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_countsHooked) {
      _countsHooked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.listenManual<int>(libraryCountProvider, (_, next) {
          if (mounted) setState(() => _libraryCount = next);
        }, fireImmediately: true);
        ref.listenManual<int>(favoriteCountProvider, (_, next) {
          if (mounted) setState(() => _favoriteCount = next);
        }, fireImmediately: true);
      });
    }
  }

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
    final text = stringsFor(settings.localeCode);
    final selectedTab = ref.watch(sidebarTabProvider);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncSidebarTabWithRoute();
    });

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: () {},
      child: Shortcuts(
        shortcuts: <LogicalKeySet, Intent>{
          LogicalKeySet(LogicalKeyboardKey.keyT, LogicalKeyboardKey.control):
              const _ToggleThemeIntent(),
          LogicalKeySet(LogicalKeyboardKey.keyL, LogicalKeyboardKey.control):
              const _ToggleLocaleIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _ToggleThemeIntent: CallbackAction<_ToggleThemeIntent>(
              onInvoke: (_) => _onThemeShortcut(),
            ),
            _ToggleLocaleIntent: CallbackAction<_ToggleLocaleIntent>(
              onInvoke: (_) => _onLocaleShortcut(),
            ),
          },
          child: ColoredBox(
            color: context.theme.colors.background,
            child: Row(
              children: [
                _Sidebar(
                  collapsed: _sidebarCollapsed,
                  onToggleCollapse: () =>
                      setState(() => _sidebarCollapsed = !_sidebarCollapsed),
                  text: text,
                  selectedTab: selectedTab,
                  libraryCount: _libraryCount,
                  favoriteCount: _favoriteCount,
                  onSelectTab: _setSelectedTab,
                ),
                Expanded(
                  child: Column(
                    children: [
                      _TopBar(
                        text: text,
                        themeMode: settings.themeMode,
                        locale: settings.localeCode,
                        onThemeChanged: (mode) async {
                          ref
                              .read(appSettingsProvider.notifier)
                              .setThemeMode(mode);
                          await ref
                              .read(comicRdApiProvider)
                              .setSetting(
                                'app_theme',
                                jsonEncode(themeModeToSetting(mode)),
                              );
                        },
                        onLocaleChanged: (locale) async {
                          ref
                              .read(appSettingsProvider.notifier)
                              .setLocale(locale);
                          await ref
                              .read(comicRdApiProvider)
                              .setSetting('app_locale', jsonEncode(locale));
                        },
                      ),
                      Expanded(child: widget.child),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _syncSidebarTabWithRoute() {
    if (!mounted) return;
    final location = GoRouterState.of(context).uri.path;
    final libraryTab = ref.read(libraryPreferencesProvider).selectedTab;
    SidebarTab nextTab;
    if (location == '/settings') {
      nextTab = SidebarTab.settings;
    } else {
      nextTab = switch (libraryTab) {
        LibraryTab.library => SidebarTab.library,
        LibraryTab.history => SidebarTab.history,
        LibraryTab.favorites => SidebarTab.favorites,
      };
    }
    if (ref.read(sidebarTabProvider) != nextTab) {
      ref.read(sidebarTabProvider.notifier).set(nextTab);
    }
  }

  Future<void> _setSelectedTab(SidebarTab selectedTab) async {
    ref.read(sidebarTabProvider.notifier).set(selectedTab);
    switch (selectedTab) {
      case SidebarTab.library:
        ref
            .read(libraryPreferencesProvider.notifier)
            .setSelectedTab(LibraryTab.library);
        await ref
            .read(comicRdApiProvider)
            .setSetting(
              'library_selected_tab',
              jsonEncode(encodeLibraryTab(LibraryTab.library)),
            );
        if (mounted) context.go('/');
      case SidebarTab.history:
        ref
            .read(libraryPreferencesProvider.notifier)
            .setSelectedTab(LibraryTab.history);
        await ref
            .read(comicRdApiProvider)
            .setSetting(
              'library_selected_tab',
              jsonEncode(encodeLibraryTab(LibraryTab.history)),
            );
        if (mounted) context.go('/');
      case SidebarTab.favorites:
        ref
            .read(libraryPreferencesProvider.notifier)
            .setSelectedTab(LibraryTab.favorites);
        await ref
            .read(comicRdApiProvider)
            .setSetting(
              'library_selected_tab',
              jsonEncode(encodeLibraryTab(LibraryTab.favorites)),
            );
        if (mounted) context.go('/');
      case SidebarTab.settings:
        if (mounted) context.go('/settings');
    }
  }

  void _onThemeShortcut() {
    ref.read(appSettingsProvider.notifier).toggleTheme();
  }

  void _onLocaleShortcut() {
    ref.read(appSettingsProvider.notifier).toggleLocale();
  }
}

class _Sidebar extends StatefulWidget {
  const _Sidebar({
    required this.collapsed,
    required this.onToggleCollapse,
    required this.text,
    required this.selectedTab,
    required this.libraryCount,
    required this.favoriteCount,
    required this.onSelectTab,
  });

  final bool collapsed;
  final VoidCallback onToggleCollapse;
  final AppStrings text;
  final SidebarTab selectedTab;
  final int libraryCount;
  final int favoriteCount;
  final ValueChanged<SidebarTab> onSelectTab;

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  // Hover state lives at the sidebar level so it survives any rebuild of the
  // shell (e.g. settings hydration, count updates) and is not coupled to
  // individual nav item widgets that may be re-created during parent
  // reconciliation. This prevents the cursor-above-but-hover-cleared bug.
  int? _hoveredIndex;

  void _setHovered(int? index) {
    if (_hoveredIndex == index) return;
    setState(() => _hoveredIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOutCubic,
      clipBehavior: Clip.hardEdge,
      width: widget.collapsed ? 72.0 : 260.0,
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(right: BorderSide(color: colors.border)),
      ),
      padding: EdgeInsets.fromLTRB(
        widget.collapsed ? 8 : 16,
        24,
        widget.collapsed ? 8 : 16,
        24,
      ),
      child: Column(
        crossAxisAlignment: widget.collapsed
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          _SidebarBrand(
            collapsed: widget.collapsed,
            onToggleCollapse: widget.onToggleCollapse,
            text: widget.text,
          ),
          const SizedBox(height: 32),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topLeft,
            curve: Curves.easeOutCubic,
            child: widget.collapsed
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 12),
                    child: Text(
                      widget.text.menu.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                        color: colors.mutedForeground,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          _SidebarNavItem(
            index: 0,
            collapsed: widget.collapsed,
            icon: AppIcons.library,
            label: widget.text.library,
            count: widget.libraryCount,
            selected: widget.selectedTab == SidebarTab.library,
            hovered: _hoveredIndex == 0,
            onHoverChanged: _setHovered,
            onTap: () => widget.onSelectTab(SidebarTab.library),
          ),
          const SizedBox(height: 4),
          _SidebarNavItem(
            index: 1,
            collapsed: widget.collapsed,
            icon: AppIcons.history,
            label: widget.text.history,
            selected: widget.selectedTab == SidebarTab.history,
            hovered: _hoveredIndex == 1,
            onHoverChanged: _setHovered,
            onTap: () => widget.onSelectTab(SidebarTab.history),
          ),
          const SizedBox(height: 4),
          _SidebarNavItem(
            index: 2,
            collapsed: widget.collapsed,
            icon: AppIcons.star,
            label: widget.text.favorites,
            count: widget.favoriteCount,
            selected: widget.selectedTab == SidebarTab.favorites,
            hovered: _hoveredIndex == 2,
            onHoverChanged: _setHovered,
            onTap: () => widget.onSelectTab(SidebarTab.favorites),
          ),
          const Spacer(),
          const SizedBox(height: 4),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topLeft,
            curve: Curves.easeOutCubic,
            child: widget.collapsed
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 12),
                    child: Text(
                      widget.text.settings.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                        color: colors.mutedForeground,
                      ),
                    ),
                  ),
          ),
          _SidebarNavItem(
            index: 3,
            collapsed: widget.collapsed,
            icon: AppIcons.settings,
            label: widget.text.settings,
            selected: widget.selectedTab == SidebarTab.settings,
            hovered: _hoveredIndex == 3,
            onHoverChanged: _setHovered,
            onTap: () => widget.onSelectTab(SidebarTab.settings),
          ),
        ],
      ),
    );
  }
}

class _SidebarBrand extends StatelessWidget {
  const _SidebarBrand({
    required this.collapsed,
    required this.onToggleCollapse,
    required this.text,
  });

  final bool collapsed;
  final VoidCallback onToggleCollapse;
  final AppStrings text;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Row(
      mainAxisAlignment: collapsed
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onToggleCollapse,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.transparent,
              ),
              child: Icon(
                AppIcons.menu,
                size: 24,
                color: colors.mutedForeground,
              ),
            ),
          ),
        ),
        if (!collapsed) ...[
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              text.appName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: appFontFamily,
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: colors.foreground,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  const _SidebarNavItem({
    required this.index,
    required this.collapsed,
    required this.icon,
    required this.label,
    required this.selected,
    required this.hovered,
    required this.onHoverChanged,
    required this.onTap,
    this.count,
  });

  final int index;
  final bool collapsed;
  final IconData icon;
  final String label;
  final int? count;
  final bool selected;
  final bool hovered;
  final ValueChanged<int?> onHoverChanged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    // MouseRegion lives around the whole row so the hover state is owned by
    // the sidebar, not by this widget. This guarantees the hover highlight
    // persists even when the shell rebuilds (settings hydration, count
    // changes, etc.) which used to reset the cursor-on-but-not-hovered
    // visual on the nav items.
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      opaque: true,
      onEnter: (_) => onHoverChanged(index),
      onExit: (_) {
        if (hovered) onHoverChanged(null);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: selected
                ? colors.secondary
                : hovered
                ? colors.secondary.withValues(alpha: 0.55)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final hasSpace = constraints.maxWidth > 100;
              return Row(
                mainAxisAlignment: !hasSpace
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  if (selected && hasSpace)
                    Container(
                      width: 3,
                      height: 18,
                      margin: const EdgeInsets.only(right: 9),
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    )
                  else if (hasSpace)
                    const SizedBox(width: 12),
                  Icon(
                    icon,
                    size: 20,
                    color: selected ? colors.primary : colors.mutedForeground,
                  ),
                  if (hasSpace) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: selected ? colors.primary : colors.foreground,
                        ),
                      ),
                    ),
                    if (count != null && count! > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.secondary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colors.primary,
                          ),
                        ),
                      ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.text,
    required this.themeMode,
    required this.locale,
    required this.onThemeChanged,
    required this.onLocaleChanged,
  });

  final AppStrings text;
  final ThemeMode themeMode;
  final String locale;
  final ValueChanged<ThemeMode> onThemeChanged;
  final ValueChanged<String> onLocaleChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: context.theme.colors.background,
        border: Border(bottom: BorderSide(color: context.theme.colors.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _ThemeMenuButton(
                text: text,
                themeMode: themeMode,
                onChanged: onThemeChanged,
              ),
              const SizedBox(width: 8),
              _LocaleMenuButton(
                text: text,
                locale: locale,
                onChanged: onLocaleChanged,
              ),
            ],
          ),
        ),
      ),
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
    final activeColor = context.appAccent;
    return FPopoverMenu(
      menuAnchor: .bottomEnd,
      childAnchor: .topEnd,
      menu: [
        FItemGroup(
          children: [
            FItem(
              prefix: Icon(
                AppIcons.monitor,
                color: themeMode == ThemeMode.system ? activeColor : null,
              ),
              title: Text(text.themeSystem),
              suffix: themeMode == ThemeMode.system
                  ? Icon(AppIcons.check, size: 16, color: activeColor)
                  : null,
              selected: themeMode == ThemeMode.system,
              onPress: () => onChanged(ThemeMode.system),
            ),
            FItem(
              prefix: Icon(
                AppIcons.sun,
                color: themeMode == ThemeMode.light ? activeColor : null,
              ),
              title: Text(text.themeLight),
              suffix: themeMode == ThemeMode.light
                  ? Icon(AppIcons.check, size: 16, color: activeColor)
                  : null,
              selected: themeMode == ThemeMode.light,
              onPress: () => onChanged(ThemeMode.light),
            ),
            FItem(
              prefix: Icon(
                AppIcons.moon,
                color: themeMode == ThemeMode.dark ? activeColor : null,
              ),
              title: Text(text.themeDark),
              suffix: themeMode == ThemeMode.dark
                  ? Icon(AppIcons.check, size: 16, color: activeColor)
                  : null,
              selected: themeMode == ThemeMode.dark,
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
  const _LocaleMenuButton({
    required this.text,
    required this.locale,
    required this.onChanged,
  });

  final AppStrings text;
  final String locale;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final activeColor = context.appAccent;
    return FPopoverMenu(
      menuAnchor: .bottomEnd,
      childAnchor: .topEnd,
      menu: [
        FItemGroup(
          children: [
            FItem(
              prefix: const Text('🇺🇸'),
              title: Text(text.english),
              suffix: locale == 'en'
                  ? Icon(AppIcons.check, size: 16, color: activeColor)
                  : null,
              selected: locale == 'en',
              onPress: () => onChanged('en'),
            ),
            FItem(
              prefix: const Text('🇮🇩'),
              title: Text(text.indonesian),
              suffix: locale == 'id'
                  ? Icon(AppIcons.check, size: 16, color: activeColor)
                  : null,
              selected: locale == 'id',
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

class _ToggleThemeIntent extends Intent {
  const _ToggleThemeIntent();
}

class _ToggleLocaleIntent extends Intent {
  const _ToggleLocaleIntent();
}
