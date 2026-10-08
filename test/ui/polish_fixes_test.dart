import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/data/models/vault_entry.dart';
import 'package:hisn/l10n/app_localizations.dart';
import 'package:hisn/services/ocr/ocr_parser.dart';
import 'package:hisn/services/password_generator.dart';
import 'package:hisn/services/settings.dart';
import 'package:hisn/ui/app_scope.dart';
import 'package:hisn/ui/home_screen.dart';
import 'package:hisn/ui/import/import_review_screen.dart';
import 'package:hisn/ui/ocr/ocr_widgets.dart';
import 'package:hisn/ui/ocr/quick_save_sheet.dart';
import 'package:hisn/ui/settings_screen.dart';
import 'package:hisn/ui/unlock_screen.dart';
import 'package:hisn/ui/theme/app_theme.dart';
import 'package:hisn/ui/theme/tokens.dart';
import 'package:hisn/ui/widgets/focus_ring.dart';
import 'package:hisn/ui/widgets/secret_text.dart';
import 'package:hisn/ui/widgets/strength_bar.dart';

import 'helpers.dart';

/// Settings that never touch the disk (see `tools_screens_test.dart`).
class _MemorySettings extends AppSettings {
  _MemorySettings() : super(File('/virtual/settings.json'));

  @override
  Future<void> update(void Function(AppSettings s) change) async {
    change(this);
    notifyListeners();
  }
}

/// A material app with the real theme and localisations around [home].
Widget _app(
  Widget home, {
  Locale locale = const Locale('en'),
  bool disableAnimations = false,
}) => MaterialApp(
  theme: AppTheme.dark(locale),
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
    child: child!,
  ),
  home: home,
);

double _luminance(Color c) {
  double lin(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// [top] painted over [base].
Color _over(Color base, Color top) => Color.alphaBlend(top, base);

/// Fixes from the integration review: each test names the problem it guards.
void main() {
  late Directory dir;
  late AppServices services;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vs_polish');
    final base = await buildTestServices(dir);
    services = AppServices(
      session: base.session,
      settings: _MemorySettings(),
      clipboard: base.clipboard,
      generator: base.generator,
      strength: base.strength,
      importExport: base.importExport,
      bridge: base.bridge,
      breaches: base.breaches,
      favicons: base.favicons,
    );
  });
  tearDown(() async {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
    await services.session.lock();
    dir.deleteSync(recursive: true);
  });

  Future<void> useWindow(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> openVault(WidgetTester tester, List<VaultEntry> entries) async {
    await tester.runAsync(() async {
      await services.session.init();
      await services.session.createVault(testMasterPassword);
      await services.session.saveEntries(entries);
    });
  }

  group('strength label', () {
    Future<void> show(WidgetTester tester, String crack, Locale locale) async {
      await tester.pumpWidget(
        _app(
          Scaffold(body: StrengthBar(result: StrengthResult(4, crack, null))),
          locale: locale,
        ),
      );
    }

    testWidgets('English: zxcvbn phrases read as plain English', (
      tester,
    ) async {
      const en = Locale('en');
      await show(tester, '3 years', en);
      expect(find.text('Very strong · 3 years'), findsOneWidget);
      await show(tester, '1 day', en);
      expect(find.text('Very strong · 1 day'), findsOneWidget);
      // The package appends an "s" to "seconds" a second time.
      await show(tester, '5 secondss', en);
      expect(find.text('Very strong · 5 seconds'), findsOneWidget);
      await show(tester, 'less than a second', en);
      expect(find.text('Very strong · less than a second'), findsOneWidget);
      await show(tester, 'centuries', en);
      expect(find.text('Very strong · centuries'), findsOneWidget);
    });

    testWidgets('Arabic: the duration is Arabic, with the right plural', (
      tester,
    ) async {
      const ar = Locale('ar');
      for (final (crack, ar_) in [
        ('3 years', '3 سنوات'),
        ('2 years', 'سنتان'),
        ('1 year', 'سنة واحدة'),
        ('12 days', '12 يومًا'),
        ('centuries', 'قرون'),
        ('less than a second', 'أقل من ثانية'),
      ]) {
        await show(tester, crack, ar);
        expect(find.text('قوية جدًا · $ar_'), findsOneWidget, reason: crack);
      }
    });

    testWidgets('an unknown phrase is kept, left to right inside Arabic', (
      tester,
    ) async {
      await show(tester, 'forever', const Locale('ar'));
      expect(find.text('قوية جدًا · \u2066forever\u2069'), findsOneWidget);
    });
  });

  testWidgets('a masked password is announced as hidden, not as bullets', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(const Scaffold(body: SecretText('xQmR42abCD5k', obscure: true))),
    );
    expect(find.bySemanticsLabel('Password hidden'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('•')), findsNothing);
    handle.dispose();
  });

  group('theme', () {
    test('high contrast gives borders and hairlines the outline colour', () {
      for (final b in Brightness.values) {
        final normal = AppTheme.resolve(b, null, transparentScaffold: true);
        final high = AppTheme.resolve(
          b,
          null,
          transparentScaffold: true,
          highContrast: true,
        );
        final t = AppTokens.of(b);
        expect(normal.dividerColor, t.line);
        expect(high.dividerColor, t.outline);
        expect(high.extension<AppTokens>()!.line2, t.outline);
        expect(high.extension<AppTokens>()!.cardBorder, t.outline);
        // Text and fills are the same.
        expect(high.extension<AppTokens>()!.ink, t.ink);
        expect(high.extension<AppTokens>()!.strong, t.strong);
      }
    });

    test('the filled button label keeps 4.5:1 while focused or pressed', () {
      for (final b in Brightness.values) {
        final theme = AppTheme.resolve(b, null);
        final style = theme.filledButtonTheme.style!;
        final t = AppTokens.of(b);
        for (final state in [
          <WidgetState>{},
          {WidgetState.hovered},
          {WidgetState.focused},
          {WidgetState.focused, WidgetState.hovered},
          {WidgetState.pressed},
          {WidgetState.pressed, WidgetState.focused},
        ]) {
          final fill = style.backgroundColor!.resolve(state)!;
          final overlay = style.overlayColor!.resolve(state)!;
          final shown = _over(fill, overlay);
          expect(
            _contrast(t.onStrong, shown),
            greaterThanOrEqualTo(4.5),
            reason: '${b.name} $state',
          );
        }
      }
    });
  });

  group('reduced motion', () {
    testWidgets('a pushed page replaces the one under it on the first frame', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  const Text('UNDER'),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const Scaffold(body: Text('OVER')),
                      ),
                    ),
                    child: const Text('go'),
                  ),
                ],
              ),
            ),
          ),
          disableAnimations: true,
        ),
      );
      double opacityOf(String text) => tester
          .widget<Opacity>(
            find
                .ancestor(of: find.text(text), matching: find.byType(Opacity))
                .first,
          )
          .opacity;

      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      // 40 ms into the 300 ms route: the old page is already gone.
      expect(opacityOf('UNDER'), 0);
      expect(opacityOf('OVER'), 1);

      Navigator.of(tester.element(find.text('OVER'))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(opacityOf('UNDER'), 1);
      expect(opacityOf('OVER'), 0);
      await tester.pumpAndSettle();
    });

    for (final reduce in [true, false]) {
      testWidgets('a dialog ${reduce ? 'is there at once' : 'fades in'}', (
        tester,
      ) async {
        await tester.pumpWidget(
          _app(
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  animationStyle: context.motionStyle,
                  builder: (_) => const AlertDialog(title: Text('Dialog')),
                ),
                child: const Text('open'),
              ),
            ),
            disableAnimations: reduce,
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        final fade = tester.widget<FadeTransition>(
          find
              .ancestor(
                of: find.byType(AlertDialog),
                matching: find.byType(FadeTransition),
              )
              .first,
        );
        if (reduce) {
          expect(fade.opacity.value, 1);
        } else {
          expect(fade.opacity.value, lessThan(1));
        }
        await tester.pumpAndSettle();
      });
    }
  });

  group('keyboard focus', () {
    testWidgets('a FocusRing shows only while navigating with the keyboard', (
      tester,
    ) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Center(
              child: FocusRing(
                child: InkWell(onTap: () {}, child: const Text('row')),
              ),
            ),
          ),
        ),
      );
      Finder ring() => find.descendant(
        of: find.byType(FocusRing),
        matching: find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              w.position == DecorationPosition.foreground &&
              (w.decoration as BoxDecoration).border != null,
        ),
      );
      expect(ring(), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(ring(), findsOneWidget);
      final border =
          (tester.widget<DecoratedBox>(ring()).decoration as BoxDecoration)
              .border!
              .top;
      expect(border.width, 2);
      expect(border.color, AppTokens.dark.focusRing);

      // A pointer takes over: no ring left behind.
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTouch;
      await tester.pump();
      expect(ring(), findsNothing);
    });

    testWidgets('settings: Tab finishes one column before the other', (
      tester,
    ) async {
      await useWindow(tester, const Size(1280, 800));
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      await tester.pumpWidget(
        AppScope(services: services, child: _app(const SettingsScreen())),
      );
      await tester.pumpAndSettle();
      final columns = <int>[];
      Rect? first;
      for (var i = 0; i < 60; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump(const Duration(milliseconds: 50));
        final r = FocusManager.instance.primaryFocus!.rect;
        // Round the whole tab cycle: stop when it wraps to the first stop.
        if (first == null) {
          first = r;
        } else if (r == first) {
          break;
        }
        // The back arrow and app bar are not in either column.
        if (r.top < 60) continue;
        columns.add(r.center.dx < 640 ? 0 : 1);
      }
      expect(columns, contains(0));
      expect(columns, contains(1));
      // Every stop of the left column, then every stop of the right one.
      expect(columns, [...columns]..sort(), reason: '$columns');
    });

    testWidgets('settings: the menu pills are keyboard focusable and say '
        'whether they are open', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        AppScope(services: services, child: _app(const SettingsScreen())),
      );
      await tester.pumpAndSettle();
      final finder = find.bySemanticsLabel('Auto-lock after inactivity: 2 min');
      expect(finder, findsOneWidget);
      var data = tester.getSemantics(finder);
      // Keyboard focusable: the node reports a focus state at all.
      expect(data.flagsCollection.isFocused, isNot(Tristate.none));
      expect(data.flagsCollection.isExpanded, Tristate.isFalse);
      await tester.tap(find.text('2 min'));
      await tester.pumpAndSettle();
      data = tester.getSemantics(finder);
      expect(data.flagsCollection.isExpanded, Tristate.isTrue);
      handle.dispose();
    });
  });

  group('home', () {
    List<VaultEntry> entries() => [
      for (var i = 0; i < 6; i++)
        VaultEntry(
          id: 'e$i',
          title: 'Entry $i',
          username: 'abcde07@hotmail.com',
          password: 'xQmR42abCD5k',
          url: 'https://site$i.com',
          tags: const [
            'work',
            'personal',
            'dev',
            'finance',
            'travel',
            'family',
          ],
        ),
    ];

    testWidgets('the search pill has a name for a screen reader', (
      tester,
    ) async {
      await useWindow(tester, const Size(390, 844));
      await openVault(tester, entries());
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        AppScope(services: services, child: _app(const HomeScreen())),
      );
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('Arabic, two panes: Tab brings each filter pill into the '
        'list pane', (tester) async {
      await useWindow(tester, const Size(1280, 800));
      await openVault(tester, entries());
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      await tester.pumpWidget(
        AppScope(
          services: services,
          child: _app(const HomeScreen(), locale: const Locale('ar')),
        ),
      );
      await tester.pumpAndSettle();
      // The list pane is the start (right) 32 % of the window.
      final pane = Rect.fromLTRB(1280 - 409.6, 0, 1280, 800);
      var checked = 0;
      for (var i = 0; i < 16; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        // Frame 1 starts the scroll animation, then it runs its 200 ms.
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 300));
        final f = FocusManager.instance.primaryFocus!;
        // Pills sit in a band under the search field.
        if (f.rect.top > 130 && f.rect.top < 200 && f.rect.height < 60) {
          expect(
            pane.contains(f.rect.center),
            isTrue,
            reason: 'pill at ${f.rect} is outside the pane $pane',
          );
          expect(f.rect.left, greaterThanOrEqualTo(pane.left));
          checked++;
        }
      }
      expect(checked, greaterThanOrEqualTo(6));
    });
  });

  testWidgets('the dialog icon is a square badge, not a flat bar', (
    tester,
  ) async {
    await useWindow(tester, const Size(390, 844));
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => offerClearClipboard(context, screenshot: true),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(OcrIconTile)), const Size(56, 56));
  });

  testWidgets('quick save is a bottom sheet on a phone, a dialog on a wide '
      'window', (tester) async {
    mockChannel(tester, platformChannel, (_) async => null);
    await tester.runAsync(() async {
      await services.session.init();
      await services.session.createVault(testMasterPassword);
    });
    for (final (size, dialog) in [
      (const Size(390, 844), false),
      (const Size(1280, 800), true),
    ]) {
      await useWindow(tester, size);
      await tester.pumpWidget(
        AppScope(
          services: services,
          child: _app(
            Builder(
              builder: (context) => TextButton(
                onPressed: () => QuickSaveSheet.show(
                  context,
                  const OcrResult(
                    chips: ['abcde07@hotmail.com', 'xQmR42abCD5k'],
                    email: 'abcde07@hotmail.com',
                    username: 'abcde07@hotmail.com',
                    password: 'xQmR42abCD5k',
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(QuickSaveSheet), findsOneWidget);
      expect(find.byType(BottomSheet), dialog ? findsNothing : findsOneWidget);
      expect(find.byType(Dialog), dialog ? findsOneWidget : findsNothing);
      // Its width is the dialog's 560, centred.
      if (dialog) {
        final r = tester.getRect(find.byType(QuickSaveSheet));
        expect(r.width, 560);
        expect(r.center.dx, 640);
      }
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(QuickSaveSheet), findsNothing);
    }
  });

  testWidgets('the unlock countdown is announced once, not every second', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await services.session.init();
      await services.session.createVault(testMasterPassword);
      await services.session.lock();
    });
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      AppScope(services: services, child: _app(const UnlockScreen())),
    );
    // Past the entrance animation, which hides the screen from semantics.
    await tester.pump(const Duration(seconds: 2));
    final pill = find.textContaining('Too many attempts');
    expect(pill, findsNothing);

    // Wrong guesses: the throttle starts, and the one-second ticker shows it.
    await tester.runAsync(() async {
      for (var i = 0; i < 6; i++) {
        await services.session.throttle.recordFailure();
      }
    });
    await tester.pump(const Duration(seconds: 1));
    expect(pill, findsOneWidget);
    SemanticsNode node() => tester.getSemantics(pill);
    expect(node().label, startsWith('Too many attempts'));
    expect(node().getSemanticsData().flagsCollection.isLiveRegion, isTrue);

    // The next ticks change the number but must not announce it again.
    await tester.pump(const Duration(seconds: 1));
    expect(node().getSemanticsData().flagsCollection.isLiveRegion, isFalse);
    handle.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('import review: each tick box is named after its login', (
    tester,
  ) async {
    await useWindow(tester, const Size(900, 1800));
    await tester.runAsync(() async {
      await services.session.init();
      await services.session.createVault(testMasterPassword);
    });
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: _app(
          ImportReviewScreen(
            imported: [
              VaultEntry(
                id: 'a',
                title: 'Contoso',
                username: 'abcde07@hotmail.com',
                password: 'Tz8pLq2wXv9m',
                url: 'https://mail.contoso-test.com/',
              ),
            ],
            skipped: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final box = tester.getSemantics(find.byType(Checkbox));
    expect(box.label, 'abcde07@hotmail.com, https://mail.contoso-test.com/');
    expect(box.flagsCollection.isChecked, CheckedState.isTrue);
    handle.dispose();
  });
}
