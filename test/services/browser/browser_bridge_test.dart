import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/core/crypto/crypto.dart';
import 'package:hisn/data/models/vault_entry.dart';
import 'package:hisn/services/browser/browser_activity.dart';
import 'package:hisn/services/browser/browser_bridge.dart';
import 'package:hisn/services/settings.dart';
import 'package:hisn/services/unlock_throttle.dart';
import 'package:hisn/services/vault_session.dart';
import 'package:khazna_bridge/bridge_host.dart';
import 'package:khazna_bridge/bridge_protocol.dart';

const _pw = 'violet-harbor-test-71-lantern';

/// A key the extension made: 32 bytes, base64url without padding.
String _key(int seed) => base64Url
    .encode(List.generate(32, (i) => (seed * 31 + i) & 0xff))
    .replaceAll('=', '');

String _hash(String key) =>
    sha256.convert(base64Url.decode('$key=')).toString();

void main() {
  late VaultCrypto crypto;
  late Directory dir;
  late VaultSession session;
  late AppSettings settings;
  late BrowserActivityLog activity;
  late BrowserBridge bridge;
  var shown = 0;

  setUpAll(() async => crypto = VaultCrypto(await loadSodium()));

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('browser_bridge');
    session = VaultSession(
      crypto: crypto,
      directory: Directory('${dir.path}/vault'),
      throttle: UnlockThrottle(File('${dir.path}/t.json')),
    );
    settings = AppSettings(File('${dir.path}/settings.json'));
    activity = BrowserActivityLog(session);
    shown = 0;
    bridge = BrowserBridge(
      session: session,
      settings: settings,
      activity: activity,
      directory: Directory('${dir.path}/bridge'),
      showWindow: () async => shown++,
      appVersion: '0.1.2',
      pairTimeout: const Duration(seconds: 2),
      random: Random(1),
    );
    await session.init();
    await session.createVault(_pw);
    for (final e in [
      VaultEntry(
        id: 'gh',
        title: 'GitHub',
        username: 'someone@example.test',
        password: 'old-pass-1',
        url: 'https://github.com/login',
      ),
      VaultEntry(
        id: 'gh2',
        title: 'GitHub work',
        username: 'someone.else@example.test',
        password: 'work-pass-2',
        url: 'github.com',
      ),
      VaultEntry(
        id: 'evil',
        title: 'Look-alike',
        username: 'someone@example.test',
        password: 'nope',
        url: 'https://github.com.evil.test',
      ),
    ]) {
      await session.saveEntry(e);
    }
  });

  tearDown(() async {
    await bridge.stop();
    await session.lock();
    dir.deleteSync(recursive: true);
  });

  Future<BridgeClient> paired([String key = '']) async {
    final k = key.isEmpty ? _key(1) : key;
    await settings.update(
      (s) => s.pairedBrowsers = [
        PairedBrowser(
          keyHash: _hash(k),
          name: 'Chrome',
          pairedAt: DateTime.utc(2030),
        ),
      ],
    );
    final c = BridgeClient();
    final r = await bridge.handle(c, {
      'id': 1,
      't': 'hello',
      'key': k,
      'browser': 'Chrome',
    });
    expect(r['paired'], isTrue);
    return c;
  }

  group('pairing', () {
    test('an unknown extension can only say hello and ask to pair', () async {
      final c = BridgeClient();
      final hello = await bridge.handle(c, {
        'id': 1,
        't': 'hello',
        'key': _key(9),
        'browser': 'Chrome',
      });
      expect(hello, {'id': 1, 'ok': true, 'paired': false, 'app': '0.1.2'});
      for (final t in ['status', 'list', 'fill', 'check', 'save', 'show']) {
        final r = await bridge.handle(c, {
          'id': 2,
          't': t,
          'url': 'https://github.com',
        });
        expect(r, {'id': 2, 'ok': false, 'error': 'not_paired'}, reason: t);
      }
    });

    test(
      'the user allows it: the key hash is kept, the code matches',
      () async {
        final c = BridgeClient();
        final key = _key(2);
        final reply = bridge.handle(c, {
          'id': 5,
          't': 'pair',
          'key': key,
          'browser': 'Edge<script>',
        });
        await pumpEventQueue();
        final req = bridge.pendingPairing!;
        expect(req.browser, 'Edgescript');
        expect(
          req.code,
          pairingCode(sha256.convert(base64Url.decode('$key=')).bytes),
        );
        expect(shown, 1);
        bridge.answerPairing(true);
        expect(await reply, {
          'id': 5,
          'ok': true,
          'paired': true,
          'state': 'unlocked',
        });
        expect(settings.pairedBrowsers.single.keyHash, _hash(key));
        expect(activity.events.single.kind, BrowserActivityKind.paired);
        expect((await bridge.handle(c, {'t': 'status'}))['state'], 'unlocked');
      },
    );

    test('denied, or not answered in time: nothing is kept', () async {
      final c = BridgeClient();
      final denied = bridge.handle(c, {'t': 'pair', 'key': _key(3)});
      await pumpEventQueue();
      bridge.answerPairing(false);
      expect(await denied, {'ok': false, 'error': 'denied'});

      final late = await bridge.handle(c, {'t': 'pair', 'key': _key(3)});
      expect(late, {'ok': false, 'error': 'denied'});
      expect(bridge.pendingPairing, isNull);
      expect(settings.pairedBrowsers, isEmpty);
    });

    test('one question at a time', () async {
      final first = bridge.handle(BridgeClient(), {
        't': 'pair',
        'key': _key(4),
      });
      await pumpEventQueue();
      final second = await bridge.handle(BridgeClient(), {
        't': 'pair',
        'key': _key(5),
      });
      expect(second['error'], 'busy');
      bridge.answerPairing(false);
      await first;
    });

    test('a bad key is a bad request', () async {
      for (final key in [null, 1, 'short', '${_key(1)}=', '${_key(1)}!']) {
        final r = await bridge.handle(BridgeClient(), {
          't': 'hello',
          'key': key,
        });
        expect(r['error'], 'bad_request', reason: '$key');
      }
    });

    test('removing a paired browser stops it at once', () async {
      final c = await paired();
      await bridge.unpair(_hash(_key(1)));
      expect((await bridge.handle(c, {'t': 'status'}))['error'], 'not_paired');
    });
  });

  group('fill', () {
    test('lists only the logins of the page host, https only', () async {
      final c = await paired();
      final r = await bridge.handle(c, {
        'id': 3,
        't': 'list',
        'url': 'https://www.github.com/session?x=1',
      });
      expect(r['ok'], isTrue);
      final ids = [for (final e in r['entries']! as List) (e as Map)['id']];
      expect(ids.toSet(), {'gh', 'gh2'});
      expect(jsonEncode(r), isNot(contains('pass')));

      final sub = await bridge.handle(c, {
        't': 'list',
        'url': 'https://gist.github.com/',
      });
      expect((sub['entries']! as List).length, 2);

      for (final url in [
        'http://github.com/',
        'file:///C:/x.html',
        'chrome://extensions',
        'javascript:alert(1)',
      ]) {
        final bad = await bridge.handle(c, {'t': 'list', 'url': url});
        expect(bad['error'], 'insecure_page', reason: url);
      }
      expect(
        (await bridge.handle(c, {'t': 'list', 'url': 42}))['error'],
        'bad_request',
      );
    });

    test('fills only an entry that matches the page, and logs it', () async {
      final c = await paired();
      final ok = await bridge.handle(c, {
        't': 'fill',
        'url': 'https://github.com/login',
        'entry': 'gh',
      });
      expect(ok, {
        'ok': true,
        'username': 'someone@example.test',
        'password': 'old-pass-1',
      });
      final wrongSite = await bridge.handle(c, {
        't': 'fill',
        'url': 'https://github.com.evil.test/',
        'entry': 'gh',
      });
      expect(wrongSite['error'], 'not_found');
      final e = activity.events.first;
      expect(e.kind, BrowserActivityKind.filled);
      expect(e.host, 'github.com');
      expect(e.title, 'GitHub');
      expect(e.browser, 'Chrome');
      expect(jsonEncode(e.toJson()), isNot(contains('old-pass-1')));
      expect(jsonEncode(e.toJson()), isNot(contains('someone@')));
    });

    test('locked: nothing to list or fill', () async {
      final c = await paired();
      await session.lock();
      expect((await bridge.handle(c, {'t': 'status'}))['state'], 'locked');
      for (final t in ['list', 'fill', 'check', 'save']) {
        final r = await bridge.handle(c, {
          't': t,
          'url': 'https://github.com',
          'entry': 'gh',
          'password': 'x',
        });
        expect(r['error'], 'locked', reason: t);
      }
    });
  });

  group('save and update', () {
    test('check: new login, new password, or nothing to do', () async {
      final c = await paired();
      Future<Object?> action(String user, String pass) async =>
          (await bridge.handle(c, {
            't': 'check',
            'url': 'https://github.com/login',
            'username': user,
            'password': pass,
          }))['action'];

      expect(await action('someone@example.test', 'old-pass-1'), 'none');
      expect(await action(' SOMEONE@example.test ', 'old-pass-1'), 'none');
      expect(await action('someone@example.test', 'new-pass'), 'update');
      expect(await action('third@example.test', 'pw'), 'save');
      expect(await action('third@example.test', ''), 'none');
    });

    test('save adds a login for the page host and logs it', () async {
      final c = await paired();
      final r = await bridge.handle(c, {
        't': 'save',
        'url': 'https://www.example.test/signin',
        'username': 'someone@example.test',
        'password': 'fresh-pass',
      });
      expect(r['ok'], isTrue);
      final e = session.byId(r['entry']! as String)!;
      expect(e.title, 'example.test');
      expect(e.url, 'https://www.example.test');
      expect(e.username, 'someone@example.test');
      expect(e.password, 'fresh-pass');
      expect(activity.events.first.kind, BrowserActivityKind.saved);
    });

    test(
      'update changes the password and keeps the old one in history',
      () async {
        final c = await paired();
        final r = await bridge.handle(c, {
          't': 'save',
          'url': 'https://github.com/login',
          'entry': 'gh',
          'username': 'someone@example.test',
          'password': 'new-pass',
        });
        expect(r, {'ok': true, 'entry': 'gh'});
        final e = session.byId('gh')!;
        expect(e.password, 'new-pass');
        expect(e.history.first.password, 'old-pass-1');
        expect(activity.events.first.kind, BrowserActivityKind.updated);

        final other = await bridge.handle(c, {
          't': 'save',
          'url': 'https://example.test/',
          'entry': 'gh',
          'password': 'hijack',
        });
        expect(other['error'], 'not_found');
        expect(session.byId('gh')!.password, 'new-pass');
      },
    );
  });

  group('over the network', () {
    Future<(Socket, Stream<Map<String, Object?>>)> connect({
      String? token,
    }) async {
      final s = await Socket.connect(
        InternetAddress.loopbackIPv4,
        bridge.port!,
      );
      final d = FrameDecoder();
      final frames = s.expand(d.add).asBroadcastStream();
      final t =
          token ??
          BridgeEndpoint.tryParse(
            await endpointFile(Directory('${dir.path}/bridge')).readAsString(),
          )!.token;
      s.add(encodeFrame({'t': 'bridge', 'token': t}));
      return (s, frames);
    }

    test('start writes the endpoint; stop removes it', () async {
      await bridge.start();
      final file = endpointFile(Directory('${dir.path}/bridge'));
      final ep = BridgeEndpoint.tryParse(await file.readAsString())!;
      expect(ep.port, bridge.port);
      expect(ep.pid, pid);
      await bridge.stop();
      expect(file.existsSync(), isFalse);
    });

    test('a connection without the token is closed', () async {
      await bridge.start();
      final (s, frames) = await connect(token: '0' * 64);
      s.add(encodeFrame({'id': 1, 't': 'hello', 'key': _key(1)}));
      expect(await frames.toList(), isEmpty);
      s.destroy();
      // A refused connection does not keep a place.
      expect(bridge.connections, 0);
    });

    test('a connection that says nothing is closed', () async {
      final quick = BrowserBridge(
        session: session,
        settings: settings,
        activity: activity,
        directory: Directory('${dir.path}/bridge2'),
        authTimeout: const Duration(milliseconds: 100),
      );
      await quick.start();
      final s = await Socket.connect(InternetAddress.loopbackIPv4, quick.port!);
      await s.drain<void>().timeout(const Duration(seconds: 5));
      await quick.stop();
    });

    test('the helper relays a whole conversation', () async {
      await paired();
      await bridge.start();
      final toHelper = StreamController<List<int>>();
      final fromHelper = _Sink();
      final run = runBridgeHost(
        input: toHelper.stream,
        output: fromHelper,
        args: const [extensionOrigin, '--parent-window=0'],
        directory: Directory('${dir.path}/bridge'),
      );
      toHelper.add(encodeFrame({'id': 1, 't': 'hello', 'key': _key(1)}));
      toHelper.add(
        encodeFrame({'id': 2, 't': 'list', 'url': 'https://github.com/'}),
      );
      final replies = await fromHelper.frames.take(2).toList();
      expect(replies[0]['paired'], isTrue);
      expect((replies[1]['entries']! as List).length, 2);
      await toHelper.close();
      expect(await run, 0);
    });

    test('the helper exits when the app goes away', () async {
      await bridge.start();
      final toHelper = StreamController<List<int>>();
      final run = runBridgeHost(
        input: toHelper.stream,
        output: _Sink(),
        args: const [extensionOrigin],
        directory: Directory('${dir.path}/bridge'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await bridge.stop();
      expect(await run.timeout(const Duration(seconds: 5)), 0);
      await toHelper.close();
    });
  });

  group('helper without the app', () {
    test('answers app_not_running once and exits', () async {
      final out = _Sink();
      final run = runBridgeHost(
        input: Stream.value(encodeFrame({'id': 7, 't': 'hello'})),
        output: out,
        args: const [extensionOrigin],
        directory: Directory('${dir.path}/nothing'),
      );
      expect(await run, 0);
      expect(await out.frames.first, {
        'id': 7,
        'ok': false,
        'error': 'app_not_running',
      });
    });

    test('"open" starts the app', () async {
      var launched = 0;
      final out = _Sink();
      final run = runBridgeHost(
        input: Stream.value(encodeFrame({'id': 1, 't': 'open'})),
        output: out,
        args: const [extensionOrigin],
        directory: null,
        launchApp: () async => launched++,
      );
      expect(await run, 0);
      expect(launched, 1);
      expect((await out.frames.first)['launched'], isTrue);
    });

    test('refuses any caller but the extension', () async {
      final run = runBridgeHost(
        input: const Stream.empty(),
        output: _Sink(),
        args: const ['chrome-extension://someoneelse/'],
        directory: null,
      );
      expect(await run, 2);
    });
  });
}

/// An IOSink that collects what the helper writes to Chrome.
class _Sink implements IOSink {
  final _bytes = StreamController<List<int>>();
  late final Stream<Map<String, Object?>> frames = _bytes.stream
      .expand(FrameDecoder().add)
      .asBroadcastStream();

  @override
  void add(List<int> data) => _bytes.add(data);

  @override
  Future<void> flush() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
