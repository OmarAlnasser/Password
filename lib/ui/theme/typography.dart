import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Font families bundled under `assets/fonts/` (see `assets/fonts/README.md`).
/// Nothing is fetched at run time.
abstract final class AppFonts {
  /// English UI text, brand wordmark and stat numerals in every language.
  static const String en = 'Outfit';

  /// Arabic UI text. It also has a Latin alphabet, so it is the fallback of
  /// [en].
  static const String ar = 'IBMPlexSansArabic';

  /// Passwords, emails, URLs, codes. Coding ligatures are removed from it.
  static const String mono = 'JetBrainsMono';

  /// Family names to load when a test registers the bundled fonts by hand.
  static const List<String> all = [en, ar, mono];
}

/// Type styles that do not belong to a Material text role.
abstract final class AppText {
  /// Base style of a language: the right family plus the other one as
  /// fallback, so a mixed English / Arabic string renders in either.
  static TextStyle base({required bool arabic}) => TextStyle(
    fontFamily: arabic ? AppFonts.ar : AppFonts.en,
    fontFamilyFallback: [arabic ? AppFonts.en : AppFonts.ar],
  );

  /// Passwords and recovery keys, 18 px. Always render left-to-right; see
  /// `SecretText`. `calt` is switched off on top of the font's own removal so
  /// a password never changes shape.
  static const TextStyle secret = TextStyle(
    fontFamily: AppFonts.mono,
    fontFamilyFallback: ['monospace'],
    fontFeatures: [FontFeature.disable('calt')],
    fontSize: 18,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.8,
    height: 1.5,
  );

  /// Email, URL and username lines under a title, 12.5 px.
  static const TextStyle secretSmall = TextStyle(
    fontFamily: AppFonts.mono,
    fontFamilyFallback: ['monospace'],
    fontFeatures: [FontFeature.disable('calt')],
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.5,
  );

  /// Big numerals on stat tiles: always Outfit, tabular figures.
  static const TextStyle numeral = TextStyle(
    fontFamily: AppFonts.en,
    fontFamilyFallback: [AppFonts.ar],
    fontFeatures: [FontFeature.tabularFigures()],
    fontSize: 34,
    fontWeight: FontWeight.w600,
    height: 1.1,
  );

  /// Brand wordmark: Outfit 600, 15, +1 tracking, in both languages.
  static const TextStyle wordmark = TextStyle(
    fontFamily: AppFonts.en,
    fontFamilyFallback: [AppFonts.ar],
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 1,
    height: 1.2,
  );

  /// The same style with the mono family forced (keeps size, colour, ...).
  /// Weights above 500 do not exist in JetBrains Mono, so they map to 500.
  static TextStyle asSecret(TextStyle s) => s.copyWith(
    fontFamily: AppFonts.mono,
    fontFamilyFallback: const ['monospace'],
    fontFeatures: const [FontFeature.disable('calt')],
    fontWeight: (s.fontWeight?.value ?? 400) >= 600
        ? FontWeight.w500
        : (s.fontWeight ?? FontWeight.w400),
    fontStyle: FontStyle.normal,
  );
}

/// The Material [TextTheme] for one language and one colour set
/// (DESIGN section 3.2). Arabic styles never track (Flutter ignores
/// `letterSpacing` on Arabic runs, and Latin words inside them stay
/// untracked), and carry more line height.
TextTheme buildTextTheme(AppTokens t, {required bool arabic}) {
  final family = AppText.base(arabic: arabic);
  TextStyle s(
    double en,
    double ar,
    FontWeight w,
    double ls,
    double hEn,
    double hAr, {
    Color? color,
  }) {
    return family.copyWith(
      fontSize: arabic ? ar : en,
      fontWeight: w,
      letterSpacing: arabic ? 0 : ls,
      height: arabic ? hAr : hEn,
      color: color ?? t.ink,
    );
  }

  const w4 = FontWeight.w400;
  const w5 = FontWeight.w500;
  const w6 = FontWeight.w600;
  const w7 = FontWeight.w700;
  return TextTheme(
    displayLarge: s(40, 36, w7, -1.0, 1.10, 1.35),
    displayMedium: s(34, 31, w7, -0.8, 1.15, 1.40),
    displaySmall: s(28, 26, w7, -0.5, 1.20, 1.40),
    headlineLarge: s(32, 30, w6, -0.6, 1.20, 1.40),
    headlineMedium: s(26, 24, w6, -0.3, 1.25, 1.45),
    headlineSmall: s(22, 21, w6, -0.2, 1.30, 1.50),
    titleLarge: s(22, 21, w6, -0.2, 1.30, 1.50),
    titleMedium: s(16, 16, w6, 0, 1.40, 1.55),
    titleSmall: s(14, 14, w6, 0.1, 1.40, 1.55),
    bodyLarge: s(16, 16, w4, 0, 1.65, 1.80),
    bodyMedium: s(14, 15, w4, 0, 1.55, 1.75),
    bodySmall: s(13, 13, w4, 0.1, 1.50, 1.70, color: t.muted),
    labelLarge: s(15, 15, w6, 0.1, 1.20, 1.30),
    labelMedium: s(14, 14, w5, 0.2, 1.20, 1.35),
    labelSmall: s(11, 12, w5, 1.4, 1.60, 1.60, color: t.muted),
  );
}
