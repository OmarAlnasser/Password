import 'package:flutter/material.dart';

import '../data/models/vault_entry.dart';
import '../services/vault_session.dart';
import 'app_scope.dart';
import 'generator_screen.dart';
import 'widgets/secret_text.dart';
import 'widgets/strength_bar.dart';
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
  bool _obscure = true;
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
    // OCR prefill: show the password so the user can verify each character.
    _obscure = widget.prefill == null;
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
    await context.services.session.saveEntry(entry);
    if (!mounted) return;
    final cb = widget.onSaved;
    if (cb != null) await cb(context);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final strength = context.services.strength.evaluate(
      _pw.text,
      userInputs: [_user.text, _title.text],
    );
    InputDecoration deco(String label) => InputDecoration(labelText: label);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? l.addEntry : l.editEntry),
        actions: [TextButton(onPressed: _save, child: Text(l.save))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.prefill != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(l.ocrReview),
                subtitle: Text(l.ocrAmbiguous),
              ),
            ),
          TextField(controller: _title, decoration: deco(l.title)),
          const SizedBox(height: 12),
          TextField(
            controller: _user,
            decoration: deco(l.username),
            autocorrect: false,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pw,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: deco(l.password).copyWith(
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
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
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (!_obscure && _pw.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            SecretText(_pw.text),
          ],
          const SizedBox(height: 8),
          StrengthBar(result: strength),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            decoration: deco(l.url),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _totp,
            decoration: deco(l.totpSecret).copyWith(errorText: _totpError),
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: 12),
          TextField(controller: _tags, decoration: deco(l.tags)),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            decoration: deco(l.notes),
            minLines: 3,
            maxLines: 8,
          ),
          SwitchListTile(
            title: Text(l.favorite),
            value: _favorite,
            onChanged: (v) => setState(() => _favorite = v),
          ),
        ],
      ),
    );
  }
}
