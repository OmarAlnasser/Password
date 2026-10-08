import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/tokens.dart';

import '../theme/typography.dart';

/// Characters that are easy to misread, especially in OCR output.
const ambiguousChars = {'0', 'O', 'o', 'l', 'I', '1', '|', '5', 'S', '8', 'B'};

/// Monospace text that highlights ambiguous characters and always lays out
/// left-to-right (passwords must not be reordered by the Arabic RTL layout).
///
/// Set in the bundled JetBrains Mono (`AppFonts.mono`) on every platform, so a
/// password looks the same everywhere: its `0` has an inner mark, `O` is a
/// plain oval, `1` has a flag and a base, `l` has a curved tail, `I` has
/// serifs and `|` is a bar. The font has no coding ligatures, and `calt` is
/// switched off as well, so `->` or `!=` in a password never fuse.
///
/// Colours: digits `primary`, symbols `error`, letters as the text, and
/// ambiguous characters bolder on the `tertiaryContainer` background, so the
/// warning is not colour alone. In a right-to-left layout the value sits at
/// the start (right) edge but its characters stay left-to-right.
class SecretText extends StatelessWidget {
  const SecretText(
    this.text, {
    super.key,
    this.obscure = false,
    this.style,
    this.highlightAmbiguous = true,
    this.hiddenLabel,
  });

  final String text;
  final bool obscure;
  final TextStyle? style;
  final bool highlightAmbiguous;

  /// What a screen reader hears while [obscure]: "Password hidden" unless
  /// given. Text that is masked only because it might be a password (the
  /// pieces OCR read) passes the neutral `textHidden` instead. Never the
  /// value itself.
  final String? hiddenLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final given = style ?? Theme.of(context).textTheme.bodyLarge!;
    final size = given.fontSize ?? 16;
    final base = AppText.asSecret(given).copyWith(
      // 0.045 em: 0.8 px at the 18 px of DESIGN's `secret` style.
      letterSpacing: size * 0.045,
      height: given.height ?? 1.5,
    );
    // The value sits at the start edge of the surrounding layout, but its
    // characters are always laid out left-to-right.
    final align = Directionality.of(context) == TextDirection.rtl
        ? TextAlign.right
        : TextAlign.left;
    if (obscure) {
      // A screen reader would say "bullet, bullet, ..." for the dots (and
      // reveal that the count is a fixed 8 to 16), so it hears one phrase.
      final hidden =
          hiddenLabel ??
          Localizations.of<AppLocalizations>(
            context,
            AppLocalizations,
          )?.passwordHidden;
      return Semantics(
        label: hidden,
        excludeSemantics: hidden != null,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            '•' * text.length.clamp(8, 16),
            style: base,
            textAlign: align,
          ),
        ),
      );
    }
    final spans = <TextSpan>[
      for (final ch in text.characters)
        TextSpan(
          text: ch,
          style: highlightAmbiguous && ambiguousChars.contains(ch)
              ? TextStyle(
                  color: scheme.onTertiaryContainer,
                  backgroundColor: scheme.tertiaryContainer,
                  fontWeight: FontWeight.w500,
                )
              : _classStyle(ch, scheme),
        ),
    ];
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SelectableText.rich(
        TextSpan(style: base, children: spans),
        textAlign: align,
      ),
    );
  }

  static TextStyle? _classStyle(String ch, ColorScheme scheme) {
    final c = ch.codeUnitAt(0);
    if (c >= 0x30 && c <= 0x39) return TextStyle(color: scheme.primary);
    final isAlpha =
        (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a) || c > 0x7f;
    if (!isAlpha) return TextStyle(color: scheme.error);
    return null;
  }
}

/// The box a revealed secret sits in (DESIGN section 8.8): `surface2` fill,
/// 1 px `line2` border, 12 px radius, 16 px padding. Put a [SecretText] in it,
/// with a `StrengthBar` under it where a strength is known. It does not know
/// about the secret itself, so it never carries it into semantics or keys.
class SecretBox extends StatelessWidget {
  const SecretBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: AppRadius.controlAll,
        border: Border.all(color: t.line2),
      ),
      child: child,
    );
  }
}

/// A technical string (email, URL, domain, username, IP address) that must
/// always lay out left-to-right, in the small mono style of DESIGN's
/// `secretSmall`, truncated to one line by default.
///
/// In a right-to-left layout the text sits at the start (right) edge, but its
/// characters and its trailing punctuation stay left-to-right, which is what
/// the portfolio does for its metrics (`direction:ltr; text-align:right`).
/// Not for secrets: they use [SecretText], which also highlights ambiguous
/// characters.
class LtrText extends StatelessWidget {
  const LtrText(
    this.text, {
    super.key,
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
  });

  final String text;

  /// Merged over `AppText.secretSmall` in the muted colour.
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final outer = Directionality.of(context);
    final base = AppText.secretSmall.copyWith(color: t.muted);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text(
        text,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: outer == TextDirection.rtl
            ? TextAlign.right
            : TextAlign.left,
        style: style == null ? base : base.merge(style),
      ),
    );
  }
}
