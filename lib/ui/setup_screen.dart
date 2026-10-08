import 'package:flutter/material.dart';

import '../services/password_generator.dart';
import '../services/sync/sync_service.dart';
import 'app_scope.dart';
import 'sign_in_screen.dart';
import 'theme/tokens.dart';
import 'widgets/brand_mark.dart';
import 'widgets/primary_button.dart';
import 'widgets/secret_text.dart';
import 'widgets/section_header.dart';
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
    final navigator = Navigator.of(context);
    try {
      final result = await services.session.createVault(_pw.text);
      _pw.clear();
      _confirm.clear();
      // createVault has just unlocked the session, so the next frame replaces
      // this screen with HomeScreen (HisnApp._home) and unmounts it.
      // Push the recovery key route now, before any further await, or it is
      // never shown. It blocks navigation until the user has confirmed it.
      final shown = navigator.push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) =>
              RecoveryKeyScreen(recoveryKey: result.recoveryKeyText),
        ),
      );
      // Kept (hashed, inside the encrypted DB) so sync can register it later.
      await SyncService.storeRecoveryAuthHash(
        services.session,
        result.recoveryAuthSecret,
      );
      await shown;
    } on Object {
      if (mounted) setState(() => _error = l.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AuthPage(
      contentHeight: 660,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BrandLockup(),
            const SizedBox(height: 28),
            SectionHeader(title: l.createVault, size: SectionHeaderSize.screen),
          ],
        ),
        AuthNotice(l.masterPasswordHint),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthField(
              controller: _pw,
              label: l.masterPassword,
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
              onSubmitted: (_) => _busy ? null : _create(),
            ),
            AuthNoticeSlot(_error),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PrimaryButton(
              expanded: true,
              onPressed: _busy ? null : _create,
              child: _busy ? AuthSpinner(label: l.create) : Text(l.create),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.login_rounded),
              label: Text(l.signInExisting),
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SignInScreen(),
                      ),
                    ),
            ),
          ],
        ),
      ],
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

  Future<void> _copy() async {
    final s = context.services;
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    await s.clipboard.copySecret(widget.recoveryKey);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(l.copied(s.settings.clipboardClearSeconds))),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final groups = widget.recoveryKey.split('-');
    return PopScope(
      canPop: false,
      child: AuthPage(
        maxWidth: AppLayout.narrow + 40,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AuthIconTile(Icons.key_rounded),
              const SizedBox(height: 20),
              SectionHeader(
                title: l.recoveryKeyTitle,
                size: SectionHeaderSize.screen,
              ),
            ],
          ),
          AuthNotice(l.recoveryKeyExplain, tone: AuthTone.warn),
          _RecoveryKeyCard(groups: groups, onCopy: _copy),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The sentence is long: above the field it can wrap, in a
              // label it would be cut off.
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4, bottom: 10),
                child: Text(
                  l.recoveryKeyConfirm('…'),
                  style: Theme.of(context).textTheme.bodyMedium!
                      .copyWith(color: t.soft),
                ),
              ),
              AuthField(
                controller: _confirm,
                kind: AuthFieldKind.recoveryKey,
                label: l.recoveryKey,
                onChanged: (_) => setState(() {}),
                suffix: _ok
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: Icon(Icons.check_circle_rounded, color: t.good),
                      )
                    : null,
              ),
            ],
          ),
          PrimaryButton(
            expanded: true,
            icon: const Icon(Icons.check_rounded),
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
    );
  }
}

/// The recovery key in a bordered card, in groups of five characters (the
/// key's own grouping), left-to-right in the monospace font, each group
/// numbered. The last group, which the user types back to confirm, has a
/// violet outline. Wraps to fewer columns for a big text size.
class _RecoveryKeyCard extends StatelessWidget {
  const _RecoveryKeyCard({required this.groups, required this.onCopy});

  final List<String> groups;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        gradient: t.featuredGradient,
        borderRadius: BorderRadius.circular(AppRadius.dialog),
        border: Border.all(color: t.featuredBorder),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 12, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l.recoveryKey,
                  style: tt.labelMedium!.copyWith(
                    color: t.accent2,
                    letterSpacing: context.isArabic ? 0 : 0.3,
                  ),
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.copy_rounded),
                label: Text(l.copy),
                onPressed: onCopy,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Hugs the start edge of the layout (right in Arabic) ...
          Align(
            alignment: AlignmentDirectional.centerStart,
            // ... but the key is a code, not a sentence: always left-to-right,
            // so group 1 is at the left even in an Arabic layout.
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (var i = 0; i < groups.length; i++)
                    _KeyGroup(
                      number: i + 1,
                      group: groups[i],
                      emphasised: i == groups.length - 1,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyGroup extends StatelessWidget {
  const _KeyGroup({
    required this.number,
    required this.group,
    required this.emphasised,
  });

  final int number;
  final String group;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: emphasised ? t.selected : t.surface2.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: emphasised ? t.selectedBorder : t.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Text(
              '$number',
              style: tt.bodySmall!.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SecretText(group, highlightAmbiguous: false),
        ],
      ),
    );
  }
}
