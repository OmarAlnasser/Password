import 'dart:async';

import 'package:flutter/material.dart';

import '../core/crypto/crypto.dart';
import '../services/unlock_throttle.dart';
import 'app_scope.dart';

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
                onPressed: () => setState(() {
                  _recoveryMode = !_recoveryMode;
                  _pw.clear();
                  _error = null;
                }),
                child: Text(
                  _recoveryMode ? l.masterPassword : l.useRecoveryKey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
