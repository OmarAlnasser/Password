import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// An app bar that is transparent at rest and turns into blurred glass
/// (`glass` colour, blur 14, hairline underneath) once content scrolls under
/// it, like the portfolio's `.site-header.scrolled` (DESIGN section 8.1).
///
/// Use it as `Scaffold.appBar`. The blur only shows content that is really
/// behind the bar, so for the full effect set
/// `Scaffold(extendBodyBehindAppBar: true, ...)` and pad the list by
/// `MediaQuery.paddingOf(context).top + kToolbarHeight`. Without that it is
/// still a clean transparent bar that gains the hairline when scrolled.
/// Everything else (leading, back button, actions, tooltips) is a regular
/// [AppBar], so semantics and the automatic back button are unchanged.
///
/// [alwaysGlass] keeps the glass on (a pinned header of a desktop pane).
class GlassBar extends StatefulWidget implements PreferredSizeWidget {
  const GlassBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.bottom,
    this.automaticallyImplyLeading = true,
    this.centerTitle = false,
    this.toolbarHeight = kToolbarHeight,
    this.alwaysGlass = false,
  });

  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool automaticallyImplyLeading;
  final bool centerTitle;

  /// 56 on phones; 72 reads better on desktop (DESIGN section 4).
  final double toolbarHeight;
  final bool alwaysGlass;

  @override
  Size get preferredSize =>
      Size.fromHeight(toolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  State<GlassBar> createState() => _GlassBarState();
}

class _GlassBarState extends State<GlassBar> {
  ScrollNotificationObserverState? _observer;
  bool _scrolled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _observer?.removeListener(_onScroll);
    _observer = ScrollNotificationObserver.maybeOf(context)
      ?..addListener(_onScroll);
  }

  @override
  void dispose() {
    _observer?.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll(ScrollNotification n) {
    if (n is! ScrollUpdateNotification) return;
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return;
    final scrolled = n.metrics.extentBefore > 0.5;
    if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
  }

  @override
  Widget build(BuildContext context) {
    final glass = widget.alwaysGlass || _scrolled;
    return AppBar(
      title: widget.title,
      leading: widget.leading,
      actions: widget.actions,
      bottom: widget.bottom,
      automaticallyImplyLeading: widget.automaticallyImplyLeading,
      centerTitle: widget.centerTitle,
      toolbarHeight: widget.toolbarHeight,
      backgroundColor: Colors.transparent,
      scrolledUnderElevation: 0,
      flexibleSpace: _GlassLayer(active: glass),
    );
  }
}

class _GlassLayer extends StatelessWidget {
  const _GlassLayer({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: active ? 1 : 0),
      duration: context.motion(AppMotion.page),
      curve: AppMotion.standard,
      builder: (context, v, _) {
        final fill = DecoratedBox(
          decoration: BoxDecoration(
            color: Color.lerp(t.glass.withValues(alpha: 0), t.glass, v),
            border: Border(
              bottom: BorderSide(
                color: Color.lerp(t.line.withValues(alpha: 0), t.line, v)!,
              ),
            ),
          ),
          child: const SizedBox.expand(),
        );
        // No BackdropFilter at rest: a blur layer costs frames for nothing.
        if (v < 0.01) return fill;
        return ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14 * v, sigmaY: 14 * v),
            child: fill,
          ),
        );
      },
    );
  }
}
