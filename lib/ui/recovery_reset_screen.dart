import 'package:flutter/material.dart';

import '../services/password_generator.dart';
import '../services/sync/sync_service.dart';
import 'app_scope.dart';
import 'setup_screen.dart';
import 'sign_in_screen.dart';
import 'theme/tokens.dart';
import 'widgets/primary_button.dart';
import 'widgets/section_header.dart';
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
      child: AuthPage(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AuthIconTile(Icons.lock_reset_rounded),
              const SizedBox(height: 20),
              SectionHeader(
                title: l.newPassword,
                size: SectionHeaderSize.screen,
              ),
            ],
          ),
          AuthNotice(l.masterPasswordHint),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthField(
                controller: _pw,
                label: l.newPassword,
                textInputAction: TextInputAction.next,
                onChanged: (v) => setState(
                  () => _strength = context.services.strength.evaluate(v),
                ),
              ),
              // Nothing to rate until something is typed.
              AnimatedSize(
                duration: context.motion(AppMotion.fast),
                curve: AppMotion.ease,
                alignment: Alignment.topCenter,
                child: _pw.text.isEmpty
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: StrengthBar(result: _strength),
                      ),
              ),
              const SizedBox(height: 16),
              AuthField(
                controller: _confirm,
                label: l.confirmPassword,
                invalid: _error != null,
                onSubmitted: (_) => _busy ? null : _submit(),
              ),
              AuthNoticeSlot(_error),
            ],
          ),
          PrimaryButton(
            expanded: true,
            onPressed: _busy ? null : _submit,
            child: _busy ? AuthSpinner(label: l.save) : Text(l.save),
          ),
        ],
      ),
    );
  }
}
