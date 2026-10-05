import 'package:flutter/material.dart';

/// Characters that are easy to misread, especially in OCR output.
const ambiguousChars = {'0', 'O', 'o', 'l', 'I', '1', '|', '5', 'S', '8', 'B'};

/// Monospace text that highlights ambiguous characters and always lays out
/// left-to-right (passwords must not be reordered by the Arabic RTL layout).
class SecretText extends StatelessWidget {
  const SecretText(
    this.text, {
    super.key,
    this.obscure = false,
    this.style,
    this.highlightAmbiguous = true,
  });

  final String text;
  final bool obscure;
  final TextStyle? style;
  final bool highlightAmbiguous;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = (style ?? Theme.of(context).textTheme.bodyLarge!).copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Courier New', 'Consolas', 'Menlo'],
      letterSpacing: 1.2,
    );
    if (obscure) {
      return Text('•' * text.length.clamp(8, 16), style: base);
    }
    final spans = <TextSpan>[
      for (final ch in text.characters)
        TextSpan(
          text: ch,
          style: highlightAmbiguous && ambiguousChars.contains(ch)
              ? TextStyle(
                  color: scheme.onTertiaryContainer,
                  backgroundColor: scheme.tertiaryContainer,
                  fontWeight: FontWeight.bold,
                )
              : _classStyle(ch, scheme),
        ),
    ];
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SelectableText.rich(TextSpan(style: base, children: spans)),
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
