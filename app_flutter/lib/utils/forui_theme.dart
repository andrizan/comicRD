import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';

export 'package:forui/forui.dart' show FLucideIcons;

/// The font family used across the app (declared in `pubspec.yaml`).
const String appFontFamily = 'Plus Jakarta Sans';

// ---------------------------------------------------------------------------
// ComicRD Theme — soft violet on a lavender-cream ground.
//
// Every text pairing below is >= 4.5:1 and every UI pairing >= 3:1; the
// figures are listed next to the tokens that carry them.
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

  /// Light palette — lavender-cream ground, white cards, violet accent.
  static final FThemeData light = FThemeData(
    touch: false,
    typography: _buildTypography(FColors.neutralLight),
    colors: FColors.neutralLight.copyWith(
      // Background / Foreground — 15.45:1
      background: const Color(0xFFF6F5FA),
      foreground: const Color(0xFF1F1B2D),
      // Card — the surface cards, inputs and panels sit on (16.76:1)
      card: const Color(0xFFFFFFFF),
      // Primary — 5.05:1 for its label, 4.66:1 against the ground
      primary: const Color(0xFF6D5DD3),
      primaryForeground: const Color(0xFFFFFFFF),
      // Secondary — accent-soft fill with accent-ink text (6.70:1)
      secondary: const Color(0xFFECE9FB),
      secondaryForeground: const Color(0xFF4A3FB0),
      // Muted — surface2 (tracks, segmented fills) / muted text 5.11:1
      muted: const Color(0xFFEFEDF6),
      mutedForeground: const Color(0xFF6A6580),
      // Destructive — 5.0:1
      destructive: const Color(0xFFCC3B30),
      destructiveForeground: const Color(0xFFFFFFFF),
      // Error — 4.7:1
      error: const Color(0xFFE11D48),
      errorForeground: const Color(0xFFFFFFFF),
      // Border — control outline, 3.82:1 on white (WCAG 1.4.11)
      border: const Color(0xFF857F9A),
    ),
  );

  /// Dark palette — deep plum ground, lavender accent.
  static final FThemeData dark = FThemeData(
    touch: false,
    typography: _buildTypography(FColors.neutralDark),
    colors: FColors.neutralDark.copyWith(
      // Background / Foreground — 16.05:1
      background: const Color(0xFF121018),
      foreground: const Color(0xFFEEEBF7),
      // Card — 14.85:1
      card: const Color(0xFF1B1824),
      // Primary — 6.88:1 for its label, 7.38:1 against the ground
      primary: const Color(0xFFA294FF),
      primaryForeground: const Color(0xFF1A1530),
      // Secondary — accent-soft (16% accent over card) with ink 8.39:1
      secondary: const Color(0xFF312C47),
      secondaryForeground: const Color(0xFFCFC7FF),
      // Muted — surface2 / muted text 7.23:1
      muted: const Color(0xFF262232),
      mutedForeground: const Color(0xFFA29DB8),
      // Destructive — 5.3:1
      destructive: const Color(0xFFE2685D),
      destructiveForeground: const Color(0xFF1B1926),
      // Error — 6.1:1
      error: const Color(0xFFF0708C),
      errorForeground: const Color(0xFF1B1926),
      // Border — control outline, 4.02:1 on the card
      border: const Color(0xFF7B768F),
    ),
  );
}

// ---------------------------------------------------------------------------
// App-specific color tokens via ThemeExtension.
// ---------------------------------------------------------------------------

@immutable
class ComicReaderColors extends ThemeExtension<ComicReaderColors> {
  const ComicReaderColors({
    required this.canvas,
    required this.progress,
    required this.progressTrack,
    required this.badgeNew,
    required this.badgeNewForeground,
    required this.star,
    required this.success,
    required this.successSoft,
    required this.line,
    required this.shadow,
    required this.shadowSoft,
    required this.scrim,
  });

  /// Background canvas behind comic pages (the reader is always dark).
  final Color canvas;

  /// Progress bar / chapter completion indicator.
  final Color progress;

  /// Progress bar track (background) color.
  final Color progressTrack;

  /// "New" badge fill.
  final Color badgeNew;

  /// "New" badge text (6.45:1 / 8.79:1 on the fill).
  final Color badgeNewForeground;

  /// Favorite star fill — 3.71:1 on white so the icon reads alone.
  final Color star;

  /// Finished / connected state.
  final Color success;

  /// Soft fill behind success text (4.63:1 / 7.16:1).
  final Color successSoft;

  /// Hairline divider inside cards (decorative only).
  final Color line;

  /// Card shadow (the soft, tinted drop).
  final Color shadow;

  /// Small control shadow.
  final Color shadowSoft;

  /// Scrim behind icons drawn over cover art (4.38:1 for the star).
  final Color scrim;

  static const light = ComicReaderColors(
    canvas: Color(0xFF0E0D13),
    progress: Color(0xFF6D5DD3),
    progressTrack: Color(0xFFEFEDF6),
    badgeNew: Color(0xFFFFF1D6),
    badgeNewForeground: Color(0xFF7A4E00),
    star: Color(0xFFBF7300),
    success: Color(0xFF167A59),
    successSoft: Color(0xFFE1F4EC),
    line: Color(0x141F1B2D),
    shadow: Color(0x474A3FB0),
    shadowSoft: Color(0x0F1F1B2D),
    scrim: Color(0x9E140F23),
  );

  static const dark = ComicReaderColors(
    canvas: Color(0xFF0E0D13),
    progress: Color(0xFFA294FF),
    progressTrack: Color(0xFF262232),
    badgeNew: Color(0xFF40332D),
    badgeNewForeground: Color(0xFFFFD58A),
    star: Color(0xFFFFC15A),
    success: Color(0xFF5FD3A8),
    successSoft: Color(0xFF253237),
    line: Color(0x14FFFFFF),
    shadow: Color(0xB3000000),
    shadowSoft: Color(0x73000000),
    scrim: Color(0x9E140F23),
  );

  @override
  ComicReaderColors copyWith({
    Color? canvas,
    Color? progress,
    Color? progressTrack,
    Color? badgeNew,
    Color? badgeNewForeground,
    Color? star,
    Color? success,
    Color? successSoft,
    Color? line,
    Color? shadow,
    Color? shadowSoft,
    Color? scrim,
  }) {
    return ComicReaderColors(
      canvas: canvas ?? this.canvas,
      progress: progress ?? this.progress,
      progressTrack: progressTrack ?? this.progressTrack,
      badgeNew: badgeNew ?? this.badgeNew,
      badgeNewForeground: badgeNewForeground ?? this.badgeNewForeground,
      star: star ?? this.star,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      line: line ?? this.line,
      shadow: shadow ?? this.shadow,
      shadowSoft: shadowSoft ?? this.shadowSoft,
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
      badgeNew: Color.lerp(badgeNew, other.badgeNew, t)!,
      badgeNewForeground: Color.lerp(
        badgeNewForeground,
        other.badgeNewForeground,
        t,
      )!,
      star: Color.lerp(star, other.star, t)!,
      success: Color.lerp(success, other.success, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      line: Color.lerp(line, other.line, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      shadowSoft: Color.lerp(shadowSoft, other.shadowSoft, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
    );
  }
}

// ---------------------------------------------------------------------------
// Shape and shadow tokens.
// ---------------------------------------------------------------------------

class AppShape {
  const AppShape._();

  /// Buttons inside a segmented control.
  static const double radiusSmall = 12;

  /// Buttons, inputs, nav items.
  static const double radiusControl = 16;

  /// Covers, list rows.
  static const double radiusMedium = 20;

  /// Cards and panels.
  static const double radiusCard = 24;

  /// Large cards (settings groups, chapter list shell).
  static const double radiusLarge = 28;

  /// One control height for the whole app; primary CTAs go 52.
  static const double controlHeight = 44;

  static List<BoxShadow> cardShadow(ComicReaderColors colors) => [
    BoxShadow(
      color: colors.shadowSoft,
      blurRadius: 2,
      offset: const Offset(0, 1),
    ),
    BoxShadow(
      color: colors.shadow,
      blurRadius: 32,
      spreadRadius: -14,
      offset: const Offset(0, 14),
    ),
  ];

  static List<BoxShadow> controlShadow(ComicReaderColors colors) => [
    BoxShadow(
      color: colors.shadowSoft,
      blurRadius: 2,
      offset: const Offset(0, 1),
    ),
  ];
}

// ---------------------------------------------------------------------------
// Icon registry.
// ---------------------------------------------------------------------------

class AppIcons {
  const AppIcons._();

  static const IconData search = FLucideIcons.search;
  static const IconData chevronDown = FLucideIcons.chevronDown;
  static const IconData refresh = FLucideIcons.refreshCcw;
  static const IconData settings = FLucideIcons.settings;
  static const IconData library = FLucideIcons.bookOpen;
  static const IconData bookmark = FLucideIcons.bookmark;
  static const IconData folderBookmark = FLucideIcons.folderBookmark;
  static const IconData folderOpen = FLucideIcons.folderOpen;
  static const IconData gridView = FLucideIcons.layoutGrid;
  static const IconData list = FLucideIcons.list;
  static const IconData star = FLucideIcons.star;
  static const IconData arrowUp = FLucideIcons.arrowUp;
  static const IconData chevronRight = FLucideIcons.chevronRight;
  static const IconData chevronLeft = FLucideIcons.chevronLeft;
  static const IconData check = FLucideIcons.check;
  static const IconData more = FLucideIcons.ellipsis;
  static const IconData sun = FLucideIcons.sun;
  static const IconData moon = FLucideIcons.moon;
  static const IconData monitor = FLucideIcons.monitor;
  static const IconData download = FLucideIcons.download;
  static const IconData upload = FLucideIcons.upload;
  static const IconData save = FLucideIcons.save;
  static const IconData close = FLucideIcons.x;
  static const IconData minimize = FLucideIcons.minimize;
  static const IconData maximize = FLucideIcons.maximize;
  static const IconData copyTitle = FLucideIcons.text;
  static const IconData copyPath = FLucideIcons.copy;
  static const IconData code = FLucideIcons.code;
  static const IconData play = FLucideIcons.play;
  static const IconData chevronsLeft = FLucideIcons.chevronsLeft;
  static const IconData chevronsRight = FLucideIcons.chevronsRight;
  static const IconData sliders = FLucideIcons.slidersHorizontal;
  static const IconData folder = FLucideIcons.folder;
  static const IconData offline = FLucideIcons.wifiOff;
  static const IconData restart = FLucideIcons.rotateCcw;
  static const IconData sort = FLucideIcons.arrowUpDown;
  static const IconData database = FLucideIcons.database;
  static const IconData clock = FLucideIcons.clock;
  static const IconData circleAlert = FLucideIcons.circleAlert;
  static const IconData externalLink = FLucideIcons.externalLink;
  static const IconData fileArchive = FLucideIcons.fileArchive;
  static const IconData panelLeft = FLucideIcons.panelLeft;
}

// ---------------------------------------------------------------------------
// BuildContext extensions for quick access.
// ---------------------------------------------------------------------------

extension AppThemeContext on BuildContext {
  Color get appSurface => theme.colors.background;
  Color get appBorder => theme.colors.border;

  /// App-specific colors (reader canvas, markers, success, shadows).
  ComicReaderColors get appReader {
    return Theme.of(this).extension<ComicReaderColors>() ??
        ComicReaderColors.light;
  }
}
