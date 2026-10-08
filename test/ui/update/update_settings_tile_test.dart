import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/l10n/app_localizations.dart';
import 'package:hisn/services/update/app_version.dart';
import 'package:hisn/services/update/update_controller.dart';
import 'package:hisn/services/update/update_failure.dart';
import 'package:hisn/services/update/update_service.dart';
import 'package:hisn/ui/app_scope.dart';
import 'package:hisn/ui/update/update_settings_tile.dart';

import '../../tool/screenshot_harness.dart' show loadBundledFonts;
import '../helpers.dart';
import 'update_ui_kit.dart';

/// The updates block of the settings screen and the About version row.
void main() {
  late UpdateRig rig;

  setUp(() => rig = UpdateRig());
  tearDown(() => rig.dispose());

  UpdateSettingsTile tile({UpdateRig? using}) {
    final r = using ?? rig;
    return UpdateSettingsTile(
      controller: r.controller,
      settings: r.settings,
      installed: UpdateRig.installed,
    );
  }

  Finder button(String label) => find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate(
      (w) => w is ButtonStyleButton,
      description: 'a button',
    ),
  );

  group('UpdateSettingsTile', () {
    testWidgets('shows nothing where a release build has no updater', (
      tester,
    ) async {
      // A platform without packages: the version is known, no controller works.
      final none = UpdateRig(enabled: false);
      addTearDown(none.dispose);
      await pumpTile(tester, tile(using: none));
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(ListTile), findsNothing);
      expect(find.text('Check for updates automatically'), findsNothing);
      expect(find.text('Check now'), findsNothing);
      expect(find.text('Updates are off in development builds.'), findsNothing);
    });

    testWidgets('a development build says that updates are off', (
      tester,
    ) async {
      final dev = UpdateRig(enabled: false);
      addTearDown(dev.dispose);
      await pumpTile(
        tester,
        UpdateSettingsTile(
          controller: dev.controller,
          settings: dev.settings,
          installed: AppVersion.none,
        ),
      );
      expect(find.text('Updates'), findsOneWidget);
      expect(
        find.text('Updates are off in development builds.'),
        findsOneWidget,
      );
      expect(find.byType(Switch), findsNothing);
      expect(find.text('Check now'), findsNothing);
    });

    testWidgets('reads the controller and the settings from the app scope', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('vs_upd_tile');
      addTearDown(() => dir.deleteSync(recursive: true));
      final base = (await tester.runAsync(() => buildTestServices(dir)))!;
      AppServices withUpdates(UpdateController? updates) => AppServices(
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
      Widget app(AppServices services) => AppScope(
        services: services,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: ListView(children: const [UpdateSettingsTile()]),
          ),
        ),
      );

      await tester.pumpWidget(app(withUpdates(rig.controller)));
      expect(find.text('Check for updates automatically'), findsOneWidget);

      // No updater in this build (development, other platforms): nothing.
      await tester.pumpWidget(app(withUpdates(null)));
      expect(find.text('Check for updates automatically'), findsNothing);
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('the switch is the "check automatically" setting', (
      tester,
    ) async {
      await pumpTile(tester, tile());
      expect(find.text('Check for updates automatically'), findsOneWidget);
      expect(
        find.textContaining('at most once a day'),
        findsOneWidget,
        reason: 'it says how often and what GitHub sees',
      );
      expect(find.textContaining('IP address'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(rig.settings.checkUpdates, isFalse);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(rig.settings.checkUpdates, isTrue);
    });

    testWidgets('shows the version and when it was last checked', (
      tester,
    ) async {
      await pumpTile(tester, tile());
      expect(find.text('Version'), findsOneWidget);
      expect(find.textContaining('0.2.0'), findsOneWidget);
      expect(textLike('0.2.0 (build 2000)'), findsOneWidget);
      expect(find.text('Not checked yet'), findsOneWidget);

      final when = DateTime(2026, 10, 7, 9, 5);
      rig.settings.lastUpdateCheck = when.millisecondsSinceEpoch;
      await tester.pumpWidget(const SizedBox());
      await pumpTile(tester, tile());
      expect(find.textContaining('Last checked:'), findsOneWidget);
      expect(find.textContaining('2026-10-07 09:05'), findsOneWidget);
      expect(find.text('Not checked yet'), findsNothing);
    });

    testWidgets('Check now: up to date', (tester) async {
      rig.service.nextCheck = const UpdateUpToDate(2000);
      await pumpTile(tester, tile());
      await tester.tap(button('Check now'));
      await tester.pumpAndSettle();

      expect(rig.service.checkCalls, 1);
      expect(find.text('You have the latest version.'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.textContaining('Last checked:'), findsOneWidget);
      expect(find.text('View update'), findsNothing);
    });

    testWidgets('Check now: a newer version, View update opens the sheet', (
      tester,
    ) async {
      rig.service.offerUpdate();
      await pumpTile(tester, tile());
      await tester.tap(button('Check now'));
      await tester.pumpAndSettle();

      expect(find.textContaining('is available'), findsOneWidget);
      expect(find.textContaining('0.3.0'), findsOneWidget);
      await tester.tap(button('View update'));
      await tester.pumpAndSettle();
      expect(button('Update now'), findsOneWidget);
      expect(find.textContaining('Faster unlock.'), findsOneWidget);
      // Opening the sheet changed nothing.
      expect(rig.service.downloadCalls, 0);
    });

    testWidgets('Check now shows a skipped version again', (tester) async {
      rig.settings.skippedBuild = 3000;
      rig.service.offerUpdate();
      await pumpTile(tester, tile());
      await tester.tap(button('Check now'));
      await tester.pumpAndSettle();
      expect(rig.controller.status, UpdateStatus.available);
      expect(button('View update'), findsOneWidget);
    });

    testWidgets('Check now: offline', (tester) async {
      rig.service.nextCheck = const UpdateFailed(UpdateFailure.network);
      await pumpTile(tester, tile());
      await tester.tap(button('Check now'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Couldn’t reach GitHub. Check your internet connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('View update'), findsNothing);
    });

    testWidgets('Check now: a bad signature is "not used", in plain words', (
      tester,
    ) async {
      rig.service.nextCheck = const UpdateFailed(
        UpdateFailure.signatureInvalid,
      );
      await pumpTile(tester, tile());
      await tester.tap(button('Check now'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('signature could not be verified'),
        findsOneWidget,
      );
      expect(find.textContaining('signatureInvalid'), findsNothing);
      expect(find.text('View update'), findsNothing);
    });

    testWidgets('the button waits while a check runs', (tester) async {
      rig.service
        ..nextCheck = const UpdateUpToDate(2000)
        ..checkGate = Completer<void>();
      await pumpTile(tester, tile());
      await tester.tap(button('Check now'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Checking for updates…'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(button('Check now')).onPressed,
        isNull,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      rig.service.checkGate!.complete();
      await tester.pumpAndSettle();
      expect(
        tester.widget<OutlinedButton>(button('Check now')).onPressed,
        isNotNull,
      );
    });

    testWidgets('progress shows in the line under the version', (tester) async {
      rig.service.offerUpdate();
      await pumpTile(tester, tile());
      await rig.controller.checkNow();
      unawaited(rig.controller.startDownload());
      await tester.pump();
      rig.service.emitProgress(1, 4);
      await tester.pump();
      expect(find.text('Downloading update… 25%'), findsOneWidget);
      // Nothing can be checked in the middle of a download.
      expect(
        tester.widget<OutlinedButton>(button('Check now')).onPressed,
        isNull,
      );
      expect(button('View update'), findsOneWidget);
      rig.service.failDownload(UpdateFailure.network);
      await tester.pumpAndSettle();
    });

    testWidgets('buttons are at least 48 dp tall', (tester) async {
      rig.service.offerUpdate();
      await pumpTile(tester, tile());
      await tester.tap(button('Check now'));
      await tester.pumpAndSettle();
      for (final label in ['Check now', 'View update']) {
        expect(
          tester.getSize(button(label)).height,
          greaterThanOrEqualTo(48),
          reason: label,
        );
      }
      expect(
        tester.getSize(find.byType(SwitchListTile)).height,
        greaterThanOrEqualTo(48),
      );
    });

    testWidgets('Arabic: Arabic text, right to left, Western digits', (
      tester,
    ) async {
      rig.service.offerUpdate();
      rig.settings.lastUpdateCheck = DateTime(
        2026,
        10,
        7,
        9,
        5,
      ).millisecondsSinceEpoch;
      await pumpTile(tester, tile(), locale: const Locale('ar'));
      expect(find.text('التحقق من التحديثات تلقائيًا'), findsOneWidget);
      expect(find.text('الإصدار'), findsOneWidget);
      expect(find.textContaining('رقم البناء'), findsOneWidget);
      expect(find.textContaining('آخر تحقق'), findsOneWidget);
      expect(find.textContaining('2026-10-07 09:05'), findsOneWidget);
      expect(find.textContaining('٠'), findsNothing);
      expect(
        Directionality.of(tester.element(find.text('الإصدار'))),
        TextDirection.rtl,
      );

      await tester.tap(button('تحقق الآن'));
      await tester.pumpAndSettle();
      expect(find.textContaining('يتوفر الإصدار'), findsOneWidget);
      expect(button('عرض التحديث'), findsOneWidget);
    });

    for (final locale in [const Locale('en'), const Locale('ar')]) {
      testWidgets('${locale.languageCode} at 200% text on a small phone', (
        tester,
      ) async {
        await tester.runAsync(loadBundledFonts);
        rig.service.nextCheck = const UpdateFailed(
          UpdateFailure.signatureInvalid,
        );
        await pumpTile(
          tester,
          tile(),
          locale: locale,
          size: const Size(360, 640),
          textScale: 2,
        );
        await tester.ensureVisible(find.byType(OutlinedButton));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(OutlinedButton));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('AboutVersionTile', () {
    testWidgets('shows version and build', (tester) async {
      await pumpTile(tester, AboutVersionTile(version: UpdateRig.installed));
      expect(find.text('Version'), findsOneWidget);
      expect(textLike('0.2.0 (build 2000)'), findsOneWidget);
    });

    testWidgets('says so in a development build', (tester) async {
      await pumpTile(tester, const AboutVersionTile(version: AppVersion.none));
      expect(find.text('Development build'), findsOneWidget);
    });

    testWidgets('Arabic', (tester) async {
      await pumpTile(
        tester,
        AboutVersionTile(version: UpdateRig.installed),
        locale: const Locale('ar'),
      );
      expect(find.text('الإصدار'), findsOneWidget);
      expect(find.textContaining('رقم البناء'), findsOneWidget);
    });
  });
}
