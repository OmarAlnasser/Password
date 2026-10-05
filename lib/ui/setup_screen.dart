import 'package:flutter/material.dart';

import '../services/password_generator.dart';
import '../services/sync/sync_service.dart';
import 'app_scope.dart';
import 'sign_in_screen.dart';
import 'widgets/secret_text.dart';
import 'widgets/strength_bar.dart';

/// First run: create a vault, then show the recovery key once.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _pw = TextEditingController();
  final _confirm = TextEditingController();
  StrengthResult _strength = const StrengthResult(0, '', null);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pw.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final l = context.l10n;
    if (_pw.text != _confirm.text) {
      setState(() => _error = l.passwordsDontMatch);
      return;
    }
    if (_strength.score < 3) {
      setState(() => _error = l.passwordTooWeak);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final services = context.services;
    try {
      final result = await services.session.createVault(_pw.text);
      // Kept (hashed, inside the encrypted DB) so sync can register it later.
      await SyncService.storeRecoveryAuthHash(
        services.session,
        result.recoveryAuthSecret,
      );
      _pw.clear();
      _confirm.clear();
      if (!mounted) return;
      // The session is already unlocked; block navigation until the user has
      // confirmed the recovery key.
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) =>
              RecoveryKeyScreen(recoveryKey: result.recoveryKeyText),
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
    return Scaffold(
      appBar: AppBar(title: Text(l.createVault)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.lock_outline, size: 64),
              const SizedBox(height: 16),
              Text(l.masterPasswordHint),
              const SizedBox(height: 24),
              TextField(
                controller: _pw,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                enableIMEPersonalizedLearning: false,
                decoration: InputDecoration(labelText: l.masterPassword),
                onChanged: (v) => setState(
                  () => _strength = context.services.strength.evaluate(v),
                ),
              ),
              const SizedBox(height: 8),
              StrengthBar(result: _strength),
              const SizedBox(height: 16),
              TextField(
                controller: _confirm,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                enableIMEPersonalizedLearning: false,
                decoration: InputDecoration(labelText: l.confirmPassword),
                onSubmitted: (_) => _create(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _create,
                child: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l.create),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SignInScreen(),
                        ),
                      ),
                child: Text(l.signInExisting),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows the recovery key once and requires the user to type back its last
/// group before continuing.
class RecoveryKeyScreen extends StatefulWidget {
  const RecoveryKeyScreen({super.key, required this.recoveryKey});

  final String recoveryKey;

  @override
  State<RecoveryKeyScreen> createState() => _RecoveryKeyScreenState();
}

class _RecoveryKeyScreenState extends State<RecoveryKeyScreen> {
  final _confirm = TextEditingController();

  String get _lastGroup => widget.recoveryKey.split('-').last;

  static String _norm(String s) => s
      .trim()
      .toUpperCase()
      .replaceAll('O', '0')
      .replaceAll(RegExp('[IL]'), '1');

  bool get _ok => _norm(_confirm.text) == _norm(_lastGroup);

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.recoveryKeyTitle),
          automaticallyImplyLeading: false,
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(l.recoveryKeyExplain),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SecretText(
                  widget.recoveryKey.replaceAll('-', ' '),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                icon: const Icon(Icons.copy),
                label: Text(l.copy),
                onPressed: () =>
                    context.services.clipboard.copySecret(widget.recoveryKey),
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _confirm,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: l.recoveryKeyConfirm('…')),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _ok
                  ? () {
                      context.services.clipboard.clearNow();
                      Navigator.of(context).pop();
                    }
                  : null,
              child: Text(l.iSavedIt),
            ),
          ],
        ),
      ),
    );
  }
}
