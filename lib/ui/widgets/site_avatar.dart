import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// The 44 px icon tile of a list row or detail header (DESIGN section 8.6): a
/// rounded square on `surface2` with a `line2` border. Without [child] it
/// shows the first letter of [title] in lavender; with a [child] (a website
/// icon) it shows that, padded and clipped to the tile. Never empty.
///
/// `SiteIcon` builds one of these for both of its states.
class SiteAvatar extends StatelessWidget {
  const SiteAvatar({
    super.key,
    required this.title,
    this.size = 44,
    this.child,
    this.selected = false,
  });

  final String title;
  final double size;

  /// The website icon, when there is one. It is laid out `size * 0.18` inside
  /// the tile with rounded corners.
  final Widget? child;

  /// Lighter border for the selected row.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final radius = BorderRadius.circular(size * 0.27);
    final letter = title.trim().isEmpty
        ? '?'
        : title.trim().characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: radius,
        border: Border.all(color: selected ? t.selectedBorder : t.line2),
      ),
      child: child == null
          ? Text(
              letter,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontFamily: AppFonts.en,
                fontFamilyFallback: const [AppFonts.ar],
                fontSize: size * 0.4,
                fontWeight: FontWeight.w600,
                color: t.accent2,
                height: 1,
              ),
            )
          : Padding(
              padding: EdgeInsets.all(size * 0.18),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(size * 0.14),
                child: child,
              ),
            ),
    );
  }
}
