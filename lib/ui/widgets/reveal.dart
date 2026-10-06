import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// First-appearance animation (the portfolio's `.reveal`, DESIGN section 7):
/// the child fades in and rises 20 px over 700 ms on
/// `cubic-bezier(.2,.8,.2,1)`. Give the items of a list or grid their
/// [index] to stagger them by 70 ms; only the first 8 are delayed.
///
/// It plays once, when the widget is first built. Do not use it on the rows
/// of a long recycling list (they would replay while scrolling); pass
/// `enabled: index < 8`. With "reduce motion" on, or [enabled] false, the
/// child is shown as it is. Never wrap a secret that is being shown or hidden.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.index = 0,
    this.enabled = true,
  });

  final Widget child;
  final int index;
  final bool enabled;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  Animation<double>? _t;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!widget.enabled || MediaQuery.disableAnimationsOf(context)) return;
    final delay = AppMotion.stagger * widget.index.clamp(0, 7);
    final total = AppMotion.reveal + delay;
    final c = AnimationController(vsync: this, duration: total);
    _c = c;
    _t = CurvedAnimation(
      parent: c,
      curve: Interval(
        delay.inMilliseconds / total.inMilliseconds,
        1,
        curve: AppMotion.ease,
      ),
    );
    c.forward();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    if (t == null) return widget.child;
    return AnimatedBuilder(
      animation: t,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: t.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - t.value) * 20),
          child: child,
        ),
      ),
    );
  }
}
