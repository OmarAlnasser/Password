import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/app.dart';
import 'package:hisn/ui/app_scope.dart';

import 'helpers.dart';

void main() {
  late Directory dir;
  late AppServices services;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vs_ui');
    services = await buildTestServices(dir);
  });
  tearDown(() async {
    // Close the vault (and its drift isolate) before removing its files.
    await services.session.lock();
    dir.deleteSync(recursive: true);
  });

  testWidgets('first run: create vault, confirm recovery key, see empty list', (
    tester,
  ) async {
    await tester.runAsync(() => services.session.init());
    await tester.pumpWidget(HisnApp(services: services));
    await tester.pumpAndSettle();
    expect(find.text('Create your vault'), findsOneWidget);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'weak');
    await tester.enterText(fields.at(1), 'weak');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.textContaining('stronger password'), findsOneWidget);

    const strong = 'violet-harbor-quantum-71-lantern';
    await tester.enterText(fields.at(0), strong);
    await tester.enterText(fields.at(1), strong);
    // The error above pushed the button below the 600 px test window; the
    // form scrolls, so scroll to it as a user would.
    await tester.ensureVisible(find.text('Create'));
    // Argon2id and the database run on real isolates.
    await tester.runAsync(() => tester.tap(find.text('Create')));
    await pumpUntilFound(tester, find.text('Your recovery key'));
    await tester.pumpAndSettle();
    expect(find.text('Your recovery key'), findsOneWidget);
    final saved = find.widgetWithText(FilledButton, 'I saved it');
    expect(tester.widget<FilledButton>(saved).onPressed, isNull);
  });

  testWidgets('Arabic locale lays out right-to-left', (tester) async {
    await tester.runAsync(() async {
      await services.session.init();
      await services.settings.update((s) => s.locale = const Locale('ar'));
    });
    await tester.pumpWidget(HisnApp(services: services));
    await tester.pumpAndSettle();
    expect(find.text('أنشئ خزنتك'), findsOneWidget);
    final dir = Directionality.of(tester.element(find.byType(TextField).first));
    expect(dir, TextDirection.rtl);
  });

  testWidgets('locked vault shows unlock screen; wrong password errors', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await services.session.init();
      await services.session.createVault('violet-harbor-quantum-71-lantern');
      await services.session.lock();
    });
    await tester.pumpWidget(HisnApp(services: services));
    await tester.pumpAndSettle();
    expect(find.text('Unlock'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'nope');
    await tester.runAsync(() => tester.tap(find.text('Unlock')));
    await pumpUntilFound(tester, find.text('Wrong password'));
    await tester.pumpAndSettle();
    expect(find.text('Wrong password'), findsOneWidget);
    expect(services.session.isUnlocked, isFalse);
  });
}
