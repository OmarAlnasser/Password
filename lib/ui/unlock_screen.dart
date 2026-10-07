import 'dart:async';

import 'package:flutter/material.dart';

import '../core/crypto/crypto.dart';
import '../services/ios_autofill_snapshot.dart';
import '../services/unlock_throttle.dart';
import 'app_scope.dart';
import 'sign_in_screen.dart';
import 'theme/tokens.dart';
import 'widgets/primary_button.dart';

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
    } on UnlockThrottledException {
      // The countdown pill under the field shows the wait, second by second.
      setState(() => _error = null);
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
    final choice = await showDialog<_Forgot>(
      context: context,
      builder: (_) => const _ForgotDialog(),
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
    return AuthPage(
      maxWidth: 420,
      spacing: 32,
      contentHeight: 470,
      topShare: 0.55,
      children: [
        const AuthHero(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthField(
              controller: _pw,
              autofocus: true,
              kind: _recoveryMode
                  ? AuthFieldKind.recoveryKey
                  : AuthFieldKind.password,
              label: _recoveryMode ? l.recoveryKey : l.masterPassword,
              invalid: _error != null,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => throttled || _busy ? null : _unlock(),
            ),
            AuthNoticeSlot(_error),
            if (throttled) ...[
              const SizedBox(height: 16),
              Center(
                child: _CountdownPill(l.tryAgainIn(remaining.inSeconds + 1)),
              ),
            ],
            const SizedBox(height: 20),
            PrimaryButton(
              expanded: true,
              onPressed: _busy || throttled ? null : _unlock,
              child: _busy ? AuthSpinner(label: l.unlock) : Text(l.unlock),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_bioAvailable && !_recoveryMode) ...[
              OutlinedButton.icon(
                icon: const Icon(Icons.fingerprint_rounded),
                label: Text(l.unlockWithBiometrics),
                onPressed: _busy ? null : _unlockBiometric,
              ),
              const SizedBox(height: 8),
            ],
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              children: [
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
          ],
        ),
      ],
    );
  }
}

/// "Too many attempts. Try again in 12s" as an amber pill; the screen
/// rebuilds every second, so the number counts down.
class _CountdownPill extends StatelessWidget {
  const _CountdownPill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 16, 6),
      decoration: ShapeDecoration(
        color: t.warnContainer,
        // A capsule on one line, a rounded panel when a big text size or a
        // long translation wraps it.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: t.warn.withValues(alpha: 0.45)),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Icon(Icons.timer_outlined, size: 18, color: t.warn),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color: t.warn,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Forgot your master password?": nobody can recover it, so the choice is
/// the recovery key or starting over (shown as a red, separate option).
class _ForgotDialog extends StatelessWidget {
  const _ForgotDialog();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    return AlertDialog(
      clipBehavior: Clip.antiAlias,
      constraints: const BoxConstraints(maxWidth: 440),
      title: _DialogTitle(
        icon: Icons.lock_reset_rounded,
        text: l.forgotPasswordTitle,
      ),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.forgotPasswordBody),
          const SizedBox(height: 16),
          _ChoiceTile(
            icon: Icons.key_rounded,
            title: l.useRecoveryKey,
            subtitle: l.useRecoveryKeyExplain,
            onTap: () => Navigator.pop(context, _Forgot.recoveryKey),
          ),
          const SizedBox(height: 10),
          _ChoiceTile(
            icon: Icons.delete_forever_rounded,
            title: l.resetVault,
            subtitle: l.resetVaultExplain,
            danger: true,
            onTap: () => Navigator.pop(context, _Forgot.reset),
          ),
        ],
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: t.soft),
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
      ],
    );
  }
}

/// A dialog's title: the hero icon tile (red for [danger]) beside the words,
/// so the dialog stays short enough for a small window.
class _DialogTitle extends StatelessWidget {
  const _DialogTitle({
    required this.icon,
    required this.text,
    this.danger = false,
  });

  final IconData icon;
  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AuthIconTile(icon, size: 44, danger: danger),
        const SizedBox(width: 14),
        Expanded(child: Text(text)),
      ],
    );
  }
}

/// One option of the forgot-password dialog: an icon tile, a title and a
/// sentence, in a bordered row at least 64 dp tall. [danger] gives it the red
/// treatment of an irreversible action.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final tint = danger ? t.error : t.accent2;
    final radius = BorderRadius.circular(AppRadius.card);
    return Semantics(
      button: true,
      child: Material(
        color: danger ? t.errorContainer.withValues(alpha: 0.55) : t.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: danger ? t.error.withValues(alpha: 0.45) : t.line2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 8, 10),
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: 0.14),
                        borderRadius: AppRadius.controlAll,
                      ),
                      child: Icon(icon, size: 22, color: tint),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: tt.titleSmall!.copyWith(
                            color: danger ? t.error : t.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(subtitle, style: tt.bodySmall),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  ExcludeSemantics(
                    child: Icon(Icons.chevron_right_rounded, color: t.muted),
                  ),
                ],
              ),
            ),
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
    final confirmed = {
      l.resetConfirmWord.toUpperCase(),
      'DELETE',
    }.contains(_word.text.trim().toUpperCase());
    return AlertDialog(
      clipBehavior: Clip.antiAlias,
      constraints: const BoxConstraints(maxWidth: 440),
      title: _DialogTitle(
        icon: Icons.warning_amber_rounded,
        text: l.resetVaultTitle,
        danger: true,
      ),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthNotice(l.resetVaultBody, tone: AuthTone.error, showIcon: false),
          const SizedBox(height: 20),
          TextField(
            controller: _word,
            autocorrect: false,
            enableSuggestions: false,
            // No icon in front: the label is long and must not be cut off.
            decoration: InputDecoration(
              labelText: l.resetTypeToConfirm(l.resetConfirmWord),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actionsOverflowButtonSpacing: 8,
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.cancel),
        ),
        PrimaryButton(
          destructive: true,
          onPressed: confirmed ? () => Navigator.pop(context, true) : null,
          child: Text(l.eraseVault),
        ),
      ],
    );
  }
}
