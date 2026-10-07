import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'page_transitions.dart';
import 'tokens.dart';
import 'typography.dart';

/// Builds the app's [ThemeData] from the tokens in `docs/DESIGN.md`.
///
/// ```dart
/// MaterialApp(
///   theme: AppTheme.light(locale),
///   darkTheme: AppTheme.dark(locale),
///   builder: (context, child) => AppShell(child: child!),
/// )
/// ```
///
/// The text theme depends on the language (Outfit for English, IBM Plex Sans
/// Arabic for Arabic); `AppShell` re-resolves the theme for the locale that
/// is really in use, so "follow the system language" works too.
///
/// Themes are cached: calling these on every build is cheap.
abstract final class AppTheme {
  /// The dark theme (the identity). [locale] picks the type scale; null means
  /// English.
  static ThemeData dark([Locale? locale]) => resolve(Brightness.dark, locale);

  /// The light theme, same violet character.
  static ThemeData light([Locale? locale]) => resolve(Brightness.light, locale);

  /// The theme for [brightness] and [locale].
  ///
  /// With [transparentScaffold] the `Scaffold` background is transparent, so
  /// the app-wide background (`AppBackground`, with the ambient glow) shows
  /// through every screen. `AppShell` uses it.
  static ThemeData resolve(
    Brightness brightness,
    Locale? locale, {
    bool transparentScaffold = false,
  }) {
    final arabic = locale?.languageCode == 'ar';
    return _cache.putIfAbsent((
      brightness,
      arabic,
      transparentScaffold,
    ), () => _build(AppTokens.of(brightness), arabic, transparentScaffold));
  }

  static final Map<(Brightness, bool, bool), ThemeData> _cache = {};
}

// -----------------------------------------------------------------------------

ThemeData _build(AppTokens t, bool arabic, bool transparentScaffold) {
  final text = buildTextTheme(t, arabic: arabic);
  final scheme = _colorScheme(t);
  final base = AppText.base(arabic: arabic);

  BorderSide ring(Color c) => BorderSide(
    color: c,
    width: 2,
    strokeAlign: BorderSide.strokeAlignOutside,
  );
  final shape12 = RoundedRectangleBorder(borderRadius: AppRadius.controlAll);
  const fieldPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 14);
  final disabledInk = t.ink.withValues(alpha: 0.38);

  // --- buttons ---------------------------------------------------------------
  final filled = ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.disabled)) {
        return t.ink.withValues(alpha: 0.10);
      }
      if (s.contains(WidgetState.pressed)) return t.strongPressed;
      if (s.contains(WidgetState.hovered)) return t.strongHover;
      return t.strong;
    }),
    foregroundColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.disabled) ? disabledInk : t.onStrong,
    ),
    iconColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.disabled) ? disabledInk : t.onStrong,
    ),
    overlayColor: WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.pressed)) {
        return Colors.white.withValues(alpha: 0.16);
      }
      if (s.contains(WidgetState.focused)) {
        return Colors.white.withValues(alpha: 0.10);
      }
      return Colors.transparent;
    }),
    side: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.focused) ? ring(t.focusRing) : null,
    ),
    elevation: const WidgetStatePropertyAll(0),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 22, vertical: 13),
    ),
    minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
    iconSize: const WidgetStatePropertyAll(20),
    shape: WidgetStatePropertyAll(shape12),
    textStyle: WidgetStatePropertyAll(text.labelLarge),
    animationDuration: AppMotion.fast,
    splashFactory: InkRipple.splashFactory,
  );

  final outlined = ButtonStyle(
    backgroundColor: WidgetStatePropertyAll(t.ghostFill),
    foregroundColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.disabled) ? disabledInk : t.ink,
    ),
    iconColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.disabled) ? disabledInk : t.ink,
    ),
    overlayColor: WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.pressed)) {
        return t.accent.withValues(alpha: 0.18);
      }
      if (s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)) {
        return t.hoverFill;
      }
      return Colors.transparent;
    }),
    side: WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.disabled)) return BorderSide(color: t.line);
      if (s.contains(WidgetState.focused)) return ring(t.focusRing);
      if (s.contains(WidgetState.hovered) || s.contains(WidgetState.pressed)) {
        return BorderSide(color: t.accent);
      }
      return BorderSide(color: t.line2);
    }),
    elevation: const WidgetStatePropertyAll(0),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 22, vertical: 13),
    ),
    minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
    iconSize: const WidgetStatePropertyAll(20),
    shape: WidgetStatePropertyAll(shape12),
    textStyle: WidgetStatePropertyAll(text.labelLarge),
    animationDuration: AppMotion.fast,
    splashFactory: InkRipple.splashFactory,
  );

  final textButton = ButtonStyle(
    foregroundColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.disabled) ? disabledInk : t.link,
    ),
    iconColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.disabled) ? disabledInk : t.link,
    ),
    overlayColor: WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.pressed)) {
        return t.accent.withValues(alpha: 0.18);
      }
      if (s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)) {
        return t.hoverFill;
      }
      return Colors.transparent;
    }),
    side: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.focused) ? ring(t.focusRing) : null,
    ),
    elevation: const WidgetStatePropertyAll(0),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
    iconSize: const WidgetStatePropertyAll(20),
    shape: WidgetStatePropertyAll(shape12),
    textStyle: WidgetStatePropertyAll(text.labelLarge),
    animationDuration: AppMotion.fast,
    splashFactory: InkRipple.splashFactory,
  );

  final iconButton = ButtonStyle(
    foregroundColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.disabled) ? disabledInk : t.soft,
    ),
    overlayColor: WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.pressed)) {
        return t.accent.withValues(alpha: 0.18);
      }
      if (s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)) {
        return t.hoverFill;
      }
      return Colors.transparent;
    }),
    side: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.focused) ? ring(t.focusRing) : null,
    ),
    minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
    shape: WidgetStatePropertyAll(shape12),
    animationDuration: AppMotion.fast,
    splashFactory: InkRipple.splashFactory,
  );

  // --- inputs ----------------------------------------------------------------
  OutlineInputBorder border(Color c, double w) => OutlineInputBorder(
    borderRadius: AppRadius.controlAll,
    borderSide: BorderSide(color: c, width: w),
  );
  final inputs = InputDecorationThemeData(
    filled: true,
    fillColor: t.surface2,
    contentPadding: fieldPadding,
    border: border(t.outline, 1),
    enabledBorder: border(t.outline, 1),
    focusedBorder: border(t.focusRing, 2),
    errorBorder: border(t.error, 1),
    focusedErrorBorder: border(t.error, 2),
    disabledBorder: border(t.line, 1),
    labelStyle: text.bodyMedium!.copyWith(color: t.muted),
    floatingLabelStyle: WidgetStateTextStyle.resolveWith(
      (s) => text.bodySmall!.copyWith(
        color: s.contains(WidgetState.error)
            ? t.error
            : s.contains(WidgetState.focused)
            ? t.focusRing
            : t.muted,
      ),
    ),
    hintStyle: text.bodyMedium!.copyWith(color: t.muted),
    helperStyle: text.bodySmall,
    errorStyle: text.bodySmall!.copyWith(color: t.error),
    errorMaxLines: 3,
    helperMaxLines: 3,
    prefixIconColor: WidgetStateColor.resolveWith(
      (s) => s.contains(WidgetState.focused) ? t.focusRing : t.muted,
    ),
    suffixIconColor: WidgetStateColor.resolveWith(
      (s) => s.contains(WidgetState.focused) ? t.focusRing : t.soft,
    ),
  );

  // --- selection controls ----------------------------------------------------
  final switchTheme = SwitchThemeData(
    thumbColor: WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.disabled)) {
        return t.muted.withValues(alpha: 0.5);
      }
      return s.contains(WidgetState.selected) ? t.onStrong : t.muted;
    }),
    trackColor: WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.selected)) {
        return s.contains(WidgetState.disabled)
            ? t.strong.withValues(alpha: 0.4)
            : t.strong;
      }
      return t.surface3;
    }),
    trackOutlineColor: WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.focused)) return t.focusRing;
      return s.contains(WidgetState.selected) ? Colors.transparent : t.outline;
    }),
    trackOutlineWidth: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.focused) ? 2.0 : 1.0,
    ),
    overlayColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.pressed) || s.contains(WidgetState.focused)
          ? t.accent.withValues(alpha: 0.18)
          : s.contains(WidgetState.hovered)
          ? t.hoverFill
          : Colors.transparent,
    ),
  );

  final checkbox = CheckboxThemeData(
    fillColor: WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.selected)) {
        return s.contains(WidgetState.disabled)
            ? t.strong.withValues(alpha: 0.4)
            : t.strong;
      }
      return Colors.transparent;
    }),
    checkColor: WidgetStatePropertyAll(t.onStrong),
    side: WidgetStateBorderSide.resolveWith((s) {
      if (s.contains(WidgetState.selected)) {
        return const BorderSide(width: 2, color: Colors.transparent);
      }
      return BorderSide(
        width: 2,
        color: s.contains(WidgetState.focused) ? t.focusRing : t.outline,
      );
    }),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    overlayColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.pressed) || s.contains(WidgetState.focused)
          ? t.accent.withValues(alpha: 0.18)
          : s.contains(WidgetState.hovered)
          ? t.hoverFill
          : Colors.transparent,
    ),
  );

  final radio = RadioThemeData(
    fillColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.selected) ? t.focusRing : t.outline,
    ),
    overlayColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.pressed) || s.contains(WidgetState.focused)
          ? t.accent.withValues(alpha: 0.18)
          : s.contains(WidgetState.hovered)
          ? t.hoverFill
          : Colors.transparent,
    ),
  );

  // --- chips / segmented / tabs ----------------------------------------------
  final chips = ChipThemeData(
    backgroundColor: t.surface,
    selectedColor: t.strong,
    disabledColor: t.surface,
    color: WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.selected)) {
        return s.contains(WidgetState.hovered) ? t.strongHover : t.strong;
      }
      return s.contains(WidgetState.hovered) ? t.surface2 : t.surface;
    }),
    side: WidgetStateBorderSide.resolveWith((s) {
      if (s.contains(WidgetState.focused)) {
        return BorderSide(color: t.focusRing, width: 2);
      }
      if (s.contains(WidgetState.selected)) {
        return BorderSide(color: t.pillSelectedBorder);
      }
      if (s.contains(WidgetState.hovered)) return BorderSide(color: t.accent);
      return BorderSide(color: t.line2);
    }),
    shape: const StadiumBorder(),
    showCheckmark: false,
    labelStyle: text.labelMedium!.copyWith(color: t.soft),
    secondaryLabelStyle: text.labelMedium!.copyWith(color: t.onStrong),
    iconTheme: IconThemeData(color: t.soft, size: 18),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
    elevation: 0,
    pressElevation: 0,
    shadowColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
  );

  final segmented = SegmentedButtonThemeData(
    style: ButtonStyle(
      shape: const WidgetStatePropertyAll(StadiumBorder()),
      backgroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.selected : t.surface,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled)
            ? disabledInk
            : s.contains(WidgetState.selected)
            ? t.ink
            : t.soft,
      ),
      side: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.focused)
            ? BorderSide(color: t.focusRing, width: 2)
            : BorderSide(
                color: s.contains(WidgetState.selected)
                    ? t.selectedBorder
                    : t.line2,
              ),
      ),
      overlayColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.pressed)
            ? t.accent.withValues(alpha: 0.18)
            : s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)
            ? t.hoverFill
            : Colors.transparent,
      ),
      textStyle: WidgetStatePropertyAll(text.labelMedium),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      ),
      minimumSize: const WidgetStatePropertyAll(Size(48, 44)),
      animationDuration: AppMotion.fast,
      splashFactory: InkRipple.splashFactory,
    ),
    selectedIcon: const Icon(Icons.check_rounded),
  );

  final tabs = TabBarThemeData(
    indicatorSize: TabBarIndicatorSize.tab,
    indicator: BoxDecoration(
      color: t.selected,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      border: Border.all(color: t.selectedBorder),
    ),
    labelColor: t.ink,
    unselectedLabelColor: t.soft,
    labelStyle: text.labelMedium,
    unselectedLabelStyle: text.labelMedium,
    dividerColor: Colors.transparent,
    overlayColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.hovered) ? t.hoverFill : Colors.transparent,
    ),
    splashBorderRadius: BorderRadius.circular(AppRadius.pill),
  );

  // --- bars, rails, lists ----------------------------------------------------
  final navIcon = WidgetStateProperty.resolveWith(
    (s) => IconThemeData(
      size: 24,
      color: s.contains(WidgetState.selected) ? t.link : t.muted,
    ),
  );
  final navigationBar = NavigationBarThemeData(
    height: 68,
    backgroundColor: t.bg2,
    surfaceTintColor: Colors.transparent,
    shadowColor: Colors.transparent,
    elevation: 0,
    indicatorColor: t.selected,
    indicatorShape: const StadiumBorder(),
    iconTheme: navIcon,
    labelTextStyle: WidgetStateProperty.resolveWith(
      (s) => text.labelMedium!.copyWith(
        fontSize: 12,
        color: s.contains(WidgetState.selected) ? t.ink : t.muted,
      ),
    ),
    labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    overlayColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.hovered) ? t.hoverFill : Colors.transparent,
    ),
  );
  final navigationRail = NavigationRailThemeData(
    backgroundColor: t.bg2,
    elevation: 0,
    minWidth: 76,
    useIndicator: true,
    indicatorColor: t.selected,
    indicatorShape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    ),
    selectedIconTheme: IconThemeData(color: t.link, size: 24),
    unselectedIconTheme: IconThemeData(color: t.muted, size: 24),
    selectedLabelTextStyle: text.labelMedium!.copyWith(color: t.ink),
    unselectedLabelTextStyle: text.labelMedium!.copyWith(color: t.muted),
  );
  final listTile = ListTileThemeData(
    iconColor: t.soft,
    textColor: t.ink,
    titleTextStyle: text.titleMedium,
    subtitleTextStyle: text.bodySmall,
    leadingAndTrailingTextStyle: text.bodySmall,
    selectedColor: t.ink,
    selectedTileColor: t.selected,
    contentPadding: const EdgeInsetsDirectional.only(start: 16, end: 12),
    minVerticalPadding: 8,
    horizontalTitleGap: 14,
    minLeadingWidth: 24,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  );

  // --- surfaces and overlays -------------------------------------------------
  final menuShape = RoundedRectangleBorder(
    borderRadius: AppRadius.controlAll,
    side: BorderSide(color: t.line2),
  );
  final dialog = DialogThemeData(
    backgroundColor: t.dialogSolid,
    surfaceTintColor: Colors.transparent,
    shadowColor: t.shadow,
    elevation: 0,
    barrierColor: t.scrim,
    shape: RoundedRectangleBorder(
      borderRadius: AppRadius.dialogAll,
      side: BorderSide(color: t.dialogBorder),
    ),
    titleTextStyle: text.titleLarge,
    contentTextStyle: text.bodyMedium!.copyWith(color: t.soft),
    iconColor: t.accent2,
    actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    constraints: const BoxConstraints(maxWidth: AppLayout.dialogRich),
  );
  final sheet = BottomSheetThemeData(
    backgroundColor: t.dialogSolid,
    modalBackgroundColor: t.dialogSolid,
    surfaceTintColor: Colors.transparent,
    modalBarrierColor: t.scrim,
    elevation: 14,
    modalElevation: 14,
    shadowColor: t.isDark ? t.strong.withValues(alpha: 0.55) : t.shadow,
    showDragHandle: true,
    dragHandleColor: t.line2,
    dragHandleSize: const Size(36, 4),
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: AppRadius.sheetTop,
      side: BorderSide(color: t.dialogBorder),
    ),
    constraints: const BoxConstraints(maxWidth: AppLayout.form),
  );
  final snack = SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: t.surface3,
    contentTextStyle: text.bodyMedium,
    actionTextColor: t.link,
    disabledActionTextColor: t.muted,
    elevation: 0,
    insetPadding: const EdgeInsets.all(16),
    shape: menuShape,
    closeIconColor: t.soft,
  );
  final popup = PopupMenuThemeData(
    color: t.surface3,
    surfaceTintColor: Colors.transparent,
    shadowColor: t.shadow,
    elevation: 10,
    shape: menuShape,
    textStyle: text.bodyMedium,
    labelTextStyle: WidgetStatePropertyAll(text.bodyMedium),
    iconColor: t.soft,
    position: PopupMenuPosition.under,
  );
  final menu = MenuThemeData(
    style: MenuStyle(
      backgroundColor: WidgetStatePropertyAll(t.surface3),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      shadowColor: WidgetStatePropertyAll(t.shadow),
      elevation: const WidgetStatePropertyAll(10),
      shape: WidgetStatePropertyAll(menuShape),
    ),
  );
  final tooltip = TooltipThemeData(
    decoration: BoxDecoration(
      color: t.surface3,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: t.line2),
    ),
    textStyle: text.bodySmall!.copyWith(color: t.ink, fontSize: 12.5),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    margin: const EdgeInsets.all(8),
    waitDuration: const Duration(milliseconds: 500),
    showDuration: const Duration(seconds: 3),
    preferBelow: true,
  );
  final scrollbar = ScrollbarThemeData(
    thumbColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.hovered) || s.contains(WidgetState.dragged)
          ? t.outline
          : t.line2,
    ),
    radius: const Radius.circular(4),
    thickness: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.hovered) ? 8.0 : 6.0,
    ),
    crossAxisMargin: 2,
    interactive: true,
  );
  final progress = ProgressIndicatorThemeData(
    color: t.accent2.withValues(alpha: 1),
    linearTrackColor: t.line,
    circularTrackColor: Colors.transparent,
    linearMinHeight: 4,
    refreshBackgroundColor: t.surface3,
  );
  final slider = SliderThemeData(
    trackHeight: 4,
    activeTrackColor: t.accent,
    inactiveTrackColor: t.surface3,
    thumbColor: t.focusRing,
    overlayColor: t.accent.withValues(alpha: 0.20),
    valueIndicatorColor: t.surface3,
    valueIndicatorTextStyle: text.labelMedium,
    activeTickMarkColor: Colors.transparent,
    inactiveTickMarkColor: Colors.transparent,
  );
  final fab = FloatingActionButtonThemeData(
    backgroundColor: t.strong,
    foregroundColor: t.onStrong,
    hoverColor: t.strongHover,
    focusColor: t.strongHover,
    elevation: 4,
    hoverElevation: 6,
    focusElevation: 6,
    highlightElevation: 2,
    shape: const StadiumBorder(),
    extendedTextStyle: text.labelLarge,
  );
  final expansion = ExpansionTileThemeData(
    iconColor: t.link,
    collapsedIconColor: t.soft,
    textColor: t.ink,
    collapsedTextColor: t.ink,
    shape: const Border(),
    collapsedShape: const Border(),
    tilePadding: const EdgeInsetsDirectional.only(start: 16, end: 12),
  );
  final appBar = AppBarThemeData(
    backgroundColor: WidgetStateColor.resolveWith(
      (s) =>
          s.contains(WidgetState.scrolledUnder) ? t.glass : Colors.transparent,
    ),
    foregroundColor: t.ink,
    surfaceTintColor: Colors.transparent,
    shadowColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
    titleSpacing: 16,
    titleTextStyle: text.titleLarge,
    iconTheme: IconThemeData(color: t.soft, size: 24),
    actionsIconTheme: IconThemeData(color: t.soft, size: 24),
    systemOverlayStyle:
        (t.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
            .copyWith(statusBarColor: Colors.transparent),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: t.brightness,
    colorScheme: scheme,
    extensions: [t],
    visualDensity: VisualDensity.adaptivePlatformDensity,
    splashFactory: InkRipple.splashFactory,
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final p in TargetPlatform.values)
          p: const AppPageTransitionsBuilder(),
      },
    ),
    // Colour defaults that Material components fall back to.
    scaffoldBackgroundColor: transparentScaffold ? Colors.transparent : t.bg,
    canvasColor: t.surface3,
    cardColor: t.surface,
    dividerColor: t.line,
    disabledColor: disabledInk,
    hintColor: t.muted,
    hoverColor: t.hoverFill,
    focusColor: t.focusRing.withValues(alpha: 0.18),
    highlightColor: Colors.transparent,
    splashColor: t.accent.withValues(alpha: 0.14),
    shadowColor: t.shadow,
    // Text.
    fontFamily: base.fontFamily,
    fontFamilyFallback: base.fontFamilyFallback,
    textTheme: text,
    primaryTextTheme: text,
    iconTheme: IconThemeData(color: t.soft, size: 24),
    primaryIconTheme: IconThemeData(color: t.soft, size: 24),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: t.focusRing,
      selectionColor: t.accent.withValues(alpha: 0.35),
      selectionHandleColor: t.accent,
    ),
    // Components.
    appBarTheme: appBar,
    cardTheme: CardThemeData(
      color: t.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardAll,
        side: BorderSide(color: t.cardBorder),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: filled),
    elevatedButtonTheme: ElevatedButtonThemeData(style: filled),
    outlinedButtonTheme: OutlinedButtonThemeData(style: outlined),
    textButtonTheme: TextButtonThemeData(style: textButton),
    iconButtonTheme: IconButtonThemeData(style: iconButton),
    floatingActionButtonTheme: fab,
    inputDecorationTheme: inputs,
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: text.bodyLarge,
      inputDecorationTheme: inputs,
      menuStyle: menu.style,
    ),
    switchTheme: switchTheme,
    checkboxTheme: checkbox,
    radioTheme: radio,
    sliderTheme: slider,
    chipTheme: chips,
    segmentedButtonTheme: segmented,
    tabBarTheme: tabs,
    navigationBarTheme: navigationBar,
    navigationRailTheme: navigationRail,
    listTileTheme: listTile,
    expansionTileTheme: expansion,
    dividerTheme: DividerThemeData(color: t.line, thickness: 1, space: 1),
    dialogTheme: dialog,
    bottomSheetTheme: sheet,
    snackBarTheme: snack,
    popupMenuTheme: popup,
    menuTheme: menu,
    tooltipTheme: tooltip,
    scrollbarTheme: scrollbar,
    progressIndicatorTheme: progress,
  );
}

ColorScheme _colorScheme(AppTokens t) => ColorScheme(
  brightness: t.brightness,
  primary: t.accent,
  onPrimary: t.onAccent,
  primaryContainer: t.strong,
  onPrimaryContainer: t.onStrong,
  secondary: t.accent2,
  onSecondary: t.onAccent,
  secondaryContainer: t.tint,
  onSecondaryContainer: t.ink,
  // Amber on purpose: SecretText marks ambiguous characters with
  // tertiaryContainer, and "look twice" must not read as "fine" (green).
  tertiary: t.warn,
  onTertiary: t.onWarn,
  tertiaryContainer: t.warnContainer,
  onTertiaryContainer: t.warn,
  error: t.error,
  onError: t.onError,
  errorContainer: t.errorContainer,
  onErrorContainer: t.onErrorContainer,
  surface: t.bg,
  onSurface: t.ink,
  onSurfaceVariant: t.muted,
  surfaceContainerLowest: t.isDark ? t.bg : t.surface,
  surfaceContainerLow: t.bg2,
  surfaceContainer: t.surface,
  surfaceContainerHigh: t.surface2,
  surfaceContainerHighest: t.surface3,
  outline: t.outline,
  outlineVariant: t.line2,
  inverseSurface: t.ink,
  onInverseSurface: t.bg,
  inversePrimary: t.accent,
  scrim: t.scrim.withValues(alpha: 1),
  shadow: Colors.black,
  surfaceTint: Colors.transparent,
);
