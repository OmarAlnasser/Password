import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/core/crypto/crypto.dart';
import 'package:hisn/services/browser/browser_activity.dart';
import 'package:hisn/services/browser/browser_registration.dart';
import 'package:hisn/services/unlock_throttle.dart';
import 'package:hisn/services/vault_session.dart';
import 'package:khazna_bridge/bridge_protocol.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('browser_reg'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('registration', () {
    late List<List<String>> calls;
    late BrowserRegistration reg;
    var exitCode = 0;

    setUp(() {
      calls = [];
      exitCode = 0;
      reg = BrowserRegistration(
        directory: Directory('${dir.path}/bridge'),
        appDirectory: Directory('${dir.path}/app'),
        run: (exe, args) async {
          calls.add([exe, ...args]);
          return ProcessResult(0, exitCode, '', '');
        },
      );
    });

    void ship() {
      File('${dir.path}/app/$bridgeExeName').createSync(recursive: true);
      File('${dir.path}/app/extension/manifest.json')
          .createSync(recursive: true);
    }

    test('nothing happens without the helper (a development build)', () async {
      expect(reg.shipped, isFalse);
      expect(await reg.register(), isFalse);
      expect(calls, isEmpty);
    });

    test('writes the manifest and a key per browser', () async {
      ship();
      expect(await reg.register(), isTrue);
      final m = jsonDecode(reg.manifestFile.readAsStringSync()) as Map;
      expect(m['name'], nativeHostName);
      expect(m['type'], 'stdio');
      expect(m['path'], reg.helperExe.path);
      expect(m['allowed_origins'], [extensionOrigin]);
      expect(calls.length, 3);
      for (final (i, key) in BrowserRegistration.registryKeys.indexed) {
        expect(calls[i], [
          'reg', 'add', key, '/ve', '/t', 'REG_SZ', //
          '/d', reg.manifestFile.path, '/f',
        ]);
        expect(key, startsWith(r'HKCU\Software\'));
        expect(key, endsWith(r'\NativeMessagingHosts\app.khazna.bridge'));
      }
    });

    test('at start-up, an up-to-date manifest runs nothing', () async {
      ship();
      await reg.register();
      calls.clear();
      expect(await reg.register(force: false), isTrue);
      expect(calls, isEmpty);
      // The app folder moved: the manifest is out of date.
      reg.manifestFile.writeAsStringSync('{}');
      expect(await reg.register(force: false), isTrue);
      expect(calls.length, 3);
    });

    test('the native way, when the app has it, instead of reg.exe', () async {
      ship();
      final native = <String?>[];
      final viaApp = BrowserRegistration(
        directory: Directory('${dir.path}/bridge'),
        appDirectory: Directory('${dir.path}/app'),
        native: (m) async {
          native.add(m);
          return true;
        },
        run: (exe, args) async {
          calls.add([exe, ...args]);
          return ProcessResult(0, 0, '', '');
        },
      );
      expect(await viaApp.register(), isTrue);
      await viaApp.unregister();
      expect(native, [viaApp.manifestFile.path, null]);
      expect(calls, isEmpty);
    });

    test("fails when Chrome's key cannot be written", () async {
      ship();
      exitCode = 1;
      expect(await reg.register(), isFalse);
    });

    test('unregister removes the keys and the manifest', () async {
      ship();
      await reg.register();
      calls.clear();
      await reg.unregister();
      expect(reg.manifestFile.existsSync(), isFalse);
      expect(
        [for (final c in calls) c.take(2).join(' ')],
        ['reg delete', 'reg delete', 'reg delete'],
      );
      // Twice is fine.
      await reg.unregister();
    });
  });

  test(
    'the activity log lives in the vault: kept across lock and unlock',
    () async {
      final session = VaultSession(
        crypto: VaultCrypto(await loadSodium()),
        directory: Directory('${dir.path}/vault'),
        throttle: UnlockThrottle(File('${dir.path}/t.json')),
      );
      await session.init();
      await session.createVault('violet-harbor-test-71-lantern');
      var now = DateTime.utc(2030, 1, 1);
      final log = BrowserActivityLog(session, clock: () => now);

      await log.add(
        BrowserActivityKind.filled,
        host: 'github.com',
        title: 'GitHub',
      );
      now = now.add(const Duration(minutes: 1));
      await log.add(BrowserActivityKind.saved, host: 'example.test');
      expect(log.unseen, 2);
      await log.markSeen();
      expect(log.unseen, 0);
      now = now.add(const Duration(minutes: 1));
      await log.add(
        BrowserActivityKind.updated,
        host: 'github.com',
        title: 'GitHub',
      );
      expect(log.unseen, 1);

      await session.lock();
      expect(log.events, isEmpty);
      expect(log.unseen, 0);
      await log.add(BrowserActivityKind.filled, host: 'locked.test');

      await session.unlockWithPassword('violet-harbor-test-71-lantern');
      await pumpEventQueue();
      expect(
        [for (final e in log.events) e.kind],
        [
          BrowserActivityKind.updated,
          BrowserActivityKind.saved,
          BrowserActivityKind.filled,
        ],
      );
      expect(log.events.last.title, 'GitHub');
      expect(log.unseen, 1);

      for (var i = 0; i < BrowserActivityLog.maxEntries + 5; i++) {
        await log.add(BrowserActivityKind.filled, host: 'h$i.test');
      }
      expect(log.events.length, BrowserActivityLog.maxEntries);
      await log.clear();
      expect(log.events, isEmpty);
      await session.lock();
    },
  );
}
