import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';

import '../state/library_state.dart';
import '../utils/forui_theme.dart';
import 'comic_thumbnail_image.dart';

// ---------------------------------------------------------------------------
// Shared soft-UI building blocks: one control height (44), radii 12-28,
// white surfaces with soft tinted shadows, accent only for the active
// state. Pages compose these instead of styling raw containers.
// ---------------------------------------------------------------------------

/// A white surface card with the soft tinted drop shadow.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = AppShape.radiusCard,
    this.color,
    this.shadow = true,
    this.ring = false,
    this.clip = Clip.none,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final bool shadow;

  /// Draws the 1.5 px accent ring (hover / selected state).
  final bool ring;
  final Clip clip;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final reader = context.appReader;
    return Container(
      clipBehavior: clip,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? colors.card,
        borderRadius: BorderRadius.circular(radius),
        border: ring ? Border.all(color: colors.primary, width: 1.5) : null,
        boxShadow: shadow ? AppShape.cardShadow(reader) : null,
      ),
      child: child,
    );
  }
}

/// A card that lifts and gains the accent ring on hover, and opens on tap.
class HoverCard extends StatefulWidget {
  const HoverCard({
    super.key,
    required this.child,
    required this.onTap,
    this.radius = AppShape.radiusCard,
    this.padding = EdgeInsets.zero,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback onTap;
  final double radius;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final reader = context.appReader;
    final active = _hovered || _focused;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        mouseCursor: SystemMouseCursors.click,
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
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(0, active ? -2 : 0, 0),
            padding: widget.padding,
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(widget.radius),
              border: Border.all(
                color: active ? colors.primary : Colors.transparent,
                width: 1.5,
              ),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: reader.shadow,
                        blurRadius: 44,
                        spreadRadius: -16,
                        offset: const Offset(0, 22),
                      ),
                    ]
                  : AppShape.cardShadow(reader),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

enum SoftButtonVariant { primary, soft, outline, text }

/// The 44 px pill-cornered button in the four design variants.
class SoftButton extends StatelessWidget {
  const SoftButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.iconColor,
    this.variant = SoftButtonVariant.outline,
    this.height = AppShape.controlHeight,
    this.expand = false,
    this.pill = false,
    this.semanticLabel,
    this.toggled,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Overrides the icon tint (e.g. the amber star of an active favorite).
  final Color? iconColor;
  final SoftButtonVariant variant;
  final double height;
  final bool expand;

  /// Fully rounded ends (the back button).
  final bool pill;
  final String? semanticLabel;

  /// Announced as a toggle (favorite / bookmark buttons).
  final bool? toggled;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final reader = context.appReader;
    final enabled = onPressed != null;
    final (
      Color bg,
      Color fg,
      BoxBorder? border,
      List<BoxShadow>? shadow,
    ) = switch (variant) {
      SoftButtonVariant.primary => (
        colors.primary,
        colors.primaryForeground,
        null,
        AppShape.controlShadow(reader),
      ),
      SoftButtonVariant.soft => (
        colors.secondary,
        colors.secondaryForeground,
        null,
        null,
      ),
      SoftButtonVariant.outline => (
        colors.card,
        colors.foreground,
        Border.all(color: reader.line),
        null,
      ),
      SoftButtonVariant.text => (
        Colors.transparent,
        colors.secondaryForeground,
        null,
        null,
      ),
    };
    final big = height >= 52;
    final radius = pill
        ? 999.0
        : big
        ? AppShape.radiusMedium
        : AppShape.radiusControl;
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: big ? 20 : 18, color: iconColor ?? fg),
          SizedBox(width: big ? 12 : 8),
        ],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: big ? 16 : 14,
              fontWeight: big ? FontWeight.w800 : FontWeight.w700,
              color: fg,
            ),
          ),
        ),
      ],
    );
    return _PressableSurface(
      onPressed: onPressed,
      semanticLabel: semanticLabel ?? label,
      toggled: toggled,
      radius: radius,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Container(
          height: height,
          padding: EdgeInsets.symmetric(
            horizontal: variant == SoftButtonVariant.text
                ? 4
                : big
                ? 28
                : 20,
          ),
          decoration: BoxDecoration(
            color: bg,
            border: border,
            borderRadius: BorderRadius.circular(radius),
            boxShadow: shadow,
          ),
          child: content,
        ),
      ),
    );
  }
}

/// A 44 px square icon button; `filled` draws it as a soft accent chip and
/// `round` makes it a circle (favorite / play actions).
class SoftIconButton extends StatelessWidget {
  const SoftIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = AppShape.controlHeight,
    this.iconSize = 18,
    this.filled = false,
    this.primary = false,
    this.round = false,
    this.outline = true,
    this.color,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;

  /// Soft accent background with accent ink.
  final bool filled;

  /// Solid accent background with on-accent icon.
  final bool primary;
  final bool round;

  /// Draw the 1 px line and surface; false yields a bare ghost button.
  final bool outline;
  final Color? color;

  /// Announced as toggled for screen readers (favorite / bookmark).
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final reader = context.appReader;
    final Color bg;
    final Color fg;
    BoxBorder? border;
    if (primary) {
      bg = colors.primary;
      fg = colors.primaryForeground;
    } else if (filled) {
      bg = colors.secondary;
      fg = colors.secondaryForeground;
    } else if (outline) {
      bg = colors.card;
      fg = color ?? colors.mutedForeground;
      border = Border.all(color: reader.line);
    } else {
      bg = Colors.transparent;
      fg = color ?? colors.mutedForeground;
    }
    final radius = round ? size / 2 : AppShape.radiusControl;
    return FTooltip(
      tipBuilder: (context, _) => Text(tooltip),
      child: _PressableSurface(
        onPressed: onPressed,
        semanticLabel: tooltip,
        toggled: selected,
        radius: radius,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: bg,
            border: border,
            borderRadius: BorderRadius.circular(radius),
            boxShadow: primary ? AppShape.controlShadow(reader) : null,
          ),
          child: Icon(icon, size: iconSize, color: fg),
        ),
      ),
    );
  }
}

/// Mouse cursor, keyboard activation and a focus ring around a control.
class _PressableSurface extends StatefulWidget {
  const _PressableSurface({
    required this.child,
    required this.onPressed,
    required this.radius,
    this.semanticLabel,
    this.toggled,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final double radius;
  final String? semanticLabel;
  final bool? toggled;

  @override
  State<_PressableSurface> createState() => _PressableSurfaceState();
}

class _PressableSurfaceState extends State<_PressableSurface> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Semantics(
      button: true,
      enabled: widget.onPressed != null,
      label: widget.semanticLabel,
      toggled: widget.toggled,
      child: FocusableActionDetector(
        enabled: widget.onPressed != null,
        mouseCursor: widget.onPressed == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius + 2),
              border: Border.all(
                color: _focused ? colors.primary : Colors.transparent,
                width: 2,
              ),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// A full-pill filter chip with an optional count; selected uses the accent.
class SoftChip extends StatelessWidget {
  const SoftChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final reader = context.appReader;
    final fg = selected ? colors.primaryForeground : colors.foreground;
    return _PressableSurface(
      onPressed: onPressed,
      semanticLabel: count == null ? label : '$label $count',
      toggled: selected,
      radius: 999,
      child: Container(
        height: AppShape.controlHeight,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: selected ? colors.primary : colors.card,
          borderRadius: BorderRadius.circular(999),
          border: selected ? null : Border.all(color: reader.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: fg,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 8),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? colors.primaryForeground
                      : colors.mutedForeground,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One option of a [SoftSegmented] control.
class SoftSegment<T> {
  const SoftSegment({
    required this.value,
    this.label,
    this.icon,
    this.tooltip,
    this.count,
  }) : assert(label != null || icon != null);

  final T value;
  final String? label;
  final IconData? icon;
  final String? tooltip;

  /// A muted count rendered after the label ("All 30").
  final int? count;
}

/// A 44 px segmented control; the selected segment is a raised white pill
/// with a 1.5 px accent ring.
class SoftSegmented<T> extends StatelessWidget {
  const SoftSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  final List<SoftSegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final reader = context.appReader;
    return Container(
      height: AppShape.controlHeight,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(AppShape.radiusControl),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < segments.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            _Segment(
              segment: segments[i],
              selected: segments[i].value == value,
              colors: colors,
              reader: reader,
              onPressed: () => onChanged(segments[i].value),
            ),
          ],
        ],
      ),
    );
  }
}

class _Segment<T> extends StatelessWidget {
  const _Segment({
    required this.segment,
    required this.selected,
    required this.colors,
    required this.reader,
    required this.onPressed,
  });

  final SoftSegment<T> segment;
  final bool selected;
  final FColors colors;
  final ComicReaderColors reader;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final iconOnly = segment.label == null;
    final fg = selected
        ? (iconOnly ? colors.secondaryForeground : colors.foreground)
        : colors.mutedForeground;
    final body = Container(
      height: 36,
      width: iconOnly ? 40 : null,
      padding: iconOnly ? null : const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: selected ? colors.card : Colors.transparent,
        borderRadius: BorderRadius.circular(AppShape.radiusSmall),
        border: selected
            ? Border.all(color: colors.primary, width: 1.5)
            : Border.all(color: Colors.transparent, width: 1.5),
        boxShadow: selected ? AppShape.controlShadow(reader) : null,
      ),
      child: iconOnly
          ? Icon(segment.icon, size: 18, color: fg)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (segment.icon != null) ...[
                  Icon(segment.icon, size: 16, color: fg),
                  const SizedBox(width: 8),
                ],
                Text(
                  segment.label!,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: fg,
                  ),
                ),
                if (segment.count != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '${segment.count}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.mutedForeground,
                    ),
                  ),
                ],
              ],
            ),
    );
    final pressable = _PressableSurface(
      onPressed: onPressed,
      semanticLabel: segment.count == null
          ? (segment.tooltip ?? segment.label)
          : '${segment.label} ${segment.count}',
      toggled: selected,
      radius: AppShape.radiusSmall,
      child: body,
    );
    if (segment.tooltip == null) return pressable;
    return FTooltip(
      tipBuilder: (context, _) => Text(segment.tooltip!),
      child: pressable,
    );
  }
}

/// One entry of a [SoftSortMenu].
class SoftSortOption<T> {
  const SoftSortOption({required this.value, required this.label});

  final T value;
  final String label;
}

/// "Sort: Name A–Z" — a 44 px outline button opening a popover of orders.
class SoftSortMenu<T> extends StatelessWidget {
  const SoftSortMenu({
    super.key,
    required this.prefix,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  /// The muted lead-in, e.g. "Sort".
  final String prefix;
  final List<SoftSortOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final reader = context.appReader;
    final current = options.firstWhere(
      (option) => option.value == value,
      orElse: () => options.first,
    );
    return FPopoverMenu(
      menuAnchor: .topEnd,
      childAnchor: .bottomEnd,
      menu: [
        FItemGroup(
          children: [
            for (final option in options)
              FItem(
                title: Text(option.label),
                suffix: option.value == value
                    ? Icon(AppIcons.check, size: 16, color: colors.primary)
                    : null,
                selected: option.value == value,
                onPress: () => onChanged(option.value),
              ),
          ],
        ),
      ],
      builder: (context, controller, _) => _PressableSurface(
        onPressed: controller.toggle,
        semanticLabel: '$prefix: ${current.label}',
        radius: AppShape.radiusControl,
        child: Container(
          height: AppShape.controlHeight,
          padding: const EdgeInsets.fromLTRB(16, 0, 14, 0),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(AppShape.radiusControl),
            border: Border.all(color: reader.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AppIcons.sort, size: 16, color: colors.mutedForeground),
              const SizedBox(width: 10),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$prefix: ',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: colors.mutedForeground,
                      ),
                    ),
                    TextSpan(text: current.label),
                  ],
                ),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.foreground,
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                AppIcons.chevronDown,
                size: 16,
                color: colors.mutedForeground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 32 px outline pill for passive facts ("30 chapters", "CBZ").
class SoftPill extends StatelessWidget {
  const SoftPill({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final reader = context.appReader;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: reader.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: colors.mutedForeground),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}

/// The 48×28 accent toggle with a 44 px tap area.
class SoftSwitch extends StatelessWidget {
  const SoftSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final reader = context.appReader;
    final enabled = onChanged != null;
    return _PressableSurface(
      onPressed: enabled ? () => onChanged!(!value) : null,
      semanticLabel: semanticLabel,
      toggled: value,
      radius: 999,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: SizedBox(
          width: 52,
          height: AppShape.controlHeight,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              width: 48,
              height: 28,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: value ? colors.primary : reader.progressTrack,
                borderRadius: BorderRadius.circular(999),
                border: value ? null : Border.all(color: colors.border),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: value ? 22 : 20,
                  height: value ? 22 : 20,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 6 px accent slider with a white, accent-ringed thumb.
class SoftSlider extends StatelessWidget {
  const SoftSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.semanticLabel,
    this.divisions,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String semanticLabel;
  final int? divisions;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final reader = context.appReader;
    return Material(
      type: MaterialType.transparency,
      child: SliderTheme(
        data: SliderThemeData(
          trackHeight: 6,
          activeTrackColor: colors.primary,
          inactiveTrackColor: reader.progressTrack,
          thumbColor: Colors.white,
          overlayColor: colors.primary.withValues(alpha: 0.18),
          thumbShape: const _RingedThumbShape(),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
          activeTickMarkColor: Colors.transparent,
          inactiveTickMarkColor: Colors.transparent,
          trackShape: const RoundedRectSliderTrackShape(),
        ),
        child: SizedBox(
          height: AppShape.controlHeight,
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            semanticFormatterCallback: (_) => semanticLabel,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

/// White 20 px thumb with the 3 px accent ring from the design system.
class _RingedThumbShape extends SliderComponentShape {
  const _RingedThumbShape();

  static const double _radius = 10;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.fromRadius(_radius + 3);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    canvas.drawCircle(
      center.translate(0, 1),
      _radius + 1,
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );
    canvas.drawCircle(
      center,
      _radius + 3,
      Paint()..color = sliderTheme.activeTrackColor ?? Colors.black,
    );
    canvas.drawCircle(
      center,
      _radius,
      Paint()..color = sliderTheme.thumbColor ?? Colors.white,
    );
  }
}

/// The 44 px search input with a leading glass and a clear button.
class SoftSearchField extends StatelessWidget {
  const SoftSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.width = 320,
    this.filled = false,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final double? width;

  /// Use the surface2 fill (inside a card) instead of white with a line.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final reader = context.appReader;
    // TextField needs a Material ancestor; the shell has none.
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: width,
        height: AppShape.controlHeight,
        decoration: BoxDecoration(
          color: filled ? colors.muted : colors.card,
          borderRadius: BorderRadius.circular(AppShape.radiusControl),
          border: filled ? null : Border.all(color: colors.border),
          boxShadow: filled ? null : AppShape.controlShadow(reader),
        ),
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => TextField(
            controller: controller,
            onChanged: onChanged,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: colors.foreground,
            ),
            cursorColor: colors.primary,
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colors.mutedForeground,
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 16, right: 10),
                child: Icon(
                  AppIcons.search,
                  size: 18,
                  color: colors.mutedForeground,
                ),
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 44,
                minHeight: 44,
              ),
              suffixIcon: value.text.isEmpty
                  ? null
                  : SoftIconButton(
                      icon: AppIcons.close,
                      tooltip: hint,
                      size: 36,
                      iconSize: 16,
                      outline: false,
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      },
                    ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 44,
                minHeight: 44,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 0,
                vertical: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A rounded progress track; `height` 6 for lists, 10 for summaries.
class SoftProgressBar extends StatelessWidget {
  const SoftProgressBar({
    super.key,
    required this.value,
    this.height = 6,
    this.color,
    this.trackColor,
    this.semanticLabel,
  });

  final double value;
  final double height;
  final Color? color;
  final Color? trackColor;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final reader = context.appReader;
    final clamped = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return Semantics(
      label: semanticLabel,
      value: semanticLabel == null ? null : '${(clamped * 100).round()}%',
      child: Container(
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: trackColor ?? reader.progressTrack,
          borderRadius: BorderRadius.circular(999),
        ),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: clamped,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color ?? reader.progress,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      ),
    );
  }
}

enum SoftBadgeTone { amber, success, accent, neutral }

/// A 20 px status pill (New, Finished, Reading, tags).
class SoftBadge extends StatelessWidget {
  const SoftBadge({
    super.key,
    required this.label,
    this.tone = SoftBadgeTone.neutral,
    this.icon,
  });

  final String label;
  final SoftBadgeTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final reader = context.appReader;
    final (Color bg, Color fg) = switch (tone) {
      SoftBadgeTone.amber => (reader.badgeNew, reader.badgeNewForeground),
      SoftBadgeTone.success => (reader.successSoft, reader.success),
      SoftBadgeTone.accent => (colors.secondary, colors.secondaryForeground),
      SoftBadgeTone.neutral => (colors.muted, colors.mutedForeground),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              height: 20 / 12,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// A comic cover thumbnail with the muted fallback and rounded corners.
class CoverThumbnail extends ConsumerWidget {
  const CoverThumbnail({
    super.key,
    required this.sourcePath,
    this.radius = AppShape.radiusMedium,
    this.width,
    this.height,
    this.maxWidth = 200,
    this.maxHeight = 300,
    this.fallbackIconSize = 28,
  });

  final String sourcePath;
  final double radius;
  final double? width;
  final double? height;
  final int maxWidth;
  final int maxHeight;
  final double fallbackIconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    final thumbnail = ref.watch(
      comicThumbnailProvider((
        sourcePath: sourcePath,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      )),
    );
    final fallback = Center(
      child: Icon(
        AppIcons.library,
        size: fallbackIconSize,
        color: colors.mutedForeground,
      ),
    );
    return ExcludeSemantics(
      child: Container(
        width: width,
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colors.muted,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: thumbnail.when(
          data: (bytes) {
            if (bytes == null) return fallback;
            return Image(
              image: ComicThumbnailImage(
                sourcePath: sourcePath,
                maxWidth: maxWidth,
                maxHeight: maxHeight,
                bytes: bytes,
              ),
              fit: BoxFit.cover,
            );
          },
          loading: () => fallback,
          error: (_, _) => fallback,
        ),
      ),
    );
  }
}

/// The 32/40/800 page title with a muted subtitle.
class PageHeading extends StatelessWidget {
  const PageHeading({super.key, required this.title, this.subtitle});

  final String title;
  final Widget? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 32,
            height: 40 / 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            color: colors.foreground,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          DefaultTextStyle(
            style: TextStyle(
              fontSize: 14,
              height: 22 / 14,
              fontWeight: FontWeight.w500,
              color: colors.mutedForeground,
            ),
            child: subtitle!,
          ),
        ],
      ],
    );
  }
}

/// The 18/26/800 section heading.
class SectionHeading extends StatelessWidget {
  const SectionHeading({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18,
        height: 26 / 18,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.18,
        color: context.theme.colors.foreground,
      ),
    );
  }
}

/// Centered empty / error message inside a list area.
class SoftEmptyState extends StatelessWidget {
  const SoftEmptyState({
    super.key,
    required this.message,
    this.icon,
    this.isError = false,
  });

  final String message;
  final IconData? icon;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: isError ? colors.muted : colors.secondary,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  icon,
                  size: 24,
                  color: isError
                      ? colors.mutedForeground
                      : colors.secondaryForeground,
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 22 / 14,
                fontWeight: FontWeight.w600,
                color: isError ? colors.foreground : colors.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
