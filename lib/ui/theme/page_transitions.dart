import 'package:flutter/material.dart';

import 'tokens.dart';

/// Fade-through page transition with a subtle 16 px rise (DESIGN section 7):
/// the page underneath fades out first, then the new page fades in while it
/// settles 2 % of the screen height upwards, 300 ms on the portfolio's
/// `cubic-bezier(.2,.8,.2,1)`.
///
/// The two fades do not overlap on purpose: with the app-wide background (see
/// `AppShell`) screens have a transparent `Scaffold`, so overlapping pages
/// would show through each other. One builder serves every platform.
///
/// With "reduce motion" on (`MediaQuery.disableAnimations`) the page simply
/// appears: the page underneath is hidden on the first frame of a push and
/// the page on top on the first frame of a pop, instead of the two sharing
/// the screen for the 300 ms the route still runs.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Duration get transitionDuration => AppMotion.page;

  @override
  Duration get reverseTransitionDuration => AppMotion.page;

  static final Animatable<double> _fadeIn = CurveTween(
    curve: const Interval(0.3, 1.0, curve: AppMotion.ease),
  );
  static final Animatable<double> _fadeOutUnder = Tween<double>(
    begin: 1,
    end: 0,
  ).chain(CurveTween(curve: const Interval(0, 0.3, curve: Curves.ease)));
  static final Animatable<Offset> _rise = Tween<Offset>(
    begin: const Offset(0, 0.02),
    end: Offset.zero,
  ).chain(CurveTween(curve: AppMotion.ease));

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return AnimatedBuilder(
        animation: Listenable.merge([animation, secondaryAnimation]),
        child: child,
        builder: (context, child) {
          // Another page is being pushed over this one, or is already there.
          final covered =
              secondaryAnimation.status == AnimationStatus.forward ||
              secondaryAnimation.status == AnimationStatus.completed;
          // This page is being popped.
          final leaving = animation.status == AnimationStatus.reverse;
          return Opacity(opacity: covered || leaving ? 0 : 1, child: child);
        },
      );
    }
    return FadeTransition(
      opacity: _fadeIn.animate(animation),
      child: SlideTransition(
        position: _rise.animate(animation),
        child: FadeTransition(
          opacity: _fadeOutUnder.animate(secondaryAnimation),
          child: child,
        ),
      ),
    );
  }
}
