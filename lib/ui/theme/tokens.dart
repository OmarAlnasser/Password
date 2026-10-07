/// Design tokens: colour, spacing, radii, motion and layout constants from
/// `docs/DESIGN.md`. Import this one file; it re-exports [AppTokens].
///
/// ```dart
/// final t = context.tokens;                  // colours of the active theme
/// Container(color: t.surface, padding: const EdgeInsets.all(AppSpace.s16));
/// AnimatedContainer(duration: context.motion(AppMotion.fast), ...);
/// ```
library;

import 'package:flutter/material.dart';

import 'app_tokens.dart';

export 'app_tokens.dart';
export 'gradients.dart';

/// Spacing scale in dp (DESIGN section 4).
abstract final class AppSpace {
  static const double s2 = 2;
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s40 = 40;
  static const double s48 = 48;
  static const double s64 = 64;

  /// Gap between list tiles.
  static const double tileGap = 10;

  /// Gap between stat tiles and grid cells.
  static const double gridGap = 12;

  /// Page gutter: 16 on phones, 20 elsewhere.
  static double gutter(double width) => width < AppLayout.compact ? 16 : 20;

  /// [gutter] for the current window.
  static double gutterOf(BuildContext context) =>
      gutter(MediaQuery.sizeOf(context).width);
}

/// Corner radii in dp (DESIGN section 4).
abstract final class AppRadius {
  /// Read-only tag.
  static const double tag = 6;

  /// Button, input, secret box, menu, site icon tile.
  static const double control = 12;

  /// Stat tile.
  static const double stat = 14;

  /// Card, list tile.
  static const double card = 16;

  /// Dialog, bottom sheet (top corners), featured card.
  static const double dialog = 22;

  /// Pill: use with [StadiumBorder] or this as a radius.
  static const double pill = 30;

  static const BorderRadius controlAll = BorderRadius.all(
    Radius.circular(control),
  );
  static const BorderRadius statAll = BorderRadius.all(Radius.circular(stat));
  static const BorderRadius cardAll = BorderRadius.all(Radius.circular(card));
  static const BorderRadius dialogAll = BorderRadius.all(
    Radius.circular(dialog),
  );
  static const BorderRadius sheetTop = BorderRadius.vertical(
    top: Radius.circular(dialog),
  );
}

/// Window-size classes and content widths (DESIGN section 9).
abstract final class AppLayout {
  /// Below this the app is single-column with a bottom bar.
  static const double compact = 600;

  /// From here the vault shows list and detail side by side.
  static const double expanded = 900;

  /// From here the navigation rail may show labels.
  static const double large = 1200;

  /// Widest full-page content (the portfolio's `--wrap`).
  static const double page = 1180;

  /// Forms and the detail pane.
  static const double form = 640;

  /// Narrow forms (lock screen, sign in).
  static const double narrow = 480;

  /// Dialogs, and rich dialogs.
  static const double dialog = 560;
  static const double dialogRich = 680;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compact;

  static bool isExpanded(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= expanded;
}

/// Durations and curves (DESIGN section 7).
abstract final class AppMotion {
  /// `--ease: cubic-bezier(.2,.8,.2,1)`: the one curve of the portfolio.
  static const Curve ease = Cubic(0.2, 0.8, 0.2, 1.0);

  /// CSS default `ease`, for colour and border transitions.
  static const Curve standard = Curves.ease;

  /// Hover and focus colour, border, button lift.
  static const Duration fast = Duration(milliseconds: 200);

  /// Card hover.
  static const Duration card = Duration(milliseconds: 250);

  /// Header glass, dialog and page transitions.
  static const Duration page = Duration(milliseconds: 300);

  /// Strength / progress fill.
  static const Duration fill = Duration(milliseconds: 500);

  /// First appearance of a list or grid.
  static const Duration reveal = Duration(milliseconds: 700);

  /// Stagger between revealed items.
  static const Duration stagger = Duration(milliseconds: 70);

  /// One live-dot pulse.
  static const Duration pulse = Duration(milliseconds: 2400);

  /// [d], or zero when the user asked the system to reduce motion.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;
}

extension AppThemeContext on BuildContext {
  /// The colour tokens of the active theme. Falls back to the dark or light
  /// set by [Brightness] when the theme has no [AppTokens] (a bare
  /// `MaterialApp` in a test), so shared widgets never crash.
  AppTokens get tokens {
    final theme = Theme.of(this);
    return theme.extension<AppTokens>() ?? AppTokens.of(theme.brightness);
  }

  /// [AppMotion.of] for this context: zero when animations are disabled.
  Duration motion(Duration d) => AppMotion.of(this, d);

  /// True when the active language is Arabic (real RTL, Arabic type scale).
  bool get isArabic => Localizations.maybeLocaleOf(this)?.languageCode == 'ar';
}
