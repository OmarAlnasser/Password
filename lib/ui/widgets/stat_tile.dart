import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// A KPI tile (the portfolio's `.stats div`, DESIGN section 8.5): `surface`
/// fill, 1 px border, 14 px radius, a big lavender numeral and a small muted
/// label. It sizes to its content, never to a fixed aspect ratio, so large
/// system text and Arabic do not overflow.
///
/// [value] is a string so the caller controls the digits: always Western
/// digits (`'128'`), also in Arabic. With [onTap] the tile is a button.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.onTap,
    this.valueColor,
    this.footnote,
  });

  final String value;
  final String label;
  final VoidCallback? onTap;

  /// Defaults to `accent2`. Use `tokens.error` / `tokens.good` sparingly.
  final Color? valueColor;

  /// Small line under the label, such as a delta ("+12") in `good`. Numbers
  /// are shown left-to-right also in Arabic.
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final radius = AppRadius.statAll;
    Widget content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.numeral.copyWith(color: valueColor ?? t.accent2),
          ),
          const SizedBox(height: 2),
          Text(label, style: tt.bodySmall),
          if (footnote != null) ...[
            const SizedBox(height: 2),
            Text(
              _isolate(footnote!),
              style: tt.bodySmall!.copyWith(color: t.good),
            ),
          ],
        ],
      ),
    );
    if (onTap != null) {
      content = Material(
        type: MaterialType.transparency,
        child: InkWell(onTap: onTap, borderRadius: radius, child: content),
      );
    }
    return MergeSemantics(
      child: Semantics(
        button: onTap != null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: radius,
            border: Border.all(color: t.line),
          ),
          child: ClipRRect(borderRadius: radius, child: content),
        ),
      ),
    );
  }
}

/// Keeps a footnote such as "+1" or "-2" left-to-right inside an Arabic
/// layout, where a bare "+1" would be shown as "1+". Text with Arabic letters
/// is left alone.
String _isolate(String s) =>
    RegExp('[\u0600-\u06FF]').hasMatch(s) ? s : '\u2066$s\u2069';

/// Lays [tiles] out in rows of equal-height cells: 2 per row on phones,
/// 4 from 640 px of width (or [columns]). Built with [IntrinsicHeight] rows,
/// not a fixed-aspect grid, so tiles grow with their content.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.tiles, this.columns, this.gap = 12});

  final List<Widget> tiles;
  final int? columns;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final n = columns ?? (c.maxWidth >= 640 ? 4 : 2);
        final rows = <Widget>[];
        for (var i = 0; i < tiles.length; i += n) {
          final slice = tiles.sublist(i, (i + n).clamp(0, tiles.length));
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = 0; j < n; j++) ...[
                    if (j > 0) SizedBox(width: gap),
                    Expanded(
                      child: j < slice.length ? slice[j] : const SizedBox(),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) SizedBox(height: gap),
              rows[i],
            ],
          ],
        );
      },
    );
  }
}
