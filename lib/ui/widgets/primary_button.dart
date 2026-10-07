import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The portfolio's `.button.primary`: a violet [FilledButton] with a soft
/// violet glow under it that lifts 2 px on mouse hover (DESIGN section 8.2).
///
/// It always builds a plain [FilledButton] (also with [icon]), so a test or
/// screen reader that looks for `FilledButton` with a label keeps working.
/// The fill, hover, pressed, focus and disabled colours come from the theme
/// (`AppTheme`); this widget only adds the glow, the lift and the layout
/// options. For a secondary action use a plain `OutlinedButton` (the ghost
/// button) and for a tertiary one a `TextButton`; both are themed.
///
/// The portfolio's primary button is a flat fill, not a gradient, so there is
/// no separate gradient button.
class PrimaryButton extends StatefulWidget {
  const PrimaryButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.expanded = false,
    this.destructive = false,
    this.glow = true,
    this.focusNode,
    this.autofocus = false,
  });

  final VoidCallback? onPressed;
  final Widget child;

  /// Shown before [child] (after it in a right-to-left layout).
  final Widget? icon;

  /// Fill the available width (lock screen, forms on phones).
  final bool expanded;

  /// Red fill for erase / delete confirmations. Name what is lost in the
  /// dialog around it.
  final bool destructive;

  /// Turn the glow off where several primary buttons are on screen.
  final bool glow;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final enabled = widget.onPressed != null;
    final ButtonStyle? style = widget.destructive
        ? ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((s) {
              if (s.contains(WidgetState.disabled)) {
                return t.ink.withValues(alpha: 0.10);
              }
              if (s.contains(WidgetState.pressed)) {
                return Color.lerp(t.error, Colors.black, 0.18);
              }
              if (s.contains(WidgetState.hovered)) {
                return Color.lerp(t.error, Colors.white, 0.10);
              }
              return t.error;
            }),
            foregroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.disabled)
                  ? t.ink.withValues(alpha: 0.38)
                  : t.onError,
            ),
            iconColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.disabled)
                  ? t.ink.withValues(alpha: 0.38)
                  : t.onError,
            ),
          )
        : null;

    final label = widget.icon == null
        ? widget.child
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconTheme.merge(
                data: const IconThemeData(size: 20),
                child: widget.icon!,
              ),
              const SizedBox(width: 10),
              Flexible(child: widget.child),
            ],
          );

    final glowColor = widget.destructive
        ? t.error.withValues(alpha: 0.25)
        : t.buttonGlow;
    Widget button = AnimatedContainer(
      duration: context.motion(AppMotion.fast),
      curve: AppMotion.standard,
      transform: Matrix4.translationValues(0, _hover && enabled ? -2 : 0, 0),
      decoration: BoxDecoration(
        borderRadius: AppRadius.controlAll,
        boxShadow: enabled && widget.glow
            ? [
                BoxShadow(
                  color: glowColor,
                  offset: const Offset(0, 8),
                  blurRadius: 26,
                ),
              ]
            : null,
      ),
      child: FilledButton(
        onPressed: widget.onPressed,
        style: style,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        child: label,
      ),
    );
    if (widget.expanded) {
      button = SizedBox(width: double.infinity, child: button);
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: button,
    );
  }
}
