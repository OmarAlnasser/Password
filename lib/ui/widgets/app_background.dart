import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The page background: the near-black violet colour with a faint violet glow
/// bleeding in from the physical top-right corner, like the portfolio's
/// `body::before` (DESIGN section 6).
///
/// `AppShell` puts one behind the whole app, so screens normally do not need
/// it. Use it directly for a pane or a dialog that needs the same backdrop.
/// The glow is decoration: it is excluded from semantics and never takes
/// pointer events, and it stays in the top-right corner in right-to-left
/// layouts (as in the portfolio).
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, this.child});

  /// Painted above the background; fills the available space.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final wide = MediaQuery.sizeOf(context).width >= AppLayout.expanded;
    // A square-ish box on phones, an ellipse-ish one on desktop, so the circle
    // matches the portfolio's 70vw x 70vh ellipse at either size.
    final size = wide ? const Size(900, 700) : const Size(520, 520);
    final top = wide ? -200.0 : -170.0;
    final right = wide ? -150.0 : -110.0;
    return ColoredBox(
      color: t.bg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: top,
            right: right,
            width: size.width,
            height: size.height,
            child: ExcludeSemantics(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [t.glow, t.glow.withValues(alpha: 0)],
                        radius: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          ?child,
        ],
      ),
    );
  }
}
