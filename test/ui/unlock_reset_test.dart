import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultsnap/app.dart';
import 'package:vaultsnap/services/vault_session.dart';
import 'package:vaultsnap/ui/app_scope.dart';

import 'helpers.dart';

/// "Forgot password?" on the unlock screen: nobody can recover the master
/// password; the user can use the recovery key or erase the vault.
void main() {
  late Directory dir;
  late AppServices services;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vs_reset');
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
    await tester.pumpWidget(VaultSnapApp(services: services));
    await tester.pumpAndSettle();
  }

  File header() => File('${dir.path}/vault_header.json');
  File database() => File('${dir.path}/vault.db');

  testWidgets('the recovery key option switches to recovery mode', (
    tester,
  ) async {
    await lockedVault(tester);
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('not even the VaultSnap developer'),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Use recovery key'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.widgetWithText(TextField, 'Recovery key'), findsOneWidget);
    expect(find.text('Forgot password?'), findsNothing);
  });

  testWidgets('reset erases the vault only after typing DELETE', (
    tester,
  ) async {
    await lockedVault(tester);
    Future<void> openReset() async {
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset vault — erase everything'));
      await tester.pumpAndSettle();
      expect(find.text('Erase this vault?'), findsOneWidget);
    }

    VoidCallback? erase() => tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Erase vault'))
        .onPressed;
    final word = find.widgetWithText(TextField, 'Type DELETE to confirm');

    // Cancel keeps everything.
    await openReset();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(header().existsSync(), isTrue);
    expect(services.session.state, VaultState.locked);

    await openReset();
    expect(erase(), isNull);
    for (final wrong in ['', 'DELET', 'erase', 'حذف']) {
      await tester.enterText(word, wrong);
      await tester.pump();
      expect(erase(), isNull, reason: wrong);
    }
    await tester.enterText(word, 'DELETE');
    await tester.pump();
    expect(erase(), isNotNull);
    expect(header().existsSync(), isTrue);

    // Wrong guesses at the forgotten password.
    await tester.runAsync(() async {
      for (var i = 0; i < 5; i++) {
        await services.session.throttle.recordFailure();
      }
    });
    await tester.runAsync(() => tester.tap(find.text('Erase vault')));
    await pumpUntilFound(tester, find.text('Create your vault'));
    await tester.pumpAndSettle();
    expect(find.text('Create your vault'), findsOneWidget);
    expect(services.session.state, VaultState.noVault);
    expect(header().existsSync(), isFalse);
    expect(database().existsSync(), isFalse);
    // The new vault does not inherit the old back-off.
    expect(services.session.throttle.failures, 0);
    expect(services.session.throttle.remaining, Duration.zero);
  });

  testWidgets('in Arabic the confirmation word is حذف, or DELETE', (
    tester,
  ) async {
    await tester.runAsync(
      () => services.settings.update((s) => s.locale = const Locale('ar')),
    );
    await lockedVault(tester);
    await tester.tap(find.text('نسيت كلمة المرور؟'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إعادة تعيين الخزنة — مسح كل شيء'));
    await tester.pumpAndSettle();

    VoidCallback? erase() => tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'مسح الخزنة'))
        .onPressed;
    final word = find.widgetWithText(TextField, 'اكتب «حذف» للتأكيد');
    await tester.enterText(word, 'حذ');
    await tester.pump();
    expect(erase(), isNull);
    await tester.enterText(word, 'حذف');
    await tester.pump();
    expect(erase(), isNotNull);
    // Without an Arabic keyboard layout the English word works too.
    await tester.enterText(word, 'delete');
    await tester.pump();
    expect(erase(), isNotNull);

    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(header().existsSync(), isTrue);
  });
}
