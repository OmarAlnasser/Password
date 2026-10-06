import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The portfolio's pulsing mint dot (`.dot` + `@keyframes pulse`, DESIGN
/// section 8.9): an 8 px dot with a 4 px ring that swells to 8 px and fades,
/// every 2.4 s.
///
/// It pulses [pulses] times after it appears (or after [active] turns on)
/// and then rests on its ring. A dot that pulses forever would keep the
/// engine drawing 60 frames a second for a status light, which drains the
/// battery of a password manager that sits open for hours, and it would make
/// `pumpAndSettle` in tests never settle. With "reduce motion" on it never
/// moves.
///
/// Decorative: the text next to it carries the meaning ("Synced 2 min ago"),
/// so it is excluded from semantics. Pass `tokens.muted` / `tokens.error`
/// and `active: false` for offline or error states.
class PulseDot extends StatefulWidget {
  const PulseDot({
    super.key,
    this.color,
    this.size = 8,
    this.active = true,
    this.pulses = 3,
  });

  /// Defaults to the mint `good` colour.
  final Color? color;
  final double size;

  /// False: a still dot without a ring (offline, error).
  final bool active;

  /// How many times it pulses before it rests; 0 for a still dot with ring.
  final int pulses;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppMotion.pulse,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(PulseDot old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active || old.pulses != widget.pulses) {
      _started = false;
      _sync();
    }
  }

  void _sync() {
    if (_started) return;
    _started = true;
    _c.value = 0;
    final still = MediaQuery.disableAnimationsOf(context);
    if (widget.active && widget.pulses > 0 && !still) {
      _c.repeat(count: widget.pulses);
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.tokens.good;
    final s = widget.size;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            // 0 -> 1 -> 0 over one pulse: ring 4 -> 8 px, alpha .13 -> 0.
            final p = _c.value < 0.5 ? _c.value * 2 : (1 - _c.value) * 2;
            return SizedBox.square(
              dimension: s + 16,
              child: Center(
                child: Container(
                  width: s,
                  height: s,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: widget.active
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.133 * (1 - p)),
                              spreadRadius: s * 0.5 * (1 + p),
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The portfolio's `.hero-kicker`: a pill (`surface` fill, `line2` border)
/// with a [PulseDot] and a short status text such as "Encrypted on this
/// device" or "Synced 2 min ago" (DESIGN section 8.9). The text carries the
/// meaning; the dot is decoration. For offline or error states pass a
/// different [color] and `active: false`.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.color,
    this.active = true,
    this.pulses = 3,
  });

  final String label;
  final Color? color;
  final bool active;
  final int pulses;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsetsDirectional.only(start: 8, end: 14),
      constraints: const BoxConstraints(minHeight: 36),
      decoration: ShapeDecoration(
        color: t.surface,
        shape: StadiumBorder(side: BorderSide(color: t.line2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PulseDot(color: color, active: active, pulses: pulses),
          const SizedBox(width: 2),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium!
                  .copyWith(color: t.soft),
            ),
          ),
        ],
      ),
    );
  }
}
