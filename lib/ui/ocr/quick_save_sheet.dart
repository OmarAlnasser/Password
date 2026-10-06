import 'package:flutter/material.dart';

import '../../data/models/vault_entry.dart';
import '../../services/ocr/ocr_parser.dart';
import '../../services/ocr/ocr_scanner.dart';
import '../../services/vault_session.dart';
import '../app_scope.dart';
import '../widgets/secret_text.dart';
import 'ocr_widgets.dart';

/// Bottom sheet that saves a login read from the clipboard (a pasted
/// screenshot or text) in a few taps.
///
/// Quick asks only for a name and shows the detected username and password
/// for checking. Advanced adds where the login is from, why it exists and
/// tags. Switching keeps what was typed; everything filled in is saved,
/// except a detected link the user never saw: it would also make the app
/// fetch that site's icon.
///
/// Never a dead end: when only part of the login was found, the sheet still
/// opens with what there is, the other readings of each value to pick from,
/// and every piece of text that was read, to tap and use as the username,
/// password, link or name.
class QuickSaveSheet extends StatefulWidget {
  const QuickSaveSheet({
    super.key,
    required this.found,
    this.passes = const [],
  });

  final OcrResult found;

  /// What each scan pass read, for "What was read". Empty for pasted text.
  final List<ScanPass> passes;

  /// Shows the sheet. True when an entry was saved.
  static Future<bool> show(
    BuildContext context,
    OcrResult found, {
    List<ScanPass> passes = const [],
  }) async =>
      await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        builder: (_) => QuickSaveSheet(found: found, passes: passes),
      ) ??
      false;

  @override
  State<QuickSaveSheet> createState() => _QuickSaveSheetState();
}

class _QuickSaveSheetState extends State<QuickSaveSheet> {
  late final TextEditingController _name, _user, _pw, _url, _notes, _tags;
  bool _advanced = false;

  /// Advanced, which shows the link field, has been open.
  bool _linkShown = false;
  bool _saving = false;

  /// The username or the password was not found: the text read is shown open.
  late final bool _incomplete;

  @override
  void initState() {
    super.initState();
    final f = widget.found;
    _incomplete = (f.username ?? f.email) == null || f.password == null;
    _name = TextEditingController(text: f.title ?? '');
    _user = TextEditingController(text: f.username ?? f.email ?? '');
    _pw = TextEditingController(text: f.password ?? '');
    _url = TextEditingController(text: f.url ?? '');
    _notes = TextEditingController();
    _tags = TextEditingController();
  }

  @override
  void dispose() {
    for (final c in [_name, _user, _pw, _url, _notes, _tags]) {
      c
        ..clear()
        ..dispose();
    }
    super.dispose();
  }

  bool get _canSave =>
      !_saving && (_user.text.trim().isNotEmpty || _pw.text.isNotEmpty);

  /// Puts a piece of the text that was read into [field].
  void _use(String value, OcrField field) => setState(() {
    switch (field) {
      case OcrField.username:
        _user.text = value;
      case OcrField.password:
        _pw.text = value;
      case OcrField.name:
        _name.text = value;
      case OcrField.link:
        // Shown, so it is saved: the user has seen it.
        _url.text = value;
        _advanced = true;
        _linkShown = true;
    }
  });

  Future<void> _save() async {
    final s = context.services;
    final l = context.l10n;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final user = _user.text.trim();
    final title = [
      _name.text.trim(),
      widget.found.title ?? '',
      user,
    ].firstWhere((t) => t.isNotEmpty, orElse: () => '');
    final entry = VaultEntry(
      id: VaultSession.newId(),
      title: title,
      username: user,
      password: _pw.text,
      url: _linkShown ? _url.text.trim() : '',
      notes: _notes.text,
      tags: _tags.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toSet()
          .toList(),
    );
    setState(() => _saving = true);
    try {
      await s.session.saveEntry(entry);
    } on Object {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(l.error)));
      return;
    }
    s.prefetchIcons();
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final f = widget.found;
    const gap = SizedBox(height: 12);
    return Padding(
      // Keep the fields above the on-screen keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.saveLogin, style: theme.textTheme.titleLarge),
            gap,
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.bolt),
                  label: Text(l.quickMode),
                ),
                ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.tune),
                  label: Text(l.advancedMode),
                ),
              ],
              selected: {_advanced},
              onSelectionChanged: (v) => setState(() {
                _advanced = v.single;
                _linkShown |= _advanced;
              }),
            ),
            const SizedBox(height: 16),
            if (_incomplete && f.chips.isNotEmpty) ...[
              Card(
                margin: EdgeInsets.zero,
                color: theme.colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.touch_app_outlined,
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l.ocrPickHint,
                          style: TextStyle(
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              gap,
            ],
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: l.name),
            ),
            gap,
            TextField(
              controller: _user,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              keyboardType: TextInputType.emailAddress,
              // Addresses and passwords read left to right in Arabic too.
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: l.username),
              onChanged: (_) => setState(() {}),
            ),
            OcrCandidates(
              values: f.emailCandidates,
              current: _user.text.trim(),
              onPick: (v) => setState(() => _user.text = v),
            ),
            gap,
            // Shown in clear text: OCR output must be checked character by
            // character before it is saved.
            TextField(
              controller: _pw,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              style: const TextStyle(fontFamily: 'monospace'),
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: l.password),
              onChanged: (_) => setState(() {}),
            ),
            OcrCandidates(
              values: f.passwordCandidates,
              current: _pw.text,
              onPick: (v) => setState(() => _pw.text = v),
            ),
            if (_pw.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              SecretText(_pw.text),
              Text(l.ocrAmbiguous, style: theme.textTheme.bodySmall),
            ],
            if (_advanced) ...[
              gap,
              TextField(
                controller: _url,
                autocorrect: false,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(labelText: l.whereFrom),
              ),
              gap,
              TextField(
                controller: _notes,
                minLines: 2,
                maxLines: 5,
                enableIMEPersonalizedLearning: false,
                decoration: InputDecoration(labelText: l.whyNotes),
              ),
              gap,
              TextField(
                controller: _tags,
                decoration: InputDecoration(labelText: l.tags),
              ),
            ],
            if (f.chips.isNotEmpty)
              ExpansionTile(
                key: const ValueKey('ocr.chips'),
                initiallyExpanded: _incomplete,
                tilePadding: EdgeInsets.zero,
                shape: const Border(),
                collapsedShape: const Border(),
                childrenPadding: const EdgeInsets.only(bottom: 8),
                expandedAlignment: AlignmentDirectional.centerStart,
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                title: Text(l.ocrChipsTitle, style: theme.textTheme.titleSmall),
                children: [
                  Text(l.ocrTapChip, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 8),
                  OcrChips(chips: f.chips, onUse: _use),
                ],
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _canSave ? _save : null,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l.save),
            ),
            OcrWhatWasRead(passes: widget.passes),
          ],
        ),
      ),
    );
  }
}

/// Asked after a login from the clipboard was saved: the screenshot or text
/// there still shows the password, and other apps can read it. Clear is the
/// default action. It empties the clipboard only; copies a clipboard history
/// (Windows + V, keyboard apps) already kept stay there, as the dialog says.
Future<void> offerClearClipboard(
  BuildContext context, {
  required bool screenshot,
}) async {
  final l = context.l10n;
  final bridge = context.services.bridge;
  final messenger = ScaffoldMessenger.of(context);
  final clear = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.content_paste_off),
      title: Text(screenshot ? l.clearScreenshotTitle : l.clearTextTitle),
      content: Text(l.clearClipboardBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: Text(l.keep),
        ),
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.pop(c, true),
          child: Text(l.clear),
        ),
      ],
    ),
  );
  if (clear ?? false) {
    await bridge.clearClipboard();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l.clipboardCleared)));
  }
}
