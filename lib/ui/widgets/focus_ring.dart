import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A 2 px keyboard-focus ring (DESIGN section 11) around a control whose own
/// focus feedback is only a faint tint: an `InkWell`, a `ListTile`, a
/// `SwitchListTile`, a `PopupMenuButton`.
///
/// Put it ABOVE the control. It listens to the focus of everything below it
/// (no focus node of its own, no extra tab stop) and draws the ring on top of
/// the child, inside its bounds, so nothing moves. The ring shows only while
/// the user is navigating with a keyboard, like the framework's own focus
/// highlight: a tap or a click never leaves one behind.
///
/// Buttons, text fields and `SurfaceCard` already draw this ring through the
/// theme; do not wrap them.
class FocusRing extends StatefulWidget {
  const FocusRing({
    super.key,
    required this.child,
    this.radius = AppRadius.stat,
  });

  final Widget child;

  /// Corner radius of the ring: the radius of the control it surrounds
  /// (14, the `ListTile` shape, by default). A large value (999) gives a
  /// pill.
  final double radius;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_modeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_modeChanged);
    super.dispose();
  }

  void _modeChanged(FocusHighlightMode _) {
    if (_focused && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final show =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) {
        if (_focused != f) setState(() => _focused = f);
      },
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: show
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(widget.radius),
                border: Border.all(color: t.focusRing, width: 2),
              )
            : const BoxDecoration(),
        child: widget.child,
      ),
    );
  }
}
