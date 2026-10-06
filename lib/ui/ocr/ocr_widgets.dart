import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/ocr/ocr_scanner.dart';
import '../app_scope.dart';
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

/// The recognised pieces of text. Tapping one opens a small "Use as" menu:
/// username, password, link or name, so a login OCR could not sort out can be
/// put together by hand. [onCopy], when given, adds a copy action.
class OcrChips extends StatefulWidget {
  const OcrChips({
    super.key,
    required this.chips,
    required this.onUse,
    this.onCopy,
    this.limit = 30,
  });

  final List<String> chips;
  final void Function(String value, OcrField field) onUse;
  final void Function(String value)? onCopy;

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
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final chip in shown)
              _UseAsChip(
                value: chip,
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

class _UseAsChip extends StatelessWidget {
  const _UseAsChip({required this.value, required this.onUse, this.onCopy});

  final String value;
  final void Function(String value, OcrField field) onUse;
  final void Function(String value)? onCopy;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return PopupMenuButton<Object>(
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
          child: Text(l.ocrUseAs, style: theme.textTheme.bodySmall),
        ),
        for (final f in OcrField.values)
          PopupMenuItem<Object>(
            key: ValueKey('ocr.useAs.${f.name}'),
            value: f,
            child: Text(ocrFieldLabel(l, f)),
          ),
        if (onCopy != null) ...[
          const PopupMenuDivider(),
          PopupMenuItem<Object>(
            key: const ValueKey('ocr.copy'),
            value: const _Copy(),
            child: Text(l.copy),
          ),
        ],
      ],
      child: Chip(
        visualDensity: VisualDensity.compact,
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Taps go to the chip, not to the selectable text inside it.
            Flexible(
              child: IgnorePointer(
                child: SecretText(value, style: theme.textTheme.bodyMedium),
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }
}

/// Other readings of one field (the candidates the parser kept), as chips to
/// pick from; the one equal to [current] is selected. Nothing is shown when
/// there is no alternative.
class OcrCandidates extends StatelessWidget {
  const OcrCandidates({
    super.key,
    required this.values,
    required this.current,
    required this.onPick,
    this.max = 5,
  });

  final List<String> values;
  final String current;
  final ValueChanged<String> onPick;
  final int max;

  @override
  Widget build(BuildContext context) {
    final shown = values.take(max).toList();
    if (shown.length < 2) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.ocrOtherReadings, style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final v in shown)
                ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  selected: v == current,
                  onSelected: (_) => onPick(v),
                  label: Text(
                    v,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontFamilyFallback: ['Courier New', 'Consolas', 'Menlo'],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "What was read": the raw lines each pass of the scanner recognised, so a
/// failure can be diagnosed. The user's own data, held in memory only; it is
/// never logged or stored.
class OcrWhatWasRead extends StatelessWidget {
  const OcrWhatWasRead({super.key, required this.passes, this.maxLines = 80});

  final List<ScanPass> passes;

  /// Lines shown per pass: tiles of a big screenshot read a lot.
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    if (passes.isEmpty) return const SizedBox.shrink();
    final l = context.l10n;
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Courier New', 'Consolas', 'Menlo'],
    );
    return ExpansionTile(
      key: const ValueKey('ocr.read'),
      tilePadding: EdgeInsets.zero,
      shape: const Border(),
      collapsedShape: const Border(),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      expandedAlignment: AlignmentDirectional.centerStart,
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      title: Text(l.ocrWhatWasRead, style: theme.textTheme.titleSmall),
      children: [
        Text(l.ocrWhatWasReadNote, style: theme.textTheme.bodySmall),
        for (final (i, pass) in passes.indexed) ...[
          const SizedBox(height: 8),
          Text(
            l.ocrPassTitle(i + 1, pass.name),
            style: theme.textTheme.labelLarge,
          ),
          if (pass.failed)
            Text(l.ocrPassFailed(pass.error!.name), style: mono)
          else if (pass.lines.isEmpty)
            Text(l.ocrPassNothing, style: theme.textTheme.bodySmall)
          else
            Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in pass.lines.take(maxLines))
                    Text(line, style: mono),
                  if (pass.lines.length > maxLines) Text('…', style: mono),
                ],
              ),
            ),
        ],
      ],
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
    final theme = Theme.of(context);
    Widget item(String marker, String text) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 20, child: Text(marker)),
          Expanded(child: Text(text)),
        ],
      ),
    );
    final children = switch (error) {
      null => [
        Text(l.ocrTipsTitle, style: theme.textTheme.titleSmall),
        item('•', l.ocrTipCrop),
        item('•', l.ocrTipVisible),
        item('•', l.ocrTipAgain),
      ],
      ScanError.noLanguage => [
        Text(l.ocrNoLanguageBody),
        const SizedBox(height: 4),
        item('1.', l.ocrNoLanguageStep1),
        item('2.', l.ocrNoLanguageStep2),
        item('3.', l.ocrNoLanguageStep3),
        item('4.', l.ocrNoLanguageStep4),
      ],
      ScanError.imageTooLarge => [Text(l.ocrTooLargeBody)],
      ScanError.unsupportedImage => [Text(l.ocrUnsupportedBody)],
      ScanError.fileUnreadable => [Text(l.ocrUnreadableBody)],
      ScanError.timeout => [Text(l.ocrTimeoutBody)],
      ScanError.failed => [Text(l.ocrFailedBody)],
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
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
    builder: (c) => AlertDialog(
      title: Text(ocrFailureTitle(l, error)),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OcrFailureBody(error: error),
              if (passes.isNotEmpty) ...[
                const SizedBox(height: 12),
                OcrWhatWasRead(passes: passes),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(l.close)),
        TextButton(
          onPressed: () => Navigator.pop(c, OcrFailureAction.byHand),
          child: Text(l.ocrFillByHand),
        ),
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.pop(c, OcrFailureAction.again),
          child: Text(l.ocrPasteAgain),
        ),
      ],
    ),
  );
}
