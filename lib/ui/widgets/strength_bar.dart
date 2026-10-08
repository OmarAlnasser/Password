import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/password_generator.dart';
import '../app_scope.dart';
import '../theme/tokens.dart';

/// Password strength as five pill segments (DESIGN section 8.8): the filled
/// ones take the ramp colour of the score, from red through amber to mint,
/// and fill from the start edge (right in Arabic). The text label under it,
/// with the crack-time estimate, carries the meaning, so the colour is never
/// the only signal; its colour is darkened in the light theme where the bar
/// colour would fall under 4.5:1.
class StrengthBar extends StatelessWidget {
  const StrengthBar({super.key, required this.result});

  final StrengthResult result;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final labels = [
      l.strength0,
      l.strength1,
      l.strength2,
      l.strength3,
      l.strength4,
    ];
    final s = result.score.clamp(0, 4);
    final fillDuration = context.motion(AppMotion.fill);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Row(
            children: [
              for (var i = 0; i < 5; i++)
                Expanded(
                  child: AnimatedContainer(
                    duration: fillDuration,
                    curve: AppMotion.ease,
                    margin: EdgeInsetsDirectional.only(end: i == 4 ? 0 : 4),
                    height: 6,
                    decoration: BoxDecoration(
                      color: i <= s ? t.ramp[s] : t.surface3,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          [
            labels[s],
            if (result.crackTimeDisplay.isNotEmpty)
              localizedCrackTime(l, result.crackTimeDisplay),
          ].join(' · '),
          style: Theme.of(context).textTheme.bodySmall!
              .copyWith(color: t.rampText[s]),
        ),
      ],
    );
  }
}

final RegExp _crackTime = RegExp(
  r'^(\d+) (second|minute|hour|day|month|year)s*$',
);

/// zxcvbn's crack-time estimate is an English phrase ("3 years", "less than
/// a second", "centuries"). This turns it into the app's language, with a
/// proper plural, so an Arabic label is not half English with its numbers
/// reversed by the bidi algorithm. A phrase it does not know is returned as it
/// is, kept left to right when it is Latin text in an Arabic sentence.
String localizedCrackTime(AppLocalizations l, String display) {
  final text = display.trim();
  if (text == 'less than a second') return l.crackLessThanSecond;
  if (text == 'centuries') return l.crackCenturies;
  final m = _crackTime.firstMatch(text);
  if (m != null) {
    final n = int.parse(m.group(1)!);
    return switch (m.group(2)) {
      'second' => l.crackSeconds(n),
      'minute' => l.crackMinutes(n),
      'hour' => l.crackHours(n),
      'day' => l.crackDays(n),
      'month' => l.crackMonths(n),
      _ => l.crackYears(n),
    };
  }
  final latin = RegExp('[A-Za-z]').hasMatch(text);
  final arabic = RegExp('[\u0600-\u06FF]').hasMatch(text);
  if (l.localeName.startsWith('ar') && latin && !arabic) {
    return '\u2066$text\u2069';
  }
  return text;
}
