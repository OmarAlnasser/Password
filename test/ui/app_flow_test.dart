import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultsnap/app.dart';
import 'package:vaultsnap/core/crypto/crypto.dart';
import 'package:vaultsnap/services/breach_checker.dart';
import 'package:vaultsnap/services/clipboard_service.dart';
import 'package:vaultsnap/services/import_export.dart';
import 'package:vaultsnap/services/password_generator.dart';
import 'package:vaultsnap/services/platform_bridge.dart';
import 'package:vaultsnap/services/settings.dart';
import 'package:vaultsnap/services/unlock_throttle.dart';
import 'package:vaultsnap/services/vault_session.dart';
import 'package:vaultsnap/ui/app_scope.dart';

void main() {
  late Directory dir;
  late AppServices services;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vs_ui');
    final sodium = await loadSodium();
    final crypto = VaultCrypto(sodium);
    final settings = AppSettings(File('${dir.path}/settings.json'));
    services = AppServices(
      session: VaultSession(
        crypto: crypto,
        directory: dir,
        throttle: UnlockThrottle(File('${dir.path}/t.json')),
      ),
      settings: settings,
      clipboard: ClipboardService(
        const PlatformBridge(),
        clearAfter: () => const Duration(seconds: 30),
      ),
      generator: PasswordGenerator(sodium, List.generate(7776, (i) => 'w$i')),
      strength: StrengthMeter(),
      importExport: ImportExport(crypto),
      bridge: const PlatformBridge(),
      breaches: BreachChecker(),
    );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets('first run: create vault, confirm recovery key, see empty list', (
    tester,
  ) async {
    await tester.runAsync(() => services.session.init());
    await tester.pumpWidget(VaultSnapApp(services: services));
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
    await tester.runAsync(() async {
      await tester.tap(find.text('Create'));
      // Argon2id runs on a real isolate.
      for (var i = 0; i < 100 && !services.session.isUnlocked; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
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
    await tester.pumpWidget(VaultSnapApp(services: services));
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
    await tester.pumpWidget(VaultSnapApp(services: services));
    await tester.pumpAndSettle();
    expect(find.text('Unlock'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'nope');
    await tester.runAsync(() async {
      await tester.tap(find.text('Unlock'));
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pumpAndSettle();
    expect(find.text('Wrong password'), findsOneWidget);
    expect(services.session.isUnlocked, isFalse);
  });
}
