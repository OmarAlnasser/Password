import 'package:flutter/material.dart';

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
            if (result.crackTimeDisplay.isNotEmpty) result.crackTimeDisplay,
          ].join(' · '),
          style: Theme.of(context).textTheme.bodySmall!
              .copyWith(color: t.rampText[s]),
        ),
      ],
    );
  }
}
