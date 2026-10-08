import 'package:flutter/material.dart';

import '../../data/models/vault_entry.dart';
import '../../services/ocr/ocr_parser.dart';
import '../../services/ocr/ocr_scanner.dart';
import '../../services/vault_session.dart';
import '../app_scope.dart';
import '../theme/theme.dart';
import '../widgets/password_field.dart';
import '../widgets/primary_button.dart';
import '../widgets/reveal_controller.dart';
import '../widgets/secret_text.dart';
import 'ocr_widgets.dart';

/// Bottom sheet that saves a login read from the clipboard (a pasted
/// screenshot or text) in a few taps. From 600 px of width it is a centred
/// dialog instead (DESIGN section 8.11), with the same content.
///
/// Quick asks only for a name and shows the detected username and password
/// for checking; the password is masked until its eye is pressed, with the
/// other readings and the text that was read. Advanced adds where the login
/// is from, why it exists and tags. Switching keeps what was typed;
/// everything filled in is saved, except a detected link the user never saw:
/// it would also make the app fetch that site's icon.
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
    this.asDialog = false,
  });

  final OcrResult found;

  /// What each scan pass read, for "What was read". Empty for pasted text.
  final List<ScanPass> passes;

  /// Drawn as a floating dialog (all corners rounded, no drag handle, no
  /// keyboard padding: the dialog route already makes room for it) instead
  /// of a bottom sheet.
  final bool asDialog;

  /// Shows the sheet, or the dialog on a wide window. True when an entry was
  /// saved.
  static Future<bool> show(
    BuildContext context,
    OcrResult found, {
    List<ScanPass> passes = const [],
  }) async {
    if (MediaQuery.sizeOf(context).width >= AppLayout.compact) {
      return await showDialog<bool>(
            context: context,
            animationStyle: context.motionStyle,
            builder: (_) => Dialog(
              // The content paints its own surface and glow.
              backgroundColor: Colors.transparent,
              elevation: 0,
              shadowColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              shape: const RoundedRectangleBorder(
                borderRadius: AppRadius.dialogAll,
              ),
              clipBehavior: Clip.none,
              insetPadding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: AppLayout.dialog),
                child: QuickSaveSheet(
                  found: found,
                  passes: passes,
                  asDialog: true,
                ),
              ),
            ),
          ) ??
          false;
    }
    return _showSheet(context, found, passes);
  }

  static Future<bool> _showSheet(
    BuildContext context,
    OcrResult found,
    List<ScanPass> passes,
  ) async =>
      await showModalBottomSheet<bool>(
        context: context,
        sheetAnimationStyle: context.motionStyle,
        isScrollControlled: true,
        useSafeArea: true,
        // The sheet paints its own surface: the violet gradient, the border
        // and the glow around it (which must not be clipped away).
        backgroundColor: Colors.transparent,
        elevation: 0,
        showDragHandle: false,
        clipBehavior: Clip.none,
        constraints: const BoxConstraints(maxWidth: AppLayout.form),
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
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final f = widget.found;
    // Latin-only fields read left to right in Arabic too, but sit at the
    // start edge of the layout (DESIGN section 8.7).
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final latinAlign = rtl ? TextAlign.right : TextAlign.left;
    final mono = AppText.secret.copyWith(
      fontSize: 15,
      letterSpacing: 0.3,
      color: t.ink,
    );
    const gap = SizedBox(height: 14);
    final bottom = MediaQuery.paddingOf(context).bottom;

    final body = <Widget>[
      if (_incomplete && f.chips.isNotEmpty) ...[
        _PickHint(text: l.ocrPickHint),
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
        textAlign: latinAlign,
        style: mono,
        decoration: InputDecoration(labelText: l.username),
        onChanged: (_) => setState(() {}),
      ),
      OcrCandidates(
        values: f.emailCandidates,
        current: _user.text.trim(),
        onPick: (v) => setState(() => _user.text = v),
      ),
      gap,
      // Masked like every stored password. OCR output is checked character by
      // character with the eye, which also shows the readings below and a
      // preview with the look-alike characters marked; it hides again after
      // 15 s.
      RevealBuilder(
        builder: (context, reveal) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PasswordField(
              controller: _pw,
              label: l.password,
              reveal: reveal,
              onChanged: (_) => setState(() {}),
            ),
            OcrCandidates(
              values: f.passwordCandidates,
              current: _pw.text,
              obscure: !reveal.shown,
              onPick: (v) => setState(() => _pw.text = v),
            ),
            if (reveal.shown && _pw.text.isNotEmpty) ...[
              const SizedBox(height: 12),
              SecretBox(child: SecretText(_pw.text)),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.visibility_outlined,
                      size: 16,
                      color: t.muted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l.ocrAmbiguous, style: tt.bodySmall)),
                ],
              ),
            ],
          ],
        ),
      ),
      if (_advanced) ...[
        gap,
        TextField(
          controller: _url,
          autocorrect: false,
          keyboardType: TextInputType.url,
          textDirection: TextDirection.ltr,
          textAlign: latinAlign,
          style: mono,
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
      if (f.chips.isNotEmpty) ...[
        const SizedBox(height: 16),
        // Any piece of the text may be the password: masked until the eye
        // of this panel is pressed; folding the panel hides it again.
        RevealBuilder(
          builder: (context, reveal) => OcrFold(
            expandKey: const ValueKey('ocr.chips'),
            initiallyExpanded: _incomplete,
            icon: Icons.text_snippet_outlined,
            title: l.ocrChipsTitle,
            onExpansionChanged: (open) {
              if (!open) reveal.hide();
            },
            children: [
              Row(
                children: [
                  Expanded(child: Text(l.ocrTapChip, style: tt.bodySmall)),
                  RevealButton(reveal: reveal),
                ],
              ),
              const SizedBox(height: 10),
              OcrChips(chips: f.chips, obscure: !reveal.shown, onUse: _use),
            ],
          ),
        ),
      ],
      OcrWhatWasRead(passes: widget.passes),
    ];

    final radius = widget.asDialog ? AppRadius.dialogAll : AppRadius.sheetTop;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: t.dialogGradient,
        borderRadius: radius,
        border: Border.all(color: t.dialogBorder),
        boxShadow: [
          // The violet glow around the sheet's top edge (all round for the
          // dialog).
          BoxShadow(
            color: t.isDark ? t.strong.withValues(alpha: 0.38) : t.shadow,
            blurRadius: 46,
            spreadRadius: -6,
            offset: Offset(0, widget.asDialog ? 12 : -10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Padding(
          // Keep the fields above the on-screen keyboard (a dialog route
          // does that itself).
          padding: EdgeInsets.only(
            bottom: widget.asDialog
                ? 0
                : MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.asDialog)
                const SizedBox(height: 14)
              else
                const _Grabber(),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 6, 8, 0),
                child: Row(
                  children: [
                    const OcrIconTile(icon: Icons.key_rounded),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(l.saveLogin, style: tt.titleLarge),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: l.close,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: PillSegments<bool>(
                  selected: _advanced,
                  segments: [
                    PillSegment(
                      value: false,
                      icon: Icons.bolt_rounded,
                      label: l.quickMode,
                    ),
                    PillSegment(
                      value: true,
                      icon: Icons.tune_rounded,
                      label: l.advancedMode,
                    ),
                  ],
                  onChanged: (v) => setState(() {
                    _advanced = v;
                    _linkShown |= _advanced;
                  }),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: body,
                  ),
                ),
              ),
              // The main action stays in reach however long the form is.
              Container(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 14 + bottom),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: t.line)),
                ),
                child: PrimaryButton(
                  expanded: true,
                  icon: _saving ? null : const Icon(Icons.check_rounded),
                  onPressed: _canSave ? _save : null,
                  child: _saving
                      ? SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: t.onStrong,
                          ),
                        )
                      : Text(l.save),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The drag handle of the sheet (decoration only).
class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 8),
        child: Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: context.tokens.line2,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Not sure which text is the email or the password": shown when part of the
/// login was not found.
class _PickHint extends StatelessWidget {
  const _PickHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.selected,
        borderRadius: AppRadius.controlAll,
        border: Border.all(color: t.selectedBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.touch_app_outlined, size: 22, color: t.accent2),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium!
                  .copyWith(color: t.ink),
            ),
          ),
        ],
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
    animationStyle: context.motionStyle,
    builder: (c) => AlertDialog(
      // Centre: the dialog's icon slot is tight, which would stretch a tile
      // with a fixed size into a flat bar.
      icon: const Center(
        child: OcrIconTile(icon: Icons.content_paste_off_rounded, size: 56),
      ),
      title: Text(
        screenshot ? l.clearScreenshotTitle : l.clearTextTitle,
        textAlign: TextAlign.center,
      ),
      content: Text(l.clearClipboardBody, textAlign: TextAlign.center),
      actionsAlignment: MainAxisAlignment.center,
      actionsOverflowAlignment: OverflowBarAlignment.center,
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
