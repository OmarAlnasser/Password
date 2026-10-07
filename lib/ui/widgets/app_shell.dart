import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_background.dart';

/// Wraps the whole app: re-resolves the theme for the language that is really
/// in use and paints the app-wide background behind every screen.
///
/// ```dart
/// MaterialApp(builder: (context, child) => AppShell(child: child!), ...)
/// ```
///
/// Inside it `Scaffold`s are transparent (see [AppTheme.resolve]), so the
/// background colour and the ambient glow show through, and page transitions
/// (fade-through, see `AppPageTransitionsBuilder`) never show two opaque
/// pages through each other. A screen that is shown outside an [AppShell]
/// (a bare `MaterialApp` in a test) keeps an opaque scaffold and still looks
/// right, just without the glow.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    return Theme(
      data: AppTheme.resolve(
        base.brightness,
        locale,
        transparentScaffold: true,
      ),
      child: AppBackground(child: child),
    );
  }
}
