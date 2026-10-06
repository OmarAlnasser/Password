import 'package:flutter/material.dart';

import '../../brand.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// What the brand tile shows inside the gradient.
enum BrandGlyph {
  /// The shield-and-keyhole mark (`assets/brand/mark_mono.png`), tinted dark.
  /// Falls back to a lock icon when the asset is not bundled.
  mark,

  /// The first letter of the app name (the portfolio's "O").
  letter,
}

/// The portfolio's `.brand-mark`: a rounded tile with the 135 degree violet
/// gradient and a dark glyph (DESIGN section 8.1). Decorative, so it is
/// excluded from semantics; put the app name next to it as text
/// ([BrandLockup]).
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 34,
    this.glyph = BrandGlyph.mark,
    this.glow = false,
  });

  /// 34 in the app bar, 38 in the rail, 72 on the lock screen.
  final double size;
  final BrandGlyph glyph;

  /// Soft violet halo under the tile (lock screen, empty states).
  final bool glow;

  /// The bundled single-colour mark. Declared in `pubspec.yaml`.
  static const markAsset = 'assets/brand/mark_mono.png';

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget lock() =>
        Icon(Icons.lock_rounded, size: size * 0.5, color: t.brandGlyph);
    final Widget inner = switch (glyph) {
      BrandGlyph.letter => Text(
        appInitial,
        style: TextStyle(
          fontFamily: AppFonts.en,
          fontFamilyFallback: const [AppFonts.ar],
          fontSize: size * 0.47,
          fontWeight: FontWeight.w700,
          color: t.brandGlyph,
          height: 1,
        ),
      ),
      BrandGlyph.mark => Image.asset(
        markAsset,
        width: size * 0.62,
        height: size * 0.62,
        color: t.brandGlyph,
        colorBlendMode: BlendMode.srcIn,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => lock(),
      ),
    };
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: t.brandGradient,
          borderRadius: BorderRadius.circular(size * 0.3),
          boxShadow: glow
              ? [
                  BoxShadow(
                    color: t.buttonGlow,
                    blurRadius: size * 0.55,
                    offset: Offset(0, size * 0.18),
                  ),
                ]
              : null,
        ),
        child: inner,
      ),
    );
  }
}

/// Brand tile plus the wordmark (Outfit 600, 15, +1 tracking, upper-case),
/// as in the portfolio header. The name comes from `lib/brand.dart`.
class BrandLockup extends StatelessWidget {
  const BrandLockup({
    super.key,
    this.size = 34,
    this.showName = true,
    this.glyph = BrandGlyph.mark,
  });

  final double size;
  final bool showName;
  final BrandGlyph glyph;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final name = appNameFor(Localizations.maybeLocaleOf(context));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: size, glyph: glyph),
        if (showName) ...[
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.wordmark.copyWith(color: t.ink),
            ),
          ),
        ],
      ],
    );
  }
}
