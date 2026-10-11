import 'package:flutter/material.dart';

import '../../services/sync/sync_service.dart';
import '../app_scope.dart';
import '../theme/tokens.dart';
import 'confirm_delete_dialog.dart';
import 'icon_tile.dart';
import 'surface_card.dart';

/// [SyncService.syncNow] for a button. A pull refused as a mass deletion is
/// shown by [SyncDeletionPrompt] (and in the sync status), so it must not
/// escape as an uncaught error; every other failure is handled inside
/// `syncNow` already.
Future<void> syncNowFromButton(SyncService sync) async {
  try {
    await sync.syncNow();
  } on MassDeletionException {
    // Waiting for the user: the prompt says so.
  }
}

/// Another device deleted most of the vault in one go, and sync on this
/// device did not apply it ([SyncService.pendingMassDeletion]). Says so and
/// offers the two ways out: "Delete here too" (asked again in the usual
/// delete dialog) or "Keep them" (pushed back, so they return on every
/// device). Until then this device still sends its own changes.
///
/// Above the entry list it is a card of its own ([framed]); in the settings
/// it is a row of the sync group, which is a card already.
class SyncDeletionPrompt extends StatefulWidget {
  const SyncDeletionPrompt({
    super.key,
    required this.sync,
    required this.count,
    this.framed = true,
  });

  final SyncService sync;

  /// How many entries the other device deleted.
  final int count;

  final bool framed;

  @override
  State<SyncDeletionPrompt> createState() => _SyncDeletionPromptState();
}

class _SyncDeletionPromptState extends State<SyncDeletionPrompt> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() resolve) async {
    setState(() => _busy = true);
    try {
      await resolve();
    } on MassDeletionException {
      // Asked again (the server changed meanwhile): the prompt stays.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    final l = context.l10n;
    final ok = await confirmDeleteEntries(
      context,
      count: widget.count,
      message: l.syncDeletionConfirmBody,
    );
    if (ok && mounted) await _run(widget.sync.applyMassDeletion);
  }

  Future<void> _keep() => _run(widget.sync.keepMassDeletion);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconTile(
              icon: Icons.cloud_sync_outlined,
              color: t.warn,
              fill: t.warnContainer,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      l.syncDeletionTitle(widget.count),
                      style: tt.titleSmall!.copyWith(color: t.ink),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l.syncDeletionBody,
                    style: tt.bodySmall!.copyWith(color: t.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Side by side at the end; stacked when large text leaves no room.
        OverflowBar(
          alignment: MainAxisAlignment.end,
          overflowAlignment: OverflowBarAlignment.end,
          spacing: 8,
          overflowSpacing: 4,
          children: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: t.error),
              onPressed: _busy ? null : _apply,
              child: Text(l.syncDeletionApply),
            ),
            OutlinedButton(
              onPressed: _busy ? null : _keep,
              child: Text(l.syncDeletionKeep),
            ),
          ],
        ),
      ],
    );
    if (!widget.framed) {
      return Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 12, 10),
        child: content,
      );
    }
    return SurfaceCard(hoverLift: 0, child: content);
  }
}
