import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A calm, centred "nothing here" message (DESIGN section 8.13): a soft
/// glowing tile with an outline icon, a title, an explanation and up to two
/// actions. One for an empty vault, one for "no results" (offer to clear the
/// filter) and a positive one for "no breach findings" ([positive]).
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.secondaryAction,
    this.positive = false,
  });

  final IconData icon;
  final String title;
  final String? message;

  /// Usually a [PrimaryButton].
  final Widget? action;

  /// Usually an `OutlinedButton` or `TextButton`.
  final Widget? secondaryAction;

  /// Mint icon instead of lavender: the empty state is good news.
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final tint = positive ? t.good : t.accent2;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Semantics(
            container: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: SizedBox.square(
                    dimension: 72,
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        // The glow is bigger than the tile but takes no layout.
                        OverflowBox(
                          maxWidth: 200,
                          maxHeight: 200,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                colors: [t.glow, t.glow.withValues(alpha: 0)],
                                radius: 0.5,
                              ),
                            ),
                            child: const SizedBox.square(dimension: 200),
                          ),
                        ),
                        Container(
                          width: 72,
                          height: 72,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                t.strong.withValues(alpha: 0.16),
                                t.brandEnd.withValues(alpha: 0.16),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: t.line2),
                          ),
                          child: Icon(icon, size: 32, color: tint),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: tt.headlineSmall,
                  ),
                ),
                if (message != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: tt.bodyMedium!.copyWith(color: t.muted),
                  ),
                ],
                if (action != null || secondaryAction != null) ...[
                  const SizedBox(height: 20),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [?action, ?secondaryAction],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
