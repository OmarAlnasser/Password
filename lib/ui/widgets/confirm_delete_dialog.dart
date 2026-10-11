import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../theme/tokens.dart';
import 'icon_tile.dart';
import 'primary_button.dart';

/// "Delete 12 entries? This cannot be undone." in the app's dialog style: the
/// red bin badge, Cancel and a red Delete. True when confirmed.
///
/// [message] replaces "This cannot be undone."; each of [notes] is one more
/// line under it (entries the search hides, what other devices will do).
/// None of them may hold anything secret.
Future<bool> confirmDeleteEntries(
  BuildContext context, {
  required int count,
  String? message,
  List<String> notes = const [],
}) async {
  final l = context.l10n;
  final ok = await showDialog<bool>(
    context: context,
    animationStyle: context.motionStyle,
    builder: (c) {
      final tt = Theme.of(c).textTheme;
      return AlertDialog(
        // Large text on a small phone: the words scroll, nothing is cut.
        scrollable: true,
        // Centre: the dialog's icon slot is tight, which would stretch a
        // tile with a fixed size into a flat bar.
        icon: Center(
          child: IconTile(
            icon: Icons.delete_outline_rounded,
            size: 56,
            color: c.tokens.error,
            fill: c.tokens.errorContainer,
          ),
        ),
        title: Text(l.deleteEntriesTitle(count), textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message ?? l.deleteCannotUndo, textAlign: TextAlign.center),
            for (final note in notes) ...[
              const SizedBox(height: 10),
              Text(
                note,
                textAlign: TextAlign.center,
                style: tt.bodyMedium!.copyWith(color: c.tokens.soft),
              ),
            ],
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsOverflowAlignment: OverflowBarAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(l.cancel),
          ),
          PrimaryButton(
            destructive: true,
            glow: false,
            onPressed: () => Navigator.pop(c, true),
            child: Text(l.delete),
          ),
        ],
      );
    },
  );
  return ok ?? false;
}
