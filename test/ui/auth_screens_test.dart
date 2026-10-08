import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/app.dart';
import 'package:hisn/brand.dart';
import 'package:hisn/l10n/app_localizations.dart';
import 'package:hisn/ui/app_scope.dart';
import 'package:hisn/ui/recovery_reset_screen.dart';
import 'package:hisn/ui/setup_screen.dart';
import 'package:hisn/ui/sign_in_screen.dart';
import 'package:hisn/ui/theme/app_theme.dart';
import 'package:hisn/ui/unlock_screen.dart';
import 'package:hisn/ui/widgets/app_shell.dart';
import 'package:hisn/ui/widgets/strength_bar.dart';

import 'helpers.dart';

/// The first-impression screens (lock, setup, recovery key, recovery reset,
/// sign in): what the redesign added on top of the flows that
/// `app_flow_test.dart` and `unlock_reset_test.dart` already cover.
void main() {
  late Directory dir;
  late AppServices services;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vs_auth');
    services = await buildTestServices(dir);
  });
  tearDown(() async {
    await services.session.lock();
    dir.deleteSync(recursive: true);
  });

  Future<void> lockedVault(WidgetTester tester) async {
    await tester.runAsync(() async {
      await services.session.init();
      await services.session.createVault(testMasterPassword);
      await services.session.lock();
    });
  }

  Future<void> setLocale(WidgetTester tester, Locale locale) => tester
      .runAsync(() => services.settings.update((s) => s.locale = locale))
      .then((_) {});

  /// A bare app around one screen, themed and localised like the real one.
  Widget host(
    Widget home, {
    Locale locale = const Locale('en'),
    Brightness brightness = Brightness.dark,
  }) => AppScope(
    services: services,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
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
      builder: (context, child) => AppShell(child: child!),
      home: home,
    ),
  );

  TextField field(WidgetTester tester, [int index = 0]) =>
      tester.widget<TextField>(find.byType(TextField).at(index));

  group('lock screen', () {
    testWidgets('shows the app name from brand.dart', (tester) async {
      await lockedVault(tester);
      await tester.pumpWidget(HisnApp(services: services));
      await tester.pumpAndSettle();
      expect(find.text(appName), findsOneWidget);
      expect(find.text(appTagline), findsOneWidget);
    });

    testWidgets('the eye shows the password and masks it again', (
      tester,
    ) async {
      await lockedVault(tester);
      await tester.pumpWidget(HisnApp(services: services));
      await tester.pumpAndSettle();
      expect(field(tester).obscureText, isTrue);
      expect(find.byTooltip('Hide'), findsNothing);

      await tester.tap(find.byTooltip('Show'));
      await tester.pump();
      expect(field(tester).obscureText, isFalse);
      expect(find.byTooltip('Hide'), findsOneWidget);

      await tester.tap(find.byTooltip('Hide'));
      await tester.pump();
      expect(field(tester).obscureText, isTrue);

      // Left open, it closes by itself.
      await tester.tap(find.byTooltip('Show'));
      await tester.pump();
      expect(field(tester).obscureText, isFalse);
      await tester.pump(const Duration(seconds: 14));
      expect(field(tester).obscureText, isFalse);
      await tester.pump(const Duration(seconds: 2));
      expect(field(tester).obscureText, isTrue);
    });

    testWidgets('typing keeps a revealed password revealed', (tester) async {
      await lockedVault(tester);
      await tester.pumpWidget(HisnApp(services: services));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show'));
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 10));
        await tester.enterText(find.byType(TextField), 'abc$i');
      }
      expect(field(tester).obscureText, isFalse);
    });

    testWidgets('the password is left-to-right at the start edge', (
      tester,
    ) async {
      await lockedVault(tester);
      await tester.pumpWidget(HisnApp(services: services));
      await tester.pumpAndSettle();
      expect(field(tester).textDirection, TextDirection.ltr);
      expect(field(tester).textAlign, TextAlign.left);
    });

    testWidgets('in Arabic it is still left-to-right, at the right edge', (
      tester,
    ) async {
      await setLocale(tester, const Locale('ar'));
      await lockedVault(tester);
      await tester.pumpWidget(HisnApp(services: services));
      await tester.pumpAndSettle();
      expect(field(tester).textDirection, TextDirection.ltr);
      expect(field(tester).textAlign, TextAlign.right);
    });

    testWidgets('a wrong password is explained under the field', (
      tester,
    ) async {
      await lockedVault(tester);
      await tester.pumpWidget(HisnApp(services: services));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'nope');
      await tester.runAsync(() => tester.tap(find.text('Unlock')));
      await pumpUntilFound(tester, find.text('Wrong password'));
      await tester.pumpAndSettle();
      expect(find.text('Wrong password'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      // The first wrong guess is free: no countdown.
      expect(find.textContaining('Too many attempts'), findsNothing);
    });

    testWidgets('while throttled a countdown pill shows and Unlock is off', (
      tester,
    ) async {
      await lockedVault(tester);
      await tester.runAsync(() async {
        for (var i = 0; i < 6; i++) {
          await services.session.throttle.recordFailure();
        }
      });
      await tester.pumpWidget(HisnApp(services: services));
      await tester.pumpAndSettle();
      expect(find.textContaining('Too many attempts'), findsOneWidget);
      final unlock = find.widgetWithText(FilledButton, 'Unlock');
      expect(tester.widget<FilledButton>(unlock).onPressed, isNull);
      final seconds = RegExp(
        r'(\d+)s',
      ).firstMatch(tester.widget<Text>(find.textContaining('Too many')).data!);
      // 6 failures = 3 free + 8 s.
      expect(int.parse(seconds!.group(1)!), inInclusiveRange(1, 8));
    });

    testWidgets('recovery mode shows the key in capitals, as plain text', (
      tester,
    ) async {
      await lockedVault(tester);
      await tester.pumpWidget(HisnApp(services: services));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use recovery key'));
      await tester.pumpAndSettle();
      expect(field(tester).obscureText, isFalse);
      expect(field(tester).textCapitalization, TextCapitalization.characters);
      // No eye on a field that is not masked.
      expect(find.byTooltip('Show'), findsNothing);
      expect(find.text('Master password'), findsOneWidget);
    });

    testWidgets('the forgot-password options are big enough to hit', (
      tester,
    ) async {
      await lockedVault(tester);
      await tester.pumpWidget(HisnApp(services: services));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      for (final option in [
        'Use recovery key',
        'Reset vault — erase everything',
      ]) {
        final tile = find.ancestor(
          of: find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text(option),
          ),
          matching: find.byType(InkWell),
        );
        expect(tile, findsOneWidget, reason: option);
        expect(
          tester.getSize(tile).height,
          greaterThanOrEqualTo(64),
          reason: option,
        );
      }
    });

    testWidgets(
      'meets the tap-target and contrast guidelines, dark and light',
      (tester) async {
        await lockedVault(tester);
        final handle = tester.ensureSemantics();
        for (final b in [Brightness.dark, Brightness.light]) {
          await tester.pumpWidget(host(const UnlockScreen(), brightness: b));
          await tester.pumpAndSettle();
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
        }
        handle.dispose();
      },
    );
  });

  group('setup', () {
    testWidgets('rates the password only once something is typed', (
      tester,
    ) async {
      await tester.runAsync(() => services.session.init());
      await tester.pumpWidget(HisnApp(services: services));
      await tester.pumpAndSettle();
      expect(find.byType(StrengthBar), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'weak');
      await tester.pumpAndSettle();
      expect(find.byType(StrengthBar), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pumpAndSettle();
      expect(find.byType(StrengthBar), findsNothing);
    });

    testWidgets('each field has its own eye', (tester) async {
      await tester.runAsync(() => services.session.init());
      await tester.pumpWidget(HisnApp(services: services));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Show'), findsNWidgets(2));
      await tester.tap(find.byTooltip('Show').first);
      await tester.pump();
      expect(field(tester, 0).obscureText, isFalse);
      expect(field(tester, 1).obscureText, isTrue);
    });

    testWidgets('a mismatch is said once, with an icon, and marks the field', (
      tester,
    ) async {
      await tester.runAsync(() => services.session.init());
      await tester.pumpWidget(HisnApp(services: services));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'one');
      await tester.enterText(find.byType(TextField).at(1), 'two');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets(
      'meets the tap-target and contrast guidelines, dark and light',
      (tester) async {
        await tester.runAsync(() => services.session.init());
        final handle = tester.ensureSemantics();
        for (final b in [Brightness.dark, Brightness.light]) {
          await tester.pumpWidget(host(const SetupScreen(), brightness: b));
          await tester.pumpAndSettle();
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
        }
        handle.dispose();
      },
    );

    testWidgets('does not overflow at 200% text on a small phone', (
      tester,
    ) async {
      await tester.runAsync(() => services.session.init());
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final locale in const [Locale('en'), Locale('ar')]) {
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: host(const SetupScreen(), locale: locale),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('recovery key', () {
    // A made-up key in the real format; the last group has look-alikes.
    const key =
        '7K2QM-X9D4B-HT6WZ-3F8RE-NP5YA-J1C0V-G4SXD-M7T2Q-9BHK6-W3ZFE-J1C0V';

    Future<void> pumpKey(WidgetTester tester, {Locale? locale}) async {
      await tester.pumpWidget(
        host(
          const RecoveryKeyScreen(recoveryKey: key),
          locale: locale ?? const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lists the eleven groups, numbered, left-to-right', (
      tester,
    ) async {
      await pumpKey(tester);
      for (final g in key.split('-').toSet()) {
        expect(find.text(g), findsWidgets);
      }
      expect(find.text('11'), findsOneWidget);
      final first = tester.getTopLeft(find.text('7K2QM'));
      final second = tester.getTopLeft(find.text('X9D4B'));
      expect(first.dx, lessThan(second.dx));
    });

    testWidgets('in Arabic the groups still run left-to-right', (tester) async {
      await pumpKey(tester, locale: const Locale('ar'));
      final first = tester.getTopLeft(find.text('7K2QM'));
      final second = tester.getTopLeft(find.text('X9D4B'));
      expect(first.dx, lessThan(second.dx));
      expect(first.dy, second.dy);
    });

    testWidgets('I saved it needs the last group; look-alikes and case pass', (
      tester,
    ) async {
      await pumpKey(tester);
      VoidCallback? saved() => tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'I saved it'))
          .onPressed;
      expect(saved(), isNull);
      await tester.enterText(find.byType(TextField), 'J1C0W');
      await tester.pump();
      expect(saved(), isNull);
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
      await tester.enterText(find.byType(TextField), ' jIcOV ');
      await tester.pump();
      expect(saved(), isNotNull);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('Copy copies the key and says when the clipboard clears', (
      tester,
    ) async {
      final copied = <Map<Object?, Object?>>[];
      mockChannel(tester, platformChannel, (call) async {
        if (call.method == 'copySensitive') {
          copied.add(call.arguments as Map<Object?, Object?>);
          return true;
        }
        return null;
      });
      await pumpKey(tester);
      await tester.runAsync(() async {
        await tester.tap(find.text('Copy'));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(copied, hasLength(1));
      expect(copied.single['text'], key);
      expect(
        find.text(
          'Copied. Clipboard clears in '
          '${services.settings.clipboardClearSeconds}s',
        ),
        findsOneWidget,
      );
      // The toast never shows the key.
      expect(find.textContaining(key), findsNothing);
      await tester.runAsync(services.clipboard.clearNow);
    });

    testWidgets('cannot be dismissed with the back button', (tester) async {
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const RecoveryKeyScreen(recoveryKey: key),
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
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Your recovery key'), findsOneWidget);
    });

    testWidgets('does not overflow at 200% text, dark and light', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final b in [Brightness.dark, Brightness.light]) {
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: host(
              const RecoveryKeyScreen(recoveryKey: key),
              brightness: b,
              locale: const Locale('ar'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('recovery reset and sign in', () {
    testWidgets('recovery reset: the same fields as setup, Save is a button', (
      tester,
    ) async {
      await tester.pumpWidget(host(const RecoveryResetScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), 'one');
      await tester.enterText(find.byType(TextField).at(1), 'two');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Passwords do not match'), findsOneWidget);
    });

    testWidgets('sign in: email is left-to-right, one generic failure', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const SignInScreen(), locale: const Locale('ar')),
      );
      await tester.pumpAndSettle();
      expect(field(tester, 0).keyboardType, TextInputType.emailAddress);
      expect(field(tester, 0).textDirection, TextDirection.ltr);
      expect(field(tester, 0).textAlign, TextAlign.right);
      // Without a sync service the test services fail the same way a
      // wrong password or unknown email does.
      await tester.enterText(
        find.byType(TextField).at(0),
        'abcde07@hotmail.com',
      );
      await tester.enterText(find.byType(TextField).at(1), 'xQmR42abCD5k');
      await tester.tap(find.widgetWithText(FilledButton, 'فتح'));
      await tester.pumpAndSettle();
      expect(find.text('فشلت المزامنة'), findsOneWidget);
    });

    testWidgets('sign in, pushed from setup, has a back button; the forced '
        'recovery reset has none', (tester) async {
      await tester.runAsync(() => services.session.init());
      await tester.pumpWidget(host(const SetupScreen()));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Sign in to an existing vault'));
      await tester.tap(find.text('Sign in to an existing vault'));
      await tester.pumpAndSettle();
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(SignInScreen), findsNothing);

      await tester.pumpWidget(host(const RecoveryResetScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(BackButton), findsNothing);
    });
  });
}
