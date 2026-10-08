import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/l10n/app_localizations.dart';
import 'package:hisn/ui/theme/app_theme.dart';
import 'package:hisn/ui/widgets/password_field.dart';
import 'package:hisn/ui/widgets/reveal_controller.dart';
import 'package:hisn/ui/widgets/secret_text.dart';

import 'secret_visibility_helpers.dart';

/// The reusable pieces that keep a password masked: [RevealController],
/// [RevealBuilder], [RevealButton] and [PasswordField]. The value in these
/// tests is synthetic.
void main() {
  const secret = 'hunter-test-1';

  Widget app(Widget home, {Locale locale = const Locale('en')}) => MaterialApp(
    theme: AppTheme.dark(locale),
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: home),
    ),
  );

  group('RevealController', () {
    testWithSemantics('starts masked, shows on demand, masks after 15 s', (
      tester,
    ) async {
      final c = RevealController();
      addTearDown(c.dispose);
      var notified = 0;
      c.addListener(() => notified++);

      expect(c.shown, isFalse);
      c.toggle();
      expect(c.shown, isTrue);
      expect(notified, 1);

      await tester.pump(const Duration(seconds: 14, milliseconds: 900));
      expect(c.shown, isTrue);
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.shown, isFalse);
      expect(notified, 2);
    });

    testWithSemantics('touch restarts the 15 s; it does nothing while masked', (
      tester,
    ) async {
      final c = RevealController();
      addTearDown(c.dispose);
      c.touch();
      expect(c.shown, isFalse);

      c.show();
      await tester.pump(const Duration(seconds: 10));
      c.touch();
      await tester.pump(const Duration(seconds: 10));
      expect(c.shown, isTrue, reason: '10 s after the last interaction');
      await tester.pump(const Duration(seconds: 5, milliseconds: 100));
      expect(c.shown, isFalse);
    });

    testWithSemantics('hide masks at once and stops the clock', (tester) async {
      final c = RevealController();
      addTearDown(c.dispose);
      c.show();
      c.hide();
      expect(c.shown, isFalse);
      // Nothing is left to fire (and the test would fail on a pending timer).
      await tester.pump(const Duration(minutes: 1));
      expect(c.shown, isFalse);
    });

    testWithSemantics('dispose cancels the clock', (tester) async {
      final c = RevealController()..show();
      c.dispose();
      await tester.pump(const Duration(minutes: 1));
    });
  });

  group('PasswordField', () {
    late TextEditingController text;
    setUp(() => text = TextEditingController(text: secret));
    tearDown(() => text.dispose());

    TextField field(WidgetTester tester) =>
        tester.widget<TextField>(find.byType(TextField));

    testWithSemantics('is masked by default and the eye is 48 dp', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(PasswordField(controller: text, label: 'Password')),
      );
      expect(field(tester).obscureText, isTrue);
      expectSecretHidden(tester, secret);
      expect(find.text(secret), findsOneWidget, reason: 'the obscured field');

      final eye = find.widgetWithIcon(IconButton, Icons.visibility_outlined);
      expect(eye, findsOneWidget);
      final size = tester.getSize(eye);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(find.byTooltip('Show'), findsOneWidget);
    });

    testWithSemantics('the eye shows it; Hide masks it again', (tester) async {
      await tester.pumpWidget(
        app(PasswordField(controller: text, label: 'Password')),
      );
      await tester.tap(find.byTooltip('Show'));
      await tester.pump();
      expect(field(tester).obscureText, isFalse);
      expectSecretShown(tester, secret);
      expect(find.byTooltip('Hide'), findsOneWidget);
      expect(find.byTooltip('Show'), findsNothing);

      await tester.tap(find.byTooltip('Hide'));
      await tester.pump();
      expect(field(tester).obscureText, isTrue);
      expectSecretHidden(tester, secret);
    });

    testWithSemantics('is masked again after 15 s without interaction', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(PasswordField(controller: text, label: 'Password')),
      );
      await tester.tap(find.byTooltip('Show'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 14));
      expect(field(tester).obscureText, isFalse);
      await tester.pump(const Duration(seconds: 2));
      expect(field(tester).obscureText, isTrue);
      expectSecretHidden(tester, secret);
      expect(find.byTooltip('Show'), findsOneWidget);
    });

    testWithSemantics('typing keeps it revealed for another 15 s', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(PasswordField(controller: text, label: 'Password')),
      );
      await tester.tap(find.byTooltip('Show'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      await tester.enterText(find.byType(TextField), '${secret}x');
      await tester.pump(const Duration(seconds: 10));
      expect(field(tester).obscureText, isFalse, reason: '10 s after typing');
      await tester.pump(const Duration(seconds: 6));
      expect(field(tester).obscureText, isTrue);
    });

    testWithSemantics('a press inside a RevealBuilder keeps it revealed', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          RevealBuilder(
            builder: (context, reveal) => Column(
              children: [
                PasswordField(
                  controller: text,
                  label: 'Password',
                  reveal: reveal,
                ),
                const SizedBox(key: ValueKey('empty'), height: 40, width: 40),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Show'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      await tester.tap(
        find.byKey(const ValueKey('empty')),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(seconds: 10));
      expect(field(tester).obscureText, isFalse);
      await tester.pump(const Duration(seconds: 6));
      expect(field(tester).obscureText, isTrue);
    });

    testWithSemantics('editing works while it is masked', (tester) async {
      String? changed;
      await tester.pumpWidget(
        app(
          PasswordField(
            controller: text,
            label: 'Password',
            onChanged: (v) => changed = v,
          ),
        ),
      );
      expect(field(tester).obscureText, isTrue);
      await tester.enterText(find.byType(TextField), 'another-test-2');
      expect(text.text, 'another-test-2');
      expect(changed, 'another-test-2');
      expect(field(tester).obscureText, isTrue, reason: 'still masked');
    });

    testWithSemantics('a screen reader never hears the value', (tester) async {
      await tester.pumpWidget(
        app(PasswordField(controller: text, label: 'Password')),
      );
      expect(semanticStrings(tester), isNotEmpty);
      expectSecretHidden(tester, secret);
      // Nor the tooltip once it is shown on hover or long-press.
      await tester.longPress(find.byTooltip('Show'));
      await tester.pump(const Duration(seconds: 1));
      expectSecretHidden(tester, secret);
    });

    testWithSemantics(
      'leaving the screen drops the clock; a new field is masked',
      (tester) async {
        await tester.pumpWidget(
          app(PasswordField(controller: text, label: 'Password')),
        );
        await tester.tap(find.byTooltip('Show'));
        await tester.pump();
        expect(field(tester).obscureText, isFalse);

        await tester.pumpWidget(app(const SizedBox()));
        // No pending timer is left behind (the test would fail on one).
        await tester.pump(const Duration(seconds: 20));

        await tester.pumpWidget(
          app(PasswordField(controller: text, label: 'Password')),
        );
        expect(field(tester).obscureText, isTrue);
      },
    );

    testWithSemantics('extra actions sit after the eye', (tester) async {
      await tester.pumpWidget(
        app(
          PasswordField(
            controller: text,
            label: 'Password',
            actions: [
              IconButton(
                icon: const Icon(Icons.casino_outlined),
                tooltip: 'Dice',
                onPressed: () {},
              ),
            ],
          ),
        ),
      );
      final eye = tester.getCenter(find.byTooltip('Show'));
      final dice = tester.getCenter(find.byTooltip('Dice'));
      expect(dice.dx, greaterThan(eye.dx));
    });

    testWithSemantics('Arabic: right-aligned, left-to-right, Arabic tooltips', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          PasswordField(controller: text, label: 'كلمة المرور'),
          locale: const Locale('ar'),
        ),
      );
      final f = tester.widget<TextField>(find.byType(TextField));
      expect(f.obscureText, isTrue);
      expect(f.textDirection, TextDirection.ltr);
      expect(f.textAlign, TextAlign.right);
      expect(find.byTooltip('إظهار'), findsOneWidget);
      expectSecretHidden(tester, secret);

      await tester.tap(find.byTooltip('إظهار'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        false,
      );
      expect(find.byTooltip('إخفاء'), findsOneWidget);
      // The eye (the end of the field) is on the left in a right-to-left page.
      final field0 = tester.getRect(find.byType(TextField));
      expect(
        tester.getCenter(find.byTooltip('إخفاء')).dx,
        lessThan(field0.center.dx),
      );
    });
  });

  group('the helpers really catch a leak', () {
    final leaks = <String, Widget Function()>{
      'a field in clear': () =>
          TextField(controller: TextEditingController(text: secret)),
      'drawn text': () => const Text(secret),
      'a semantics label': () =>
          Semantics(label: secret, child: const SizedBox(width: 9, height: 9)),
      'a tooltip': () =>
          const Tooltip(message: secret, child: SizedBox(width: 9, height: 9)),
    };
    for (final MapEntry(key: name, value: build) in leaks.entries) {
      testWithSemantics(name, (tester) async {
        await tester.pumpWidget(app(build()));
        expect(
          () => expectSecretHidden(tester, secret),
          throwsA(isA<TestFailure>()),
        );
      });
    }
  });

  group('a masked SecretText', () {
    testWithSemantics(
      'says "Password hidden" in English and Arabic, no value',
      (tester) async {
        for (final (locale, words) in [
          (const Locale('en'), 'Password hidden'),
          (const Locale('ar'), 'كلمة المرور مخفية'),
        ]) {
          await tester.pumpWidget(
            app(const SecretText(secret, obscure: true), locale: locale),
          );
          expect(find.bySemanticsLabel(words), findsOneWidget);
          expectSecretHidden(tester, secret);
        }
      },
    );
  });
}
