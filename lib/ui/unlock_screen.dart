import 'dart:async';

import 'package:flutter/material.dart';

import '../core/crypto/crypto.dart';
import '../services/ios_autofill_snapshot.dart';
import '../services/unlock_throttle.dart';
import 'app_scope.dart';

enum _Forgot { recoveryKey, reset }

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _pw = TextEditingController();
  bool _busy = false;
  bool _recoveryMode = false;
  bool _bioAvailable = false;
  String? _error;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initBiometrics());
    _startTicker();
  }

  Future<void> _initBiometrics() async {
    final s = context.services;
    final bio = s.biometrics;
    if (bio == null || !s.settings.biometricsEnabled) return;
    if (await bio.isEnabled && await bio.isAvailable()) {
      if (!mounted) return;
      setState(() => _bioAvailable = true);
      await _unlockBiometric();
    }
  }

  void _startTicker() {
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final l = context.l10n;
    final session = context.services.session;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_recoveryMode) {
        await session.unlockWithRecoveryKey(_pw.text);
      } else {
        await session.unlockWithPassword(_pw.text);
      }
      _pw.clear();
    } on UnlockThrottledException catch (e) {
      setState(() => _error = l.tryAgainIn(e.remaining.inSeconds + 1));
    } on InvalidRecoveryKeyException {
      setState(() => _error = l.invalidRecoveryKey);
    } on WrongCredentialsException {
      setState(
        () => _error = _recoveryMode ? l.invalidRecoveryKey : l.wrongPassword,
      );
    } on Object {
      setState(() => _error = l.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlockBiometric() async {
    try {
      await context.services.session.unlockWithBiometrics();
    } on Object {
      if (mounted) setState(() => _error = context.l10n.error);
    }
  }

  void _setRecoveryMode(bool on) => setState(() {
    _recoveryMode = on;
    _pw.clear();
    _error = null;
  });

  /// Nobody can recover the master password. The way back is the recovery
  /// key; without it the only option is to start over.
  Future<void> _forgotPassword() async {
    final l = context.l10n;
    final choice = await showDialog<_Forgot>(
      context: context,
      builder: (c) {
        final error = Theme.of(c).colorScheme.error;
        return AlertDialog(
          icon: const Icon(Icons.lock_reset),
          title: Text(l.forgotPasswordTitle),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.forgotPasswordBody),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.key),
                title: Text(l.useRecoveryKey),
                subtitle: Text(l.useRecoveryKeyExplain),
                onTap: () => Navigator.pop(c, _Forgot.recoveryKey),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_forever, color: error),
                title: Text(l.resetVault, style: TextStyle(color: error)),
                subtitle: Text(l.resetVaultExplain),
                onTap: () => Navigator.pop(c, _Forgot.reset),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(l.cancel),
            ),
          ],
        );
      },
    );
    if (!mounted) return;
    switch (choice) {
      case _Forgot.recoveryKey:
        _setRecoveryMode(true);
      case _Forgot.reset:
        await _resetVault();
      case null:
        break;
    }
  }

  Future<void> _resetVault() async {
    final s = context.services;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _ResetVaultDialog(),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Also signs out of sync and resets the unlock throttle.
      await s.session.wipeLocalVault();
      // Copies that outlive the vault: the iOS AutoFill snapshot, and the
      // biometric and sync settings (wipeLocalVault already removed the
      // wrapped key).
      try {
        await IosAutofillSnapshot.clear();
      } on Object {
        // Nothing to clear without the native side.
      }
      await s.settings.update((x) {
        x.biometricsEnabled = false;
        x.syncEmail = null;
      });
    } on Object {
      if (mounted) setState(() => _error = context.l10n.error);
    } finally {
      // On success the app has already switched to the setup screen.
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final remaining = context.services.session.throttle.remaining;
    final throttled = remaining > Duration.zero;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.lock, size: 72),
              const SizedBox(height: 12),
              Text(
                l.appTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _pw,
                autofocus: true,
                obscureText: !_recoveryMode,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                textCapitalization: _recoveryMode
                    ? TextCapitalization.characters
                    : TextCapitalization.none,
                decoration: InputDecoration(
                  labelText: _recoveryMode ? l.recoveryKey : l.masterPassword,
                  errorText:
                      _error ??
                      (throttled
                          ? l.tryAgainIn(remaining.inSeconds + 1)
                          : null),
                ),
                onSubmitted: (_) => throttled || _busy ? null : _unlock(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy || throttled ? null : _unlock,
                child: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l.unlock),
              ),
              if (_bioAvailable && !_recoveryMode) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.fingerprint),
                  label: Text(l.unlockWithBiometrics),
                  onPressed: _busy ? null : _unlockBiometric,
                ),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => _setRecoveryMode(!_recoveryMode),
                child: Text(
                  _recoveryMode ? l.masterPassword : l.useRecoveryKey,
                ),
              ),
              if (!_recoveryMode)
                TextButton(
                  onPressed: _busy ? null : _forgotPassword,
                  child: Text(l.forgotPassword),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Erasing the vault cannot be undone, so the user types a word (DELETE,
/// حذف in Arabic) before the button works. DELETE works in every language,
/// for a keyboard without the localized layout.
class _ResetVaultDialog extends StatefulWidget {
  const _ResetVaultDialog();

  @override
  State<_ResetVaultDialog> createState() => _ResetVaultDialogState();
}

class _ResetVaultDialogState extends State<_ResetVaultDialog> {
  final _word = TextEditingController();

  @override
  void dispose() {
    _word.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final confirmed = {
      l.resetConfirmWord.toUpperCase(),
      'DELETE',
    }.contains(_word.text.trim().toUpperCase());
    return AlertDialog(
      icon: Icon(Icons.warning_amber, color: scheme.error),
      title: Text(l.resetVaultTitle),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.resetVaultBody),
          const SizedBox(height: 16),
          TextField(
            controller: _word,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: l.resetTypeToConfirm(l.resetConfirmWord),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: confirmed ? () => Navigator.pop(context, true) : null,
          child: Text(l.eraseVault),
        ),
      ],
    );
  }
}
