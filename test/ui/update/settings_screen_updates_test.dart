import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/services/update/update_controller.dart';
import 'package:hisn/services/update/update_failure.dart';
import 'package:hisn/services/update/update_service.dart';
import 'package:hisn/ui/app_scope.dart';
import 'package:hisn/ui/settings_screen.dart';

import '../helpers.dart';
import 'update_ui_kit.dart';

/// The updates block as the owner meets it: inside the real settings screen,
/// not in isolation (`update_settings_tile_test.dart` covers the tile alone).
/// Without these tests the tile could silently fall out of the list again, and
/// "Check now" is the only way to see why an update is not offered.
void main() {
  late UpdateRig rig;

  setUp(() => rig = UpdateRig());
  tearDown(() => rig.dispose());

  /// The settings screen over real services, with [updates] as the updater.
  Future<void> pumpSettings(
    WidgetTester tester, {
    required UpdateController? updates,
    Locale locale = const Locale('en'),
  }) async {
    final dir = Directory.systemTemp.createTempSync('vs_settings_upd');
    addTearDown(() => dir.deleteSync(recursive: true));
    final base = (await tester.runAsync(() => buildTestServices(dir)))!;
    final services = AppServices(
      session: base.session,
      settings: rig.settings,
      clipboard: base.clipboard,
      generator: base.generator,
      strength: base.strength,
      importExport: base.importExport,
      bridge: base.bridge,
      breaches: base.breaches,
      updates: updates,
    );
    await pumpUpdateApp(
      tester,
      controller: null,
      gate: false,
      home: const SettingsScreen(),
      locale: locale,
      // Tall enough that the lazy list builds every row.
      size: const Size(600, 2400),
      wrap: (app) => AppScope(services: services, child: app),
    );
    await tester.pump();
  }

  Finder button(String label) => find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate(
      (w) => w is ButtonStyleButton,
      description: 'a button',
    ),
  );

  testWidgets('a release build shows the switch, the version and Check now', (
    tester,
  ) async {
    await pumpSettings(tester, updates: rig.controller);

    expect(find.text('Updates'), findsOneWidget);
    expect(find.text('Check for updates automatically'), findsOneWidget);
    expect(button('Check now'), findsOneWidget);
    // One version row: the tile has it, so the About row is not added twice.
    expect(find.text('Version'), findsOneWidget);
    expect(find.text('Not checked yet'), findsOneWidget);
    // With an updater there is no "updates are off" line.
    expect(find.text('Updates are off in development builds.'), findsNothing);
  });

  testWidgets('Check now in the settings screen runs a check', (tester) async {
    rig.service.nextCheck = const UpdateUpToDate(2000);
    await pumpSettings(tester, updates: rig.controller);

    await tester.tap(button('Check now'));
    await tester.pumpAndSettle();

    expect(rig.service.checkCalls, 1);
    expect(find.text('You have the latest version.'), findsOneWidget);
    expect(find.textContaining('Last checked:'), findsOneWidget);
  });

  testWidgets('a failed check is visible in the settings screen', (
    tester,
  ) async {
    rig.service.nextCheck = const UpdateFailed(UpdateFailure.network);
    await pumpSettings(tester, updates: rig.controller);

    await tester.tap(button('Check now'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Couldn’t reach GitHub'), findsOneWidget);
  });

  testWidgets('the switch in the settings screen is the saved setting', (
    tester,
  ) async {
    await pumpSettings(tester, updates: rig.controller);
    final switchTile = find.widgetWithText(
      SwitchListTile,
      'Check for updates automatically',
    );
    expect(tester.widget<SwitchListTile>(switchTile).value, isTrue);

    await tester.tap(switchTile);
    await tester.pump();

    expect(rig.settings.checkUpdates, isFalse);
    expect(tester.widget<SwitchListTile>(switchTile).value, isFalse);
  });

  testWidgets('a development build says why there is no updater', (
    tester,
  ) async {
    await pumpSettings(tester, updates: null);

    expect(find.text('Updates are off in development builds.'), findsOneWidget);
    expect(find.text('Development build'), findsOneWidget);
    expect(find.text('Version'), findsOneWidget);
    expect(find.text('Check for updates automatically'), findsNothing);
    expect(find.text('Check now'), findsNothing);
  });

  testWidgets('Arabic: the development build line is translated', (
    tester,
  ) async {
    await pumpSettings(tester, updates: null, locale: const Locale('ar'));

    expect(find.text('التحديثات متوقفة في نسخ التطوير.'), findsOneWidget);
    expect(find.text('نسخة تطوير'), findsOneWidget);
    expect(find.text('الإصدار'), findsOneWidget);
  });
}
