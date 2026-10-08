import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/entry_sort.dart';
import '../app_scope.dart';
import '../theme/tokens.dart';

/// The sort control of the entry list: a small pill that shows the active
/// order ("Recently used") and opens a menu with the three orders, the active
/// one ticked.
///
/// It is a themed [OutlinedButton] (so the focus ring, hover border and
/// disabled look are the app's), drawn 40 px tall inside a 48 x 48 tap
/// target. A screen reader hears "Sorted by Recently used, button"; the menu
/// items say which one is selected.
class EntrySortButton extends StatelessWidget {
  const EntrySortButton({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final EntrySort value;
  final ValueChanged<EntrySort> onChanged;

  /// The name of [sort] in the active language.
  static String labelOf(AppLocalizations l, EntrySort sort) => switch (sort) {
    EntrySort.recent => l.sortRecent,
    EntrySort.title => l.sortTitle,
    EntrySort.added => l.sortAdded,
  };

  static IconData iconOf(EntrySort sort) => switch (sort) {
    EntrySort.recent => Icons.history_rounded,
    EntrySort.title => Icons.sort_by_alpha_rounded,
    EntrySort.added => Icons.add_circle_outline_rounded,
  };

  Future<void> _open(BuildContext context) async {
    final l = context.l10n;
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final button = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    // Under the button, aligned with whichever edge of it is nearer the edge
    // of the window (its end edge here, in both directions).
    final under = Rect.fromPoints(
      button.localToGlobal(
        button.size.bottomLeft(Offset.zero),
        ancestor: overlay,
      ),
      button.localToGlobal(
        button.size.bottomRight(Offset.zero),
        ancestor: overlay,
      ),
    );
    final picked = await showMenu<EntrySort>(
      context: context,
      position: RelativeRect.fromRect(under, Offset.zero & overlay.size),
      popUpAnimationStyle: context.motionStyle,
      items: [
        for (final s in EntrySort.values)
          PopupMenuItem<EntrySort>(
            value: s,
            child: Semantics(
              selected: s == value,
              inMutuallyExclusiveGroup: true,
              child: Row(
                children: [
                  Icon(iconOf(s), size: 20, color: t.accent2),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      labelOf(l, s),
                      style: s == value
                          ? tt.bodyMedium!.copyWith(
                              color: t.ink,
                              fontWeight: FontWeight.w600,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // The tick, or the room for it, so the labels line up.
                  SizedBox.square(
                    dimension: 20,
                    child: s == value
                        ? Icon(Icons.check_rounded, size: 20, color: t.link)
                        : null,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
    if (picked != null && picked != value) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final label = labelOf(l, value);
    return Tooltip(
      message: l.sortBy,
      // The button's own label already says it.
      excludeFromSemantics: true,
      child: Builder(
        builder: (context) => OutlinedButton(
          onPressed: () => _open(context),
          style: OutlinedButton.styleFrom(
            shape: const StadiumBorder(),
            backgroundColor: t.surface,
            foregroundColor: t.soft,
            minimumSize: const Size(48, 40),
            tapTargetSize: MaterialTapTargetSize.padded,
            visualDensity: VisualDensity.standard,
            padding: const EdgeInsetsDirectional.only(start: 12, end: 8),
            textStyle: Theme.of(context).textTheme.labelMedium,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.swap_vert_rounded, size: 18, color: t.accent2),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  semanticsLabel: l.sortedBy(label),
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.expand_more_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
