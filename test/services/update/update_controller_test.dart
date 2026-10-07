import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vaultsnap/services/settings.dart';
import 'package:vaultsnap/services/update/app_version.dart';
import 'package:vaultsnap/services/update/update_controller.dart';
import 'package:vaultsnap/services/update/update_failure.dart';
import 'package:vaultsnap/services/update/update_installer.dart';

import 'update_test_kit.dart';

void main() {
  late UpdateEnv env;
  late AppSettings settings;
  late FakeUpdateInstaller installer;
  late DateTime now;
  late int locks;
  late List<String> events;
  late UpdateController controller;

  UpdateController build() => UpdateController(
    service: env.service,
    installer: installer,
    settings: settings,
    prepareExit: () async {
      locks++;
      events.add('lock');
    },
    clock: () => now,
  );

  Future<void> boot({AppVersion? version, bool publish = true}) async {
    env = await UpdateEnv.create(version: version);
    settings = env.newSettings();
    installer = FakeUpdateInstaller();
    now = DateTime.utc(2026, 10, 7, 12);
    locks = 0;
    events = [];
    if (publish) env.publish();
    controller = build();
    final (c, e) = (controller, env);
    addTearDown(() async {
      c.dispose();
      await e.dispose();
    });
  }

  setUp(() => boot());

  int ms(DateTime t) => t.millisecondsSinceEpoch;

  /// Records every status the controller goes through.
  List<UpdateStatus> watch() {
    final seen = <UpdateStatus>[controller.status];
    controller.addListener(() {
      if (seen.last != controller.status) seen.add(controller.status);
    });
    return seen;
  }

  group('throttle', () {
    const day = Duration(hours: 24);

    test('isCheckDue', () {
      final t = ms(DateTime.utc(2026, 10, 7, 12));
      expect(UpdateController.isCheckDue(lastCheckMs: 0, nowMs: t), isTrue);
      expect(UpdateController.isCheckDue(lastCheckMs: t, nowMs: t), isFalse);
      expect(
        UpdateController.isCheckDue(
          lastCheckMs: t,
          nowMs: t + day.inMilliseconds - 1,
        ),
        isFalse,
      );
      expect(
        UpdateController.isCheckDue(
          lastCheckMs: t,
          nowMs: t + day.inMilliseconds,
        ),
        isTrue,
      );
      // The clock went backwards (or the stored time is from the future).
      expect(UpdateController.isCheckDue(lastCheckMs: t, nowMs: t - 1), isTrue);
      expect(UpdateController.isCheckDue(lastCheckMs: -5, nowMs: t), isTrue);
      expect(
        UpdateController.isCheckDue(
          lastCheckMs: t,
          nowMs: t + 3600000,
          interval: const Duration(hours: 1),
        ),
        isTrue,
      );
    });

    test('at most one automatic check per 24 hours', () async {
      // Nothing newer exists, so the controller is idle again after a check
      // and only the clock decides.
      env.net.routes.clear();
      env.publish(manifest: manifestJson(version: '0.1.0'));
      await controller.checkAutomatically();
      expect(env.net.requests, isNotEmpty);
      expect(settings.lastUpdateCheck, ms(now));
      final after = env.net.requests.length;

      // Two hours later: not due.
      now = now.add(const Duration(hours: 2));
      await controller.checkAutomatically();
      expect(env.net.requests.length, after);

      // 23h59m later: not due. 24h later: due.
      now = DateTime.utc(2026, 10, 8, 11, 59);
      await controller.checkAutomatically();
      expect(env.net.requests.length, after);
      now = DateTime.utc(2026, 10, 8, 12);
      await controller.checkAutomatically();
      expect(env.net.requests.length, greaterThan(after));
      expect(settings.lastUpdateCheck, ms(now));
    });

    test('a persisted last check from a previous run is honoured', () async {
      await settings.update((s) => s.lastUpdateCheck = ms(now) - 3600000);
      await controller.checkAutomatically();
      expect(env.net.requests, isEmpty);
      expect(controller.status, UpdateStatus.idle);
    });

    group('an offer that was lost with the process', () {
      Future<void> foundBefore() => settings.update((s) {
        s.highestSeenBuild = 2000;
        s.lastUpdateCheck = ms(now) - 3600000;
      });

      test('a restart after "found" offers the update again', () async {
        await controller.checkAutomatically();
        expect(controller.status, UpdateStatus.available);
        expect(settings.highestSeenBuild, 2000);

        // The user tapped Later and closed the app, or Android sent them to
        // "install unknown apps" and the process was recreated.
        controller.dispose();
        now = now.add(const Duration(minutes: 5));
        final restarted = build();
        addTearDown(restarted.dispose);
        final n = env.net.requests.length;

        expect(restarted.autoCheckDue, isTrue);
        await restarted.checkAutomatically();

        expect(env.net.requests.length, greaterThan(n));
        expect(restarted.status, UpdateStatus.available);
        expect(restarted.manifest!.version.version, '0.2.0');
      });

      test(
        'the 24 hour limit is skipped once per run, not every time',
        () async {
          await foundBefore();
          // The release was pulled meanwhile: nothing newer is published.
          env.net.routes.clear();
          env.publish(manifest: manifestJson(version: '0.1.0'));
          expect(controller.autoCheckDue, isTrue);

          await controller.checkAutomatically();
          final n = env.net.requests.length;
          expect(n, greaterThan(0));
          expect(controller.status, UpdateStatus.idle);

          now = now.add(const Duration(hours: 2));
          expect(controller.autoCheckDue, isFalse);
          await controller.checkAutomatically();
          expect(env.net.requests.length, n);
        },
      );

      test('an offline start keeps the offer owed', () async {
        await foundBefore();
        env.net.routes.clear(); // everything 404 -> a transient failure
        await controller.checkAutomatically();
        expect(controller.status, UpdateStatus.idle);

        now = now.add(const Duration(minutes: 5));
        expect(controller.autoCheckDue, isFalse, reason: 'no hammering');
        now = now.add(const Duration(minutes: 40));
        expect(controller.autoCheckDue, isTrue);

        env.publish();
        await controller.checkAutomatically();
        expect(controller.status, UpdateStatus.available);
      });

      test('a skipped build stays quiet', () async {
        await foundBefore();
        await settings.update((s) => s.skippedBuild = 2000);
        expect(controller.autoCheckDue, isFalse);
        await controller.checkAutomatically();
        expect(env.net.requests, isEmpty);
      });

      test('an installed build is not offered again', () async {
        await settings.update((s) {
          s.highestSeenBuild = 1000; // the installed build
          s.lastUpdateCheck = ms(now) - 3600000;
        });
        expect(controller.autoCheckDue, isFalse);
        await controller.checkAutomatically();
        expect(env.net.requests, isEmpty);
      });

      test('turned off in settings: still no automatic check', () async {
        await foundBefore();
        await settings.update((s) => s.checkUpdates = false);
        await controller.checkAutomatically();
        expect(env.net.requests, isEmpty);
      });
    });

    test('a clock set back triggers a check', () async {
      await settings.update((s) => s.lastUpdateCheck = ms(now) + 86400000 * 30);
      await controller.checkAutomatically();
      expect(env.net.requests, isNotEmpty);
    });

    test('turned off in settings: never checks automatically', () async {
      await settings.update((s) => s.checkUpdates = false);
      await controller.checkAutomatically();
      expect(env.net.requests, isEmpty);
      expect(controller.status, UpdateStatus.idle);
      // ...but a manual check still works.
      await controller.checkNow();
      expect(controller.status, UpdateStatus.available);
    });

    test('a manual check ignores the 24 hour limit', () async {
      await controller.checkAutomatically();
      controller.dismiss();
      final n = env.net.requests.length;
      await controller.checkNow();
      expect(env.net.requests.length, greaterThan(n));
    });

    test('offline: not counted, retried soon but not on every call', () async {
      env.net.routes.clear(); // everything 404 -> badStatus (transient)
      await controller.checkAutomatically();
      expect(
        controller.status,
        UpdateStatus.idle,
        reason: 'automatic = silent',
      );
      expect(controller.failure, UpdateFailure.badStatus);
      expect(
        settings.lastUpdateCheck,
        0,
        reason: 'a failed attempt is not a check',
      );
      final n = env.net.requests.length;

      now = now.add(const Duration(minutes: 5));
      await controller.checkAutomatically();
      expect(env.net.requests.length, n, reason: 'no hammering');

      now = now.add(const Duration(minutes: 40));
      env.publish();
      await controller.checkAutomatically();
      expect(env.net.requests.length, greaterThan(n));
      expect(controller.status, UpdateStatus.available);
    });

    test('a signature failure is counted (no retry for a day)', () async {
      env.net.routes.clear();
      env.publish(signedBy: await TestSigner.create());
      await controller.checkAutomatically();
      expect(settings.lastUpdateCheck, ms(now));
      expect(controller.failure, UpdateFailure.signatureInvalid);
      expect(controller.status, UpdateStatus.idle);
      expect(controller.autoCheckDue, isFalse);
    });
  });

  group('checking', () {
    test('automatic check offers an update quietly', () async {
      final seen = watch();
      await controller.checkAutomatically();
      expect(seen, [
        UpdateStatus.idle,
        UpdateStatus.checking,
        UpdateStatus.available,
      ]);
      expect(controller.manifest!.version.version, '0.2.0');
      expect(controller.asset!.name, 'app-release.apk');
      expect(controller.failure, isNull);
      expect(settings.highestSeenBuild, 2000);
    });

    test('automatic check with nothing newer shows nothing', () async {
      env.net.routes.clear();
      env.publish(manifest: manifestJson(version: '0.1.0'));
      await controller.checkAutomatically();
      expect(controller.status, UpdateStatus.idle);
      expect(settings.lastUpdateCheck, ms(now));
    });

    test('manual check says "up to date"', () async {
      env.net.routes.clear();
      env.publish(manifest: manifestJson(version: '0.1.0'));
      await controller.checkNow();
      expect(controller.status, UpdateStatus.upToDate);
      controller.dismiss();
      expect(controller.status, UpdateStatus.idle);
    });

    test('manual check reports errors', () async {
      env.net.routes.clear();
      await controller.checkNow();
      expect(controller.status, UpdateStatus.error);
      expect(controller.failure, UpdateFailure.badStatus);
      controller.dismiss();
      expect(controller.status, UpdateStatus.idle);
      expect(controller.failure, isNull);
    });

    test(
      'dev build (no APP_VERSION): disabled, no request, no state change',
      () async {
        await env.dispose();
        await boot(version: AppVersion.none);
        expect(controller.enabled, isFalse);
        final seen = watch();
        await controller.checkAutomatically();
        await controller.checkNow();
        await controller.startDownload();
        await controller.installUpdate();
        expect(env.net.requests, isEmpty);
        expect(env.leftovers(), isEmpty);
        expect(seen, [UpdateStatus.idle]);
        expect(settings.lastUpdateCheck, 0);
      },
    );

    test('cancelling a check goes back to idle', () async {
      env.net.routes.clear();
      env.publish();
      final gate = Completer<http.StreamedResponse>();
      var asked = false;
      env.net.on(env.config.manifestUri, (_) {
        asked = true;
        return gate.future;
      });
      final future = controller.checkNow();
      await waitFor(() => asked);
      expect(controller.status, UpdateStatus.checking);
      controller.cancel();
      await future;
      expect(controller.status, UpdateStatus.idle);
      expect(controller.failure, isNull);
    });

    test(
      'a replayed old signed manifest is refused and does not lower the floor',
      () async {
        await settings.update((s) => s.highestSeenBuild = 5000);
        env.net.routes.clear();
        env.publish(manifest: manifestJson(version: '0.3.0'));
        await controller.checkNow();
        expect(controller.status, UpdateStatus.error);
        expect(controller.failure, UpdateFailure.rollback);
        expect(settings.highestSeenBuild, 5000);
      },
    );

    test('the highest build seen only ever goes up', () async {
      await controller.checkNow(); // 0.2.0 -> 2000
      expect(settings.highestSeenBuild, 2000);
      env.net.routes.clear();
      env.publish(manifest: manifestJson(version: '0.4.0'));
      await controller.checkNow();
      expect(settings.highestSeenBuild, 4000);
      // A reloaded settings object remembers it.
      final reloaded = AppSettings(File('${env.dir.path}/s.json'));
      await reloaded.load();
      expect(reloaded.highestSeenBuild, 4000);
    });

    test('a failed check does not move the replay floor', () async {
      await settings.update((s) => s.highestSeenBuild = 1500);
      env.net.routes.clear();
      env.publish(signedBy: await TestSigner.create());
      await controller.checkNow();
      expect(settings.highestSeenBuild, 1500);
    });
  });

  group('skip this version', () {
    test('automatic checks stay quiet about the skipped build only', () async {
      await controller.checkAutomatically();
      expect(controller.status, UpdateStatus.available);
      await controller.skipThisVersion();
      expect(controller.status, UpdateStatus.idle);
      expect(controller.manifest, isNull);
      expect(settings.skippedBuild, 2000);

      // 25 hours later the same release is still silent...
      now = now.add(const Duration(hours: 25));
      await controller.checkAutomatically();
      expect(controller.status, UpdateStatus.idle);
      expect(env.net.requests, isNotEmpty);

      // ...a newer one is offered again.
      env.net.routes.clear();
      env.publish(manifest: manifestJson(version: '0.2.1'));
      now = now.add(const Duration(hours: 25));
      await controller.checkAutomatically();
      expect(controller.status, UpdateStatus.available);
      expect(controller.manifest!.version.version, '0.2.1');
    });

    test('a manual check still shows the skipped version', () async {
      await settings.update((s) => s.skippedBuild = 2000);
      await controller.checkNow();
      expect(controller.status, UpdateStatus.available);
    });

    test('skipping survives a restart', () async {
      await controller.checkAutomatically();
      await controller.skipThisVersion();
      final reloaded = AppSettings(File('${env.dir.path}/s.json'));
      await reloaded.load();
      expect(reloaded.skippedBuild, 2000);
    });

    test('skipping after the download removes the files', () async {
      await controller.checkNow();
      await controller.startDownload();
      expect(env.leftovers(), isNotEmpty);
      await controller.skipThisVersion();
      expect(env.leftovers(), isEmpty);
      expect(controller.status, UpdateStatus.idle);
    });
  });

  group('downloading', () {
    test('available -> downloading -> verifying -> readyToInstall', () async {
      await controller.checkNow();
      final seen = watch();
      final progress = <double?>[];
      controller.addListener(() => progress.add(controller.progress));
      await controller.startDownload();
      expect(seen, [
        UpdateStatus.available,
        UpdateStatus.downloading,
        UpdateStatus.verifying,
        UpdateStatus.readyToInstall,
      ]);
      expect(
        progress.whereType<double>().every((p) => p >= 0 && p <= 1),
        isTrue,
      );
      expect(progress.whereType<double>(), contains(1.0));
      expect(controller.progress, isNull);
      expect(controller.failure, isNull);
    });

    test('startDownload does nothing unless an update is on offer', () async {
      await controller.startDownload();
      expect(controller.status, UpdateStatus.idle);
      expect(env.net.requests, isEmpty);
    });

    test(
      'a package with the wrong hash ends in an error and no files',
      () async {
        env.net.routes.clear();
        env.publish(apk: payload(3000, seed: 99));
        await controller.checkNow();
        await controller.startDownload();
        expect(controller.status, UpdateStatus.error);
        expect(controller.failure, UpdateFailure.hashMismatch);
        expect(env.leftovers(), isEmpty);
        // The offer comes back on dismiss, so the user can retry.
        controller.dismiss();
        expect(controller.status, UpdateStatus.available);
      },
    );

    test('truncated package: error, no files', () async {
      env.net.routes.clear();
      env.publish(apk: payload(100, seed: 1));
      await controller.checkNow();
      await controller.startDownload();
      expect(controller.failure, UpdateFailure.truncated);
      expect(env.leftovers(), isEmpty);
    });

    test('cancelling goes back to available and deletes the partial file', () async {
      await controller.checkNow();
      final stalling = StallingBody(Uint8List(10));
      env.net.on(
        Uri.parse(
          'https://objects.githubusercontent.com/v0.2.0/app-release.apk?sig=1',
        ),
        (_) => stalling.response(),
      );
      final future = controller.startDownload();
      await waitFor(() => stalling.listened);
      expect(controller.status, UpdateStatus.downloading);
      controller.cancel();
      await future;
      expect(controller.status, UpdateStatus.available);
      expect(controller.failure, isNull);
      expect(env.leftovers(), isEmpty);
      expect(stalling.cancelled, isTrue);
    });

    test('actions are ignored while busy', () async {
      await controller.checkNow();
      final gate = Completer<http.StreamedResponse>();
      var asked = false;
      env.net.on(
        Uri.parse(
          'https://objects.githubusercontent.com/v0.2.0/app-release.apk?sig=1',
        ),
        (_) {
          asked = true;
          return gate.future;
        },
      );
      final first = controller.startDownload();
      await waitFor(() => asked);
      final n = env.net.requests.length;
      await controller.startDownload();
      await controller.checkNow();
      await controller.checkAutomatically();
      await controller.skipThisVersion();
      await controller.installUpdate();
      expect(env.net.requests.length, n);
      expect(controller.status, UpdateStatus.downloading);
      controller.cancel();
      await first;
    });
  });

  group('installing', () {
    Future<void> ready() async {
      await controller.checkNow();
      await controller.startDownload();
      expect(controller.status, UpdateStatus.readyToInstall);
    }

    test('hands a verified private copy to the installer', () async {
      await ready();
      await controller.installUpdate();
      expect(installer.installed, hasLength(1));
      expect(installer.lastBytes, payload(3000, seed: 1));
      expect(installer.prepareExitCalls, 1);
      expect(locks, 1, reason: 'vault locked exactly once');
      expect(controller.installOutcome, InstallOutcome.started);
      // After "started" the system installer may still read the file.
      expect(installer.installed.single.existsSync(), isTrue);
      expect(controller.status, UpdateStatus.readyToInstall);
    });

    test(
      'the file given to the installer is a copy, not the download',
      () async {
        await ready();
        final dirs = env.workRoot.listSync().map((e) => e.path).toSet();
        expect(dirs, hasLength(1));
        await controller.installUpdate();
        final handed = installer.installed.single;
        expect(handed.path.startsWith(dirs.single), isFalse);
        expect(env.workRoot.listSync(), hasLength(2));
      },
    );

    test('the vault is locked before the install starts', () async {
      final order = <String>[];
      final fake = _OrderedInstaller(order);
      controller.dispose();
      controller = UpdateController(
        service: env.service,
        installer: fake,
        settings: settings,
        prepareExit: () async => order.add('lock'),
        clock: () => now,
      );
      await ready();
      await controller.installUpdate();
      expect(order, ['lock', 'handover']);
    });

    test('prepareExit that is called twice only locks once', () async {
      installer = _TwiceInstaller();
      controller.dispose();
      controller = build();
      await ready();
      await controller.installUpdate();
      expect(locks, 1);
    });

    test('installer outcomes other than started allow a retry', () async {
      for (final outcome in [
        InstallOutcome.permissionRequired,
        InstallOutcome.cancelled,
        InstallOutcome.failed,
        InstallOutcome.unsupported,
      ]) {
        installer.outcome = outcome;
        if (controller.status != UpdateStatus.readyToInstall) await ready();
        await controller.installUpdate();
        expect(controller.installOutcome, outcome);
        expect(
          controller.status,
          UpdateStatus.readyToInstall,
          reason: '$outcome',
        );
        expect(
          installer.installed.last.existsSync(),
          isFalse,
          reason: 'staging removed',
        );
      }
      // The retry works and re-stages a fresh verified copy.
      installer.outcome = InstallOutcome.started;
      await controller.installUpdate();
      expect(controller.installOutcome, InstallOutcome.started);
      expect(installer.lastBytes, payload(3000, seed: 1));
    });

    test('an installer that throws is reported as failed', () async {
      installer.error = StateError('secret path /home/someone/x');
      await ready();
      await controller.installUpdate();
      expect(controller.installOutcome, InstallOutcome.failed);
      expect(controller.status, UpdateStatus.readyToInstall);
      expect(controller.failure, isNull);
    });

    test(
      'a package changed on disk after verification is not installed',
      () async {
        await ready();
        final dl = env.workRoot.listSync().single as Directory;
        final file = File('${dl.path}/app-release.apk');
        final bytes = file.readAsBytesSync()..[0] ^= 1;
        file.writeAsBytesSync(bytes);
        await controller.installUpdate();
        expect(installer.installed, isEmpty);
        expect(locks, 0, reason: 'vault stays unlocked: nothing happened');
        expect(controller.status, UpdateStatus.error);
        expect(controller.failure, UpdateFailure.hashMismatch);
        expect(env.leftovers(), isEmpty);
      },
    );

    test('installUpdate does nothing before the package is verified', () async {
      await controller.checkNow();
      await controller.installUpdate();
      expect(installer.installed, isEmpty);
      expect(controller.status, UpdateStatus.available);
    });

    test('a controller disposed mid-way does not notify afterwards', () async {
      await controller.checkNow();
      controller.dispose();
      await controller.startDownload();
      // No exception, no notification after dispose.
    });
  });

  group('next start', () {
    test('leftovers are swept even when no check is due', () async {
      await settings.update((s) => s.lastUpdateCheck = ms(now) - 60000);
      await env.workspace.create();
      expect(env.leftovers(), isNotEmpty);
      await controller.checkAutomatically();
      expect(env.net.requests, isEmpty, reason: 'not due');
      expect(env.leftovers(), isEmpty);
    });

    test('...and also when automatic checks are switched off', () async {
      await settings.update((s) => s.checkUpdates = false);
      await env.workspace.create();
      await controller.checkAutomatically();
      expect(env.net.requests, isEmpty);
      expect(env.leftovers(), isEmpty);
    });

    test('a development build touches no file at all', () async {
      await env.dispose();
      await boot(version: AppVersion.none);
      final marker = await env.workspace.create();
      await controller.checkAutomatically();
      expect(marker.existsSync(), isTrue);
    });

    test(
      'leftovers of an earlier update are swept at the first check',
      () async {
        await env.workspace.create();
        await env.workspace.create();
        expect(env.leftovers(), isNotEmpty);
        await controller.checkAutomatically();
        expect(env.leftovers(), isEmpty);
      },
    );
  });
}

class _OrderedInstaller implements UpdateInstaller {
  _OrderedInstaller(this.order);

  final List<String> order;

  @override
  Future<InstallOutcome> install(
    File package, {
    required Future<void> Function() prepareExit,
  }) async {
    await prepareExit();
    order.add('handover');
    return InstallOutcome.started;
  }
}

class _TwiceInstaller extends FakeUpdateInstaller {
  @override
  Future<InstallOutcome> install(
    File package, {
    required Future<void> Function() prepareExit,
  }) async {
    await prepareExit();
    await prepareExit();
    return InstallOutcome.started;
  }
}
