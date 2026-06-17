import 'package:fluent_ui/fluent_ui.dart';

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
          child: Tooltip(
            message: tooltip,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: FluentTheme.of(context).micaBackgroundColor,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: FluentTheme.of(
                    context,
                  ).resources.controlStrokeColorDefault,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: SizedBox.square(
                dimension: _buttonSize,
                child: IconButton(
                  onPressed: onPressed,
                  icon: const Icon(FluentIcons.up, size: 24),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
