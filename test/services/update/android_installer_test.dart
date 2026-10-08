import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:hisn/services/update/android_installer.dart';
import 'package:hisn/services/update/update_installer.dart';

/// The native side is mocked, so these tests check what the Dart side asks
/// for, in which order, and how it maps every answer. The APK bytes are
/// synthetic: the Dart side never parses them (the platform does, natively).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('app.vaultsnap/platform');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory tmp;
  late Directory updatesDir;
  late File package;
  late Uint8List packageBytes;

  /// `methodName` or `installApk:verify`, `prepareExit`, in the order seen.
  late List<String> events;
  late List<MethodCall> calls;
  late Map<String, Object? Function(MethodCall call)> native;
  late AndroidUpdateInstaller installer;

  Future<void> prepareExit() async => events.add('prepareExit');

  PlatformException nativeError(String code) =>
      PlatformException(code: code, message: 'text that must never surface');

  bool isVerifyCall(MethodCall call) =>
      call.method == 'installApk' &&
      (call.arguments as Map)['verifyOnly'] == true;

  List<String> updatesDirFiles() => updatesDir.existsSync()
      ? updatesDir.listSync().map((e) => e.path).toList()
      : <String>[];

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('android_installer_test_');
    updatesDir = Directory(p.join(tmp.path, 'cache', 'updates'));
    final staging = Directory(p.join(tmp.path, 'staging'))..createSync();
    package = File(p.join(staging.path, 'package.apk'));
    // More than one copy buffer, with a pattern so a misplaced chunk shows.
    packageBytes = Uint8List.fromList(
      List<int>.generate(700 * 1024 + 123, (i) => (i * 7 + i ~/ 251) & 0xff),
    );
    package.writeAsBytesSync(packageBytes);

    events = [];
    calls = [];
    native = {
      'canInstallPackages': (_) => true,
      'openInstallSettings': (_) => true,
      'prepareUpdatesDir': (_) {
        updatesDir.createSync(recursive: true);
        return updatesDir.path;
      },
      'installApk': (call) =>
          isVerifyCall(call) ? 'verified' : 'installer_started',
    };
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      events.add(isVerifyCall(call) ? 'installApk:verify' : call.method);
      final handler = native[call.method];
      if (handler == null) throw MissingPluginException();
      return handler(call);
    });
    installer = AndroidUpdateInstaller();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    tmp.deleteSync(recursive: true);
  });

  group('consent', () {
    test('missing: opens the settings page and does nothing else', () async {
      native['canInstallPackages'] = (_) => false;

      final outcome = await installer.install(
        package,
        prepareExit: prepareExit,
      );

      expect(outcome, InstallOutcome.permissionRequired);
      expect(events, ['canInstallPackages', 'openInstallSettings']);
      // Nothing was copied and the vault was not locked for nothing.
      expect(updatesDir.existsSync(), isFalse);
      expect(installer.lastError, isNull);
      expect(package.readAsBytesSync(), packageBytes);
    });

    test('missing and no settings page: still permissionRequired', () async {
      native['canInstallPackages'] = (_) => false;
      native['openInstallSettings'] = (_) => throw nativeError('no_activity');

      final outcome = await installer.install(
        package,
        prepareExit: prepareExit,
      );

      expect(outcome, InstallOutcome.permissionRequired);
      expect(events, ['canInstallPackages', 'openInstallSettings']);
    });

    test(
      'revoked before the check: settings opened, vault not locked',
      () async {
        native['installApk'] = (call) =>
            isVerifyCall(call) ? throw nativeError('permission_denied') : 'x';

        final outcome = await installer.install(
          package,
          prepareExit: prepareExit,
        );

        expect(outcome, InstallOutcome.permissionRequired);
        expect(events, [
          'canInstallPackages',
          'prepareUpdatesDir',
          'installApk:verify',
          'openInstallSettings',
        ]);
        expect(updatesDirFiles(), isEmpty, reason: 'the copy is removed');
      },
    );

    test('revoked at the hand-over: settings opened', () async {
      native['installApk'] = (call) => isVerifyCall(call)
          ? 'verified'
          : throw nativeError('permission_denied');

      final outcome = await installer.install(
        package,
        prepareExit: prepareExit,
      );

      expect(outcome, InstallOutcome.permissionRequired);
      expect(events.last, 'openInstallSettings');
      expect(updatesDirFiles(), isEmpty);
    });
  });

  group('success', () {
    test(
      'copies, checks, locks the vault, then starts the installer',
      () async {
        final outcome = await installer.install(
          package,
          prepareExit: prepareExit,
        );

        expect(outcome, InstallOutcome.started);
        expect(installer.lastError, isNull);
        // The vault is locked after the dry-run check and before the start.
        expect(events, [
          'canInstallPackages',
          'prepareUpdatesDir',
          'installApk:verify',
          'prepareExit',
          'installApk',
        ]);

        final checkPath =
            (calls.firstWhere(isVerifyCall).arguments as Map)['path'] as String;
        final startCall = calls.last;
        expect(startCall.method, 'installApk');
        expect(isVerifyCall(startCall), isFalse);
        final startPath = (startCall.arguments as Map)['path'] as String;
        expect(startPath, checkPath, reason: 'both calls use the same copy');

        // The copy lies directly in the prepared folder and is byte-identical;
        // it is left in place for the installer to read.
        expect(p.dirname(startPath), updatesDir.path);
        expect(startPath, endsWith('.apk'));
        expect(File(startPath).readAsBytesSync(), packageBytes);
        // The staged package itself is never touched.
        expect(package.readAsBytesSync(), packageBytes);
      },
    );

    test('each install uses a new random file name', () async {
      await installer.install(package, prepareExit: prepareExit);
      await installer.install(package, prepareExit: prepareExit);

      final paths = calls
          .where((c) => c.method == 'installApk' && !isVerifyCall(c))
          .map((c) => (c.arguments as Map)['path'] as String)
          .toList();
      expect(paths, hasLength(2));
      expect(paths[0], isNot(paths[1]));
      for (final path in paths) {
        expect(
          p.basename(path),
          matches(RegExp(r'^update-[0-9a-f]{32}\.apk$')),
        );
      }
    });

    test('lastError is cleared by a later success', () async {
      native['installApk'] = (call) => throw nativeError('not_newer');
      await installer.install(package, prepareExit: prepareExit);
      expect(installer.lastError, AndroidInstallError.notNewer);

      native['installApk'] = (call) =>
          isVerifyCall(call) ? 'verified' : 'installer_started';
      final outcome = await installer.install(
        package,
        prepareExit: prepareExit,
      );

      expect(outcome, InstallOutcome.started);
      expect(installer.lastError, isNull);
    });
  });

  group('native error codes', () {
    // Every code the native side can answer, and what the caller learns.
    const codes = <String, AndroidInstallError>{
      'apk_unreadable': AndroidInstallError.apkUnreadable,
      'wrong_package': AndroidInstallError.wrongPackage,
      'not_newer': AndroidInstallError.notNewer,
      'signature_mismatch': AndroidInstallError.signatureMismatch,
      'path_not_allowed': AndroidInstallError.pathNotAllowed,
      'no_installer': AndroidInstallError.noInstaller,
      'install_failed': AndroidInstallError.installFailed,
      'busy': AndroidInstallError.installFailed,
      'bad_arguments': AndroidInstallError.installFailed,
      'updates_dir_unavailable': AndroidInstallError.installFailed,
      'a_code_from_the_future': AndroidInstallError.installFailed,
    };

    for (final entry in codes.entries) {
      test('${entry.key} at the check: failed, vault left unlocked', () async {
        native['installApk'] = (call) => throw nativeError(entry.key);

        final outcome = await installer.install(
          package,
          prepareExit: prepareExit,
        );

        expect(outcome, InstallOutcome.failed);
        expect(installer.lastError, entry.value);
        expect(events, isNot(contains('prepareExit')));
        expect(updatesDirFiles(), isEmpty, reason: 'the copy is removed');
        expect(package.readAsBytesSync(), packageBytes);
      });

      test('${entry.key} at the start: failed, copy removed', () async {
        native['installApk'] = (call) =>
            isVerifyCall(call) ? 'verified' : throw nativeError(entry.key);

        final outcome = await installer.install(
          package,
          prepareExit: prepareExit,
        );

        expect(outcome, InstallOutcome.failed);
        expect(installer.lastError, entry.value);
        // The check passed, so the vault was locked before the start.
        expect(events, contains('prepareExit'));
        expect(updatesDirFiles(), isEmpty);
      });
    }

    test('unsupported (not the main activity) maps to unsupported', () async {
      native['prepareUpdatesDir'] = (_) => throw nativeError('unsupported');

      final outcome = await installer.install(
        package,
        prepareExit: prepareExit,
      );

      expect(outcome, InstallOutcome.unsupported);
      expect(installer.lastError, isNull);
      expect(events, isNot(contains('prepareExit')));
    });

    test('no native side at all maps to unsupported', () async {
      messenger.setMockMethodCallHandler(channel, null);

      final outcome = await installer.install(
        package,
        prepareExit: prepareExit,
      );

      expect(outcome, InstallOutcome.unsupported);
      expect(events, isEmpty);
    });

    test('an unexpected answer is a failure, not a success', () async {
      native['installApk'] = (call) => isVerifyCall(call) ? null : 'x';

      final outcome = await installer.install(
        package,
        prepareExit: prepareExit,
      );

      expect(outcome, InstallOutcome.failed);
      expect(installer.lastError, AndroidInstallError.installFailed);
      expect(events, isNot(contains('prepareExit')));
      expect(updatesDirFiles(), isEmpty);
    });

    test('an installer start that is not confirmed is a failure', () async {
      native['installApk'] = (call) => isVerifyCall(call) ? 'verified' : true;

      final outcome = await installer.install(
        package,
        prepareExit: prepareExit,
      );

      expect(outcome, InstallOutcome.failed);
      expect(installer.lastError, AndroidInstallError.installFailed);
      expect(updatesDirFiles(), isEmpty);
    });
  });

  group('locking the vault', () {
    test('a prepareExit that throws stops the install', () async {
      final outcome = await installer.install(
        package,
        prepareExit: () async {
          events.add('prepareExit');
          throw StateError('keys could not be wiped');
        },
      );

      expect(outcome, InstallOutcome.failed);
      expect(installer.lastError, AndroidInstallError.prepareExitFailed);
      // The system installer was never started.
      expect(
        calls.where((c) => c.method == 'installApk' && !isVerifyCall(c)),
        isEmpty,
      );
      expect(updatesDirFiles(), isEmpty);
    });

    test('prepareExit is awaited before the installer is started', () async {
      var finished = false;
      bool? lockedWhenStarted;
      native['installApk'] = (call) {
        if (isVerifyCall(call)) return 'verified';
        lockedWhenStarted = finished;
        return 'installer_started';
      };

      final outcome = await installer.install(
        package,
        prepareExit: () async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          finished = true;
        },
      );

      expect(outcome, InstallOutcome.started);
      expect(lockedWhenStarted, isTrue);
    });
  });

  group('copying', () {
    test('a missing source is a copy failure', () async {
      package.deleteSync();

      final outcome = await installer.install(
        package,
        prepareExit: prepareExit,
      );

      expect(outcome, InstallOutcome.failed);
      expect(installer.lastError, AndroidInstallError.copyFailed);
      expect(events, ['canInstallPackages', 'prepareUpdatesDir']);
      expect(updatesDirFiles(), isEmpty);
    });

    test('an empty source is a copy failure', () async {
      package.writeAsBytesSync(const []);

      final outcome = await installer.install(
        package,
        prepareExit: prepareExit,
      );

      expect(outcome, InstallOutcome.failed);
      expect(installer.lastError, AndroidInstallError.copyFailed);
      expect(updatesDirFiles(), isEmpty);
    });

    test(
      'a package over the size cap stops the copy and leaves nothing',
      () async {
        installer = AndroidUpdateInstaller(maxBytes: packageBytes.length - 1);

        final outcome = await installer.install(
          package,
          prepareExit: prepareExit,
        );

        expect(outcome, InstallOutcome.failed);
        expect(installer.lastError, AndroidInstallError.copyFailed);
        expect(events, isNot(contains('installApk:verify')));
        expect(updatesDirFiles(), isEmpty, reason: 'no partial copy is left');
      },
    );

    test('a package exactly at the cap is copied', () async {
      installer = AndroidUpdateInstaller(maxBytes: packageBytes.length);

      final outcome = await installer.install(
        package,
        prepareExit: prepareExit,
      );

      expect(outcome, InstallOutcome.started);
    });

    test('no updates folder from the native side is a copy failure', () async {
      native['prepareUpdatesDir'] = (_) => null;

      final outcome = await installer.install(
        package,
        prepareExit: prepareExit,
      );

      expect(outcome, InstallOutcome.failed);
      expect(installer.lastError, AndroidInstallError.copyFailed);
      expect(events, ['canInstallPackages', 'prepareUpdatesDir']);
    });

    test(
      'an updates folder that cannot be written is a copy failure',
      () async {
        // A path whose parent is a regular file cannot be written into.
        final blocker = File(p.join(tmp.path, 'blocker'))
          ..writeAsStringSync('x');
        native['prepareUpdatesDir'] = (_) => p.join(blocker.path, 'updates');

        final outcome = await installer.install(
          package,
          prepareExit: prepareExit,
        );

        expect(outcome, InstallOutcome.failed);
        expect(installer.lastError, AndroidInstallError.copyFailed);
        expect(events, ['canInstallPackages', 'prepareUpdatesDir']);
      },
    );
  });
}
