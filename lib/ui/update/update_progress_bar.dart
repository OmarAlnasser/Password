import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The thin progress bar of the update flow (DESIGN section 8.14): a
/// lavender-to-violet fill on a `line` track that grows from the START edge
/// (the right in Arabic), 500 ms on the portfolio curve, still with "reduce
/// motion" on.
///
/// With a null [value] it is the themed indeterminate bar. [label] is what a
/// screen reader says ("Downloading update").
class UpdateProgressBar extends StatelessWidget {
  const UpdateProgressBar({super.key, this.value, this.label, this.height = 6});

  /// 0 to 1, or null when the length of the wait is unknown.
  final double? value;
  final String? label;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final radius = BorderRadius.circular(height / 2);
    final v = value;
    final Widget bar;
    if (v == null) {
      bar = LinearProgressIndicator(minHeight: height, borderRadius: radius);
    } else {
      bar = SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(color: t.line, borderRadius: radius),
          child: ClipRRect(
            borderRadius: radius,
            child: AnimatedFractionallySizedBox(
              duration: context.motion(AppMotion.fill),
              curve: AppMotion.ease,
              alignment: AlignmentDirectional.centerStart,
              widthFactor: v.clamp(0.0, 1.0),
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.centerStart,
                    end: AlignmentDirectional.centerEnd,
                    colors: [t.accent2, t.strong],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Semantics(
      label: label,
      value: v == null ? null : '${(v.clamp(0.0, 1.0) * 100).floor()}%',
      child: ExcludeSemantics(child: bar),
    );
  }
}
