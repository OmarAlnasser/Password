import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/brand.dart';
import 'package:hisn/l10n/app_localizations.dart';
import 'package:hisn/services/password_generator.dart';
import 'package:hisn/services/settings.dart';
import 'package:hisn/ui/theme/app_theme.dart';
import 'package:hisn/ui/theme/tokens.dart';
import 'package:hisn/ui/theme/typography.dart';
import 'package:hisn/ui/widgets/app_background.dart';
import 'package:hisn/ui/widgets/app_shell.dart';
import 'package:hisn/ui/widgets/brand_mark.dart';
import 'package:hisn/ui/widgets/empty_state.dart';
import 'package:hisn/ui/widgets/glass_bar.dart';
import 'package:hisn/ui/widgets/max_width_body.dart';
import 'package:hisn/ui/widgets/pill_chip.dart';
import 'package:hisn/ui/widgets/primary_button.dart';
import 'package:hisn/ui/widgets/pulse_dot.dart';
import 'package:hisn/ui/widgets/reveal.dart';
import 'package:hisn/ui/widgets/secret_text.dart';
import 'package:hisn/ui/widgets/section_header.dart';
import 'package:hisn/ui/widgets/site_avatar.dart';
import 'package:hisn/ui/widgets/stat_tile.dart';
import 'package:hisn/ui/widgets/strength_bar.dart';
import 'package:hisn/ui/widgets/surface_card.dart';

import 'screenshot_harness.dart';

/// Guards for the design foundations (`docs/DESIGN.md`): tokens keep their
/// contrast, the theme wires the fonts per language, the shared widgets keep
/// their public behaviour, and nothing overflows in Arabic at 200% text.
void main() {
  group('settings', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('vs_theme'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('a new install starts in dark mode', () async {
      final s = AppSettings(File('${dir.path}/settings.json'));
      expect(s.themeMode, ThemeMode.dark);
      await s.load(); // no file yet
      expect(s.themeMode, ThemeMode.dark);
    });

    test('a saved choice wins, including "system"', () async {
      final file = File('${dir.path}/settings.json');
      final a = AppSettings(file);
      await a.update((s) => s.themeMode = ThemeMode.system);
      final b = AppSettings(file);
      await b.load();
      expect(b.themeMode, ThemeMode.system);
      await b.update((s) => s.themeMode = ThemeMode.light);
      final c = AppSettings(file);
      await c.load();
      expect(c.themeMode, ThemeMode.light);
    });

    test('a settings file without a theme means dark', () async {
      final file = File('${dir.path}/settings.json')
        ..writeAsStringSync('{"lang":"ar"}');
      final s = AppSettings(file);
      await s.load();
      expect(s.themeMode, ThemeMode.dark);
      expect(s.locale, const Locale('ar'));
    });
  });

  group('tokens', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
    }

    for (final t in [AppTokens.dark, AppTokens.light]) {
      final name = t.isDark ? 'dark' : 'light';

      test('$name: text colours reach 4.5:1 on every surface', () {
        final surfaces = {
          'bg': t.bg,
          'surface': t.surface,
          'surface2': t.surface2,
        };
        final texts = {
          'ink': t.ink,
          'soft': t.soft,
          'muted': t.muted,
          'accent': t.accent,
          'accent2': t.accent2,
          'good': t.good,
          'error': t.error,
          'warn': t.warn,
        };
        for (final s in surfaces.entries) {
          for (final x in texts.entries) {
            expect(
              contrast(x.value, s.value),
              greaterThanOrEqualTo(4.5),
              reason: '$name ${x.key} on ${s.key}',
            );
          }
        }
        expect(contrast(t.muted, t.surface3), greaterThanOrEqualTo(4.5));
        expect(contrast(t.ink, t.surface3), greaterThanOrEqualTo(4.5));
      });

      test('$name: filled controls keep readable text in every state', () {
        for (final fill in [t.strong, t.strongHover, t.strongPressed]) {
          expect(contrast(t.onStrong, fill), greaterThanOrEqualTo(4.5));
        }
        expect(contrast(t.onAccent, t.accent), greaterThanOrEqualTo(4.5));
        expect(contrast(t.onAccent, t.accent2), greaterThanOrEqualTo(4.5));
        expect(contrast(t.onError, t.error), greaterThanOrEqualTo(4.5));
        expect(contrast(t.onWarn, t.warn), greaterThanOrEqualTo(4.5));
        expect(contrast(t.warn, t.warnContainer), greaterThanOrEqualTo(4.5));
        expect(contrast(t.good, t.goodContainer), greaterThanOrEqualTo(4.5));
        expect(
          contrast(t.onErrorContainer, t.errorContainer),
          greaterThanOrEqualTo(4.5),
        );
      });

      test(
        '$name: control borders reach 3:1, the strength ramp stays legible',
        () {
          for (final s in [t.bg, t.surface, t.surface2]) {
            expect(contrast(t.outline, s), greaterThanOrEqualTo(3));
          }
          for (var i = 0; i < 5; i++) {
            expect(contrast(t.ramp[i], t.surface2), greaterThanOrEqualTo(3));
            expect(
              contrast(t.rampText[i], t.surface2),
              greaterThanOrEqualTo(4.5),
              reason: 'strength label $i',
            );
          }
        },
      );
    }

    test('lerp and copyWith keep every token', () {
      final mid = AppTokens.dark.lerp(AppTokens.light, 0.5);
      expect(mid.ramp, hasLength(5));
      expect(mid.bg, Color.lerp(AppTokens.dark.bg, AppTokens.light.bg, 0.5));
      expect(AppTokens.dark.copyWith(bg: Colors.red).bg, Colors.red);
      expect(AppTokens.dark.copyWith().surface, AppTokens.dark.surface);
    });

    test('the brand constant is the only place the name is written', () {
      expect(appName, isNotEmpty);
      expect(appInitial, appName.characters.first.toUpperCase());
      expect(appNameFor(const Locale('ar')), appNameAr);
      expect(appNameFor(const Locale('en')), appName);
    });
  });

  group('theme', () {
    test('has the tokens, the explicit palette and the right fonts', () {
      for (final b in Brightness.values) {
        final en = AppTheme.resolve(b, const Locale('en'));
        final ar = AppTheme.resolve(b, const Locale('ar'));
        final t = AppTokens.of(b);
        expect(en.extension<AppTokens>(), same(t));
        expect(en.colorScheme.primary, t.accent);
        expect(en.colorScheme.surface, t.bg);
        expect(en.colorScheme.tertiaryContainer, t.warnContainer);
        expect(en.colorScheme.brightness, b);
        expect(en.textTheme.bodyMedium!.fontFamily, AppFonts.en);
        expect(en.textTheme.bodyMedium!.fontFamilyFallback, [AppFonts.ar]);
        expect(ar.textTheme.bodyMedium!.fontFamily, AppFonts.ar);
        expect(ar.textTheme.bodyMedium!.fontFamilyFallback, [AppFonts.en]);
        expect(ar.textTheme.headlineLarge!.letterSpacing, 0);
        expect(en.textTheme.headlineLarge!.letterSpacing, lessThan(0));
        expect(en.useMaterial3, isTrue);
      }
    });

    test('is cached, and the shell variant has a transparent scaffold', () {
      expect(AppTheme.dark(), same(AppTheme.dark(const Locale('en'))));
      expect(AppTheme.dark(), isNot(same(AppTheme.dark(const Locale('ar')))));
      expect(AppTheme.dark().scaffoldBackgroundColor, AppTokens.dark.bg);
      expect(
        AppTheme.resolve(
          Brightness.dark,
          null,
          transparentScaffold: true,
        ).scaffoldBackgroundColor,
        Colors.transparent,
      );
    });

    test('buttons are 12 px rounded with a 48 px minimum height', () {
      final t = AppTheme.dark();
      final s = t.filledButtonTheme.style!;
      final shape = s.shape!.resolve({})! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(12));
      expect(s.minimumSize!.resolve({})!.height, 48);
      expect(s.backgroundColor!.resolve({}), AppTokens.dark.strong);
      expect(
        s.backgroundColor!.resolve({WidgetState.hovered}),
        AppTokens.dark.strongHover,
      );
    });

    test('the pubspec bundles the three fonts and never uses google_fonts', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, isNot(contains('google_fonts')));
      for (final f in AppFonts.all) {
        expect(pubspec, contains('family: $f'));
      }
    });
  });

  group('widgets', () {
    Future<void> pumpApp(
      WidgetTester tester,
      Widget home, {
      Locale locale = const Locale('en'),
      Brightness brightness = Brightness.dark,
      double textScale = 1,
      Size size = const Size(390, 844),
    }) async {
      await tester.runAsync(loadBundledFonts);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(locale),
          darkTheme: AppTheme.dark(locale),
          themeMode: brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: AppShell(child: child!),
          ),
          home: home,
        ),
      );
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets(
      'AppShell: locale-aware theme, background, transparent scaffold',
      (tester) async {
        await pumpApp(
          tester,
          const Scaffold(body: Text('x')),
          locale: const Locale('ar'),
        );
        final theme = Theme.of(tester.element(find.text('x')));
        expect(theme.textTheme.bodyMedium!.fontFamily, AppFonts.ar);
        expect(theme.scaffoldBackgroundColor, Colors.transparent);
        expect(find.byType(AppBackground), findsOneWidget);
      },
    );

    testWidgets('PrimaryButton is a plain FilledButton with its label', (
      tester,
    ) async {
      var taps = 0;
      await pumpApp(
        tester,
        Scaffold(
          body: Column(
            children: [
              PrimaryButton(
                onPressed: () => taps++,
                child: const Text('Create'),
              ),
              PrimaryButton(
                onPressed: () => taps++,
                icon: const Icon(Icons.lock_open_rounded),
                expanded: true,
                child: const Text('Unlock'),
              ),
              const PrimaryButton(onPressed: null, child: Text('Off')),
            ],
          ),
        ),
      );
      expect(find.widgetWithText(FilledButton, 'Create'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Unlock'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
      await tester.tap(find.widgetWithText(FilledButton, 'Off'));
      expect(taps, 2);
      final unlock = tester.getSize(
        find.widgetWithText(FilledButton, 'Unlock'),
      );
      expect(unlock.width, 390);
      expect(unlock.height, greaterThanOrEqualTo(48));
    });

    testWidgets('SecretText keeps its API: LTR, mono, ambiguous characters', (
      tester,
    ) async {
      await pumpApp(
        tester,
        const Scaffold(
          body: Column(
            children: [
              SecretText('aO1b'),
              SecretText('secret-value', obscure: true),
              SecretText('x', obscure: true),
              SecretText('aO1b', highlightAmbiguous: false),
            ],
          ),
        ),
        locale: const Locale('ar'),
      );
      final scheme = AppTheme.dark().colorScheme;
      // The first one is selectable rich text, forced left-to-right, mono.
      final rich = tester.widgetList<SelectableText>(
        find.byType(SelectableText),
      );
      expect(rich, hasLength(2));
      final spans = rich.first.textSpan!;
      expect(spans.style!.fontFamily, AppFonts.mono);
      expect(spans.style!.fontFeatures, isNotEmpty);
      final chars = spans.children!.cast<TextSpan>();
      expect(chars.map((s) => s.text).join(), 'aO1b');
      expect(chars[0].style?.backgroundColor, isNull);
      expect(chars[1].style!.backgroundColor, scheme.tertiaryContainer);
      expect(chars[2].style!.backgroundColor, scheme.tertiaryContainer);
      expect(chars[2].style!.color, scheme.onTertiaryContainer);
      expect(
        (rich.last.textSpan!.children!.cast<TextSpan>())[1]
            .style
            ?.backgroundColor,
        isNull,
      );
      expect(
        tester
            .widget<Directionality>(
              find
                  .ancestor(
                    of: find.byWidget(rich.first),
                    matching: find.byType(Directionality),
                  )
                  .first,
            )
            .textDirection,
        TextDirection.ltr,
      );
      // Masked: the dots are clamped to 8..16 and never reveal the length.
      expect(find.text('•' * 12), findsOneWidget);
      expect(find.text('•' * 8), findsOneWidget);
    });

    testWidgets('StrengthBar shows the label for every score', (tester) async {
      await pumpApp(
        tester,
        Scaffold(
          body: Column(
            children: [
              for (var s = 0; s <= 4; s++)
                StrengthBar(result: StrengthResult(s, 'a day', null)),
            ],
          ),
        ),
      );
      final l = AppLocalizations.of(tester.element(find.byType(Scaffold)));
      for (final label in [
        l.strength0,
        l.strength1,
        l.strength2,
        l.strength3,
        l.strength4,
      ]) {
        expect(find.text('$label · a day'), findsOneWidget);
      }
    });

    testWidgets('PulseDot settles (it pulses a few times, then rests)', (
      tester,
    ) async {
      await pumpApp(
        tester,
        const Scaffold(
          body: Center(child: StatusPill(label: 'Encrypted on this device')),
        ),
      );
      await tester.pumpAndSettle(); // would time out with an endless pulse
      expect(find.text('Encrypted on this device'), findsOneWidget);
    });

    testWidgets('Reveal plays once and leaves the child alone afterwards', (
      tester,
    ) async {
      await pumpApp(
        tester,
        const Scaffold(body: Reveal(index: 3, child: Text('hello'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('hello'), findsOneWidget);
    });

    testWidgets('SurfaceCard: tap, selected, semantics label', (tester) async {
      var taps = 0;
      await pumpApp(
        tester,
        Scaffold(
          body: Column(
            children: [
              SurfaceCard(
                onTap: () => taps++,
                selected: true,
                semanticLabel: 'github.com, omar',
                child: const Text('github.com'),
              ),
              const SurfaceCard(child: Text('static')),
            ],
          ),
        ),
      );
      await tester.tap(find.text('github.com'));
      expect(taps, 1);
      expect(find.bySemanticsLabel('github.com, omar'), findsOneWidget);
    });

    testWidgets('GlassBar turns to glass when the page scrolls', (
      tester,
    ) async {
      await pumpApp(
        tester,
        Scaffold(
          extendBodyBehindAppBar: true,
          appBar: const GlassBar(title: Text('Title')),
          body: ListView(
            children: [for (var i = 0; i < 60; i++) Text('row $i')],
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('pages fade through, also with reduced motion', (tester) async {
      for (final reduce in [false, true]) {
        await tester.runAsync(loadBundledFonts);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
              child: AppShell(child: child!),
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(body: Text('second')),
                    ),
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();
        expect(find.text('second'), findsOneWidget);
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pumpAndSettle();
        expect(find.text('second'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }
    });

    // Every shared widget, in Arabic (real RTL) at 200% text on the narrowest
    // phone, in both themes. A RenderFlex overflow fails the test.
    for (final brightness in Brightness.values) {
      testWidgets(
        'nothing overflows: ar, 200% text, 360 wide, ${brightness.name}',
        (tester) async {
          await pumpApp(
            tester,
            Scaffold(
              appBar: GlassBar(
                title: const BrandLockup(),
                actions: [
                  IconButton(onPressed: () {}, icon: const Icon(Icons.search)),
                ],
              ),
              body: Builder(
                builder: (context) => ListView(
                  padding: MaxWidthBody.insets(context),
                  children: [
                    const SectionHeader(
                      eyebrow: 'خزنتك',
                      title: 'كلماتك محمية',
                      subtitle: 'مشفّرة على جهازك',
                      size: SectionHeaderSize.screen,
                      accentDot: true,
                      trailing: Icon(Icons.tune),
                    ),
                    const StatusPill(label: 'مشفّرة على جهازك'),
                    Wrap(
                      spacing: 8,
                      children: [
                        PillChip(
                          label: 'الكل',
                          selected: true,
                          onSelected: (_) {},
                        ),
                        PillChip(label: 'المفضلة', onSelected: (_) {}),
                        PillChip(label: 'ضعيفة', onSelected: (_) {}),
                      ],
                    ),
                    const StatGrid(
                      tiles: [
                        StatTile(
                          value: '128',
                          label: 'كل الحسابات',
                          footnote: '+1',
                        ),
                        StatTile(value: '6', label: 'ضعيفة'),
                      ],
                    ),
                    SurfaceCard(
                      onTap: () {},
                      child: const Row(
                        children: [
                          SiteAvatar(title: 'G'),
                          SizedBox(width: 14),
                          Expanded(child: LtrText('accounts.google.com')),
                        ],
                      ),
                    ),
                    const SecretBox(
                      child: Column(
                        children: [
                          SecretText('Tr0ub4dor&3-Il1O|xQ'),
                          StrengthBar(result: StrengthResult(2, 'يومان', null)),
                        ],
                      ),
                    ),
                    PrimaryButton(
                      onPressed: () {},
                      expanded: true,
                      icon: const Icon(Icons.lock_open_rounded),
                      child: const Text('فتح الخزنة'),
                    ),
                    const SizedBox(
                      height: 400,
                      child: EmptyState(
                        icon: Icons.lock_outline,
                        title: 'خزنتك فارغة',
                        message: 'أضف أول حساب. يُشفَّر على هذا الجهاز.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            locale: const Locale('ar'),
            brightness: brightness,
            textScale: 2,
            size: const Size(360, 1800),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
