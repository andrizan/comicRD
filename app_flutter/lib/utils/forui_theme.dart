import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

export 'package:forui/forui.dart' show FLucideIcons;

/// The font family used across the app (declared in `pubspec.yaml`).
const String appFontFamily = 'Inter';

// ---------------------------------------------------------------------------
// ComicRD Theme — Violet-Indigo accent, WCAG AA validated contrasts.
// ---------------------------------------------------------------------------

class ComicReaderFTheme {
  const ComicReaderFTheme._();

  static FTypography _buildTypography(FColors colors) {
    final typeface = FTypeface.inherit(
      colors: colors,
      touch: false,
      fontFamily: appFontFamily,
    );
    return FTypography(display: typeface, body: typeface);
  }

  /// Light palette — warm cream background, violet accent.
  static final FThemeData light = FThemeData(
    touch: false,
    typography: _buildTypography(FColors.neutralLight),
    colors: FColors.neutralLight.copyWith(
      // Background / Foreground — 14.9:1
      background: const Color(0xFFF7F6F3),
      foreground: const Color(0xFF221F2C),
      // Card — sedikit lebih terang dari background untuk elevasi halus
      card: const Color(0xFFFAF9F7),
      // Primary — 5.1:1
      primary: const Color(0xFF6D5DD3),
      primaryForeground: const Color(0xFFFFFFFF),
      // Secondary — 9.3:1
      secondary: const Color(0xFFECE9F9),
      secondaryForeground: const Color(0xFF3D3564),
      // Muted — 4.6:1
      muted: const Color(0xFFEFEEEA),
      mutedForeground: const Color(0xFF6E6B63),
      // Destructive — 5.0:1
      destructive: const Color(0xFFCC3B30),
      destructiveForeground: const Color(0xFFFFFFFF),
      // Error — 4.7:1
      error: const Color(0xFFE11D48),
      errorForeground: const Color(0xFFFFFFFF),
      // Border
      border: const Color(0xFFE4E1DC),
    ),
  );

  /// Dark palette — charcoal background, light violet accent.
  static final FThemeData dark = FThemeData(
    touch: false,
    typography: _buildTypography(FColors.neutralDark),
    colors: FColors.neutralDark.copyWith(
      // Background / Foreground — 15.3:1
      background: const Color(0xFF17151C),
      foreground: const Color(0xFFEDEBF5),
      // Card — sedikit lebih terang dari background untuk elevasi halus
      card: const Color(0xFF1E1B26),
      // Primary — 6.3:1
      primary: const Color(0xFF9C8CFF),
      primaryForeground: const Color(0xFF1B1926),
      // Secondary — 12.5:1
      secondary: const Color(0xFF2A2635),
      secondaryForeground: const Color(0xFFEDEBF5),
      // Muted — 5.9:1
      muted: const Color(0xFF211E29),
      mutedForeground: const Color(0xFF9D99AC),
      // Destructive — 5.3:1
      destructive: const Color(0xFFE2685D),
      destructiveForeground: const Color(0xFF1B1926),
      // Error — 6.1:1
      error: const Color(0xFFF0708C),
      errorForeground: const Color(0xFF1B1926),
      // Border
      border: const Color(0xFF2E2A38),
    ),
  );
}

// ---------------------------------------------------------------------------
// Reader-specific color tokens via ThemeExtension.
// ---------------------------------------------------------------------------

@immutable
class ComicReaderColors extends ThemeExtension<ComicReaderColors> {
  const ComicReaderColors({
    required this.canvas,
    required this.progress,
    required this.progressTrack,
    required this.bookmark,
    required this.badgeNew,
    required this.star,
    required this.scrim,
  });

  /// Background canvas behind comic pages.
  final Color canvas;

  /// Progress bar / chapter completion indicator.
  final Color progress;

  /// Progress bar track (background) color.
  final Color progressTrack;

  /// Bookmark highlight color.
  final Color bookmark;

  /// "New" badge accent.
  final Color badgeNew;

  /// Star / rating icon fill.
  final Color star;

  /// Scrim overlay behind reader controls.
  final Color scrim;

  static const light = ComicReaderColors(
    canvas: Color(0xFF221F2C),
    progress: Color(0xFF6D5DD3),
    progressTrack: Color(0xFFE8E6E1),
    bookmark: Color(0xFF6D5DD3),
    badgeNew: Color(0xFF6D5DD3),
    star: Color(0xFFE5A832),
    scrim: Color(0x66221F2C),
  );

  static const dark = ComicReaderColors(
    canvas: Color(0xFF0D0B12),
    progress: Color(0xFF9C8CFF),
    progressTrack: Color(0xFF252230),
    bookmark: Color(0xFF9C8CFF),
    badgeNew: Color(0xFF9C8CFF),
    star: Color(0xFFF5C542),
    scrim: Color(0x880D0B12),
  );

  @override
  ComicReaderColors copyWith({
    Color? canvas,
    Color? progress,
    Color? progressTrack,
    Color? bookmark,
    Color? badgeNew,
    Color? star,
    Color? scrim,
  }) {
    return ComicReaderColors(
      canvas: canvas ?? this.canvas,
      progress: progress ?? this.progress,
      progressTrack: progressTrack ?? this.progressTrack,
      bookmark: bookmark ?? this.bookmark,
      badgeNew: badgeNew ?? this.badgeNew,
      star: star ?? this.star,
      scrim: scrim ?? this.scrim,
    );
  }

  @override
  ComicReaderColors lerp(ComicReaderColors? other, double t) {
    if (other is! ComicReaderColors) return this;
    return ComicReaderColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      progress: Color.lerp(progress, other.progress, t)!,
      progressTrack: Color.lerp(progressTrack, other.progressTrack, t)!,
      bookmark: Color.lerp(bookmark, other.bookmark, t)!,
      badgeNew: Color.lerp(badgeNew, other.badgeNew, t)!,
      star: Color.lerp(star, other.star, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
    );
  }
}

// ---------------------------------------------------------------------------
// Icon registry.
// ---------------------------------------------------------------------------

class AppIcons {
  const AppIcons._();

  static const IconData menu = FLucideIcons.menu;
  static const IconData search = FLucideIcons.search;
  static const IconData image = FLucideIcons.image;
  static const IconData chevronDown = FLucideIcons.chevronDown;
  static const IconData refresh = FLucideIcons.refreshCcw;
  static const IconData settings = FLucideIcons.settings;
  static const IconData library = FLucideIcons.bookOpen;
  static const IconData history = FLucideIcons.history;
  static const IconData bookmark = FLucideIcons.bookmark;
  static const IconData folderOpen = FLucideIcons.folderOpen;
  static const IconData gridView = FLucideIcons.layoutGrid;
  static const IconData list = FLucideIcons.list;
  static const IconData star = FLucideIcons.star;
  static const IconData back = FLucideIcons.arrowLeft;
  static const IconData arrowUp = FLucideIcons.arrowUp;
  static const IconData chevronRight = FLucideIcons.chevronRight;
  static const IconData chevronLeft = FLucideIcons.chevronLeft;
  static const IconData check = FLucideIcons.check;
  static const IconData read = FLucideIcons.bookOpen;
  static const IconData sortUp = FLucideIcons.arrowUpNarrowWide;
  static const IconData sortDown = FLucideIcons.arrowDownWideNarrow;
  static const IconData more = FLucideIcons.ellipsis;
  static const IconData sun = FLucideIcons.sun;
  static const IconData moon = FLucideIcons.moon;
  static const IconData monitor = FLucideIcons.monitor;
  static const IconData languages = FLucideIcons.languages;
  static const IconData download = FLucideIcons.download;
  static const IconData upload = FLucideIcons.upload;
  static const IconData save = FLucideIcons.save;
  static const IconData close = FLucideIcons.x;
  static const IconData chevronFirst = FLucideIcons.chevronFirst;
  static const IconData chevronLast = FLucideIcons.chevronLast;
  static const IconData alignCenter = FLucideIcons.alignCenterHorizontal;
  static const IconData minimize = FLucideIcons.minimize;
  static const IconData maximize = FLucideIcons.maximize;
  static const IconData scroll = FLucideIcons.scroll;
  static const IconData minus = FLucideIcons.minus;
  static const IconData plus = FLucideIcons.plus;
  static const IconData copyTitle = FLucideIcons.text;
  static const IconData copyPath = FLucideIcons.copy;
}

// ---------------------------------------------------------------------------
// BuildContext extensions for quick access.
// ---------------------------------------------------------------------------

extension AppThemeContext on BuildContext {
  FThemeData get appTheme => theme;
  FColors get appColors => theme.colors;
  FTypography get appTypography => theme.typography;

  Color get appAccent => theme.colors.primary;
  Color get appSurface => theme.colors.background;
  Color get appMutedText => theme.colors.mutedForeground;
  Color get appSecondarySurface => theme.colors.secondary;
  Color get appBorder => theme.colors.border;

  /// Reader-specific colors.
  ComicReaderColors get appReader {
    return Theme.of(this).extension<ComicReaderColors>() ??
        ComicReaderColors.light;
  }

  TextStyle get appTitleStyle => theme.typography.display.lg;
  TextStyle get appSubtitleStyle => theme.typography.display.sm;
  TextStyle get appBodyStyle => theme.typography.body.md;
  TextStyle get appBodyStrongStyle =>
      theme.typography.body.md.copyWith(fontWeight: FontWeight.w600);
  TextStyle get appCaptionStyle => theme.typography.body.sm;
}
