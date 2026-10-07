import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Text sizes of a [SectionHeader].
enum SectionHeaderSize {
  /// Lock-screen sized (`displayLarge`).
  display,

  /// Screen title (`headlineLarge`).
  screen,

  /// Section title (`headlineMedium`).
  section,

  /// Small group label (`titleSmall`, muted).
  group,
}

/// A title with an optional eyebrow above it (the portfolio's `.eyebrow` +
/// heading, DESIGN section 3.2) and an optional [trailing] widget at the end
/// (a "see all" link, a filter button). The title is marked as a heading for
/// screen readers.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.trailing,
    this.size = SectionHeaderSize.section,
    this.accentDot = false,
  });

  final String title;

  /// Small lavender kicker above the title ("Your vault").
  final String? eyebrow;

  /// Muted explanation under the title.
  final String? subtitle;
  final Widget? trailing;
  final SectionHeaderSize size;

  /// Ends the title with a violet full stop, like the portfolio's name.
  final bool accentDot;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final style = switch (size) {
      SectionHeaderSize.display => tt.displayLarge!,
      SectionHeaderSize.screen => tt.headlineLarge!,
      SectionHeaderSize.section => tt.headlineMedium!,
      SectionHeaderSize.group => tt.titleSmall!.copyWith(color: t.muted),
    };
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (eyebrow != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              eyebrow!,
              style: tt.labelMedium!.copyWith(
                color: t.accent2,
                letterSpacing: context.isArabic ? 0 : 0.3,
              ),
            ),
          ),
        Semantics(
          header: true,
          child: accentDot
              ? Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: title),
                      TextSpan(
                        text: '.',
                        style: TextStyle(color: t.accent),
                      ),
                    ],
                  ),
                  style: style,
                )
              : Text(title, style: style),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              subtitle!,
              style: tt.bodyMedium!.copyWith(color: t.soft),
            ),
          ),
      ],
    );
    if (trailing == null) return column;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: column),
        const SizedBox(width: 12),
        trailing!,
      ],
    );
  }
}
