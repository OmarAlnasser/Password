// AUDIT: inspect every network call the real Supabase client makes during
// sign-up, sync and sign-in on a second device, and prove that no master
// password, key or plaintext ever leaves the device.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hisn/core/crypto/crypto.dart';
import 'package:hisn/data/models/vault_entry.dart';
import 'package:hisn/services/sync/supabase_remote_store.dart';
import 'package:hisn/services/sync/sync_service.dart';
import 'package:hisn/services/unlock_throttle.dart';
import 'package:hisn/services/vault_session.dart';

const master = 'violet-harbor-quantum-71-lantern';

/// Minimal fake of GoTrue + PostgREST that records every request.
class RecordingBackend {
  final List<http.Request> log = [];
  Map<String, dynamic>? header;
  final Map<String, Map<String, dynamic>> items = {};
  int seq = 0;
  String? password;

  String _jwt() {
    String b64(Map<String, dynamic> m) =>
        base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
    final exp =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000;
    return '${b64({'alg': 'HS256', 'typ': 'JWT'})}.${b64({'sub': 'u1', 'exp': exp, 'role': 'authenticated'})}.sig';
  }

  Map<String, dynamic> _session() => {
    'access_token': _jwt(),
    'refresh_token': 'rt-${DateTime.now().microsecondsSinceEpoch}',
    'expires_in': 3600,
    'token_type': 'bearer',
    'user': {
      'id': 'u1',
      'aud': 'authenticated',
      'email': 'me@example.com',
      'created_at': '2026-01-01T00:00:00Z',
      'app_metadata': {},
      'user_metadata': {},
    },
  };

  late final MockClient client = MockClient((req) async {
    log.add(req);
    final p = req.url.path;
    final body = req.body.isEmpty ? null : jsonDecode(req.body);
    http.Response json(Object? o, [int code = 200]) => http.Response(
      jsonEncode(o),
      code,
      request: req,
      headers: {'content-type': 'application/json'},
    );
    http.Response empty(int code) => http.Response('', code, request: req);
    if (p.endsWith('/auth/v1/signup')) {
      password = (body as Map)['password'] as String;
      return json(_session());
    }
    if (p.endsWith('/auth/v1/token')) {
      final b = body as Map;
      if (b['password'] != null && b['password'] != password) {
        return json({'error': 'invalid_grant'}, 400);
      }
      return json(_session());
    }
    if (p.endsWith('/auth/v1/user')) return json(_session()['user'] as Object);
    if (p.endsWith('/auth/v1/logout')) return empty(204);
    if (p.endsWith('/rest/v1/rpc/prelogin')) {
      final h = header!['header'] as Map;
      return json({'salt': h['salt'], 'kdf': h['kdf']});
    }
    if (p.endsWith('/rest/v1/vault_headers')) {
      if (req.method == 'POST') {
        header = (body as Map).cast<String, dynamic>();
        return empty(201);
      }
      return json(header == null ? null : {'header': header!['header']});
    }
    if (p.endsWith('/rest/v1/rpc/push_item')) {
      final b = (body as Map).cast<String, dynamic>();
      final cur = items[b['p_id']];
      final row = {
        'id': b['p_id'],
        'payload': b['p_payload'],
        'deleted': b['p_deleted'],
        'revision': ((cur?['revision'] as int?) ?? 0) + 1,
        'seq': ++seq,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'conflict': false,
      };
      items[b['p_id'] as String] = row;
      return json([row]);
    }
    if (p.endsWith('/rest/v1/vault_items')) {
      final gt = int.parse(
        req.url.queryParameters['seq']!.replaceFirst('gt.', ''),
      );
      return json(items.values.where((r) => (r['seq'] as int) > gt).toList());
    }
    return http.Response('unexpected ${req.method} $p', 404, request: req);
  });
}

void main() {
  late VaultCrypto crypto;
  setUpAll(() async => crypto = VaultCrypto(await loadSodium()));

  test('every request is free of secrets and plaintext', () async {
    final backend = RecordingBackend();
    SupabaseClient newClient() => SupabaseClient(
      'https://project.supabase.co',
      'anon-key',
      httpClient: backend.client,
      authOptions: const AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
    );

    final dirA = Directory.systemTemp.createTempSync('net_a');
    final dirB = Directory.systemTemp.createTempSync('net_b');
    addTearDown(() {
      dirA.deleteSync(recursive: true);
      dirB.deleteSync(recursive: true);
    });

    // Device A: create vault, add secrets, enable sync.
    final a = VaultSession(
      crypto: crypto,
      directory: dirA,
      throttle: UnlockThrottle(File('${dirA.path}/t')),
    );
    await a.init();
    final signup = await a.createVault(master);
    await SyncService.storeRecoveryAuthHash(a, signup.recoveryAuthSecret);
    await a.saveEntry(
      VaultEntry(
        id: 'e1',
        title: 'PLAINTEXT-TITLE',
        username: 'plaintext-user@example.com',
        password: 'PLAINTEXT-PASSWORD',
        notes: 'PLAINTEXT-NOTES',
        totpSecret: 'JBSWY3DPEHPK3PXP',
        url: 'https://bank.example',
      ),
    );
    final syncA = SyncService(a, SupabaseRemoteStore(newClient()));
    await syncA.enableSync('me@example.com', master);
    await syncA.syncNow();

    // Device B: sign in with email + master password, pull everything.
    final b = VaultSession(
      crypto: crypto,
      directory: dirB,
      throttle: UnlockThrottle(File('${dirB.path}/t')),
    );
    await b.init();
    final syncB = SyncService(b, SupabaseRemoteStore(newClient()));
    await syncB.signInExisting('me@example.com', master);
    expect(b.byId('e1')!.password, 'PLAINTEXT-PASSWORD');

    // ---------------------------------------------------------------- check
    String hex(List<int> x) =>
        x.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    final secrets = <String, String>{
      'master password': master,
      'master password (b64)': base64.encode(utf8.encode(master)),
      'entry title': 'PLAINTEXT-TITLE',
      'entry user': 'plaintext-user@example.com',
      'entry password': 'PLAINTEXT-PASSWORD',
      'entry notes': 'PLAINTEXT-NOTES',
      'totp secret': 'JBSWY3DPEHPK3PXP',
      'entry url': 'bank.example',
      'recovery key': signup.recoveryKeyText,
      'recovery key compact': signup.recoveryKeyText.replaceAll('-', ''),
      'recovery auth secret': signup.recoveryAuthSecret,
    };
    for (final (name, key) in [
      ('vault key', a.keyring.vaultKey),
      ('entry key', a.keyring.entryKey),
      ('database key', a.keyring.databaseKey),
    ]) {
      final raw = key.extractBytes();
      secrets['$name hex'] = hex(raw);
      secrets['$name b64'] = base64.encode(raw);
      secrets['$name b64url'] = base64Url.encode(raw).replaceAll('=', '');
    }

    final report = StringBuffer();
    for (final r in backend.log) {
      final wire = '${r.method} ${r.url}\n${r.headers}\n${r.body}';
      for (final MapEntry(key: name, value: s) in secrets.entries) {
        expect(
          wire.contains(s),
          isFalse,
          reason: '$name leaked in ${r.method} ${r.url.path}',
        );
      }
      final bodyKeys = r.body.isEmpty
          ? '-'
          : (jsonDecode(r.body) is Map
                ? (jsonDecode(r.body) as Map).keys.join(',')
                : 'list');
      report.writeln(
        '${r.method.padRight(5)} ${r.url.path}${r.url.hasQuery ? '?${r.url.query}' : ''}  body:{$bodyKeys}',
      );
    }
    // The only credential that reaches the server is the derived auth secret.
    expect(backend.password, isNot(master));
    expect(backend.password!.length, 43);
    // Recovery hash is a SHA-256 of the recovery auth secret, not the key.
    expect(
      backend.header!['recovery_auth_hash'],
      SyncService.hashRecoveryAuth(signup.recoveryAuthSecret),
    );
    // Uploaded payload decrypts only with the entry key.
    final payload = base64.decode(backend.items['e1']!['payload'] as String);
    expect(String.fromCharCodes(payload).contains('PLAINTEXT'), isFalse);

    File('build/audit_network_calls.txt')
      ..createSync(recursive: true)
      ..writeAsStringSync(report.toString());
    // ignore: avoid_print
    print(report);
  });
}
