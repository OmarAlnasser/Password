import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/app.dart';
import 'package:hisn/services/vault_session.dart';
import 'package:hisn/ui/app_scope.dart';

import 'helpers.dart';

/// The real way in, through the unlock screen's own fields: the master
/// password, and the recovery key typed the ways people actually type it.
void main() {
  late Directory dir;
  late AppServices services;
  late String recoveryKey;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vs_unlock_creds');
    services = await buildTestServices(dir);
  });
  tearDown(() async {
    await services.session.lock();
    dir.deleteSync(recursive: true);
  });

  Future<void> lockedVault(WidgetTester tester) async {
    await tester.runAsync(() async {
      await services.session.init();
      final created = await services.session.createVault(testMasterPassword);
      recoveryKey = created.recoveryKeyText;
      await services.session.lock();
    });
    await tester.pumpWidget(HisnApp(services: services));
    await tester.pumpAndSettle();
  }

  Future<void> useRecoveryKeyMode(WidgetTester tester) async {
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Use recovery key'),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester, String label, String text) async {
    await tester.enterText(find.widgetWithText(TextField, label), text);
    await tester.pump();
    final unlock = find.widgetWithText(FilledButton, 'Unlock');
    await tester.ensureVisible(unlock);
    await tester.pump();
    await tester.runAsync(() => tester.tap(unlock));
    // Argon2id and the database open run on real time, not fake time. The
    // home screen never stops animating, so pump instead of settling.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 6)),
    );
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('the master password opens the vault', (tester) async {
    await lockedVault(tester);
    await submit(tester, 'Master password', testMasterPassword);
    expect(services.session.state, VaultState.unlocked);
  });

  testWidgets('a wrong master password is refused', (tester) async {
    await lockedVault(tester);
    await submit(tester, 'Master password', '${testMasterPassword}x');
    expect(services.session.state, VaultState.locked);
  });

  final variants = <String, String Function(String)>{
    'exactly as shown': (k) => k,
    'lower case': (k) => k.toLowerCase(),
    'without dashes': (k) => k.replaceAll('-', ''),
    'with spaces instead of dashes': (k) => k.replaceAll('-', ' '),
    'with surrounding spaces': (k) => '  $k  ',
  };
  for (final entry in variants.entries) {
    testWidgets('the recovery key opens the vault: ${entry.key}', (
      tester,
    ) async {
      await lockedVault(tester);
      await useRecoveryKeyMode(tester);
      await submit(tester, 'Recovery key', entry.value(recoveryKey));
      expect(services.session.state, VaultState.unlocked);
    });
  }

  testWidgets('a recovery key with one wrong character is refused', (
    tester,
  ) async {
    await lockedVault(tester);
    await useRecoveryKeyMode(tester);
    final chars = recoveryKey.split('');
    final i = chars.indexWhere((c) => c != '-');
    chars[i] = chars[i] == '2' ? '3' : '2';
    await submit(tester, 'Recovery key', chars.join());
    expect(services.session.state, VaultState.locked);
  });
}
