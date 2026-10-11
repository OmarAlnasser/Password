@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/core/crypto/crypto.dart';
import 'package:hisn/data/models/vault_entry.dart';
import 'package:hisn/services/browser/browser_activity.dart';
import 'package:hisn/services/browser/browser_bridge.dart';
import 'package:hisn/services/settings.dart';
import 'package:hisn/services/unlock_throttle.dart';
import 'package:hisn/services/vault_session.dart';
import 'package:khazna_bridge/bridge_protocol.dart';

/// The whole browser extension, end to end, on Linux: Chromium with the
/// unpacked extension (browser/extension), the browser helper compiled from
/// browser/bridge and started by Chromium through native messaging, and this
/// app's [BrowserBridge] over a real vault. The page is a login form served
/// over https as github.com.
///
/// It pairs, fills, updates a password and saves a new login, then checks
/// the vault and the activity log. Needs Node, Playwright and Chromium
/// (preinstalled in the dev container) and `dart` on PATH:
///
///     flutter test --run-skipped -t e2e test/tool/extension_e2e_test.dart
void main() {
  test('pair, fill, update and save from Chromium', () async {
    final tmp = Directory.systemTemp.createTempSync('ext_e2e');
    addTearDown(() => tmp.deleteSync(recursive: true));

    // --- the app: a vault with two GitHub logins, and the bridge ----------
    final crypto = VaultCrypto(await loadSodium());
    final session = VaultSession(
      crypto: crypto,
      directory: Directory('${tmp.path}/vault'),
      throttle: UnlockThrottle(File('${tmp.path}/t.json')),
    );
    await session.init();
    await session.createVault('violet-harbor-test-71-lantern');
    await session.saveEntry(
      VaultEntry(
        id: 'gh',
        title: 'GitHub',
        username: 'someone@example.test',
        password: 'old-pass-1',
        url: 'https://github.com',
      ),
    );
    await session.saveEntry(
      VaultEntry(
        id: 'gh2',
        title: 'GitHub work',
        username: 'someone.else@example.test',
        password: 'work-pass-2',
        url: 'https://github.com',
      ),
    );
    final settings = AppSettings(File('${tmp.path}/settings.json'));
    final activity = BrowserActivityLog(session);
    final bridgeDir = Directory('${tmp.path}/bridge');
    final bridge = BrowserBridge(
      session: session,
      settings: settings,
      activity: activity,
      directory: bridgeDir,
      appVersion: '0.0.0',
    );
    String? askedCode;
    bridge.addListener(() {
      final p = bridge.pendingPairing;
      if (p != null) {
        askedCode = p.code;
        bridge.answerPairing(true);
      }
    });
    await bridge.start();
    addTearDown(bridge.stop);
    addTearDown(session.lock);

    // --- the helper, registered for Chromium -------------------------------
    final helper = '${tmp.path}/khazna_bridge';
    final compiled = await Process.run('dart', [
      'compile',
      'exe',
      'bin/khazna_bridge.dart',
      '-o',
      helper,
    ], workingDirectory: 'browser/bridge');
    expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
    final wrapper = File('${tmp.path}/host.sh')
      ..writeAsStringSync(
        '#!/bin/sh\nKHAZNA_BRIDGE_DIR="${bridgeDir.path}" exec "$helper" "\$@"\n',
      );
    await Process.run('chmod', ['+x', wrapper.path]);
    final userData = Directory('${tmp.path}/chromium');
    File('${userData.path}/NativeMessagingHosts/$nativeHostName.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'name': nativeHostName,
          'description': 'Khazna (test)',
          'path': wrapper.path,
          'type': 'stdio',
          'allowed_origins': [extensionOrigin],
        }),
      );

    // --- the page: https://github.com:<port>/login -------------------------
    final cert = await Process.run('openssl', [
      'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1', //
      '-subj', '/CN=github.com',
      '-keyout', '${tmp.path}/key.pem', '-out', '${tmp.path}/cert.pem',
    ]);
    expect(cert.exitCode, 0, reason: '${cert.stderr}');
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      SecurityContext()
        ..useCertificateChain('${tmp.path}/cert.pem')
        ..usePrivateKey('${tmp.path}/key.pem'),
    );
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      final page = req.uri.path == '/done'
          ? '<h1>Welcome</h1>'
          : '<form method="post" action="/done">'
                '<input type="email" name="email" autocomplete="username">'
                '<input type="password" name="pw" autocomplete="current-password">'
                '<button type="submit">Sign in</button></form>';
      await req.drain<void>();
      req.response.headers.contentType = ContentType.html;
      req.response.write('<!doctype html><html><body>$page</body></html>');
      await req.response.close();
    });

    // --- the browser ---------------------------------------------------------
    final node = await Process.start(
      'node',
      ['browser/extension/test/e2e.mjs'],
      environment: {
        'PLAYWRIGHT': '/opt/node-tools/node_modules/playwright/index.mjs',
        'EXT_DIR': '${Directory.current.path}/browser/extension',
        'USER_DATA_DIR': userData.path,
        'ORIGIN': 'https://github.com:${server.port}',
      },
    );
    final out = StringBuffer();
    node.stdout.transform(utf8.decoder).listen(out.write);
    node.stderr.transform(utf8.decoder).listen(out.write);
    final code = await node.exitCode.timeout(const Duration(minutes: 3));
    // ignore: avoid_print
    print(out);
    expect(code, 0, reason: '$out');
    expect(out.toString(), contains('E2E OK'));

    // --- what the vault and the log say -------------------------------------
    expect(out.toString(), contains('CODE $askedCode'));
    expect(settings.pairedBrowsers.single.name, 'Chrome');
    expect(session.byId('gh')!.password, 'new-pass-9');
    expect(session.byId('gh')!.history.first.password, 'old-pass-1');
    final added = session.entries.where(
      (e) => e.username == 'third@example.test',
    );
    expect(added.single.password, 'brand-new-1');
    expect(added.single.url, 'https://github.com');
    expect(
      [for (final e in activity.events) e.kind],
      [
        BrowserActivityKind.saved,
        BrowserActivityKind.updated,
        BrowserActivityKind.filled,
        BrowserActivityKind.paired,
      ],
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
