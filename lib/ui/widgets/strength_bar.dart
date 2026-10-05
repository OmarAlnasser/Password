import 'package:flutter/material.dart';

import '../../services/password_generator.dart';
import '../app_scope.dart';

class StrengthBar extends StatelessWidget {
  const StrengthBar({super.key, required this.result});

  final StrengthResult result;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final labels = [
      l.strength0,
      l.strength1,
      l.strength2,
      l.strength3,
      l.strength4,
    ];
    const colors = [
      Colors.red,
      Colors.deepOrange,
      Colors.amber,
      Colors.lightGreen,
      Colors.green,
    ];
    final s = result.score.clamp(0, 4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: (s + 1) / 5,
          color: colors[s],
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
        ),
        const SizedBox(height: 4),
        Text(
          [
            labels[s],
            if (result.crackTimeDisplay.isNotEmpty) result.crackTimeDisplay,
          ].join(' · '),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
