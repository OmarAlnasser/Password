import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/focus_ring.dart';
import '../widgets/pulse_dot.dart';
import 'update_progress_bar.dart';

/// How the banner looks: the mint "live" dot for news and progress, a still red
/// dot for something that went wrong.
enum UpdateBannerTone { info, error }

/// The pill at the top of the app that says an update exists, is downloading,
/// is ready or failed. Portfolio style: a lavender-to-violet gradient border
/// around a `surface` body, a mint [PulseDot] (still and red for [error]), two
/// short lines of text and a close button.
///
/// The whole text area is one button ([onOpen], which opens the update sheet);
/// the close button ([onHide]) hides the banner for now. Both are at least
/// 48 dp tall. The text wraps, so it survives 200 % text size and Arabic.
///
/// It lives above the `Navigator` (see `UpdateGate`), where there is no
/// `Overlay`, so the close button has a semantics label but no tooltip (a
/// tooltip needs an overlay to appear in).
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({
    super.key,
    required this.title,
    required this.onOpen,
    required this.onHide,
    required this.hideLabel,
    this.subtitle,
    this.progress,
    this.indeterminate = false,
    this.tone = UpdateBannerTone.info,
  });

  final String title;
  final String? subtitle;

  /// 0 to 1: shows a progress bar under the text.
  final double? progress;

  /// Shows an indeterminate bar under the text (a wait of unknown length).
  final bool indeterminate;
  final UpdateBannerTone tone;
  final VoidCallback onOpen;
  final VoidCallback onHide;

  /// Screen-reader name of the close button ("Hide for now").
  final String hideLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final failed = tone == UpdateBannerTone.error;
    final gutter = AppSpace.gutterOf(context);
    final borderColors = failed
        ? [t.error, t.error.withValues(alpha: 0.6)]
        : [t.accent2, t.strong];
    const border = 1.5;
    final radius = BorderRadius.circular(AppRadius.card);
    final inner = BorderRadius.circular(AppRadius.card - border);

    final text = Padding(
      padding: const EdgeInsetsDirectional.only(top: 10, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: tt.titleSmall!.copyWith(color: t.ink)),
          if (subtitle != null)
            Text(subtitle!, style: tt.bodySmall!.copyWith(color: t.muted)),
          if (progress != null || indeterminate) ...[
            const SizedBox(height: 8),
            UpdateProgressBar(value: progress, height: 4),
          ],
        ],
      ),
    );

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 4),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppLayout.form),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: AlignmentDirectional.centerStart,
                  end: AlignmentDirectional.centerEnd,
                  colors: borderColors,
                ),
                borderRadius: radius,
                boxShadow: failed ? null : t.buttonShadow,
              ),
              child: Padding(
                padding: const EdgeInsets.all(border),
                child: ClipRRect(
                  borderRadius: inner,
                  child: Material(
                    color: t.surface,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: MergeSemantics(
                            child: Semantics(
                              button: true,
                              child: FocusRing(
                                radius: AppRadius.control,
                                child: InkWell(
                                  onTap: onOpen,
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      minHeight: 48,
                                    ),
                                    child: Row(
                                      children: [
                                        const SizedBox(width: 6),
                                        PulseDot(
                                          color: failed ? t.error : null,
                                          active: !failed,
                                        ),
                                        const SizedBox(width: 2),
                                        Expanded(child: text),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Semantics(
                          button: true,
                          label: hideLabel,
                          excludeSemantics: true,
                          onTap: onHide,
                          child: IconButton(
                            onPressed: onHide,
                            icon: const Icon(Icons.close),
                            iconSize: 20,
                            color: t.soft,
                            style: IconButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              tapTargetSize: MaterialTapTargetSize.padded,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
