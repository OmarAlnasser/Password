import 'package:flutter/material.dart';

import '../services/password_generator.dart';
import '../services/sync/sync_service.dart';
import 'app_scope.dart';
import 'setup_screen.dart';
import 'widgets/strength_bar.dart';

/// Forced after a recovery-key unlock: choose a new master password; the
/// recovery key is rotated and the new one shown.
class RecoveryResetScreen extends StatefulWidget {
  const RecoveryResetScreen({super.key});

  @override
  State<RecoveryResetScreen> createState() => _RecoveryResetScreenState();
}

class _RecoveryResetScreenState extends State<RecoveryResetScreen> {
  final _pw = TextEditingController();
  final _confirm = TextEditingController();
  StrengthResult _strength = const StrengthResult(0, '', null);
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pw.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l = context.l10n;
    if (_pw.text != _confirm.text) {
      setState(() => _error = l.passwordsDontMatch);
      return;
    }
    if (_strength.score < 3) {
      setState(() => _error = l.passwordTooWeak);
      return;
    }
    setState(() => _busy = true);
    final s = context.services;
    try {
      final r = await s.session.setPasswordAfterRecovery(_pw.text);
      await SyncService.storeRecoveryAuthHash(s.session, r.recoveryAuth);
      await s.sync?.onPasswordReset(
        newAuthSecret: r.auth,
        newRecoveryAuth: r.recoveryAuth,
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => RecoveryKeyScreen(recoveryKey: r.recoveryText),
        ),
      );
    } on Object {
      if (mounted) setState(() => _error = l.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.newPassword),
          automaticallyImplyLeading: false,
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextField(
              controller: _pw,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(labelText: l.newPassword),
              onChanged: (v) => setState(
                () => _strength = context.services.strength.evaluate(v),
              ),
            ),
            const SizedBox(height: 8),
            StrengthBar(result: _strength),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: l.confirmPassword,
                errorText: _error,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(l.save),
            ),
          ],
        ),
      ),
    );
  }
}
