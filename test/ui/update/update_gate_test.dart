import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/services/settings.dart';
import 'package:hisn/services/update/update_controller.dart';
import 'package:hisn/services/update/update_failure.dart';
import 'package:hisn/services/update/update_installer.dart';
import 'package:hisn/services/update/update_manifest.dart';
import 'package:hisn/services/update/update_providers.dart';
import 'package:hisn/services/update/update_service.dart';
import 'package:hisn/services/update/windows_installer.dart';

import '../../tool/screenshot_harness.dart' show loadBundledFonts;
import 'update_ui_kit.dart';

/// The update banner and sheet, driven through the same wiring as
/// `lib/app.dart` (a gate above the Navigator), with a scripted service and
/// installer: no network, no disk, no real install.
void main() {
  late UpdateRig rig;

  setUp(() => rig = UpdateRig());
  tearDown(() => rig.dispose());

  /// Starts the app and lets the start-up check run.
  Future<void> startWithUpdate(
    WidgetTester tester, {
    UpdateRig? using,
    Locale locale = const Locale('en'),
    TargetPlatform platform = TargetPlatform.android,
    Size size = const Size(390, 844),
    double textScale = 1,
    bool disableAnimations = false,
    UrlOpener? openUrl,
  }) async {
    final r = using ?? rig;
    r.service.offerUpdate();
    await pumpUpdateApp(
      tester,
      controller: r.controller,
      locale: locale,
      platform: platform,
      size: size,
      textScale: textScale,
      disableAnimations: disableAnimations,
      openUrl: openUrl,
    );
    await tester.pumpAndSettle();
    expect(r.controller.status, UpdateStatus.available);
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(
      find.descendant(of: bannerFinder(), matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();
  }

  Finder button(String label) => find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate(
      (w) => w is ButtonStyleButton,
      description: 'a button',
    ),
  );

  Future<void> tapButton(WidgetTester tester, String label) async {
    // The middle of the sheet scrolls; bring the button into view first.
    await tester.ensureVisible(button(label));
    await tester.pumpAndSettle();
    await tester.tap(button(label));
    await tester.pumpAndSettle();
  }

  /// Lets real I/O finish (the settings file) between frames, until [done].
  Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pumpAndSettle();
  }

  /// Update now -> download finished -> verified: the Install step.
  Future<void> downloadAndVerify(
    WidgetTester tester, {
    UpdateRig? using,
  }) async {
    final r = using ?? rig;
    await tapButton(tester, 'Update now');
    r.service.finishDownload();
    await tester.pumpAndSettle();
    expect(r.controller.status, UpdateStatus.readyToInstall);
  }

  group('automatic check', () {
    testWidgets('a banner appears when a newer version is found', (
      tester,
    ) async {
      rig.service.offerUpdate();
      await pumpUpdateApp(tester, controller: rig.controller);
      expect(bannerFinder(), findsNothing);
      await tester.pumpAndSettle();

      expect(rig.service.checkCalls, 1);
      expect(bannerFinder(), findsOneWidget);
      expect(find.text('Update available'), findsOneWidget);
      expect(find.textContaining('0.3.0'), findsOneWidget);
      // It never downloaded or installed anything by itself.
      expect(rig.service.downloadCalls, 0);
      expect(rig.installer.installs, 0);
    });

    testWidgets('the check waits a few seconds after start-up', (tester) async {
      rig.service.offerUpdate();
      await pumpUpdateApp(
        tester,
        controller: rig.controller,
        startDelay: const Duration(seconds: 3),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(rig.service.checkCalls, 0);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(rig.service.checkCalls, 1);
    });

    testWidgets('a development build shows nothing and asks nothing', (
      tester,
    ) async {
      final dev = UpdateRig(enabled: false);
      addTearDown(dev.dispose);
      dev.service.offerUpdate();
      await pumpUpdateApp(tester, controller: dev.controller);
      await tester.pumpAndSettle();

      expect(dev.controller.enabled, isFalse);
      expect(dev.service.checkCalls, 0);
      expect(dev.service.cleanupCalls, 0);
      expect(bannerFinder(), findsNothing);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('no controller: just the page', (tester) async {
      await pumpUpdateApp(tester, controller: null);
      await tester.pumpAndSettle();
      expect(bannerFinder(), findsNothing);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('the switch turns automatic checks off', (tester) async {
      rig.settings.checkUpdates = false;
      rig.service.offerUpdate();
      await pumpUpdateApp(tester, controller: rig.controller);
      await tester.pumpAndSettle();

      expect(rig.service.checkCalls, 0);
      expect(bannerFinder(), findsNothing);
      // The leftovers of the last update are still swept.
      expect(rig.service.cleanupCalls, 1);
    });

    testWidgets('it checks at most once a day, also on unlock', (tester) async {
      final unlocks = ValueNotifier<int>(0);
      addTearDown(unlocks.dispose);
      rig.service.nextCheck = const UpdateUpToDate(2000);
      await pumpUpdateApp(
        tester,
        controller: rig.controller,
        triggers: unlocks,
      );
      await tester.pumpAndSettle();
      expect(rig.service.checkCalls, 1);

      // Unlocking right after: nothing is due.
      unlocks.value++;
      await tester.pumpAndSettle();
      expect(rig.service.checkCalls, 1);

      // A day later it is due again.
      rig.now = rig.now.add(const Duration(hours: 25));
      unlocks.value++;
      await tester.pumpAndSettle();
      expect(rig.service.checkCalls, 2);
    });

    testWidgets('it checks again when the app returns to the foreground', (
      tester,
    ) async {
      rig.service.nextCheck = const UpdateUpToDate(2000);
      await pumpUpdateApp(tester, controller: rig.controller);
      await tester.pumpAndSettle();
      expect(rig.service.checkCalls, 1);

      rig.now = rig.now.add(const Duration(days: 2));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(rig.service.checkCalls, 2);
    });

    testWidgets('the highest build seen is passed on and remembered', (
      tester,
    ) async {
      rig.settings.highestSeenBuild = 2500;
      await startWithUpdate(tester);
      expect(rig.service.lastHighestSeen, 2500);
      expect(rig.settings.highestSeenBuild, 3000);
      expect(rig.settings.lastUpdateCheck, rig.now.millisecondsSinceEpoch);
    });
  });

  group('banner', () {
    testWidgets('sits above the page instead of covering its app bar', (
      tester,
    ) async {
      await pumpUpdateApp(tester, controller: rig.controller);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byType(AppBar)).dy, 0);

      rig.service.offerUpdate();
      await tester.runAsync(rig.controller.checkNow);
      await tester.pumpAndSettle();

      final banner = tester.getRect(bannerFinder());
      final appBar = tester.getRect(find.byType(AppBar));
      expect(appBar.top, greaterThanOrEqualTo(banner.bottom));
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('the page below keeps its state when the banner shows up', (
      tester,
    ) async {
      rig.service.nextCheck = const UpdateUpToDate(2000);
      await pumpUpdateApp(tester, controller: rig.controller);
      await tester.pumpAndSettle();
      await tester.tap(find.text('count 0'));
      await tester.pump();
      await tester.tap(find.text('count 1'));
      await tester.pump();
      expect(find.text('count 2'), findsOneWidget);

      rig.service.offerUpdate();
      await rig.controller.checkNow();
      await tester.pumpAndSettle();
      expect(bannerFinder(), findsOneWidget);
      expect(find.text('count 2'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(bannerFinder(), findsNothing);
      expect(find.text('count 2'), findsOneWidget);
    });

    testWidgets('closing it hides it for now, a new step shows it again', (
      tester,
    ) async {
      await startWithUpdate(tester);
      await tester.tap(
        find.descendant(of: bannerFinder(), matching: find.byIcon(Icons.close)),
      );
      await tester.pumpAndSettle();
      expect(bannerFinder(), findsNothing);
      // Hiding is not skipping: the update is still on offer.
      expect(rig.controller.status, UpdateStatus.available);
      expect(rig.settings.skippedBuild, 0);

      // The download is started elsewhere (the settings tile): progress shows.
      unawaited(rig.controller.startDownload());
      await tester.pump();
      expect(find.textContaining('Downloading update'), findsOneWidget);
      rig.service.finishDownload();
      await tester.pumpAndSettle();
      expect(find.text('Ready to install'), findsOneWidget);
    });

    testWidgets('tapping it opens the sheet with the release', (tester) async {
      await startWithUpdate(tester);
      await openSheet(tester);

      expect(find.textContaining('You have'), findsOneWidget);
      expect(find.text('Download size: 42.0 MB'), findsOneWidget);
      expect(find.textContaining('Released'), findsOneWidget);
      expect(find.text('What’s new'), findsOneWidget);
      expect(find.textContaining('Faster unlock.'), findsOneWidget);
      expect(button('Update now'), findsOneWidget);
      expect(button('Later'), findsOneWidget);
      expect(button('Skip this version'), findsOneWidget);
      // Nothing happened yet.
      expect(rig.service.downloadCalls, 0);
    });

    testWidgets('close buttons and the banner are at least 48 dp', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await startWithUpdate(tester);
      final close = find.descendant(
        of: bannerFinder(),
        matching: find.byType(IconButton),
      );
      expect(tester.getSize(close).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(close).height, greaterThanOrEqualTo(48));
      final open = find
          .descendant(of: bannerFinder(), matching: find.byType(InkWell))
          .first;
      expect(tester.getSize(open).height, greaterThanOrEqualTo(48));
      expect(find.bySemanticsLabel('Hide for now'), findsOneWidget);
      semantics.dispose();

      await openSheet(tester);
      for (final label in ['Update now', 'Later', 'Skip this version']) {
        expect(
          tester.getSize(button(label)).height,
          greaterThanOrEqualTo(48),
          reason: label,
        );
      }
    });
  });

  group('sheet', () {
    testWidgets('Later closes it and hides the banner, nothing is skipped', (
      tester,
    ) async {
      await startWithUpdate(tester);
      await openSheet(tester);
      await tapButton(tester, 'Later');

      expect(button('Update now'), findsNothing);
      expect(bannerFinder(), findsNothing);
      expect(rig.settings.skippedBuild, 0);
      expect(rig.controller.status, UpdateStatus.available);
    });

    testWidgets('Skip this version is remembered and goes quiet', (
      tester,
    ) async {
      await startWithUpdate(tester);
      await openSheet(tester);
      await tapButton(tester, 'Skip this version');

      expect(rig.settings.skippedBuild, 3000);
      expect(bannerFinder(), findsNothing);
      expect(button('Update now'), findsNothing);
      expect(rig.controller.status, UpdateStatus.idle);

      // The next day's automatic check stays quiet about this build ...
      rig.now = rig.now.add(const Duration(hours: 25));
      await rig.controller.checkAutomatically();
      await tester.pumpAndSettle();
      expect(rig.service.checkCalls, 2);
      expect(bannerFinder(), findsNothing);

      // ... but a newer one is offered.
      rig.service.offerUpdate(testManifest(version: '0.4.0'));
      rig.now = rig.now.add(const Duration(hours: 25));
      await rig.controller.checkAutomatically();
      await tester.pumpAndSettle();
      expect(bannerFinder(), findsOneWidget);
      expect(find.textContaining('0.4.0'), findsOneWidget);
    });

    testWidgets('Skip this version is written to the settings file', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('vs_upd_skip');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/settings.json');
      final real = UpdateRig(settings: AppSettings(file));
      addTearDown(real.dispose);

      real.service.offerUpdate();
      await pumpUpdateApp(tester, controller: real.controller);
      await tester.pump(const Duration(milliseconds: 10));
      // The check records the build it saw; that write is real file I/O.
      await pumpUntil(
        tester,
        () => real.controller.status != UpdateStatus.checking,
      );
      expect(real.controller.status, UpdateStatus.available);
      await openSheet(tester);
      await tester.ensureVisible(button('Skip this version'));
      await tester.tap(button('Skip this version'));
      await tester.pump();
      await pumpUntil(
        tester,
        () => real.controller.status == UpdateStatus.idle,
      );

      final reloaded = AppSettings(file);
      await tester.runAsync(reloaded.load);
      expect(reloaded.skippedBuild, 3000);
      expect(reloaded.highestSeenBuild, 3000);
    });

    testWidgets('Update now shows progress, Cancel stops the download', (
      tester,
    ) async {
      await startWithUpdate(tester);
      await openSheet(tester);
      await tapButton(tester, 'Update now');

      expect(rig.service.downloadCalls, 1);
      expect(find.text('Downloading update'), findsOneWidget);
      expect(find.text('0% of 42.0 MB'), findsOneWidget);

      rig.service.emitProgress(21 * 1024 * 1024, 42 * 1024 * 1024);
      await tester.pumpAndSettle();
      expect(find.text('50% of 42.0 MB'), findsOneWidget);
      // The banner shows it too.
      expect(find.text('Downloading update… 50%'), findsOneWidget);

      await tapButton(tester, 'Cancel download');
      expect(rig.controller.status, UpdateStatus.available);
      expect(button('Update now'), findsOneWidget);
    });

    testWidgets('a finished download is verified, then waits for the user', (
      tester,
    ) async {
      await startWithUpdate(tester);
      await openSheet(tester);
      rig.service.verifyGate = Completer<void>();
      await tapButton(tester, 'Update now');
      rig.service.finishDownload();
      await tester.pump();
      await tester.pump();
      expect(rig.controller.status, UpdateStatus.verifying);
      expect(find.text('Checking the download'), findsWidgets);

      rig.service.verifyGate!.complete();
      await tester.pumpAndSettle();
      expect(rig.controller.status, UpdateStatus.readyToInstall);
      expect(find.text('Ready to install'), findsWidgets);
      expect(button('Install'), findsOneWidget);

      // A long time later it still has not installed itself, and the vault
      // is still unlocked.
      await tester.pump(const Duration(minutes: 30));
      expect(rig.installer.installs, 0);
      expect(rig.service.stageCalls, 0);
      expect(rig.locks, 0);
    });

    testWidgets('Install hands the package over once, after locking', (
      tester,
    ) async {
      await startWithUpdate(tester);
      await openSheet(tester);
      await downloadAndVerify(tester);

      await tapButton(tester, 'Install');
      expect(rig.installer.installs, 1);
      expect(rig.locks, 1);
      expect(rig.service.stageCalls, 1);
      expect(
        find.text('The system installer is open. Tap Install there to finish.'),
        findsOneWidget,
      );
      expect(button('Open the installer again'), findsOneWidget);
    });

    testWidgets('Windows: "Closing to install..." while the app hands over', (
      tester,
    ) async {
      final win = UpdateRig(platform: UpdatePlatform.windows);
      addTearDown(win.dispose);
      await startWithUpdate(
        tester,
        using: win,
        platform: TargetPlatform.windows,
      );
      await openSheet(tester);
      await downloadAndVerify(tester, using: win);
      expect(find.textContaining('lock your vault'), findsOneWidget);

      win.installer.gate = Completer<void>();
      await tester.tap(button('Close and install'));
      await tester.pump();
      await tester.pump();
      expect(win.controller.status, UpdateStatus.installing);
      expect(find.text('Closing to install…'), findsWidgets);
      expect(win.locks, 1);

      win.installer.gate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('Android without permission: explains it and can try again', (
      tester,
    ) async {
      rig.installer
        ..outcome = InstallOutcome.permissionRequired
        ..callPrepareExit = false;
      await startWithUpdate(tester);
      await openSheet(tester);
      await downloadAndVerify(tester);
      await tapButton(tester, 'Install');

      expect(find.text('Allow installs from this app'), findsOneWidget);
      expect(find.textContaining('Allow from this source'), findsOneWidget);
      expect(rig.locks, 0);

      rig.installer.outcome = InstallOutcome.started;
      await tapButton(tester, 'Install');
      expect(rig.installer.installs, 2);
      expect(find.text('Allow installs from this app'), findsNothing);
    });

    testWidgets('Android refusing the package points to the release page', (
      tester,
    ) async {
      final browser = RecordingOpener();
      final copied = recordClipboard(tester);
      rig.installer.outcome = InstallOutcome.failed;
      await startWithUpdate(tester, openUrl: browser.call);
      await openSheet(tester);
      await downloadAndVerify(tester);
      await tapButton(tester, 'Install');

      expect(
        find.textContaining('Android didn’t accept this update'),
        findsOneWidget,
      );
      expect(find.textContaining('export or sync it first'), findsOneWidget);
      expect(button('Try again'), findsOneWidget);

      await tester.ensureVisible(button('Open release page'));
      await tester.tap(button('Open release page'));
      await tester.pump();
      expect(browser.opened, [releasePageUri]);
      expect(
        releasePageUri.toString(),
        'https://github.com/OmarAlnasser/Password/releases/latest',
      );

      await tester.ensureVisible(button('Copy link'));
      await tester.tap(button('Copy link'));
      await tester.pump();
      expect(copied, [releasePageUri.toString()]);
      expect(find.text('Link copied'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('Copy link'), findsOneWidget);
    });

    testWidgets('Windows folder that cannot be written: instructions', (
      tester,
    ) async {
      final win = UpdateRig(
        platform: UpdatePlatform.windows,
        outcome: InstallOutcome.failed,
      );
      addTearDown(win.dispose);
      final browser = RecordingOpener();
      await startWithUpdate(
        tester,
        using: win,
        platform: TargetPlatform.windows,
        openUrl: browser.call,
      );
      await openSheet(tester);
      await downloadAndVerify(tester, using: win);
      await tapButton(tester, 'Close and install');

      expect(find.textContaining('Program Files'), findsOneWidget);
      expect(find.textContaining('Nothing was changed'), findsOneWidget);
      expect(button('Open release page'), findsOneWidget);
    });

    testWidgets('an installer that cannot work here says so', (tester) async {
      rig.installer.outcome = InstallOutcome.unsupported;
      await startWithUpdate(tester);
      await openSheet(tester);
      await downloadAndVerify(tester);
      await tapButton(tester, 'Install');

      expect(find.textContaining('isn’t available here'), findsOneWidget);
      expect(button('Install'), findsNothing);
      expect(button('Copy link'), findsOneWidget);
    });

    testWidgets('without a browser only "Copy link" is offered', (
      tester,
    ) async {
      rig.installer.outcome = InstallOutcome.failed;
      await startWithUpdate(tester);
      await openSheet(tester);
      await downloadAndVerify(tester);
      await tapButton(tester, 'Install');
      expect(button('Open release page'), findsNothing);
      expect(button('Copy link'), findsOneWidget);
    });
  });

  group('errors, in plain language', () {
    testWidgets('offline: says so and can try again', (tester) async {
      await startWithUpdate(tester);
      await openSheet(tester);
      await tapButton(tester, 'Update now');
      rig.service.failDownload(UpdateFailure.network);
      await tester.pumpAndSettle();

      expect(find.text('Couldn’t update'), findsOneWidget);
      expect(
        find.text(
          'Couldn’t reach GitHub. Check your internet connection and try again.',
        ),
        findsOneWidget,
      );
      // The banner tells it too, with the error look.
      expect(find.text('The update didn’t finish'), findsOneWidget);

      await tapButton(tester, 'Try again');
      expect(rig.service.downloadCalls, 2);
      expect(rig.controller.status, UpdateStatus.downloading);
      expect(find.text('Downloading update'), findsOneWidget);
    });

    testWidgets('a rejected signature: "rejected for your safety"', (
      tester,
    ) async {
      await startWithUpdate(tester);
      await openSheet(tester);
      await tapButton(tester, 'Update now');
      rig.service.failDownload(UpdateFailure.signatureInvalid);
      await tester.pumpAndSettle();

      expect(find.text('Update rejected for your safety'), findsOneWidget);
      expect(
        find.textContaining('signature could not be verified'),
        findsOneWidget,
      );
      expect(find.textContaining('Nothing was installed'), findsOneWidget);
      // Trying the same thing again would be pointless.
      expect(button('Try again'), findsNothing);
      expect(button('Close'), findsOneWidget);
      // No raw reason, URL or path is shown.
      expect(find.textContaining('signatureInvalid'), findsNothing);
      expect(find.textContaining('http'), findsNothing);

      await tapButton(tester, 'Close');
      expect(button('Close'), findsNothing);
    });

    testWidgets('a damaged download: deleted, try again', (tester) async {
      rig.service.verifyFailure = UpdateFailure.hashMismatch;
      await startWithUpdate(tester);
      await openSheet(tester);
      await tapButton(tester, 'Update now');
      rig.service.finishDownload();
      await tester.pumpAndSettle();

      expect(rig.controller.status, UpdateStatus.error);
      expect(
        find.textContaining('didn’t match the signed release'),
        findsOneWidget,
      );
      expect(button('Try again'), findsOneWidget);
    });

    testWidgets('every failure has a message and none shows a raw value', (
      tester,
    ) async {
      await startWithUpdate(tester);
      await openSheet(tester);
      for (final reason in UpdateFailure.values) {
        if (reason == UpdateFailure.cancelled) continue;
        await tapButton(tester, 'Update now');
        rig.service.failDownload(reason);
        await tester.pumpAndSettle();
        expect(rig.controller.status, UpdateStatus.error, reason: '$reason');
        expect(find.textContaining(reason.name), findsNothing);
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
        await tapButton(tester, 'Close');
        // Closing an error with a known update puts the offer back.
        expect(rig.controller.status, UpdateStatus.available);
        await openSheet(tester);
      }
    });
  });

  group('Windows swap that did not work', () {
    testWidgets('a rollback is reported once, with a way out', (tester) async {
      await pumpUpdateApp(
        tester,
        controller: rig.controller,
        platform: TargetPlatform.windows,
        readHelperResult: () async => WindowsUpdateHelperResult.rolledBack,
      );
      await tester.pumpAndSettle();
      expect(find.text('The last update didn’t finish'), findsOneWidget);

      await tester.tap(find.text('The last update didn’t finish'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('previous version is still installed'),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(bannerFinder(), findsNothing);
    });

    testWidgets('a damaged install offers the release page', (tester) async {
      await pumpUpdateApp(
        tester,
        controller: rig.controller,
        platform: TargetPlatform.windows,
        readHelperResult: () async => WindowsUpdateHelperResult.rollbackFailed,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('The last update didn’t finish'));
      await tester.pumpAndSettle();
      expect(find.textContaining('may be damaged'), findsOneWidget);
      expect(find.text('Copy link'), findsOneWidget);
    });

    for (final quiet in [
      WindowsUpdateHelperResult.none,
      WindowsUpdateHelperResult.succeeded,
    ]) {
      testWidgets('nothing to report after $quiet', (tester) async {
        await pumpUpdateApp(
          tester,
          controller: rig.controller,
          readHelperResult: () async => quiet,
        );
        await tester.pumpAndSettle();
        expect(bannerFinder(), findsNothing);
      });
    }
  });

  group('messages after a manual check', () {
    testWidgets('"up to date" clears itself so automatic checks can go on', (
      tester,
    ) async {
      rig.service.nextCheck = const UpdateUpToDate(2000);
      await pumpUpdateApp(tester, controller: rig.controller);
      await tester.pumpAndSettle();
      rig.now = rig.now.add(const Duration(days: 2));
      await rig.controller.checkNow();
      await tester.pump();
      expect(rig.controller.status, UpdateStatus.upToDate);

      await tester.pump(const Duration(seconds: 13));
      expect(rig.controller.status, UpdateStatus.idle);
    });

    testWidgets('a failed manual check shows no banner', (tester) async {
      rig.service.nextCheck = const UpdateFailed(UpdateFailure.network);
      await pumpUpdateApp(tester, controller: rig.controller);
      await tester.pumpAndSettle();
      await rig.controller.checkNow();
      await tester.pumpAndSettle();
      expect(rig.controller.status, UpdateStatus.error);
      expect(bannerFinder(), findsNothing);
    });
  });

  group('look', () {
    testWidgets('Arabic: right to left, Arabic text, Western digits', (
      tester,
    ) async {
      await startWithUpdate(tester, locale: const Locale('ar'));
      expect(find.text('يتوفر تحديث'), findsOneWidget);
      expect(find.textContaining('الإصدار'), findsOneWidget);
      expect(find.textContaining('0.3.0'), findsOneWidget);
      expect(find.textContaining('٠'), findsNothing);

      await openSheet(tester);
      expect(find.text('حدّث الآن'), findsOneWidget);
      expect(find.text('لاحقًا'), findsOneWidget);
      expect(find.text('تخطَّ هذا الإصدار'), findsOneWidget);
      expect(find.text('الجديد في هذا الإصدار'), findsOneWidget);
      // The Arabic notes come from the release, not the English fallback.
      expect(find.text('فتح أسرع.'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('حدّث الآن'))),
        TextDirection.rtl,
      );
      // On a phone the buttons are stacked, the primary one first.
      expect(
        tester.getCenter(button('حدّث الآن')).dy,
        lessThan(tester.getCenter(button('لاحقًا')).dy),
      );
      expect(
        tester.getSize(button('حدّث الآن')).width,
        tester.getSize(button('لاحقًا')).width,
      );
    });

    testWidgets('Arabic on a wide window: the primary button is on the left', (
      tester,
    ) async {
      // The real fonts, so that the buttons fit on one row as they do on a
      // device (the test font is as wide as it is tall).
      await tester.runAsync(loadBundledFonts);
      await startWithUpdate(
        tester,
        locale: const Locale('ar'),
        size: const Size(1280, 800),
      );
      await openSheet(tester);
      expect(
        tester.getCenter(button('حدّث الآن')).dx,
        lessThan(tester.getCenter(button('لاحقًا')).dx),
      );
    });

    testWidgets('English on a wide window: the primary button is last', (
      tester,
    ) async {
      await tester.runAsync(loadBundledFonts);
      await startWithUpdate(tester, size: const Size(1280, 800));
      await openSheet(tester);
      expect(
        tester.getCenter(button('Update now')).dx,
        greaterThan(tester.getCenter(button('Later')).dx),
      );
      expect(
        tester.getCenter(button('Later')).dx,
        greaterThan(tester.getCenter(button('Skip this version')).dx),
      );
    });

    testWidgets('English notes inside the Arabic app keep their direction', (
      tester,
    ) async {
      rig.service.offerUpdate(
        testManifest(notes: {'en': 'Faster unlock (really).'}),
      );
      await pumpUpdateApp(
        tester,
        controller: rig.controller,
        locale: const Locale('ar'),
      );
      await tester.pumpAndSettle();
      await openSheet(tester);
      final note = find.text('Faster unlock (really).');
      expect(note, findsOneWidget);
      expect(Directionality.of(tester.element(note)), TextDirection.ltr);
    });

    testWidgets('reduced motion: the banner is just there', (tester) async {
      rig.service.offerUpdate();
      await pumpUpdateApp(
        tester,
        controller: rig.controller,
        disableAnimations: true,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(bannerFinder(), findsOneWidget);
      final first = tester.getSize(bannerFinder()).height;
      expect(first, greaterThan(40));
      await tester.pumpAndSettle();
      expect(tester.getSize(bannerFinder()).height, first);
      expect(
        tester.getTopLeft(find.byType(AppBar)).dy,
        tester.getRect(bannerFinder()).bottom,
      );
    });

    testWidgets('with motion the banner grows in and the page slides', (
      tester,
    ) async {
      rig.service.offerUpdate();
      await pumpUpdateApp(tester, controller: rig.controller);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      final early = tester.getTopLeft(find.byType(AppBar)).dy;
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byType(AppBar)).dy, greaterThan(early));
    });

    for (final locale in [const Locale('en'), const Locale('ar')]) {
      for (final width in [360.0, 800.0]) {
        testWidgets(
          '${locale.languageCode} at 200% text, $width dp wide: no overflow',
          (tester) async {
            await tester.runAsync(loadBundledFonts);
            await startWithUpdate(
              tester,
              locale: locale,
              size: Size(width, 640),
              textScale: 2,
              openUrl: RecordingOpener().call,
            );
            expect(bannerFinder(), findsOneWidget);
            await openSheet(tester);
            expect(tester.takeException(), isNull);

            // Downloading, ready, then the longest failure texts. The sheet
            // scrolls, so the button is brought into view first.
            Future<void> tapPrimary() async {
              final primary = find.byType(FilledButton).last;
              await tester.ensureVisible(primary);
              await tester.pumpAndSettle();
              await tester.tap(primary);
              await tester.pumpAndSettle();
            }

            await tapPrimary();
            rig.service.emitProgress(1, 2);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);

            rig.service.finishDownload();
            await tester.pumpAndSettle();
            rig.installer.outcome = InstallOutcome.failed;
            await tapPrimary();
            expect(tester.takeException(), isNull);
            expect(rig.installer.installs, 1);
          },
        );
      }
    }

    testWidgets('light theme renders too', (tester) async {
      rig.service.offerUpdate();
      await pumpUpdateApp(
        tester,
        controller: rig.controller,
        brightness: Brightness.light,
      );
      await tester.pumpAndSettle();
      await openSheet(tester);
      expect(button('Update now'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a wide window shows the sheet as a dialog', (tester) async {
      await startWithUpdate(tester, size: const Size(1280, 800));
      await openSheet(tester);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(button('Update now'), findsOneWidget);
    });

    testWidgets('a phone shows it as a bottom sheet', (tester) async {
      await startWithUpdate(tester);
      await openSheet(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
    });
  });
}
