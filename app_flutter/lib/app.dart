import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import 'bridge_generated.dart' as bridge;
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
import 'widgets/soft_ui.dart';

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
        child: FToaster(child: FTooltipGroup(child: child!)),
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
    scaffoldBackgroundColor: f.colors.background,
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
    // The selected nav item follows the route and the library tab directly,
    // so a tab change made inside a page (e.g. "View History") is reflected
    // without a second source of truth.
    final libraryTab = ref.watch(
      libraryPreferencesProvider.select((p) => p.selectedTab),
    );
    final location = GoRouterState.of(context).uri.path;
    final selectedTab = location == '/settings'
        ? SidebarTab.settings
        : switch (libraryTab) {
            LibraryTab.library => SidebarTab.library,
            LibraryTab.history => SidebarTab.history,
            LibraryTab.favorites => SidebarTab.favorites,
          };

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
                Expanded(child: widget.child),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _setSelectedTab(SidebarTab selectedTab) async {
    if (selectedTab == SidebarTab.settings) {
      context.go('/settings');
      return;
    }
    final libraryTab = switch (selectedTab) {
      SidebarTab.library => LibraryTab.library,
      SidebarTab.history => LibraryTab.history,
      SidebarTab.favorites => LibraryTab.favorites,
      SidebarTab.settings => LibraryTab.library,
    };
    ref.read(libraryPreferencesProvider.notifier).setSelectedTab(libraryTab);
    context.go('/');
    await ref
        .read(comicRdApiProvider)
        .setSetting(
          'library_selected_tab',
          jsonEncode(encodeLibraryTab(libraryTab)),
        );
  }

  Future<void> _onThemeShortcut() async {
    ref.read(appSettingsProvider.notifier).toggleTheme();
    final mode = ref.read(appSettingsProvider).themeMode;
    await ref
        .read(comicRdApiProvider)
        .setSetting('app_theme', jsonEncode(themeModeToSetting(mode)));
  }

  Future<void> _onLocaleShortcut() async {
    ref.read(appSettingsProvider.notifier).toggleLocale();
    final locale = ref.read(appSettingsProvider).localeCode;
    await ref
        .read(comicRdApiProvider)
        .setSetting('app_locale', jsonEncode(locale));
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

  static const double expandedWidth = 264;
  static const double collapsedWidth = 76;

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  // Hover state lives at the sidebar level so it survives any rebuild of the
  // shell (settings hydration, count updates) and is not coupled to nav item
  // widgets that may be re-created during parent reconciliation.
  SidebarTab? _hovered;

  void _setHovered(SidebarTab? tab) {
    if (_hovered == tab) return;
    setState(() => _hovered = tab);
  }

  @override
  Widget build(BuildContext context) {
    final collapsed = widget.collapsed;
    final reader = context.appReader;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeInOutCubic,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(color: context.theme.colors.background),
      width: collapsed ? _Sidebar.collapsedWidth : _Sidebar.expandedWidth,
      padding: EdgeInsets.fromLTRB(
        collapsed ? 12 : 24,
        28,
        collapsed ? 12 : 16,
        24,
      ),
      child: Column(
        crossAxisAlignment: collapsed
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.stretch,
        children: [
          _SidebarBrand(
            collapsed: collapsed,
            onToggleCollapse: widget.onToggleCollapse,
            text: widget.text,
          ),
          const SizedBox(height: 28),
          _SidebarNavItem(
            tab: SidebarTab.library,
            collapsed: collapsed,
            icon: AppIcons.library,
            label: widget.text.library,
            count: widget.libraryCount,
            selected: widget.selectedTab == SidebarTab.library,
            hovered: _hovered == SidebarTab.library,
            onHoverChanged: _setHovered,
            onTap: () => widget.onSelectTab(SidebarTab.library),
          ),
          const SizedBox(height: 4),
          _SidebarNavItem(
            tab: SidebarTab.history,
            collapsed: collapsed,
            icon: AppIcons.clock,
            label: widget.text.history,
            selected: widget.selectedTab == SidebarTab.history,
            hovered: _hovered == SidebarTab.history,
            onHoverChanged: _setHovered,
            onTap: () => widget.onSelectTab(SidebarTab.history),
          ),
          const SizedBox(height: 4),
          _SidebarNavItem(
            tab: SidebarTab.favorites,
            collapsed: collapsed,
            icon: AppIcons.star,
            label: widget.text.favorites,
            count: widget.favoriteCount,
            selected: widget.selectedTab == SidebarTab.favorites,
            hovered: _hovered == SidebarTab.favorites,
            onHoverChanged: _setHovered,
            onTap: () => widget.onSelectTab(SidebarTab.favorites),
          ),
          Padding(
            padding: EdgeInsets.symmetric(
              vertical: 12,
              horizontal: collapsed ? 4 : 8,
            ),
            child: Container(height: 1, color: reader.line),
          ),
          _SidebarNavItem(
            tab: SidebarTab.settings,
            collapsed: collapsed,
            icon: AppIcons.settings,
            label: widget.text.settings,
            selected: widget.selectedTab == SidebarTab.settings,
            hovered: _hovered == SidebarTab.settings,
            onHoverChanged: _setHovered,
            onTap: () => widget.onSelectTab(SidebarTab.settings),
          ),
          const Spacer(),
          _SidebarStatusCard(
            collapsed: collapsed,
            text: widget.text,
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
    if (collapsed) {
      return FTooltip(
        tipBuilder: (context, _) => Text(text.menu),
        child: Semantics(
          button: true,
          label: text.menu,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onToggleCollapse,
              child: const _BrandMark(),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        children: [
          const _BrandMark(),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text.appName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 19,
                height: 26 / 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.38,
                color: colors.foreground,
              ),
            ),
          ),
          SoftIconButton(
            icon: AppIcons.panelLeft,
            tooltip: text.menu,
            size: 36,
            iconSize: 18,
            outline: false,
            onPressed: onToggleCollapse,
          ),
        ],
      ),
    );
  }
}

/// The app mark: a violet tile holding a white comic page with panels.
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return ExcludeSemantics(
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: colors.primary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 11,
              top: 8,
              child: Container(
                width: 18,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(3.5),
                ),
              ),
            ),
            Positioned(
              left: 14,
              top: 11,
              child: _panel(12, 7, const Color(0xFF3D3564)),
            ),
            Positioned(
              left: 14,
              top: 20,
              child: _panel(5, 9, const Color(0xFFFFB547)),
            ),
            Positioned(
              left: 21,
              top: 20,
              child: _panel(5, 4, const Color(0xFFB6ABFF)),
            ),
            Positioned(
              left: 21,
              top: 25,
              child: _panel(5, 4, const Color(0xFF221F2C)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel(double width, double height, Color color) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(1.5),
      ),
    );
  }
}

class _SidebarNavItem extends StatefulWidget {
  const _SidebarNavItem({
    required this.tab,
    required this.collapsed,
    required this.icon,
    required this.label,
    required this.selected,
    required this.hovered,
    required this.onHoverChanged,
    required this.onTap,
    this.count,
  });

  final SidebarTab tab;
  final bool collapsed;
  final IconData icon;
  final String label;
  final int? count;
  final bool selected;
  final bool hovered;
  final ValueChanged<SidebarTab?> onHoverChanged;
  final VoidCallback onTap;

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final selected = widget.selected;
    final fg = selected ? colors.secondaryForeground : colors.mutedForeground;
    final item = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      height: AppShape.controlHeight,
      width: widget.collapsed ? AppShape.controlHeight : null,
      padding: widget.collapsed
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: selected
            ? colors.secondary
            : widget.hovered
            ? colors.secondary.withValues(alpha: 0.55)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _focused ? colors.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: widget.collapsed
          ? Icon(widget.icon, size: 20, color: fg)
          : Stack(
              clipBehavior: Clip.none,
              children: [
                if (selected)
                  Positioned(
                    left: -10,
                    top: 8,
                    bottom: 8,
                    child: Container(
                      width: 4,
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Icon(widget.icon, size: 20, color: fg),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: fg,
                        ),
                      ),
                    ),
                    if (widget.count != null && widget.count! > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: colors.card,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${widget.count}',
                          style: TextStyle(
                            fontSize: 12,
                            height: 20 / 12,
                            fontWeight: FontWeight.w700,
                            color: fg,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
    );
    final body = Semantics(
      button: true,
      selected: selected,
      label: widget.count != null && widget.count! > 0
          ? '${widget.label} ${widget.count}'
          : widget.label,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        onShowHoverHighlight: (value) =>
            widget.onHoverChanged(value ? widget.tab : null),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: item,
        ),
      ),
    );
    if (!widget.collapsed) return body;
    return FTooltip(
      tipBuilder: (context, _) => Text(widget.label),
      child: body,
    );
  }
}

/// The "local library" card at the foot of the sidebar: folder, path and
/// connection state. Tapping it opens Settings.
class _SidebarStatusCard extends ConsumerWidget {
  const _SidebarStatusCard({
    required this.collapsed,
    required this.text,
    required this.onTap,
  });

  final bool collapsed;
  final AppStrings text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    final reader = context.appReader;
    final status = ref.watch(librarySourceStatusProvider).asData?.value;
    final (String label, Color tone) = _describe(status, colors, reader);
    final path = status == null || status.path.isEmpty
        ? text.localLibrary
        : status.path;

    final iconBox = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: colors.secondary,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(AppIcons.folder, size: 20, color: colors.secondaryForeground),
    );
    final dot = Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
    );

    final Widget card;
    if (collapsed) {
      card = FTooltip(
        tipBuilder: (context, _) => Text('$path · $label'),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            iconBox,
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: colors.background,
                  shape: BoxShape.circle,
                ),
                child: dot,
              ),
            ),
          ],
        ),
      );
    } else {
      card = Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(AppShape.radiusMedium),
          boxShadow: AppShape.controlShadow(reader),
        ),
        child: Row(
          children: [
            iconBox,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    text.localLibrary,
                    style: TextStyle(
                      fontSize: 13,
                      height: 20 / 13,
                      fontWeight: FontWeight.w700,
                      color: colors.foreground,
                    ),
                  ),
                  Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 18 / 12,
                      fontWeight: FontWeight.w500,
                      color: colors.mutedForeground,
                    ),
                  ),
                  if (label.isNotEmpty)
                    Row(
                      children: [
                        dot,
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            label,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 18 / 12,
                              fontWeight: FontWeight.w600,
                              color: tone,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Semantics(
      button: true,
      label: '${text.localLibrary}: $path. $label',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: card,
        ),
      ),
    );
  }

  (String, Color) _describe(
    bridge.LibrarySourceStatus? status,
    FColors colors,
    ComicReaderColors reader,
  ) {
    if (status == null) return ('', colors.mutedForeground);
    if (!status.configured) return (text.notConfigured, colors.mutedForeground);
    if (status.error != null) return (text.unavailable, colors.destructive);
    return (text.connected, reader.success);
  }
}

class _ToggleThemeIntent extends Intent {
  const _ToggleThemeIntent();
}

class _ToggleLocaleIntent extends Intent {
  const _ToggleLocaleIntent();
}
