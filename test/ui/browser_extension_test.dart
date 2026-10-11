import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/app.dart';
import 'package:hisn/services/browser/browser_activity.dart';
import 'package:hisn/services/browser/browser_bridge.dart';
import 'package:hisn/ui/app_scope.dart';
import 'package:hisn/ui/browser/browser_extension_screen.dart';

import 'helpers.dart';

/// A key the extension made: 32 bytes, base64url without padding.
final _key = base64Url.encode(List.filled(32, 5)).replaceAll('=', '');

void main() {
  late Directory dir;
  late AppServices services;
  late BrowserBridge bridge;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vs_browser_ui');
    services = await buildTestServices(dir, browser: true);
    bridge = services.browser!;
  });
  tearDown(() async {
    await bridge.stop();
    await services.session.lock();
    dir.deleteSync(recursive: true);
  });

  Future<void> openUnlocked(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await services.session.init();
      await services.session.createVault(testMasterPassword);
    });
    await tester.pumpWidget(HisnApp(services: services));
    await tester.pumpAndSettle();
  }

  final toggle = find.descendant(
    of: find.byType(BrowserExtensionScreen),
    matching: find.byType(Switch),
  );

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
  }

  testWidgets('Settings > Browser extension: turn it on, see how to add it', (
    tester,
  ) async {
    await openUnlocked(tester);
    // Off: no activity button on the home screen.
    expect(find.byTooltip('Browser activity'), findsNothing);
    await openSettings(tester);
    await tester.tap(find.text('Browser extension'));
    await tester.pumpAndSettle();

    expect(find.text('Add Khazna to your browser'), findsNothing);
    await tester.runAsync(() async {
      await tester.tap(toggle);
      // enable() binds the loopback port on a real isolate.
      for (var i = 0; i < 50 && !bridge.running; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();
    expect(bridge.running, isTrue);
    expect(services.settings.browserExtension, isTrue);
    expect(find.text('Add Khazna to your browser'), findsOneWidget);
    expect(find.text('Copy address'), findsOneWidget);
    expect(find.text('No browser is paired yet.'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(toggle);
      for (var i = 0; i < 50 && services.settings.browserExtension; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();
    expect(bridge.running, isFalse);
    expect(services.settings.browserExtension, isFalse);
  });

  testWidgets('a browser asks to pair: the app shows the code, the user '
      'allows it', (tester) async {
    await openUnlocked(tester);
    final client = BridgeClient();
    late Future<Map<String, Object?>> reply;
    await tester.runAsync(() async {
      reply = bridge.handle(client, {
        'id': 1,
        't': 'pair',
        'key': _key,
        'browser': 'Chrome',
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    expect(find.text('Allow this browser?'), findsOneWidget);
    expect(find.text(bridge.pendingPairing!.code), findsOneWidget);
    expect(find.textContaining('Chrome wants to fill'), findsOneWidget);

    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();
    final r = await tester.runAsync(() => reply);
    expect(r!['ok'], isTrue);
    expect(services.settings.pairedBrowsers.single.name, 'Chrome');
    expect(find.text('Allow this browser?'), findsNothing);
  });

  testWidgets('denying, or the browser going away, closes the question', (
    tester,
  ) async {
    await openUnlocked(tester);
    late Future<Map<String, Object?>> reply;
    await tester.runAsync(() async {
      reply = bridge.handle(BridgeClient(), {'t': 'pair', 'key': _key});
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deny'));
    await tester.pumpAndSettle();
    expect((await tester.runAsync(() => reply))!['error'], 'denied');

    await tester.runAsync(() async {
      reply = bridge.handle(BridgeClient(), {'t': 'pair', 'key': _key});
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    expect(find.text('Allow this browser?'), findsOneWidget);
    // Answered elsewhere (here: the connection closed).
    bridge.answerPairing(false);
    await tester.pumpAndSettle();
    expect(find.text('Allow this browser?'), findsNothing);
    expect(services.settings.pairedBrowsers, isEmpty);
    await tester.runAsync(() => reply);
  });

  testWidgets('the activity log: a badge for new lines, cleared on opening', (
    tester,
  ) async {
    await openUnlocked(tester);
    await tester.runAsync(() async {
      await services.settings.update((s) => s.browserExtension = true);
      await bridge.activity.add(
        BrowserActivityKind.filled,
        host: 'github.com',
        title: 'GitHub',
        browser: 'Chrome',
      );
      await bridge.activity.add(
        BrowserActivityKind.saved,
        host: 'example.test',
        browser: 'Edge',
      );
    });
    await tester.pumpAndSettle();
    final button = find.byTooltip('Browser activity');
    expect(button, findsOneWidget);
    expect(
      find.descendant(of: button, matching: find.text('2')),
      findsOneWidget,
    );

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Filled GitHub on github.com'), findsOneWidget);
    expect(find.text('Saved a new login for example.test'), findsOneWidget);
    expect(find.textContaining('Chrome'), findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    expect(bridge.activity.unseen, 0);

    await tester.runAsync(() async {
      await tester.tap(find.text('Clear'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Nothing yet'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.descendant(of: button, matching: find.text('2')), findsNothing);
  });
}
