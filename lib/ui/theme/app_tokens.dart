import 'package:flutter/material.dart';

import 'gradients.dart';

/// Colour tokens of one theme (dark or light), from `docs/DESIGN.md` section 2.
///
/// A [ThemeExtension] on [ThemeData]. Components read these through
/// `context.tokens`; nothing in the UI reads a raw hex value.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.brightness,
    required this.bg,
    required this.bg2,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.ink,
    required this.soft,
    required this.muted,
    required this.line,
    required this.line2,
    required this.outline,
    required this.accent,
    required this.accent2,
    required this.strong,
    required this.strongHover,
    required this.strongPressed,
    required this.onStrong,
    required this.onAccent,
    required this.good,
    required this.goodContainer,
    required this.warn,
    required this.warnContainer,
    required this.onWarn,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.tint,
    required this.cardA,
    required this.cardB,
    required this.cardBorder,
    required this.cardHoverBorder,
    required this.cardHoverGlow,
    required this.featuredA,
    required this.featuredB,
    required this.featuredBorder,
    required this.dialogA,
    required this.dialogB,
    required this.dialogBorder,
    required this.selected,
    required this.selectedBorder,
    required this.scrim,
    required this.glass,
    required this.glow,
    required this.hoverFill,
    required this.ghostFill,
    required this.buttonGlow,
    required this.shadow,
    required this.tagFill,
    required this.tagBorder,
    required this.tagText,
    required this.brandGlyph,
    required this.brandEnd,
    required this.pillSelectedBorder,
    required this.ramp,
    required this.rampText,
  });

  final Brightness brightness;

  /// Page background (`ColorScheme.surface`).
  final Color bg;

  /// Side rail, alternate bands.
  final Color bg2;

  /// Stat tiles, pills, plain cards.
  final Color surface;

  /// Inputs, icon tiles, secret box.
  final Color surface2;

  /// Menus, tooltips, snack bars, hovered rows.
  final Color surface3;

  /// Primary text.
  final Color ink;

  /// Secondary text, icons.
  final Color soft;

  /// Captions, hints, labels.
  final Color muted;

  /// Hairlines and dividers (decorative).
  final Color line;

  /// Decorative borders (pills, buttons).
  final Color line2;

  /// Borders that identify a control (3:1 or better).
  final Color outline;

  /// Links, icons, digits (`ColorScheme.primary`).
  final Color accent;

  /// Eyebrows, stat numbers, focus ring.
  final Color accent2;

  /// Filled button, selected pill.
  final Color strong;

  /// Filled button on hover (AA with white text).
  final Color strongHover;

  /// Filled button while pressed.
  final Color strongPressed;

  /// Text on [strong].
  final Color onStrong;

  /// Text on [accent] / [accent2] fills.
  final Color onAccent;

  /// Success, the live dot, strong passwords.
  final Color good;

  /// Background for [good] text.
  final Color goodContainer;

  /// Warnings, ambiguous characters.
  final Color warn;

  /// Background for [warn] text.
  final Color warnContainer;

  /// Text on a [warn] fill.
  final Color onWarn;

  /// Errors, symbols in passwords, destructive.
  final Color error;

  /// Text on an [error] fill.
  final Color onError;

  /// Error banners.
  final Color errorContainer;

  /// Text on [errorContainer].
  final Color onErrorContainer;

  /// Tinted container (nav indicator, selected tile).
  final Color tint;

  /// Card gradient start.
  final Color cardA;

  /// Card gradient end.
  final Color cardB;

  /// Card border.
  final Color cardBorder;

  /// Card border while hovered.
  final Color cardHoverBorder;

  /// Radial glow that follows the pointer.
  final Color cardHoverGlow;

  /// Featured card gradient start.
  final Color featuredA;

  /// Featured card gradient end.
  final Color featuredB;

  /// Featured card border.
  final Color featuredBorder;

  /// Dialog and sheet radial gradient, centre.
  final Color dialogA;

  /// Dialog and sheet radial gradient, edge.
  final Color dialogB;

  /// Dialog and sheet border.
  final Color dialogBorder;

  /// Selected row / nav item fill.
  final Color selected;

  /// Selected row border.
  final Color selectedBorder;

  /// Barrier behind dialogs and sheets.
  final Color scrim;

  /// Translucent header over blurred content.
  final Color glass;

  /// Ambient glow in the page corner.
  final Color glow;

  /// Hover fill for text buttons, icon buttons, nav items.
  final Color hoverFill;

  /// Fill of the ghost (outlined) button.
  final Color ghostFill;

  /// Glow under the primary button.
  final Color buttonGlow;

  /// Big soft shadow colour.
  final Color shadow;

  /// Read-only tag fill.
  final Color tagFill;

  /// Read-only tag border.
  final Color tagBorder;

  /// Read-only tag text.
  final Color tagText;

  /// Glyph on the brand tile.
  final Color brandGlyph;

  /// Light end of the brand gradient (the same in both themes).
  final Color brandEnd;

  /// Border of the selected filter pill.
  final Color pillSelectedBorder;

  /// Password-strength ramp, score 0 to 4 (bars and fills).
  final List<Color> ramp;

  /// Same ramp, darkened where needed so a 13 px label reaches 4.5:1.
  final List<Color> rampText;

  /// The dark theme (the identity; new installs start here).
  static const AppTokens dark = AppTokens(
    brightness: Brightness.dark,
    bg: Color(0xFF07060F),
    bg2: Color(0xFF0C0A17),
    surface: Color(0xFF120E1F),
    surface2: Color(0xFF191329),
    surface3: Color(0xFF221A38),
    ink: Color(0xFFF4F1FA),
    soft: Color(0xFFD6CBE8),
    muted: Color(0xFFAAA6BC),
    line: Color(0xFF262036),
    line2: Color(0xFF3A2D50),
    outline: Color(0xFF74629A),
    accent: Color(0xFFA17CF5),
    accent2: Color(0xFFC9A8FF),
    strong: Color(0xFF8251D4),
    strongHover: Color(0xFF8A59DD),
    strongPressed: Color(0xFF7545CB),
    onStrong: Color(0xFFFFFFFF),
    onAccent: Color(0xFF0B0814),
    good: Color(0xFF7FE0A8),
    goodContainer: Color(0xFF10281C),
    warn: Color(0xFFF2C46D),
    warnContainer: Color(0xFF33270D),
    onWarn: Color(0xFF1F1500),
    error: Color(0xFFF26D6D),
    onError: Color(0xFF1B0508),
    errorContainer: Color(0xFF3A1620),
    onErrorContainer: Color(0xFFFF9AA6),
    tint: Color(0xFF251D3C),
    cardA: Color(0xFF151023),
    cardB: Color(0xFF09080F),
    cardBorder: Color(0xFF2E2340),
    cardHoverBorder: Color(0xFF7A5BA6),
    cardHoverGlow: Color(0x22B281F3),
    featuredA: Color(0xFF221437),
    featuredB: Color(0xFF0B0814),
    featuredBorder: Color(0xFF4A3368),
    dialogA: Color(0xFF35204D),
    dialogB: Color(0xFF100A1C),
    dialogBorder: Color(0xFF684686),
    selected: Color(0x22A17CF5),
    selectedBorder: Color(0xFF7A5BA6),
    scrim: Color(0xC402010B),
    glass: Color(0xCC07060F),
    glow: Color(0x2E6A3FD0),
    hoverFill: Color(0x0DFFFFFF),
    ghostFill: Color(0x06FFFFFF),
    buttonGlow: Color(0x407D43CE),
    shadow: Color(0x77000000),
    tagFill: Color(0x0F9D74E8),
    tagBorder: Color(0xFF4A355E),
    tagText: Color(0xFFCBB5EA),
    brandGlyph: Color(0xFF0B0814),
    brandEnd: Color(0xFFC9A8FF),
    pillSelectedBorder: Color(0xFFA879EE),
    ramp: [
      Color(0xFFF26D6D),
      Color(0xFFF59A6B),
      Color(0xFFF2C46D),
      Color(0xFFB6E07A),
      Color(0xFF7FE0A8),
    ],
    rampText: [
      Color(0xFFF26D6D),
      Color(0xFFF59A6B),
      Color(0xFFF2C46D),
      Color(0xFFB6E07A),
      Color(0xFF7FE0A8),
    ],
  );

  /// The light theme: same hue family, text-weight tokens darkened for AA.
  static const AppTokens light = AppTokens(
    brightness: Brightness.light,
    bg: Color(0xFFFAF8FF),
    bg2: Color(0xFFF3EFFB),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF5F1FD),
    surface3: Color(0xFFECE5F8),
    ink: Color(0xFF160F29),
    soft: Color(0xFF3B3153),
    muted: Color(0xFF5A5370),
    line: Color(0xFFE5DEF2),
    line2: Color(0xFFCFC3E6),
    outline: Color(0xFF857A9F),
    accent: Color(0xFF6A3DC4),
    accent2: Color(0xFF55299F),
    strong: Color(0xFF8251D4),
    strongHover: Color(0xFF7443C8),
    strongPressed: Color(0xFF6A38BD),
    onStrong: Color(0xFFFFFFFF),
    onAccent: Color(0xFFFFFFFF),
    good: Color(0xFF12703F),
    goodContainer: Color(0xFFDFF5E8),
    warn: Color(0xFF8A5A00),
    warnContainer: Color(0xFFFFF1D6),
    onWarn: Color(0xFFFFFFFF),
    error: Color(0xFFC0263F),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFDE7EA),
    onErrorContainer: Color(0xFF9D1B31),
    tint: Color(0xFFF0EAFA),
    cardA: Color(0xFFFFFFFF),
    cardB: Color(0xFFF6F2FD),
    cardBorder: Color(0xFFE0D6F0),
    cardHoverBorder: Color(0xFFB79DE6),
    cardHoverGlow: Color(0x148251D4),
    featuredA: Color(0xFFF1E8FF),
    featuredB: Color(0xFFFFFFFF),
    featuredBorder: Color(0xFFCDB8EE),
    dialogA: Color(0xFFEADCFF),
    dialogB: Color(0xFFFFFFFF),
    dialogBorder: Color(0xFFCDB8EE),
    selected: Color(0x1F8251D4),
    selectedBorder: Color(0xFFB79DE6),
    scrim: Color(0x8C1A0F33),
    glass: Color(0xCCFAF8FF),
    glow: Color(0x248251D4),
    hoverFill: Color(0x0F8251D4),
    ghostFill: Color(0x00FFFFFF),
    buttonGlow: Color(0x388251D4),
    shadow: Color(0x2E3A1F7A),
    tagFill: Color(0x0F8251D4),
    tagBorder: Color(0xFFCDB8EE),
    tagText: Color(0xFF55299F),
    brandGlyph: Color(0xFF0B0814),
    brandEnd: Color(0xFFC9A8FF),
    pillSelectedBorder: Color(0xFFA879EE),
    ramp: [
      Color(0xFFC0263F),
      Color(0xFFC4571C),
      Color(0xFFA86B00),
      Color(0xFF5C8A12),
      Color(0xFF12703F),
    ],
    rampText: [
      Color(0xFFC0263F),
      Color(0xFFA8460F),
      Color(0xFF8A5A00),
      Color(0xFF4A7010),
      Color(0xFF12703F),
    ],
  );

  /// [dark] or [light].
  static AppTokens of(Brightness b) => b == Brightness.dark ? dark : light;

  @override
  AppTokens copyWith({
    Brightness? brightness,
    Color? bg,
    Color? bg2,
    Color? surface,
    Color? surface2,
    Color? surface3,
    Color? ink,
    Color? soft,
    Color? muted,
    Color? line,
    Color? line2,
    Color? outline,
    Color? accent,
    Color? accent2,
    Color? strong,
    Color? strongHover,
    Color? strongPressed,
    Color? onStrong,
    Color? onAccent,
    Color? good,
    Color? goodContainer,
    Color? warn,
    Color? warnContainer,
    Color? onWarn,
    Color? error,
    Color? onError,
    Color? errorContainer,
    Color? onErrorContainer,
    Color? tint,
    Color? cardA,
    Color? cardB,
    Color? cardBorder,
    Color? cardHoverBorder,
    Color? cardHoverGlow,
    Color? featuredA,
    Color? featuredB,
    Color? featuredBorder,
    Color? dialogA,
    Color? dialogB,
    Color? dialogBorder,
    Color? selected,
    Color? selectedBorder,
    Color? scrim,
    Color? glass,
    Color? glow,
    Color? hoverFill,
    Color? ghostFill,
    Color? buttonGlow,
    Color? shadow,
    Color? tagFill,
    Color? tagBorder,
    Color? tagText,
    Color? brandGlyph,
    Color? brandEnd,
    Color? pillSelectedBorder,
    List<Color>? ramp,
    List<Color>? rampText,
  }) {
    return AppTokens(
      brightness: brightness ?? this.brightness,
      bg: bg ?? this.bg,
      bg2: bg2 ?? this.bg2,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      ink: ink ?? this.ink,
      soft: soft ?? this.soft,
      muted: muted ?? this.muted,
      line: line ?? this.line,
      line2: line2 ?? this.line2,
      outline: outline ?? this.outline,
      accent: accent ?? this.accent,
      accent2: accent2 ?? this.accent2,
      strong: strong ?? this.strong,
      strongHover: strongHover ?? this.strongHover,
      strongPressed: strongPressed ?? this.strongPressed,
      onStrong: onStrong ?? this.onStrong,
      onAccent: onAccent ?? this.onAccent,
      good: good ?? this.good,
      goodContainer: goodContainer ?? this.goodContainer,
      warn: warn ?? this.warn,
      warnContainer: warnContainer ?? this.warnContainer,
      onWarn: onWarn ?? this.onWarn,
      error: error ?? this.error,
      onError: onError ?? this.onError,
      errorContainer: errorContainer ?? this.errorContainer,
      onErrorContainer: onErrorContainer ?? this.onErrorContainer,
      tint: tint ?? this.tint,
      cardA: cardA ?? this.cardA,
      cardB: cardB ?? this.cardB,
      cardBorder: cardBorder ?? this.cardBorder,
      cardHoverBorder: cardHoverBorder ?? this.cardHoverBorder,
      cardHoverGlow: cardHoverGlow ?? this.cardHoverGlow,
      featuredA: featuredA ?? this.featuredA,
      featuredB: featuredB ?? this.featuredB,
      featuredBorder: featuredBorder ?? this.featuredBorder,
      dialogA: dialogA ?? this.dialogA,
      dialogB: dialogB ?? this.dialogB,
      dialogBorder: dialogBorder ?? this.dialogBorder,
      selected: selected ?? this.selected,
      selectedBorder: selectedBorder ?? this.selectedBorder,
      scrim: scrim ?? this.scrim,
      glass: glass ?? this.glass,
      glow: glow ?? this.glow,
      hoverFill: hoverFill ?? this.hoverFill,
      ghostFill: ghostFill ?? this.ghostFill,
      buttonGlow: buttonGlow ?? this.buttonGlow,
      shadow: shadow ?? this.shadow,
      tagFill: tagFill ?? this.tagFill,
      tagBorder: tagBorder ?? this.tagBorder,
      tagText: tagText ?? this.tagText,
      brandGlyph: brandGlyph ?? this.brandGlyph,
      brandEnd: brandEnd ?? this.brandEnd,
      pillSelectedBorder: pillSelectedBorder ?? this.pillSelectedBorder,
      ramp: ramp ?? this.ramp,
      rampText: rampText ?? this.rampText,
    );
  }

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    List<Color> mixAll(List<Color> a, List<Color> b) => [
      for (var i = 0; i < a.length; i++) mix(a[i], b[i]),
    ];
    return AppTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      bg: mix(bg, other.bg),
      bg2: mix(bg2, other.bg2),
      surface: mix(surface, other.surface),
      surface2: mix(surface2, other.surface2),
      surface3: mix(surface3, other.surface3),
      ink: mix(ink, other.ink),
      soft: mix(soft, other.soft),
      muted: mix(muted, other.muted),
      line: mix(line, other.line),
      line2: mix(line2, other.line2),
      outline: mix(outline, other.outline),
      accent: mix(accent, other.accent),
      accent2: mix(accent2, other.accent2),
      strong: mix(strong, other.strong),
      strongHover: mix(strongHover, other.strongHover),
      strongPressed: mix(strongPressed, other.strongPressed),
      onStrong: mix(onStrong, other.onStrong),
      onAccent: mix(onAccent, other.onAccent),
      good: mix(good, other.good),
      goodContainer: mix(goodContainer, other.goodContainer),
      warn: mix(warn, other.warn),
      warnContainer: mix(warnContainer, other.warnContainer),
      onWarn: mix(onWarn, other.onWarn),
      error: mix(error, other.error),
      onError: mix(onError, other.onError),
      errorContainer: mix(errorContainer, other.errorContainer),
      onErrorContainer: mix(onErrorContainer, other.onErrorContainer),
      tint: mix(tint, other.tint),
      cardA: mix(cardA, other.cardA),
      cardB: mix(cardB, other.cardB),
      cardBorder: mix(cardBorder, other.cardBorder),
      cardHoverBorder: mix(cardHoverBorder, other.cardHoverBorder),
      cardHoverGlow: mix(cardHoverGlow, other.cardHoverGlow),
      featuredA: mix(featuredA, other.featuredA),
      featuredB: mix(featuredB, other.featuredB),
      featuredBorder: mix(featuredBorder, other.featuredBorder),
      dialogA: mix(dialogA, other.dialogA),
      dialogB: mix(dialogB, other.dialogB),
      dialogBorder: mix(dialogBorder, other.dialogBorder),
      selected: mix(selected, other.selected),
      selectedBorder: mix(selectedBorder, other.selectedBorder),
      scrim: mix(scrim, other.scrim),
      glass: mix(glass, other.glass),
      glow: mix(glow, other.glow),
      hoverFill: mix(hoverFill, other.hoverFill),
      ghostFill: mix(ghostFill, other.ghostFill),
      buttonGlow: mix(buttonGlow, other.buttonGlow),
      shadow: mix(shadow, other.shadow),
      tagFill: mix(tagFill, other.tagFill),
      tagBorder: mix(tagBorder, other.tagBorder),
      tagText: mix(tagText, other.tagText),
      brandGlyph: mix(brandGlyph, other.brandGlyph),
      brandEnd: mix(brandEnd, other.brandEnd),
      pillSelectedBorder: mix(pillSelectedBorder, other.pillSelectedBorder),
      ramp: mixAll(ramp, other.ramp),
      rampText: mixAll(rampText, other.rampText),
    );
  }

  // ---------------------------------------------------------------------------
  // Derived values (gradients, shadows). Built from the tokens above so the
  // two themes cannot disagree about a recipe.
  // ---------------------------------------------------------------------------

  /// True for the dark theme.
  bool get isDark => brightness == Brightness.dark;

  /// The same tokens for a user who turned on the system's high-contrast
  /// setting (`MediaQuery.highContrastOf`): the decorative hairlines and
  /// borders (1.3 to 1.6:1 against the page) take the `outline` colour,
  /// which is 3:1 or better, so cards, pills, buttons and dividers stay
  /// visible. Text and fills are untouched.
  AppTokens withHighContrast() => copyWith(
    line: outline,
    line2: outline,
    cardBorder: outline,
    featuredBorder: outline,
    dialogBorder: outline,
    tagBorder: outline,
  );

  /// Brand tile: `linear-gradient(135deg, strong, brandEnd)`; identical in
  /// both themes.
  LinearGradient get brandGradient => cssLinear(135, [strong, brandEnd]);

  /// Card: `linear-gradient(140deg, cardA, cardB)`.
  LinearGradient get cardGradient => cssLinear(140, [cardA, cardB]);

  /// Featured card: `linear-gradient(130deg, featuredA, featuredB 70%)`.
  LinearGradient get featuredGradient =>
      cssLinear(130, [featuredA, featuredB], const [0, 0.7]);

  /// Dialog / sheet: radial from the top-right corner.
  RadialGradient get dialogGradient => RadialGradient(
    center: Alignment.topRight,
    radius: 1.3,
    colors: [dialogA, dialogB],
    stops: const [0, 0.65],
  );

  /// A single colour that sits between the dialog gradient's two stops, for
  /// surfaces that cannot paint a gradient (`AlertDialog`, modal sheets).
  Color get dialogSolid => Color.lerp(dialogA, dialogB, 0.62)!;

  /// The 2 px focus ring colour (`accent2` in dark, `accent` in light).
  Color get focusRing => isDark ? accent2 : accent;

  /// Text colour of a text button / link.
  Color get link => isDark ? accent2 : accent;

  /// The glow under a primary button (CSS `0 8px 30px`, blur x0.87).
  List<BoxShadow> get buttonShadow => [
    BoxShadow(color: buttonGlow, offset: const Offset(0, 8), blurRadius: 26),
  ];

  /// Hovered card: CSS `0 20px 50px`.
  List<BoxShadow> get cardHoverShadow => [
    BoxShadow(color: shadow, offset: const Offset(0, 20), blurRadius: 43),
  ];

  /// Dialog / sheet: CSS `0 25px 100px`.
  List<BoxShadow> get dialogShadow => [
    BoxShadow(
      color: isDark ? const Color(0xAA000000) : shadow,
      offset: const Offset(0, 25),
      blurRadius: 87,
    ),
  ];
}
