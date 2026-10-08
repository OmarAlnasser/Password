/// Render-and-look pictures of the first-impression screens (lock, setup,
/// recovery key, recovery reset, sign in). Skipped by default; run with
///
/// ```sh
/// SHOTS_DIR=/some/dir flutter test --run-skipped -t screenshots test/ui/auth_shots_test.dart
/// ```
///
/// Fake data only. Nothing is asserted: a `RenderFlex overflowed` error fails
/// the test, which is the point.
@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/l10n/app_localizations.dart';
import 'package:hisn/services/biometric_unlock.dart';
import 'package:hisn/ui/app_scope.dart';
import 'package:hisn/ui/recovery_reset_screen.dart';
import 'package:hisn/ui/setup_screen.dart';
import 'package:hisn/ui/sign_in_screen.dart';
import 'package:hisn/ui/unlock_screen.dart';

import '../tool/screenshot_harness.dart';
import 'helpers.dart';

/// A made-up key in the real format (Crockford, 11 groups of 5).
const _fakeKey =
    '7K2QM-X9D4B-HT6WZ-3F8RE-NP5YA-J1C0V-G4SXD-M7T2Q-9BHK6-W3ZFE-R5N8P';

const _pw = 'xQmR42abCD5k';

/// The strings of the language the screen is shown in.
AppLocalizations _l(WidgetTester t, Type screen) =>
    AppLocalizations.of(t.element(find.byType(screen)));

void main() {
  late Directory dir;
  late AppServices services;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vs_auth_shots');
    services = await buildTestServices(dir);
  });
  tearDown(() async {
    await services.session.lock();
    dir.deleteSync(recursive: true);
  });

  Widget Function(Widget) scope() =>
      (app) => AppScope(services: services, child: app);

  Future<void> lockedVault(WidgetTester tester) async {
    await tester.runAsync(() async {
      await services.session.init();
      await services.session.createVault(testMasterPassword);
      await services.session.lock();
    });
  }

  const phoneAndDesktop = [ShotSize.phone, ShotSize.desktop];

  testWidgets('unlock', (tester) async {
    await lockedVault(tester);
    await pumpScreenshots(
      tester,
      const UnlockScreen(),
      'unlock',
      wrap: scope(),
    );
    await pumpScreenshots(
      tester,
      const UnlockScreen(),
      'unlock-x15',
      sizes: [ShotSize.narrow],
      textScale: 1.5,
      wrap: scope(),
    );
  });

  testWidgets('unlock: typed and revealed, recovery mode', (tester) async {
    await lockedVault(tester);
    await pumpScreenshots(
      tester,
      const UnlockScreen(),
      'unlock-typed',
      sizes: [ShotSize.phone],
      wrap: scope(),
      afterPump: (t) async {
        await t.enterText(find.byType(TextField), _pw);
        await t.pump();
      },
    );
    await pumpScreenshots(
      tester,
      const UnlockScreen(),
      'unlock-revealed',
      sizes: [ShotSize.phone],
      wrap: scope(),
      afterPump: (t) async {
        await t.enterText(find.byType(TextField), _pw);
        await t.tap(find.byType(IconButton));
        await t.pump();
      },
    );
    await pumpScreenshots(
      tester,
      const UnlockScreen(),
      'unlock-recovery',
      sizes: phoneAndDesktop,
      wrap: scope(),
      afterPump: (t) async {
        await t.ensureVisible(
          find.text(_l(t, UnlockScreen).useRecoveryKey).first,
        );
        await t.tap(find.text(_l(t, UnlockScreen).useRecoveryKey).first);
        await t.pump();
        await t.enterText(find.byType(TextField), 'x7k2qm-x9d4b');
        await t.pump();
      },
    );
  });

  testWidgets('unlock: with the biometric button', (tester) async {
    await lockedVault(tester);
    await tester.runAsync(
      () => services.settings.update((s) => s.biometricsEnabled = true),
    );
    final withBio = AppServices(
      session: services.session,
      settings: services.settings,
      clipboard: services.clipboard,
      generator: services.generator,
      strength: services.strength,
      importExport: services.importExport,
      bridge: services.bridge,
      breaches: services.breaches,
      biometrics: _FakeBiometrics(dir),
      favicons: services.favicons,
    );
    await pumpScreenshots(
      tester,
      const UnlockScreen(),
      'unlock-bio',
      sizes: [ShotSize.phone],
      wrap: (app) => AppScope(services: withBio, child: app),
    );
  });

  testWidgets('unlock: throttled', (tester) async {
    await lockedVault(tester);
    await tester.runAsync(() async {
      for (var i = 0; i < 10; i++) {
        await services.session.throttle.recordFailure();
      }
    });
    await pumpScreenshots(
      tester,
      const UnlockScreen(),
      'unlock-throttled',
      wrap: scope(),
    );
    await pumpScreenshots(
      tester,
      const UnlockScreen(),
      'unlock-throttled-x15',
      sizes: [ShotSize.narrow],
      textScale: 1.5,
      wrap: scope(),
    );
  });

  testWidgets('unlock: wrong password', (tester) async {
    await lockedVault(tester);
    await pumpScreenshots(
      tester,
      const UnlockScreen(),
      'unlock-error',
      sizes: [ShotSize.phone],
      wrap: scope(),
      afterPump: (t) async {
        await t.enterText(find.byType(TextField), 'nope');
        await t.runAsync(
          () => t.tap(find.text(_l(t, UnlockScreen).unlock).last),
        );
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1500)),
        );
        await t.pump();
      },
    );
  });

  testWidgets('unlock: forgot-password dialog and reset confirmation', (
    tester,
  ) async {
    await lockedVault(tester);
    await pumpScreenshots(
      tester,
      const UnlockScreen(),
      'unlock-forgot',
      wrap: scope(),
      afterPump: (t) async {
        await t.ensureVisible(find.text(_l(t, UnlockScreen).forgotPassword));
        await t.tap(find.text(_l(t, UnlockScreen).forgotPassword));
        await t.pump();
      },
    );
    await pumpScreenshots(
      tester,
      const UnlockScreen(),
      'unlock-forgot-x15',
      sizes: [ShotSize.narrow],
      textScale: 1.5,
      themes: [Brightness.dark],
      wrap: scope(),
      afterPump: (t) async {
        await t.ensureVisible(find.text(_l(t, UnlockScreen).forgotPassword));
        await t.tap(find.text(_l(t, UnlockScreen).forgotPassword));
        await t.pump();
      },
    );
    await pumpScreenshots(
      tester,
      const UnlockScreen(),
      'unlock-reset',
      wrap: scope(),
      afterPump: (t) async {
        await t.ensureVisible(find.text(_l(t, UnlockScreen).forgotPassword));
        await t.tap(find.text(_l(t, UnlockScreen).forgotPassword));
        await t.pump(const Duration(seconds: 1));
        await t.ensureVisible(find.byIcon(Icons.delete_forever_rounded));
        await t.tap(find.byIcon(Icons.delete_forever_rounded));
        await t.pump();
      },
    );
    await pumpScreenshots(
      tester,
      const UnlockScreen(),
      'unlock-reset-armed',
      sizes: [ShotSize.phone],
      wrap: scope(),
      afterPump: (t) async {
        await t.ensureVisible(find.text(_l(t, UnlockScreen).forgotPassword));
        await t.tap(find.text(_l(t, UnlockScreen).forgotPassword));
        await t.pump(const Duration(seconds: 1));
        await t.ensureVisible(find.byIcon(Icons.delete_forever_rounded));
        await t.tap(find.byIcon(Icons.delete_forever_rounded));
        await t.pump(const Duration(seconds: 1));
        await t.enterText(find.byType(TextField).last, 'DELETE');
        await t.pump();
      },
    );
    await pumpScreenshots(
      tester,
      const UnlockScreen(),
      'unlock-reset-x15',
      sizes: [ShotSize.narrow],
      textScale: 1.5,
      themes: [Brightness.dark],
      wrap: scope(),
      afterPump: (t) async {
        await t.ensureVisible(find.text(_l(t, UnlockScreen).forgotPassword));
        await t.tap(find.text(_l(t, UnlockScreen).forgotPassword));
        await t.pump(const Duration(seconds: 1));
        await t.ensureVisible(find.byIcon(Icons.delete_forever_rounded));
        await t.tap(find.byIcon(Icons.delete_forever_rounded));
        await t.pump();
      },
    );
  });

  testWidgets('setup', (tester) async {
    await tester.runAsync(() => services.session.init());
    await pumpScreenshots(tester, const SetupScreen(), 'setup', wrap: scope());
    await pumpScreenshots(
      tester,
      const SetupScreen(),
      'setup-x15',
      sizes: [ShotSize.narrow],
      textScale: 1.5,
      wrap: scope(),
    );
    await pumpScreenshots(
      tester,
      const SetupScreen(),
      'setup-x2',
      sizes: [ShotSize.narrow],
      textScale: 2,
      themes: [Brightness.dark],
      wrap: scope(),
    );
  });

  testWidgets('setup: typed, mismatch error', (tester) async {
    await tester.runAsync(() => services.session.init());
    await pumpScreenshots(
      tester,
      const SetupScreen(),
      'setup-typed',
      sizes: phoneAndDesktop,
      wrap: scope(),
      afterPump: (t) async {
        final fields = find.byType(TextField);
        await t.enterText(fields.at(0), _pw);
        await t.enterText(fields.at(1), 'xQmR42abCD');
        await t.pump();
        await t.ensureVisible(find.text(_l(t, SetupScreen).create));
        await t.tap(find.text(_l(t, SetupScreen).create));
        await t.pump();
      },
    );
  });

  testWidgets('recovery key', (tester) async {
    await tester.runAsync(() => services.session.init());
    await pumpScreenshots(
      tester,
      const RecoveryKeyScreen(recoveryKey: _fakeKey),
      'recoverykey',
      wrap: scope(),
    );
    await pumpScreenshots(
      tester,
      const RecoveryKeyScreen(recoveryKey: _fakeKey),
      'recoverykey-x15',
      sizes: [ShotSize.narrow],
      textScale: 1.5,
      wrap: scope(),
    );
    await pumpScreenshots(
      tester,
      const RecoveryKeyScreen(recoveryKey: _fakeKey),
      'recoverykey-ok',
      sizes: phoneAndDesktop,
      wrap: scope(),
      afterPump: (t) async {
        await t.enterText(find.byType(TextField), 'r5n8p');
        await t.pump();
      },
    );
  });

  testWidgets('recovery reset', (tester) async {
    await tester.runAsync(() => services.session.init());
    await pumpScreenshots(
      tester,
      const RecoveryResetScreen(),
      'recoveryreset',
      wrap: scope(),
    );
    await pumpScreenshots(
      tester,
      const RecoveryResetScreen(),
      'recoveryreset-typed',
      sizes: [ShotSize.phone],
      wrap: scope(),
      afterPump: (t) async {
        final fields = find.byType(TextField);
        await t.enterText(fields.at(0), _pw);
        await t.enterText(fields.at(1), _pw);
        await t.pump();
      },
    );
  });

  testWidgets('sign in', (tester) async {
    await tester.runAsync(() => services.session.init());
    await pumpScreenshots(
      tester,
      const SignInScreen(),
      'signin',
      wrap: scope(),
    );
    await pumpScreenshots(
      tester,
      const SignInScreen(enableForLocal: true),
      'signin-enable',
      sizes: [ShotSize.phone],
      wrap: scope(),
      afterPump: (t) async {
        final fields = find.byType(TextField);
        await t.enterText(fields.at(0), 'abcde07@hotmail.com');
        await t.enterText(fields.at(1), _pw);
        await t.pump();
        // No sync service in the test services: one generic failure.
        await t.ensureVisible(find.text(_l(t, SignInScreen).enableSync).last);
        await t.tap(find.text(_l(t, SignInScreen).enableSync).last);
        await t.pump();
      },
    );
    await pumpScreenshots(
      tester,
      const SignInScreen(),
      'signin-x15',
      sizes: [ShotSize.narrow],
      textScale: 1.5,
      wrap: scope(),
    );
  });
}

/// Says yes to everything, so the lock screen shows its biometric button.
class _FakeBiometrics extends BiometricUnlock {
  _FakeBiometrics(super.directory);

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> get isEnabled async => true;
}
