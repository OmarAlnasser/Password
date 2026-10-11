/// Render-and-look pictures of the browser extension screens (Settings >
/// Browser extension, the activity log, the pairing question). Skipped by
/// default; run with
///
/// ```sh
/// SHOTS_DIR=/some/dir flutter test --run-skipped -t screenshots test/ui/browser_shots_test.dart
/// ```
///
/// Fake data only.
@Tags(['screenshots'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/services/browser/browser_activity.dart';
import 'package:hisn/services/browser/browser_bridge.dart';
import 'package:hisn/services/settings.dart';
import 'package:hisn/ui/app_scope.dart';
import 'package:hisn/ui/browser/browser_extension_screen.dart';

import '../tool/screenshot_harness.dart';
import 'helpers.dart';

void main() {
  late Directory dir;
  late AppServices services;
  late BrowserBridge bridge;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('browser_shots');
    services = await buildTestServices(dir, browser: true);
    bridge = services.browser!;
  });
  tearDown(() async {
    await services.session.lock();
    dir.deleteSync(recursive: true);
  });

  Future<void> seed(WidgetTester tester) => tester.runAsync(() async {
    await services.session.init();
    await services.session.createVault(testMasterPassword);
    await services.settings.update((s) {
      s.browserExtension = true;
      s.pairedBrowsers = [
        PairedBrowser(
          keyHash: 'a' * 64,
          name: 'Chrome',
          pairedAt: DateTime.utc(2026, 10, 1),
        ),
        PairedBrowser(
          keyHash: 'b' * 64,
          name: 'Edge',
          pairedAt: DateTime.utc(2026, 10, 9),
        ),
      ];
    });
    final log = bridge.activity;
    await log.add(BrowserActivityKind.paired, host: '', browser: 'Chrome');
    await log.add(
      BrowserActivityKind.filled,
      host: 'github.com',
      title: 'GitHub',
      browser: 'Chrome',
    );
    await log.add(
      BrowserActivityKind.updated,
      host: 'github.com',
      title: 'GitHub',
      browser: 'Chrome',
    );
    await log.add(
      BrowserActivityKind.saved,
      host: 'example.test',
      title: 'example.test',
      browser: 'Edge',
    );
  });

  Widget wrap(Widget app) => AppScope(services: services, child: app);

  testWidgets('browser extension settings', (tester) async {
    await seed(tester);
    await pumpScreenshots(
      tester,
      BrowserExtensionScreen(bridge: bridge),
      'browser-settings',
      wrap: wrap,
    );
  });

  testWidgets('browser activity', (tester) async {
    await seed(tester);
    await pumpScreenshots(
      tester,
      BrowserActivityScreen(log: bridge.activity),
      'browser-activity',
      sizes: const [ShotSize.phone],
      wrap: wrap,
    );
  });

  testWidgets('pairing question', (tester) async {
    await seed(tester);
    final nav = GlobalKey<NavigatorState>();
    await pumpScreenshots(
      tester,
      BrowserPairingGate(
        bridge: bridge,
        navigatorKey: nav,
        child: Navigator(
          key: nav,
          onGenerateRoute: (_) =>
              MaterialPageRoute<void>(builder: (_) => const Scaffold()),
        ),
      ),
      'browser-pair',
      sizes: const [ShotSize.phone],
      themes: const [Brightness.dark],
      wrap: wrap,
      afterPump: (tester) async {
        if (bridge.pendingPairing == null) {
          await tester.runAsync(() async {
            bridge.handle(BridgeClient(), {
              't': 'pair',
              'key': base64Url.encode(List.filled(32, 9)).replaceAll('=', ''),
              'browser': 'Chrome',
            });
            await Future<void>.delayed(const Duration(milliseconds: 20));
          });
        }
        await tester.pumpAndSettle();
      },
    );
    bridge.answerPairing(false);
  });
}
