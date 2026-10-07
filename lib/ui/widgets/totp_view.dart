import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/crypto/crypto.dart';
import '../app_scope.dart';
import '../home_screen.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'secret_text.dart';

/// Parses a stored TOTP value (otpauth URI or bare Base32 secret).
Totp? parseTotp(String value) {
  final v = value.trim();
  if (v.isEmpty) return null;
  try {
    return v.toLowerCase().startsWith('otpauth://')
        ? Totp.fromUri(v)
        : Totp.fromBase32(v);
  } on VaultCryptoException {
    return null;
  }
}

/// The current one-time code with a countdown ring, a copy button and a
/// one-line label. Refreshes every second.
///
/// It is a row, not a card: put it inside a card of the detail screen, under
/// the other credentials. The code is a secret like the password: mono,
/// always left-to-right, never in a tooltip or a semantics label (the ring
/// announces only the seconds left).
class TotpView extends StatefulWidget {
  const TotpView({super.key, required this.totp});

  final Totp totp;

  @override
  State<TotpView> createState() => _TotpViewState();
}

class _TotpViewState extends State<TotpView> {
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final code = widget.totp.now();
    final left = widget.totp.secondsRemaining();
    final pretty = code.length == 6
        ? '${code.substring(0, 3)} ${code.substring(3)}'
        : code;
    // The last five seconds turn the ring and the numeral red: the code is
    // about to change, so do not start typing it.
    final urgent = left <= 5;
    final ringColor = urgent ? t.error : t.accent2;
    final secretStyle = AppText.secret.copyWith(
      fontSize: 26,
      height: 1.2,
      color: t.ink,
    );
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 4, 12),
      child: Row(
        children: [
          Semantics(
            // Only the seconds: the code itself never goes into the label.
            label: l.seconds(left),
            child: ExcludeSemantics(
              child: _CountdownRing(
                fraction: left / widget.totp.period,
                color: ringColor,
                track: t.surface3,
                child: Text(
                  '$left',
                  textScaler: TextScaler.noScaling,
                  style: AppText.numeral.copyWith(
                    fontSize: 14,
                    height: 1,
                    color: urgent ? t.error : t.soft,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.oneTimeCode,
                  style: tt.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                SecretText(
                  pretty,
                  highlightAmbiguous: false,
                  style: secretStyle,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 20),
            tooltip: l.copy,
            onPressed: () => copySecretWithToast(context, code),
          ),
        ],
      ),
    );
  }
}

/// A 40 px ring that empties along the reading direction, with [child] in the
/// middle. Each second it eases to its new length instead of
/// jumping; with "reduce motion" on it does jump.
class _CountdownRing extends StatelessWidget {
  const _CountdownRing({
    required this.fraction,
    required this.color,
    required this.track,
    required this.child,
  });

  final double fraction;
  final Color color;
  final Color track;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return SizedBox.square(
      dimension: 40,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: fraction.clamp(0.0, 1.0)),
        duration: context.motion(AppMotion.card),
        curve: AppMotion.standard,
        builder: (context, value, child) => CustomPaint(
          painter: _RingPainter(
            fraction: value,
            color: color,
            track: track,
            mirrored: rtl,
          ),
          child: Center(child: child),
        ),
        child: child,
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.fraction,
    required this.color,
    required this.track,
    required this.mirrored,
  });

  final double fraction;
  final Color color;
  final Color track;
  final bool mirrored;

  static const double _stroke = 3.5;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(_stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (fraction <= 0) return;
    // From twelve o'clock, along the reading direction.
    final sweep = math.pi * 2 * fraction * (mirrored ? -1 : 1);
    canvas.drawArc(rect, -math.pi / 2, sweep, false, paint..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.track != track ||
      old.mirrored != mirrored;
}
