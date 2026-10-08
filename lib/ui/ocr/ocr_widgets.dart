import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/ocr/ocr_scanner.dart';
import '../app_scope.dart';
import '../theme/theme.dart';
import '../widgets/focus_ring.dart';
import '../widgets/reveal_controller.dart';
import '../widgets/secret_text.dart';

/// Where a piece of recognised text can be put.
enum OcrField { username, password, link, name }

String ocrFieldLabel(AppLocalizations l, OcrField field) => switch (field) {
  OcrField.username => l.ocrAsUsername,
  OcrField.password => l.ocrAsPassword,
  OcrField.link => l.ocrAsLink,
  OcrField.name => l.ocrAsName,
};

/// Whether [scan] has nothing the user could use: no address, password, link
/// or name, and no text to pick from. OCR that failed outright counts.
bool ocrFoundNothing(ScanResult scan) {
  final b = scan.best;
  return scan.error != null ||
      (b.chips.isEmpty &&
          b.email == null &&
          b.username == null &&
          b.password == null &&
          b.url == null &&
          b.title == null);
}

/// Why [scan] found nothing, when OCR itself is to blame; null when it simply
/// read no text.
ScanError? ocrFailureOf(ScanResult scan) =>
    scan.error ?? (scan.stop == ScanStop.timeout ? ScanError.timeout : null);

String ocrFailureTitle(AppLocalizations l, ScanError? error) => switch (error) {
  null => l.ocrNoText,
  ScanError.noLanguage => l.ocrNoLanguageTitle,
  ScanError.imageTooLarge => l.ocrTooLargeTitle,
  ScanError.unsupportedImage => l.ocrUnsupportedTitle,
  ScanError.fileUnreadable => l.ocrUnreadableTitle,
  ScanError.timeout => l.ocrTimeoutTitle,
  ScanError.failed => l.ocrFailedTitle,
};

/// One choice of a [PillSegments].
class PillSegment<T> {
  const PillSegment({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// A segmented control in the portfolio's pill style: a rounded track with
/// equal pills inside it, the chosen one filled violet. Used for Quick |
/// Advanced and Password | Passphrase.
///
/// Each pill is at least 48 px high, announces itself to a screen reader as
/// one choice of an exclusive group ("selected"), takes keyboard focus and
/// wraps its label instead of overflowing at large text sizes. The fill
/// moves with 200 ms colour changes; with "reduce motion" on it jumps.
class PillSegments<T> extends StatelessWidget {
  const PillSegments({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<PillSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: ShapeDecoration(
        color: t.surface,
        shape: StadiumBorder(side: BorderSide(color: t.line2)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final s in segments)
              Expanded(
                child: _PillSegmentView(
                  segment: s,
                  selected: s.value == selected,
                  onTap: () => onChanged(s.value),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PillSegmentView<T> extends StatelessWidget {
  const _PillSegmentView({
    required this.segment,
    required this.selected,
    required this.onTap,
  });

  final PillSegment<T> segment;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fg = selected ? t.onStrong : t.soft;
    return MergeSemantics(
      child: Semantics(
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: FocusRing(
          radius: 999,
          child: AnimatedContainer(
            duration: context.motion(AppMotion.fast),
            curve: AppMotion.standard,
            decoration: ShapeDecoration(
              color: selected ? t.strong : Colors.transparent,
              shape: StadiumBorder(
                side: BorderSide(
                  color: selected ? t.pillSelectedBorder : Colors.transparent,
                ),
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                customBorder: const StadiumBorder(),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (segment.icon != null) ...[
                        Icon(segment.icon, size: 18, color: fg),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          segment.label,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelMedium!
                              .copyWith(color: fg),
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
    );
  }
}

/// A small rounded tile with an outline icon: the leading mark of a card, a
/// hint or a dialog title in the OCR screens.
class OcrIconTile extends StatelessWidget {
  const OcrIconTile({
    super.key,
    required this.icon,
    this.size = 40,
    this.color,
    this.fill,
  });

  final IconData icon;
  final double size;

  /// Defaults to the lavender accent.
  final Color? color;

  /// Defaults to `tint`.
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill ?? t.tint,
          borderRadius: BorderRadius.circular(size * 0.3),
          border: Border.all(color: t.line2),
        ),
        child: Icon(icon, size: size * 0.52, color: color ?? t.accent2),
      ),
    );
  }
}

/// The recognised pieces of text, as pills. Tapping one opens a small "Use
/// as" menu: username, password, link or name, so a login OCR could not sort
/// out can be put together by hand. [onCopy], when given, adds a copy action.
///
/// Any of the text may be a password, so it is masked unless [obscure] is
/// turned off (the host puts a [RevealButton] next to the chips). A masked
/// chip still opens its menu; a screen reader hears "Password hidden".
class OcrChips extends StatefulWidget {
  const OcrChips({
    super.key,
    required this.chips,
    required this.onUse,
    this.onCopy,
    this.limit = 30,
    this.obscure = true,
  });

  final List<String> chips;
  final void Function(String value, OcrField field) onUse;
  final void Function(String value)? onCopy;

  /// Show bullets instead of the text.
  final bool obscure;

  /// Chips shown before "Show all": a full screenshot can have hundreds.
  final int limit;

  @override
  State<OcrChips> createState() => _OcrChipsState();
}

class _OcrChipsState extends State<OcrChips> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final chips = widget.chips;
    final shown = _all ? chips : chips.take(widget.limit).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 0,
          children: [
            for (final chip in shown)
              _UseAsChip(
                value: chip,
                obscure: widget.obscure,
                onUse: widget.onUse,
                onCopy: widget.onCopy,
              ),
          ],
        ),
        if (!_all && chips.length > shown.length)
          TextButton(
            onPressed: () => setState(() => _all = true),
            child: Text(l.ocrShowAll(chips.length)),
          ),
      ],
    );
  }
}

class _Copy {
  const _Copy();
}

IconData _fieldIcon(OcrField f) => switch (f) {
  OcrField.username => Icons.person_outline_rounded,
  OcrField.password => Icons.key_rounded,
  OcrField.link => Icons.link_rounded,
  OcrField.name => Icons.label_outline_rounded,
};

class _UseAsChip extends StatelessWidget {
  const _UseAsChip({
    required this.value,
    required this.obscure,
    required this.onUse,
    this.onCopy,
  });

  final String value;
  final bool obscure;
  final void Function(String value, OcrField field) onUse;
  final void Function(String value)? onCopy;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    return FocusRing(
      radius: 24,
      child: PopupMenuButton<Object>(
        popUpAnimationStyle: context.motionStyle,
        tooltip: l.ocrUseAs,
        onSelected: (pick) {
          if (pick is OcrField) {
            onUse(value, pick);
          } else {
            onCopy?.call(value);
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem<Object>(
            enabled: false,
            height: 32,
            child: Text(l.ocrUseAs, style: tt.bodySmall),
          ),
          for (final f in OcrField.values)
            PopupMenuItem<Object>(
              key: ValueKey('ocr.useAs.${f.name}'),
              value: f,
              child: Row(
                children: [
                  Icon(_fieldIcon(f), size: 20, color: t.accent2),
                  const SizedBox(width: 12),
                  Text(ocrFieldLabel(l, f)),
                ],
              ),
            ),
          if (onCopy != null) ...[
            const PopupMenuDivider(),
            PopupMenuItem<Object>(
              key: const ValueKey('ocr.copy'),
              value: const _Copy(),
              child: Row(
                children: [
                  Icon(Icons.copy_rounded, size: 20, color: t.soft),
                  const SizedBox(width: 12),
                  Text(l.copy),
                ],
              ),
            ),
          ],
        ],
        // The tap area is the whole 48 px band, not only the pill.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(
            widthFactor: 1,
            child: Chip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Taps go to the chip, not to the selectable text inside it.
                  Flexible(
                    child: IgnorePointer(
                      child: SecretText(
                        value,
                        obscure: obscure,
                        style: tt.bodyMedium!.copyWith(fontSize: 13.5),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.expand_more_rounded, size: 18, color: t.muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Other readings of one field (the candidates the parser kept), as pills to
/// pick from; the one equal to [current] is selected. Nothing is shown when
/// there is no alternative.
///
/// Set [obscure] for the readings of a password: they show as bullets (a
/// screen reader hears "Password hidden") until the host reveals them with
/// the same eye as the password itself.
class OcrCandidates extends StatelessWidget {
  const OcrCandidates({
    super.key,
    required this.values,
    required this.current,
    required this.onPick,
    this.max = 5,
    this.obscure = false,
  });

  final List<String> values;
  final String current;
  final ValueChanged<String> onPick;
  final int max;

  /// Show bullets instead of the readings.
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    final shown = values.take(max).toList();
    if (shown.length < 2) return const SizedBox.shrink();
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.ocrOtherReadings,
            style: tt.bodySmall!.copyWith(color: t.muted),
          ),
          const SizedBox(height: 2),
          Wrap(
            spacing: 8,
            runSpacing: 0,
            children: [
              for (final v in shown)
                ChoiceChip(
                  selected: v == current,
                  onSelected: (_) => onPick(v),
                  label: obscure
                      ? SecretText(
                          v,
                          obscure: true,
                          style: AppText.secretSmall.copyWith(fontSize: 13),
                        )
                      : Text(
                          v,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                          style: AppText.secretSmall.copyWith(fontSize: 13),
                        ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A rounded panel on `surface2` with a hairline border, for secondary
/// content that folds away.
class _FoldPanel extends StatelessWidget {
  const _FoldPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: t.surface2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.controlAll,
        side: BorderSide(color: t.line2),
      ),
      child: child,
    );
  }
}

/// A folding "panel" with a title and an icon: the text that was detected, and
/// what was read. [expandKey] goes on the [ExpansionTile], so a test (or a
/// caller) can find and tap it.
class OcrFold extends StatelessWidget {
  const OcrFold({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.expandKey,
    this.initiallyExpanded = false,
    this.onExpansionChanged,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final Key? expandKey;
  final bool initiallyExpanded;

  /// Called with true when the panel opens and false when it folds away.
  final ValueChanged<bool>? onExpansionChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    return _FoldPanel(
      child: ExpansionTile(
        expansionAnimationStyle: context.motionStyle,
        key: expandKey,
        initiallyExpanded: initiallyExpanded,
        onExpansionChanged: onExpansionChanged,
        tilePadding: const EdgeInsetsDirectional.only(start: 14, end: 10),
        shape: const Border(),
        collapsedShape: const Border(),
        childrenPadding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 14),
        expandedAlignment: AlignmentDirectional.centerStart,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        leading: Icon(icon, size: 22, color: t.accent2),
        title: Text(title, style: tt.titleSmall),
        children: children,
      ),
    );
  }
}

/// "What was read": the raw lines each pass of the scanner recognised, so a
/// failure can be diagnosed. The user's own data, held in memory only; it is
/// never logged or stored.
///
/// The lines can hold the password, so they are masked until the eye at the top
/// of the panel is pressed; they are masked again after 15 s without
/// interaction, when the panel is folded away and when it leaves the screen.
/// The titles and failure messages of the passes hold no text from the image
/// and stay visible.
class OcrWhatWasRead extends StatelessWidget {
  const OcrWhatWasRead({super.key, required this.passes, this.maxLines = 80});

  final List<ScanPass> passes;

  /// Lines shown per pass: tiles of a big screenshot read a lot.
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    if (passes.isEmpty) return const SizedBox.shrink();
    final l = context.l10n;
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final mono = AppText.secretSmall.copyWith(color: t.soft);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: RevealBuilder(
        builder: (context, reveal) => OcrFold(
          expandKey: const ValueKey('ocr.read'),
          icon: Icons.manage_search_rounded,
          title: l.ocrWhatWasRead,
          // Folding the panel away hides the text again.
          onExpansionChanged: (open) {
            if (!open) reveal.hide();
          },
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(l.ocrWhatWasReadNote, style: tt.bodySmall),
                ),
                RevealButton(reveal: reveal),
              ],
            ),
            for (final (i, pass) in passes.indexed) ...[
              const SizedBox(height: 14),
              Text(l.ocrPassTitle(i + 1, pass.name), style: tt.labelLarge),
              const SizedBox(height: 6),
              if (pass.failed)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.error_outline_rounded,
                        size: 16,
                        color: t.error,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l.ocrPassFailed(pass.error!.name),
                        style: mono.copyWith(color: t.error),
                      ),
                    ),
                  ],
                )
              else if (pass.lines.isEmpty)
                Text(l.ocrPassNothing, style: tt.bodySmall)
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: t.line),
                  ),
                  child: reveal.shown
                      ? Directionality(
                          textDirection: TextDirection.ltr,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final line in pass.lines.take(maxLines))
                                Text(line, style: mono),
                              if (pass.lines.length > maxLines)
                                Text('…', style: mono),
                            ],
                          ),
                        )
                      // One masked line for the whole pass (a fixed 8 to 16
                      // bullets, whatever was read), so a screen reader
                      // hears "Password hidden" once, not once per line.
                      : SecretText(
                          pass.lines.join('\n'),
                          obscure: true,
                          style: mono,
                        ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// What to do about an image nothing could be read from: tips, or for a
/// missing Windows OCR language the steps to add one.
class OcrFailureBody extends StatelessWidget {
  const OcrFailureBody({super.key, this.error});

  /// Null when OCR worked but found no text.
  final ScanError? error;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    // A dot or a numbered disc, drawn as a shape (the fonts have no bullet
    // glyphs that match), then the sentence.
    Widget item(String? number, String text) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 22,
              height: 22,
              margin: const EdgeInsetsDirectional.only(end: 10, top: 1),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.tint,
                shape: BoxShape.circle,
                border: Border.all(color: t.line2),
              ),
              child: number == null
                  ? Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: t.accent2,
                        shape: BoxShape.circle,
                      ),
                    )
                  : Text(
                      number,
                      textScaler: TextScaler.noScaling,
                      style: AppText.numeral.copyWith(
                        fontSize: 12,
                        color: t.accent2,
                        height: 1,
                      ),
                    ),
            ),
          ),
          Expanded(
            child: Text(text, style: tt.bodyMedium!.copyWith(color: t.soft)),
          ),
        ],
      ),
    );
    final children = switch (error) {
      null => [
        Text(l.ocrTipsTitle, style: tt.titleSmall),
        item(null, l.ocrTipCrop),
        item(null, l.ocrTipVisible),
        item(null, l.ocrTipAgain),
      ],
      ScanError.noLanguage => [
        Text(
          l.ocrNoLanguageBody,
          style: tt.bodyMedium!.copyWith(color: t.soft),
        ),
        const SizedBox(height: 2),
        item('1', l.ocrNoLanguageStep1),
        item('2', l.ocrNoLanguageStep2),
        item('3', l.ocrNoLanguageStep3),
        item('4', l.ocrNoLanguageStep4),
      ],
      ScanError.imageTooLarge => [_plain(context, l.ocrTooLargeBody)],
      ScanError.unsupportedImage => [_plain(context, l.ocrUnsupportedBody)],
      ScanError.fileUnreadable => [_plain(context, l.ocrUnreadableBody)],
      ScanError.timeout => [_plain(context, l.ocrTimeoutBody)],
      ScanError.failed => [_plain(context, l.ocrFailedBody)],
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _plain(BuildContext context, String text) => Text(
    text,
    style: Theme.of(context).textTheme.bodyMedium!
        .copyWith(color: context.tokens.soft),
  );
}

/// What the user chose in [showOcrFailureDialog].
enum OcrFailureAction {
  /// Read the clipboard again.
  again,

  /// Open the form empty and type the login in.
  byHand,
}

/// Tells the user why nothing was read, with what to try next. Closing it
/// returns null.
Future<OcrFailureAction?> showOcrFailureDialog(
  BuildContext context, {
  ScanError? error,
  List<ScanPass> passes = const [],
}) {
  final l = context.l10n;
  return showDialog<OcrFailureAction>(
    context: context,
    animationStyle: context.motionStyle,
    builder: (c) => AlertDialog(
      title: Row(
        children: [
          OcrIconTile(
            icon: error == null
                ? Icons.search_off_rounded
                : Icons.report_gmailerrorred_rounded,
            color: c.tokens.warn,
            fill: c.tokens.warnContainer,
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(ocrFailureTitle(l, error))),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OcrFailureBody(error: error),
              if (passes.isNotEmpty) OcrWhatWasRead(passes: passes),
            ],
          ),
        ),
      ),
      // Stacked at full width, the main choice first: three side-by-side
      // buttons of different widths looked unfinished and wrapped at large
      // text sizes.
      actions: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.pop(c, OcrFailureAction.again),
              child: Text(l.ocrPasteAgain),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.pop(c, OcrFailureAction.byHand),
              child: Text(l.ocrFillByHand),
            ),
            const SizedBox(height: 4),
            TextButton(onPressed: () => Navigator.pop(c), child: Text(l.close)),
          ],
        ),
      ],
    ),
  );
}
