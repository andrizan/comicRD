import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../utils/forui_theme.dart';

class BackToTopButton extends StatelessWidget {
  const BackToTopButton({
    super.key,
    required this.visible,
    required this.tooltip,
    required this.onPressed,
  });

  final bool visible;
  final String tooltip;
  final VoidCallback onPressed;

  static const double _buttonSize = 52;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      child: AnimatedScale(
        scale: visible ? 1 : 0.92,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: IgnorePointer(
          ignoring: !visible,
          child: FTooltip(
            tipBuilder: (context, _) => Text(tooltip),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.appSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.appBorder),
                boxShadow: [
                  BoxShadow(
                    color: context.theme.colors.foreground.withValues(alpha: 0.18),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: SizedBox.square(
                dimension: _buttonSize,
                child: FButton.icon(
                  variant: .ghost,
                  onPress: onPressed,
                  child: const Icon(AppIcons.arrowUp, size: 24),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
