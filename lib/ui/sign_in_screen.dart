import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../brand.dart';
import 'app_scope.dart';
import 'theme/tokens.dart';
import 'theme/typography.dart';
import 'widgets/brand_mark.dart';
import 'widgets/glass_bar.dart';
import 'widgets/primary_button.dart';
import 'widgets/pulse_dot.dart';
import 'widgets/reveal.dart';
import 'widgets/section_header.dart';

/// Sign in to a vault that already exists on the server (new device), or
/// enable sync for the local vault ([enableForLocal]).
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, this.enableForLocal = false});

  final bool enableForLocal;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _pw = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final s = context.services;
    final sync = s.sync;
    final l = context.l10n;
    if (sync == null) {
      setState(() => _error = l.syncFailed);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.enableForLocal) {
        await sync.enableSync(_email.text, _pw.text);
      } else {
        await sync.signInExisting(_email.text, _pw.text);
      }
      _pw.clear();
      await s.settings.update((x) => x.syncEmail = _email.text.trim());
      if (mounted) Navigator.of(context).pop();
    } on Object {
      // One generic message: do not reveal whether the email exists or
      // which step failed.
      if (mounted) setState(() => _error = l.syncFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final title = widget.enableForLocal ? l.enableSync : l.signInExisting;
    final label = widget.enableForLocal ? l.enableSync : l.unlock;
    return AuthPage(
      appBar: const GlassBar(),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AuthIconTile(Icons.cloud_sync_rounded),
            const SizedBox(height: 20),
            SectionHeader(title: title, size: SectionHeaderSize.screen),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthField(
              controller: _email,
              label: l.email,
              kind: AuthFieldKind.email,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            AuthField(
              controller: _pw,
              label: l.masterPassword,
              invalid: _error != null,
              onSubmitted: (_) => _busy ? null : _go(),
            ),
            AuthNoticeSlot(_error),
          ],
        ),
        PrimaryButton(
          expanded: true,
          onPressed: _busy ? null : _go,
          child: _busy ? AuthSpinner(label: label) : Text(label),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Building blocks of the first-impression screens.
//
// The unlock, setup, recovery-key, recovery-reset and sign-in screens share
// one frame, one kind of field and a few small pieces. They live here, at the
// leaf of those screens' imports, so no import cycle is needed.
// -----------------------------------------------------------------------------

/// The frame of a first-impression screen: a transparent [Scaffold] (the
/// app-wide background and its violet glow show through), safe areas, a
/// column of at most [maxWidth] that is centred across the window and scrolls
/// when the keyboard or a big text size needs the room.
///
/// The column hangs from the top and grows downwards, so a strength bar or an
/// error message that appears never moves what is above it. It starts
/// [topShare] of the room the window has beyond [contentHeight] (a typical
/// height of the column) from the top: near the optical centre in a tall
/// window, at the top in a short one.
///
/// Each of [children] fades in and rises in turn (`Reveal`), unless the
/// system asks to reduce motion. [spacing] separates them.
class AuthPage extends StatelessWidget {
  const AuthPage({
    super.key,
    required this.children,
    this.appBar,
    this.maxWidth = AppLayout.narrow,
    this.spacing = 24,
    this.contentHeight = 600,
    this.topShare = 0.3,
  });

  final List<Widget> children;
  final PreferredSizeWidget? appBar;

  /// 480 for forms, 420 for the lock screen.
  final double maxWidth;
  final double spacing;

  /// About how tall the column is at normal text size.
  final double contentHeight;

  /// 0 hangs the column from the top, 0.5 centres it.
  final double topShare;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final side = AppSpace.gutterOf(context) + 4;
    const vertical = 24.0;
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: spacing),
          Reveal(index: i, child: children[i]),
        ],
      ],
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (t.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        appBar: appBar,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                side,
                vertical +
                    ((box.maxHeight - contentHeight - 2 * vertical) * topShare)
                        .clamp(0.0, 200.0),
                side,
                vertical,
              ),
              child: Align(
                alignment: AlignmentDirectional.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: column,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The lock screen's head: the brand tile with a soft violet glow, the app
/// name from `lib/brand.dart` and the tagline in a status pill.
class AuthHero extends StatelessWidget {
  const AuthHero({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final locale = Localizations.maybeLocaleOf(context);
    final name = appNameFor(locale);
    // The wordmark is Outfit in every language; a name written in Arabic
    // script keeps the Arabic scale (and its taller lines).
    final display = Theme.of(context).textTheme.displayLarge!;
    final nameStyle = RegExp(r'[\u0600-\u06FF]').hasMatch(name)
        ? display
        : display.copyWith(
            fontFamily: AppFonts.en,
            fontFamilyFallback: const [AppFonts.ar],
            fontSize: 40,
            letterSpacing: -1,
            height: 1.1,
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: SizedBox.square(
            dimension: 72,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // A wide halo behind the tile; it takes no layout space.
                OverflowBox(
                  maxWidth: 280,
                  maxHeight: 280,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [
                          t.glow.withValues(alpha: t.isDark ? 0.55 : 0.32),
                          t.glow.withValues(alpha: 0),
                        ],
                        radius: 0.5,
                      ),
                    ),
                    child: const SizedBox.square(dimension: 280),
                  ),
                ),
                const BrandMark(size: 72, glow: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Semantics(
          header: true,
          child: Text(name, textAlign: TextAlign.center, style: nameStyle),
        ),
        const SizedBox(height: 12),
        StatusPill(label: appTaglineFor(locale)),
      ],
    );
  }
}

/// A rounded tile with the brand gradient at low opacity, a lavender outline
/// icon and a soft glow: the "hero icon" of a screen or dialog. [danger]
/// turns it red for destructive confirmations. Decorative.
class AuthIconTile extends StatelessWidget {
  const AuthIconTile(
    this.icon, {
    super.key,
    this.size = 56,
    this.danger = false,
  });

  final IconData icon;
  final double size;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tint = danger ? t.error : t.accent2;
    final halo = danger ? t.error.withValues(alpha: 0.16) : t.glow;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            OverflowBox(
              maxWidth: size * 3,
              maxHeight: size * 3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [halo, halo.withValues(alpha: 0)],
                    radius: 0.5,
                  ),
                ),
                child: SizedBox.square(dimension: size * 3),
              ),
            ),
            Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: danger
                    ? null
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          t.strong.withValues(alpha: 0.2),
                          t.brandEnd.withValues(alpha: 0.14),
                        ],
                      ),
                color: danger ? t.errorContainer : null,
                borderRadius: BorderRadius.circular(size * 0.3),
                border: Border.all(
                  color: danger ? t.error.withValues(alpha: 0.5) : t.line2,
                ),
              ),
              child: Icon(icon, size: size * 0.46, color: tint),
            ),
          ],
        ),
      ),
    );
  }
}

/// How an [AuthNotice] reads.
enum AuthTone {
  /// A failed attempt: red, announced to screen readers.
  error,

  /// A thing to take seriously (the recovery key is shown once): amber.
  warn,

  /// Calm information: violet.
  info,
}

/// A panel with an icon and a sentence (a form error, the recovery-key
/// warning, the "this password cannot be reset" note). The icon and the
/// words carry the meaning, so colour is never the only signal.
class AuthNotice extends StatelessWidget {
  const AuthNotice(
    this.message, {
    super.key,
    this.tone = AuthTone.info,
    this.icon,
    this.showIcon = true,
    this.live = false,
  });

  final String message;
  final AuthTone tone;

  /// Replaces the icon of the [tone].
  final IconData? icon;
  final bool showIcon;

  /// Announce the message when it appears (errors).
  final bool live;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final (fill, edge, iconColor, text, glyph) = switch (tone) {
      AuthTone.error => (
        t.errorContainer,
        t.error.withValues(alpha: 0.4),
        t.error,
        t.onErrorContainer,
        Icons.error_outline_rounded,
      ),
      AuthTone.warn => (
        t.warnContainer,
        t.warn.withValues(alpha: 0.4),
        t.warn,
        t.ink,
        Icons.warning_amber_rounded,
      ),
      AuthTone.info => (
        t.tint,
        t.selectedBorder.withValues(alpha: 0.7),
        t.accent2,
        t.soft,
        Icons.shield_outlined,
      ),
    };
    return Semantics(
      container: true,
      liveRegion: live,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 16, 12),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: AppRadius.controlAll,
          border: Border.all(color: edge),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showIcon) ...[
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: ExcludeSemantics(
                  child: Icon(icon ?? glyph, size: 22, color: iconColor),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(message, style: tt.bodyMedium!.copyWith(color: text)),
            ),
          ],
        ),
      ),
    );
  }
}

/// A place under a field for an error [message]: empty (and no height) while
/// it is null, otherwise an [AuthNotice] that slides open.
class AuthNoticeSlot extends StatelessWidget {
  const AuthNoticeSlot(this.message, {super.key, this.tone = AuthTone.error});

  final String? message;
  final AuthTone tone;

  @override
  Widget build(BuildContext context) {
    final text = message;
    return AnimatedSize(
      duration: context.motion(AppMotion.fast),
      curve: AppMotion.ease,
      alignment: Alignment.topCenter,
      child: text == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 12),
              child: AuthNotice(text, tone: tone, live: true),
            ),
    );
  }
}

/// The 20 px progress ring inside a busy primary button. [label] names the
/// button for a screen reader while it shows no text.
class AuthSpinner extends StatelessWidget {
  const AuthSpinner({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: context.tokens.onStrong,
        ),
      ),
    );
  }
}

/// What an [AuthField] holds.
enum AuthFieldKind {
  /// A master password: masked, with a reveal toggle. Always left-to-right.
  password,

  /// A recovery key: plain monospace capitals, left-to-right.
  recoveryKey,

  /// An email address: left-to-right, in the normal font.
  email,
}

/// The big filled text field of the first-impression screens.
///
/// * Latin-only content ([AuthFieldKind]) is always laid out left-to-right,
///   and sits at the start edge of the layout (right in Arabic).
/// * Secrets use the bundled monospace font; a password is masked and has an
///   eye button (48 dp, with a tooltip) that unmasks it, and masks it again
///   after 15 s without typing, or when the field goes away.
/// * [invalid] draws the red error border; the words belong in an
///   [AuthNoticeSlot] below the field.
class AuthField extends StatefulWidget {
  const AuthField({
    super.key,
    required this.controller,
    required this.label,
    this.kind = AuthFieldKind.password,
    this.autofocus = false,
    this.invalid = false,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final AuthFieldKind kind;
  final bool autofocus;
  final bool invalid;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;

  /// Shown at the end of a field that has no reveal toggle (a check mark).
  final Widget? suffix;

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  static const _remaskAfter = Duration(seconds: 15);

  bool _shown = false;
  Timer? _remask;

  bool get _isPassword => widget.kind == AuthFieldKind.password;

  @override
  void didUpdateWidget(AuthField old) {
    super.didUpdateWidget(old);
    if (old.kind != widget.kind) _hide();
  }

  @override
  void dispose() {
    _remask?.cancel();
    super.dispose();
  }

  void _hide() {
    _remask?.cancel();
    _remask = null;
    _shown = false;
  }

  void _toggle() {
    setState(() {
      if (_shown) {
        _hide();
      } else {
        _shown = true;
        _armRemask();
      }
    });
  }

  void _armRemask() {
    _remask?.cancel();
    _remask = Timer(_remaskAfter, () {
      if (mounted) setState(_hide);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final theme = Theme.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final kind = widget.kind;
    final base = theme.textTheme.bodyLarge!.copyWith(color: t.ink);
    final TextStyle style = kind == AuthFieldKind.email
        ? base.copyWith(height: 1.4, fontSize: 16)
        : AppText.asSecret(base)
              .copyWith(fontSize: 18, letterSpacing: 0.8, height: 1.4);
    final icon = switch (kind) {
      AuthFieldKind.password => Icons.lock_outline_rounded,
      AuthFieldKind.recoveryKey => Icons.key_rounded,
      AuthFieldKind.email => Icons.mail_outline_rounded,
    };
    Widget? suffix = widget.suffix;
    if (_isPassword) {
      suffix = IconButton(
        tooltip: _shown ? l.hide : l.show,
        isSelected: _shown,
        icon: Icon(
          _shown ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        ),
        selectedIcon: Icon(Icons.visibility_off_outlined, color: t.accent2),
        onPressed: _toggle,
      );
    }
    return TextField(
      controller: widget.controller,
      autofocus: widget.autofocus,
      obscureText: _isPassword && !_shown,
      autocorrect: false,
      enableSuggestions: kind == AuthFieldKind.email,
      enableIMEPersonalizedLearning: kind == AuthFieldKind.email,
      keyboardType: kind == AuthFieldKind.email
          ? TextInputType.emailAddress
          : null,
      textCapitalization: kind == AuthFieldKind.recoveryKey
          ? TextCapitalization.characters
          : TextCapitalization.none,
      textInputAction: widget.textInputAction,
      textDirection: TextDirection.ltr,
      textAlign: rtl ? TextAlign.right : TextAlign.left,
      style: style,
      onChanged: (v) {
        if (_shown) _armRemask();
        widget.onChanged?.call(v);
      },
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: Icon(icon),
        suffixIcon: suffix,
        // A zero-size error widget turns the border red without reserving
        // a line of text under the field.
        error: widget.invalid ? const SizedBox.shrink() : null,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
      ),
    );
  }
}
