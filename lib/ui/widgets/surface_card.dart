import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The portfolio's card: a diagonal gradient (`#151023` to `#09080f` in dark),
/// a 1 px border and a 16 px radius. With [onTap] it becomes interactive and,
/// for a mouse pointer only, lifts [hoverLift] px, lights its border, casts a
/// big soft shadow and follows the pointer with a violet radial glow
/// (DESIGN section 8.4). Touch devices never see hover states, and nothing
/// depends on them.
///
/// * [selected] draws the selected-row look (tinted fill, lighter border)
///   instead of the gradient. Use it for the open row in the two-pane layout.
/// * [featured] uses the brighter featured gradient.
///
/// Do not nest cards in cards.
class SurfaceCard extends StatefulWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.featured = false,
    this.radius = AppRadius.card,
    this.hoverGlow = true,
    this.hoverLift = 4,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool featured;
  final double radius;

  /// The radial glow that follows a mouse pointer.
  final bool hoverGlow;

  /// Pixels the card rises on mouse hover. 0 turns the lift (and its shadow)
  /// off, which suits dense lists.
  final double hoverLift;

  /// When set, a screen reader reads this instead of the card's contents
  /// (for example "title, username", never the password).
  final String? semanticLabel;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<SurfaceCard> createState() => _SurfaceCardState();
}

class _SurfaceCardState extends State<SurfaceCard> {
  final _pointer = ValueNotifier<Offset>(Offset.zero);
  bool _hover = false;
  bool _focus = false;

  bool get _interactive => widget.onTap != null || widget.onLongPress != null;

  @override
  void dispose() {
    _pointer.dispose();
    super.dispose();
  }

  void _setHover(bool v) {
    if (_hover != v) setState(() => _hover = v);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final radius = BorderRadius.circular(widget.radius);
    final hot = _hover && _interactive;
    final lifted = hot && widget.hoverLift > 0 && !widget.selected;
    final borderColor = widget.selected
        ? t.selectedBorder
        : hot
        ? t.cardHoverBorder
        : widget.featured
        ? t.featuredBorder
        : t.cardBorder;

    Widget body = Padding(padding: widget.padding, child: widget.child);
    if (widget.hoverGlow && _interactive) {
      body = Stack(
        children: [
          body,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: hot ? 1 : 0,
                duration: context.motion(AppMotion.card),
                child: ValueListenableBuilder<Offset>(
                  valueListenable: _pointer,
                  builder: (_, p, _) => CustomPaint(
                    painter: _GlowPainter(center: p, color: t.cardHoverGlow),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    if (_interactive) {
      body = Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          borderRadius: radius,
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          onFocusChange: (f) => setState(() => _focus = f),
          // The focus ring below replaces the default fill.
          focusColor: Colors.transparent,
          child: body,
        ),
      );
    }

    Widget card = AnimatedContainer(
      duration: context.motion(AppMotion.card),
      curve: AppMotion.standard,
      transform: Matrix4.translationValues(
        0,
        lifted ? -widget.hoverLift : 0,
        0,
      ),
      decoration: BoxDecoration(
        gradient: widget.selected
            ? null
            : widget.featured
            ? t.featuredGradient
            : t.cardGradient,
        color: widget.selected ? t.selected : null,
        borderRadius: radius,
        border: Border.all(color: borderColor),
        boxShadow: lifted ? t.cardHoverShadow : null,
      ),
      foregroundDecoration: _focus
          ? BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: t.focusRing, width: 2),
            )
          : null,
      child: ClipRRect(borderRadius: radius, child: body),
    );

    if (_interactive) {
      card = MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHover(true),
        onExit: (_) => _setHover(false),
        onHover: (e) => _pointer.value = e.localPosition,
        child: card,
      );
    }
    if (widget.semanticLabel != null) {
      card = Semantics(
        container: true,
        label: widget.semanticLabel,
        button: _interactive,
        selected: widget.selected,
        excludeSemantics: true,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: card,
      );
    }
    return card;
  }
}

class _GlowPainter extends CustomPainter {
  const _GlowPainter({required this.center, required this.color});

  final Offset center;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // The portfolio's `radial-gradient(320px circle at var(--mx) var(--my))`;
    // before the first pointer move it sits at the top centre.
    final c = center == Offset.zero ? Offset(size.width / 2, 0) : center;
    final shader = RadialGradient(
      colors: [color, color.withValues(alpha: 0)],
      stops: const [0, 0.7],
    ).createShader(Rect.fromCircle(center: c, radius: 320));
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_GlowPainter old) =>
      old.center != center || old.color != color;
}
