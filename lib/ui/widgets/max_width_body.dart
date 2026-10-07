import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Centres content in a column of at most [maxWidth] with the page gutter on
/// both sides: 1180 for full-page content (dashboard, settings, generator),
/// 640 for forms and the detail pane ([MaxWidthBody.form]), 480 for the lock
/// screen ([MaxWidthBody.narrow]). The portfolio's
/// `.wrap{width:min(1180px,100% - 40px)}` (DESIGN section 9).
///
/// For a scrolling list, do not wrap the `ListView` (its scrollbar would sit
/// at the column's edge); give it [MaxWidthBody.insets] as `padding` instead.
class MaxWidthBody extends StatelessWidget {
  const MaxWidthBody({
    super.key,
    required this.child,
    this.maxWidth = AppLayout.page,
    this.padding = EdgeInsets.zero,
    this.alignment = AlignmentDirectional.topCenter,
  });

  const MaxWidthBody.form({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.alignment = AlignmentDirectional.topCenter,
  }) : maxWidth = AppLayout.form;

  const MaxWidthBody.narrow({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.alignment = AlignmentDirectional.topCenter,
  }) : maxWidth = AppLayout.narrow;

  final Widget child;
  final double maxWidth;

  /// Extra padding inside the gutter (usually vertical).
  final EdgeInsetsGeometry padding;
  final AlignmentGeometry alignment;

  /// Horizontal padding that centres a `ListView`'s content in [maxWidth]
  /// (never less than the page gutter), plus [base] on every side.
  static EdgeInsets insets(
    BuildContext context, {
    double maxWidth = AppLayout.page,
    EdgeInsets base = EdgeInsets.zero,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    final side = ((width - maxWidth) / 2).clamp(
      AppSpace.gutter(width),
      double.infinity,
    );
    return base + EdgeInsets.symmetric(horizontal: side);
  }

  @override
  Widget build(BuildContext context) {
    final gutter = AppSpace.gutterOf(context);
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth + 2 * gutter),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter).add(padding),
          child: child,
        ),
      ),
    );
  }
}
