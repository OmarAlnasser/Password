import 'package:flutter/material.dart';

import '../data/models/vault_entry.dart';
import '../services/password_generator.dart';
import '../services/vault_session.dart';
import 'app_scope.dart';
import 'entry_detail_screen.dart' show EntryTitle;
import 'generator_screen.dart';
import 'theme/tokens.dart';
import 'theme/typography.dart';
import 'widgets/focus_ring.dart';
import 'widgets/glass_bar.dart';
import 'widgets/max_width_body.dart';
import 'widgets/password_field.dart';
import 'widgets/reveal.dart';
import 'widgets/reveal_controller.dart';
import 'widgets/secret_text.dart';
import 'widgets/strength_bar.dart';
import 'widgets/surface_card.dart';
import 'widgets/totp_view.dart';

/// Create / edit form. Also used by OCR import with pre-filled values.
class EntryEditScreen extends StatefulWidget {
  const EntryEditScreen({super.key, this.existing, this.prefill, this.onSaved});

  final VaultEntry? existing;

  /// Values detected by OCR (title/username/password/url/notes).
  final VaultEntry? prefill;

  final Future<void> Function(BuildContext context)? onSaved;

  @override
  State<EntryEditScreen> createState() => _EntryEditScreenState();
}

class _EntryEditScreenState extends State<EntryEditScreen> {
  late final TextEditingController _title,
      _user,
      _pw,
      _url,
      _notes,
      _tags,
      _totp;
  late bool _favorite;
  String? _totpError;

  @override
  void initState() {
    super.initState();
    final e = widget.existing ?? widget.prefill;
    _title = TextEditingController(text: e?.title ?? '');
    _user = TextEditingController(text: e?.username ?? '');
    _pw = TextEditingController(text: e?.password ?? '');
    _url = TextEditingController(text: e?.url ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _tags = TextEditingController(text: e?.tags.join(', ') ?? '');
    _totp = TextEditingController(text: e?.totpSecret ?? '');
    _favorite = e?.favorite ?? false;
  }

  @override
  void dispose() {
    for (final c in [_title, _user, _pw, _url, _notes, _tags, _totp]) {
      c
        ..clear()
        ..dispose();
    }
    super.dispose();
  }

  // The strength of the password, worked out again only when what it depends
  // on changed (typing in the notes must not run zxcvbn).
  String? _forPw, _forUser, _forTitle;
  StrengthResult? _strength;

  StrengthResult _strengthNow() {
    final pw = _pw.text;
    if (_strength == null ||
        pw != _forPw ||
        _user.text != _forUser ||
        _title.text != _forTitle) {
      _forPw = pw;
      _forUser = _user.text;
      _forTitle = _title.text;
      _strength = context.services.strength.evaluate(
        // zxcvbn gets slow on very long input; 128 characters say it all.
        pw.length > 128 ? pw.substring(0, 128) : pw,
        userInputs: [_user.text, _title.text],
      );
    }
    return _strength!;
  }

  Future<void> _save() async {
    if (_totp.text.trim().isNotEmpty && parseTotp(_totp.text) == null) {
      setState(() => _totpError = context.l10n.invalidTotp);
      return;
    }
    final tags = _tags.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList();
    final existing = widget.existing;
    final entry = existing == null
        ? VaultEntry(
            id: VaultSession.newId(),
            title: _title.text.trim(),
            username: _user.text.trim(),
            password: _pw.text,
            url: _url.text.trim(),
            notes: _notes.text,
            tags: tags,
            favorite: _favorite,
            totpSecret: _totp.text.trim(),
          )
        : existing.edit(
            title: _title.text.trim(),
            username: _user.text.trim(),
            password: _pw.text,
            url: _url.text.trim(),
            notes: _notes.text,
            tags: tags,
            favorite: _favorite,
            totpSecret: _totp.text.trim(),
          );
    final services = context.services;
    await services.session.saveEntry(entry);
    services.prefetchIcons();
    if (!mounted) return;
    final cb = widget.onSaved;
    if (cb != null) await cb(context);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final strength = _strengthNow();
    // Latin-only fields are always left-to-right, but sit at the start edge of
    // the layout: the right in Arabic (DESIGN section 8.7).
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final latinAlign = rtl ? TextAlign.right : TextAlign.left;
    final mono = AppText.secret.copyWith(
      fontSize: 15,
      letterSpacing: 0.3,
      color: t.ink,
    );
    InputDecoration deco(String label) => InputDecoration(labelText: label);
    // Free text (name, tags, notes) takes the direction of its first letter,
    // so a Latin note in an Arabic layout does not lose its full stop to the
    // wrong side; it still sits at the start edge of the layout.
    TextField freeText(
      TextEditingController c,
      String label, {
      int? minLines,
      int? maxLines = 1,
    }) {
      final own = EntryTitle.directionOf(c.text);
      final outer = Directionality.of(context);
      return TextField(
        controller: c,
        decoration: deco(label),
        minLines: minLines,
        maxLines: maxLines,
        textDirection: own,
        textAlign: own == null || own == outer ? TextAlign.start : latinAlign,
        onChanged: (_) => setState(() {}),
      );
    }

    const gap = SizedBox(height: 14);
    Widget card(List<Widget> children, {bool featured = false}) => SurfaceCard(
      featured: featured,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );

    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight + 8;
    final cards = <Widget>[
      if (widget.prefill != null)
        card(featured: true, [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: t.tint,
                  borderRadius: AppRadius.controlAll,
                ),
                child: Icon(Icons.info_outline, color: t.accent2, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.ocrReview, style: tt.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      l.ocrAmbiguous,
                      style: tt.bodySmall!.copyWith(color: t.soft),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ]),
      card([
        freeText(_title, l.title),
        gap,
        TextField(
          controller: _user,
          decoration: deco(l.username),
          autocorrect: false,
          keyboardType: TextInputType.emailAddress,
          // Left to right in Arabic too, so bidi does not reorder them.
          textDirection: TextDirection.ltr,
          textAlign: latinAlign,
          style: mono,
        ),
        gap,
        // Masked, also after an OCR scan: the eye shows it (with the
        // look-alike characters marked below) for 15 s at a time.
        RevealBuilder(
          builder: (context, reveal) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PasswordField(
                controller: _pw,
                label: l.password,
                reveal: reveal,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.casino_outlined),
                    tooltip: l.generator,
                    onPressed: () async {
                      final pw = await Navigator.of(context).push<String>(
                        MaterialPageRoute(
                          builder: (_) =>
                              const GeneratorScreen(returnResult: true),
                        ),
                      );
                      if (pw != null) setState(() => _pw.text = pw);
                    },
                  ),
                ],
                onChanged: (_) => setState(() {}),
              ),
              if (reveal.shown && _pw.text.isNotEmpty) ...[
                const SizedBox(height: 10),
                SecretBox(child: SecretText(_pw.text)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        StrengthBar(result: strength),
      ]),
      card([
        TextField(
          controller: _url,
          decoration: deco(l.url),
          keyboardType: TextInputType.url,
          autocorrect: false,
          textDirection: TextDirection.ltr,
          textAlign: latinAlign,
          style: mono,
        ),
        gap,
        TextField(
          controller: _totp,
          decoration: deco(l.totpSecret).copyWith(errorText: _totpError),
          autocorrect: false,
          enableSuggestions: false,
          textDirection: TextDirection.ltr,
          textAlign: latinAlign,
          style: mono,
        ),
      ]),
      card([
        freeText(_tags, l.tags),
        gap,
        freeText(_notes, l.notes, minLines: 3, maxLines: 8),
        const SizedBox(height: 6),
        FocusRing(
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: Icon(Icons.star_rounded, color: t.accent2),
            title: Text(l.favorite),
            value: _favorite,
            onChanged: (v) => setState(() => _favorite = v),
          ),
        ),
      ]),
    ];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassBar(
        title: Text(widget.existing == null ? l.addEntry : l.editEntry),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(64, 44),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              onPressed: _save,
              child: Text(l.save),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: MaxWidthBody.insets(
          context,
          maxWidth: AppLayout.form,
          base: EdgeInsets.only(
            top: topInset,
            bottom: MediaQuery.paddingOf(context).bottom + 32,
          ),
        ),
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            // The first appearance only; the password card is not wrapped
            // when it is the one the user is typing into.
            Reveal(index: i, child: cards[i]),
          ],
        ],
      ),
    );
  }
}
