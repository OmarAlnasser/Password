import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/autofill_app.dart';
import 'package:hisn/data/models/vault_entry.dart';
import 'package:hisn/ui/app_scope.dart';

import 'helpers.dart';

/// The Android autofill picker: filling an entry counts as using it for the
/// "Recently used" order, and the time is stored before the vault locks.
/// Every login is synthetic.
void main() {
  late Directory dir;
  late AppServices services;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vs_autofill');
    services = await buildTestServices(dir);
  });
  tearDown(() async {
    await services.session.lock();
    dir.deleteSync(recursive: true);
  });

  testWidgets('filling an entry marks it used, then locks', (tester) async {
    final calls = <MethodCall>[];
    mockChannel(tester, const MethodChannel('app.vaultsnap/autofill'), (
      call,
    ) async {
      calls.add(call);
      return switch (call.method) {
        'getRequest' => {'package': null, 'domain': 'login.example.test'},
        _ => null,
      };
    });
    final session = services.session;
    await tester.runAsync(() async {
      await session.init();
      await session.createVault(testMasterPassword);
      await session.saveEntries([
        VaultEntry(
          id: 'match',
          title: 'Example Login',
          username: 'someone@example.test',
          password: 'hunter-test-1',
          url: 'https://example.test',
        ),
        VaultEntry(
          id: 'other',
          title: 'Other Site',
          password: 'hunter-test-2',
          url: 'https://other.test',
        ),
      ]);
    });

    await tester.pumpWidget(AutofillApp(services: services));
    await tester.pumpAndSettle();
    expect(find.text('Example Login'), findsOneWidget);
    expect(find.text('Other Site'), findsNothing);
    expect(session.lastUsedAt('match'), isNull);

    await tester.runAsync(() async {
      await tester.tap(find.text('Example Login'));
      for (var i = 0; i < 100 && session.isUnlocked; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();

    final fill = calls.singleWhere((c) => c.method == 'fill');
    expect((fill.arguments as Map)['username'], 'someone@example.test');
    expect(session.isUnlocked, isFalse);

    // The time was written before the lock: it is there after unlocking.
    await tester.runAsync(() => session.unlockWithPassword(testMasterPassword));
    expect(session.lastUsedAt('match'), isNotNull);
    expect(session.lastUsedAt('other'), isNull);
    // Unmount before the tear-down locks the vault.
    await tester.pumpWidget(const SizedBox());
  });
}
