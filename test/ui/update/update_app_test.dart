import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultsnap/app.dart';
import 'package:vaultsnap/services/update/update_controller.dart';
import 'package:vaultsnap/ui/app_scope.dart';
import 'package:vaultsnap/ui/home_screen.dart';
import 'package:vaultsnap/ui/unlock_screen.dart';
import 'package:vaultsnap/ui/update/update_banner.dart';

import '../helpers.dart';
import 'update_ui_kit.dart';

/// The updater inside the real app (`VaultSnapApp`): the gate in `app.dart`,
/// the navigator key, the lock before the install.
void main() {
  late Directory dir;
  late AppServices base;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vs_upd_app');
    base = await buildTestServices(dir);
    addTearDown(() async {
      // Close the vault (and its drift isolate) before removing its files.
      await base.session.lock();
      dir.deleteSync(recursive: true);
    });
  });

  AppServices withUpdates(UpdateController? updates) => AppServices(
    session: base.session,
    settings: base.settings,
    clipboard: base.clipboard,
    generator: base.generator,
    strength: base.strength,
    importExport: base.importExport,
    bridge: base.bridge,
    breaches: base.breaches,
    favicons: base.favicons,
    updates: updates,
  );

  Future<void> createVault(WidgetTester tester, {required bool locked}) =>
      tester.runAsync(() async {
        await base.session.init();
        await base.session.createVault(testMasterPassword);
        if (locked) await base.session.lock();
      });

  Finder button(String label) => find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );

  testWidgets('the banner shows over the unlock screen, which still works', (
    tester,
  ) async {
    mockChannel(tester, platformChannel, (_) async => null);
    final rig = UpdateRig();
    addTearDown(rig.dispose);
    rig.service.offerUpdate();
    await createVault(tester, locked: true);

    await tester.pumpWidget(
      VaultSnapApp(services: withUpdates(rig.controller)),
    );
    await tester.pumpAndSettle();
    // Start-up is not delayed by an update check.
    expect(find.byType(UnlockScreen), findsOneWidget);
    expect(find.byType(UpdateBanner), findsNothing);
    expect(rig.service.checkCalls, 0);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(rig.service.checkCalls, 1);
    expect(find.byType(UpdateBanner), findsOneWidget);
    expect(find.byType(UnlockScreen), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Unlock'), findsOneWidget);
    // The page was pushed down, not covered.
    expect(
      tester.getRect(find.byType(UnlockScreen)).top,
      greaterThanOrEqualTo(tester.getRect(find.byType(UpdateBanner)).bottom),
    );
  });

  testWidgets('the sheet opens on the app navigator and installs on a tap', (
    tester,
  ) async {
    mockChannel(tester, platformChannel, (_) async => null);
    final rig = UpdateRig(onPrepareExit: base.session.lock);
    addTearDown(rig.dispose);
    rig.service.offerUpdate();
    await createVault(tester, locked: false);
    expect(base.session.isUnlocked, isTrue);

    await tester.pumpWidget(
      VaultSnapApp(services: withUpdates(rig.controller)),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(UpdateBanner), findsOneWidget);

    await tester.tap(find.text('Update available'));
    await tester.pumpAndSettle();
    await tester.tap(button('Update now'));
    await tester.pumpAndSettle();
    rig.service.finishDownload();
    await tester.pumpAndSettle();
    expect(rig.controller.status, UpdateStatus.readyToInstall);

    // Downloaded and verified, and still not installed: it waits for the tap,
    // with the vault unlocked.
    await tester.pump(const Duration(seconds: 60));
    expect(rig.installer.installs, 0);
    expect(base.session.isUnlocked, isTrue);

    await tester.tap(button('Install'));
    await tester.pump();
    // Locking closes the database on a real isolate.
    await pumpUntilFound(tester, find.byType(UnlockScreen));
    await tester.pumpAndSettle();
    expect(rig.installer.installs, 1);
    // The vault was locked (keys wiped) before the hand-over.
    expect(rig.locks, 1);
    expect(base.session.isUnlocked, isFalse);
    expect(find.byType(UnlockScreen), findsOneWidget);
  });

  testWidgets('no updater: no banner, nothing asked', (tester) async {
    mockChannel(tester, platformChannel, (_) async => null);
    await createVault(tester, locked: true);
    await tester.pumpWidget(VaultSnapApp(services: withUpdates(null)));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    expect(find.byType(UpdateBanner), findsNothing);
    expect(find.byType(UnlockScreen), findsOneWidget);
  });

  testWidgets('a development build: the controller stays silent', (
    tester,
  ) async {
    mockChannel(tester, platformChannel, (_) async => null);
    final dev = UpdateRig(enabled: false);
    addTearDown(dev.dispose);
    dev.service.offerUpdate();
    await createVault(tester, locked: true);
    await tester.pumpWidget(
      VaultSnapApp(services: withUpdates(dev.controller)),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    expect(find.byType(UpdateBanner), findsNothing);
    expect(dev.service.checkCalls, 0);
  });

  testWidgets('the privacy cover stays on top of the banner', (tester) async {
    mockChannel(tester, platformChannel, (_) async => null);
    final rig = UpdateRig();
    addTearDown(rig.dispose);
    rig.service.offerUpdate();
    await createVault(tester, locked: true);
    await tester.pumpWidget(
      VaultSnapApp(services: withUpdates(rig.controller)),
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateBanner), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pumpAndSettle();
    // The black cover is painted last, over everything (the banner too).
    final cover = find.byWidgetPredicate(
      (w) => w is ColoredBox && w.color == Colors.black,
    );
    expect(cover, findsOneWidget);
    expect(
      tester
          .getRect(cover)
          .contains(tester.getCenter(find.byType(UpdateBanner))),
      isTrue,
    );
    final order = tester.allWidgets.toList();
    expect(
      order.indexWhere((w) => w is ColoredBox && w.color == Colors.black),
      greaterThan(order.indexWhere((w) => w is UpdateBanner)),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(cover, findsNothing);
  });
}
