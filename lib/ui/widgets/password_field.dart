import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'reveal_controller.dart';

/// A form field for a stored or scanned password: masked until the eye is
/// pressed, left-to-right monospace, and masked again after 15 s without
/// interaction or when the field goes away.
///
/// It is a real obscured [TextField], not a drawing of one: the keyboard,
/// selection, paste and IME behave as in any password field, so editing works
/// while the value is masked. A screen reader hears the field as obscured,
/// and the eye's tooltip is the constant "Show" / "Hide".
///
/// Give it a [reveal] when something next to it (other readings of the
/// password, a preview) must follow the same eye; otherwise it keeps its own.
/// [actions] are extra buttons after the eye (the generator).
class PasswordField extends StatelessWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.reveal,
    this.actions = const [],
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;

  /// The shared reveal state; null: the field owns one.
  final RevealController? reveal;

  /// Buttons after the eye, inside the field.
  final List<Widget> actions;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final shared = reveal;
    if (shared == null) {
      return RevealBuilder(builder: (context, own) => _build(context, own));
    }
    return ListenableBuilder(
      listenable: shared,
      builder: (context, _) => _build(context, shared),
    );
  }

  Widget _build(BuildContext context, RevealController reveal) {
    final t = context.tokens;
    // Latin-only: always left-to-right, at the start edge of the layout
    // (the right in Arabic).
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return TextField(
      controller: controller,
      autofocus: autofocus,
      obscureText: !reveal.shown,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      textInputAction: textInputAction,
      textDirection: TextDirection.ltr,
      textAlign: rtl ? TextAlign.right : TextAlign.left,
      style: AppText.secret.copyWith(
        fontSize: 16,
        letterSpacing: 0.8,
        color: t.ink,
      ),
      onChanged: (v) {
        // Typing is interaction: keep it revealed for another 15 s.
        reveal.touch();
        onChanged?.call(v);
      },
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RevealButton(reveal: reveal),
            ...actions,
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}
