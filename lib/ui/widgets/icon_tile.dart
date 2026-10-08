import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The 36 px rounded tile with an outline icon at the start of a settings row
/// (`surface2` fill, 1 px `line2` border, 30 % corner radius). Decorative, so
/// it is excluded from semantics; the row's title carries the meaning.
///
/// Give it a `color` and `fill` pair from the tokens for a status (`good` on
/// `goodContainer`, `warn` on `warnContainer`, `error` on `errorContainer`).
/// Inside a dialog's `icon:` slot, which has tight constraints, centre it
/// (`Center(child: IconTile(...))`) or it stretches into a flat bar.
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    this.size = 36,
    this.color,
    this.fill,
  });

  final IconData icon;
  final double size;

  /// Icon colour; defaults to the lavender `accent2`.
  final Color? color;

  /// Tile fill; defaults to `surface2`.
  final Color? fill;

  /// Padding of a settings row (`ListTile.contentPadding`) that starts with an
  /// [IconTile].
  static const rowPadding = EdgeInsetsDirectional.fromSTEB(16, 4, 12, 4);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill ?? t.surface2,
          borderRadius: BorderRadius.circular(size * 0.3),
          border: Border.all(color: t.line2),
        ),
        child: Icon(icon, size: size * 0.55, color: color ?? t.accent2),
      ),
    );
  }
}
