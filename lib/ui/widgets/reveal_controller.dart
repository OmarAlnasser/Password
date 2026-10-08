import 'dart:async';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../theme/tokens.dart';

/// How long a revealed secret stays revealed without interaction. The master
/// password field (`AuthField`) uses the same 15 s.
const secretRemaskAfter = Duration(seconds: 15);

/// Whether a secret is revealed right now, and the clock that hides it again.
///
/// Every secret on screen starts masked. [show] (or [toggle]) reveals it and
/// starts a timer; [touch] restarts the timer while the user is working with
/// it (typing, tapping); when the timer runs out, or [hide] is called, it is
/// masked again. [dispose] cancels the timer, so nothing outlives the widget
/// that owned the controller, and a new one always starts masked.
///
/// This holds only a flag and a timer: the secret itself is never in here.
class RevealController extends ChangeNotifier {
  RevealController({this.remaskAfter = secretRemaskAfter});

  /// Time without interaction after which the secret is masked again.
  final Duration remaskAfter;

  bool _shown = false;
  Timer? _timer;

  /// True while the secret is revealed.
  bool get shown => _shown;

  void show() {
    _arm();
    if (_shown) return;
    _shown = true;
    notifyListeners();
  }

  void hide() {
    _timer?.cancel();
    _timer = null;
    if (!_shown) return;
    _shown = false;
    notifyListeners();
  }

  void toggle() => _shown ? hide() : show();

  /// The user is still working with the secret: wait another [remaskAfter].
  /// Does nothing while it is masked.
  void touch() {
    if (_shown) _arm();
  }

  void _arm() {
    _timer?.cancel();
    _timer = Timer(remaskAfter, hide);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

/// Owns a [RevealController] for the widgets it builds, rebuilds them when the
/// secret is shown or hidden, restarts the 15 s clock on every pointer press
/// inside the subtree, and drops the controller (so the secret is masked
/// again) when it leaves the tree.
///
/// Use it to let several widgets share one eye: a password field, the other
/// readings under it and a preview of the value.
class RevealBuilder extends StatefulWidget {
  const RevealBuilder({
    super.key,
    required this.builder,
    this.remaskAfter = secretRemaskAfter,
  });

  final Widget Function(BuildContext context, RevealController reveal) builder;
  final Duration remaskAfter;

  @override
  State<RevealBuilder> createState() => _RevealBuilderState();
}

class _RevealBuilderState extends State<RevealBuilder> {
  late final RevealController _reveal = RevealController(
    remaskAfter: widget.remaskAfter,
  );

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _reveal.touch(),
      child: ListenableBuilder(
        listenable: _reveal,
        builder: (context, _) => widget.builder(context, _reveal),
      ),
    );
  }
}

/// The eye that shows or hides a secret: 48 x 48 dp, with a "Show" / "Hide"
/// tooltip (the words `AuthField` uses). The tooltip is the same constant
/// words whatever the secret is; it never carries the value.
class RevealButton extends StatelessWidget {
  const RevealButton({super.key, required this.reveal});

  final RevealController reveal;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    return ListenableBuilder(
      listenable: reveal,
      builder: (context, _) {
        final shown = reveal.shown;
        return IconButton(
          tooltip: shown ? l.hide : l.show,
          isSelected: shown,
          icon: const Icon(Icons.visibility_outlined),
          selectedIcon: Icon(Icons.visibility_off_outlined, color: t.accent2),
          // The theme makes icon buttons 48 x 48; say it here too, so a
          // theme change cannot shrink the tap target of the eye.
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: reveal.toggle,
        );
      },
    );
  }
}
