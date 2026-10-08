import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:hisn/core/crypto/crypto.dart';
import 'package:hisn/services/update/app_version.dart';
import 'package:hisn/services/update/update_manifest.dart';
import 'package:hisn/services/update/update_providers.dart';

import 'update_ui_kit.dart';

/// Where the updater is wired in (`main.dart` calls these): who gets one, and
/// what may be opened in a browser.
void main() {
  late Directory support;
  late MemorySettings settings;

  setUp(() {
    support = Directory.systemTemp.createTempSync('vs_upd_prov');
    settings = MemorySettings();
  });
  tearDown(() => support.deleteSync(recursive: true));

  final release = AppVersion.tryParse('0.2.0')!;

  group('createUpdateController', () {
    test('a release build on Android gets an updater', () async {
      final sodium = await loadSodium();
      final c = createUpdateController(
        sodium: sodium,
        supportDir: support,
        settings: settings,
        prepareExit: () async {},
        version: release,
        platform: UpdatePlatform.android,
        installer: RecordingInstaller(),
      );
      expect(c, isNotNull);
      expect(c!.enabled, isTrue);
      expect(c.status.name, 'idle');
      c.dispose();
    });

    test('so does Windows', () async {
      final sodium = await loadSodium();
      final c = createUpdateController(
        sodium: sodium,
        supportDir: support,
        settings: settings,
        prepareExit: () async {},
        version: release,
        platform: UpdatePlatform.windows,
        installer: RecordingInstaller(),
      );
      expect(c?.enabled, isTrue);
      c?.dispose();
    });

    test('the autofill entry point never updates', () async {
      final sodium = await loadSodium();
      expect(
        createUpdateController(
          sodium: sodium,
          supportDir: support,
          settings: settings,
          prepareExit: () async {},
          forAutofill: true,
          version: release,
          platform: UpdatePlatform.android,
        ),
        isNull,
      );
    });

    test('a development build has no updater at all', () async {
      final sodium = await loadSodium();
      expect(
        createUpdateController(
          sodium: sodium,
          supportDir: support,
          settings: settings,
          prepareExit: () async {},
          version: AppVersion.none,
          platform: UpdatePlatform.android,
        ),
        isNull,
      );
      // And this test run is one: it was not compiled with APP_VERSION.
      expect(AppVersion.current.enabled, isFalse);
      expect(
        createUpdateController(
          sodium: sodium,
          supportDir: support,
          settings: settings,
          prepareExit: () async {},
          platform: UpdatePlatform.android,
        ),
        isNull,
      );
    });

    test('other platforms (iOS, macOS, Linux) have none', () async {
      // The test host is Linux: no platform given means no updater.
      final sodium = await loadSodium();
      expect(UpdatePlatform.current, isNull);
      expect(
        createUpdateController(
          sodium: sodium,
          supportDir: support,
          settings: settings,
          prepareExit: () async {},
          version: release,
        ),
        isNull,
      );
    });

    test('its files go to a folder of its own, not into the vault folder', () {
      expect(updateWorkFolderName, 'updates');
      expect(updateWorkFolderName, isNot('vault'));
      expect(
        p.join(support.path, updateWorkFolderName),
        isNot(contains('vault')),
      );
    });

    test(
      'nothing is created or requested when the controller is built',
      () async {
        final sodium = await loadSodium();
        final c = createUpdateController(
          sodium: sodium,
          supportDir: support,
          settings: settings,
          prepareExit: () async {},
          version: release,
          platform: UpdatePlatform.android,
          installer: RecordingInstaller(),
        );
        expect(support.listSync(), isEmpty);
        c?.dispose();
      },
    );
  });

  group('release page', () {
    test('is the public release list of the app repository', () {
      expect(
        releasePageUri.toString(),
        'https://github.com/OmarAlnasser/Password/releases/latest',
      );
      expect(isReleasePageUrl(releasePageUri), isTrue);
    });

    test('only that page may be opened in a browser', () {
      bool ok(String url) => isReleasePageUrl(Uri.parse(url));
      expect(ok('https://github.com/OmarAlnasser/Password/releases'), isTrue);
      expect(
        ok('https://github.com/OmarAlnasser/Password/releases/tag/v0.2.0'),
        isTrue,
      );
      expect(ok('http://github.com/OmarAlnasser/Password/releases'), isFalse);
      expect(ok('https://github.com/OmarAlnasser/Other/releases'), isFalse);
      expect(ok('https://github.com/OmarAlnasser/Password'), isFalse);
      expect(
        ok('https://github.com/OmarAlnasser/Password/releasesevil'),
        isFalse,
      );
      expect(
        ok('https://evil.example/OmarAlnasser/Password/releases'),
        isFalse,
      );
      expect(
        ok('https://github.com.evil.example/OmarAlnasser/Password/releases'),
        isFalse,
      );
      expect(
        ok('https://user@github.com/OmarAlnasser/Password/releases'),
        isFalse,
      );
      expect(
        ok('https://github.com:8443/OmarAlnasser/Password/releases'),
        isFalse,
      );
      expect(ok('file:///etc/passwd'), isFalse);
      expect(ok('javascript:alert(1)'), isFalse);
      expect(ok('rundll32.exe'), isFalse);
    });

    test('a browser is only offered where the app can start one', () {
      // Windows and Android; the test host is Linux.
      expect(
        platformUrlOpener == null,
        !Platform.isWindows && !Platform.isAndroid,
      );
    });

    group('opening the page on Android', () {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('app.vaultsnap/platform');
      late List<MethodCall> calls;
      Object? answer;

      setUp(() {
        calls = [];
        answer = true;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              final a = answer;
              if (a is Exception) throw a;
              return a;
            });
      });

      tearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      test('asks the native side to open the release page', () async {
        final opened = await openReleasePageOnAndroid(releasePageUri);

        expect(opened, isTrue);
        expect(calls, hasLength(1));
        expect(calls.single.method, 'openReleasePage');
        expect(calls.single.arguments, {'url': releasePageUri.toString()});
      });

      test('nothing but the release page ever reaches the channel', () async {
        for (final url in [
          'http://github.com/OmarAlnasser/Password/releases',
          'https://evil.example/OmarAlnasser/Password/releases',
          'https://github.com/OmarAlnasser/Other/releases',
          'https://github.com/OmarAlnasser/Password',
          'intent://scan/#Intent;scheme=zxing;end',
          'file:///etc/passwd',
        ]) {
          expect(await openReleasePageOnAndroid(Uri.parse(url)), isFalse);
        }
        expect(calls, isEmpty);
      });

      test(
        'false when the device has no browser or the channel fails',
        () async {
          answer = false;
          expect(await openReleasePageOnAndroid(releasePageUri), isFalse);

          answer = null;
          expect(await openReleasePageOnAndroid(releasePageUri), isFalse);

          answer = PlatformException(code: 'boom', message: '/secret/path');
          expect(await openReleasePageOnAndroid(releasePageUri), isFalse);
        },
      );

      test('false where there is no native side at all', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        expect(await openReleasePageOnAndroid(releasePageUri), isFalse);
      });
    });
  });
}
