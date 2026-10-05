import 'dart:typed_data';

import 'package:vaultsnap/core/crypto/crypto.dart';
import 'package:vaultsnap/services/sync/remote_store.dart';

/// In-memory server with the same semantics as push_item() in the SQL
/// migration. Shared by several "devices"; `tamper` lets tests act as a
/// malicious server.
class FakeServer {
  final Map<String, RemoteItem> items = {};
  VaultKeyHeader? header;
  String? authSecret;
  String? email;
  int _seq = 0;
  final List<String> requestLog = [];

  int nextSeq() => ++_seq;

  /// Simulates the server directly modifying a row (attacker / bug).
  void tamper(String id, RemoteItem Function(RemoteItem) f) {
    final cur = items[id]!;
    final n = f(cur);
    items[id] = RemoteItem(
      id: n.id,
      payload: n.payload,
      deleted: n.deleted,
      revision: n.revision,
      seq: nextSeq(),
      updatedAt: n.updatedAt,
    );
  }
}

class FakeRemote implements RemoteStore {
  FakeRemote(this.server);
  final FakeServer server;
  bool _signedIn = false;

  @override
  bool get isSignedIn => _signedIn;
  @override
  String? get refreshToken => _signedIn ? 'refresh-token' : null;

  @override
  Future<PreloginInfo> prelogin(String email) async {
    server.requestLog.add('prelogin $email');
    final h = server.header!;
    return PreloginInfo(h.salt, h.kdf);
  }

  @override
  Future<void> signUp(String email, String authSecret) async {
    server.requestLog.add('signUp $email $authSecret');
    server.email = email;
    server.authSecret = authSecret;
    _signedIn = true;
  }

  @override
  Future<void> signIn(String email, String authSecret) async {
    server.requestLog.add('signIn $email $authSecret');
    if (email != server.email || authSecret != server.authSecret) {
      throw StateError('invalid login');
    }
    _signedIn = true;
  }

  @override
  Future<void> signOut() async => _signedIn = false;

  @override
  Future<void> updateAuthSecret(String s) async {
    server.requestLog.add('updateAuth $s');
    server.authSecret = s;
  }

  @override
  Future<bool> restoreSession(String refreshToken) async =>
      _signedIn = refreshToken == 'refresh-token';

  @override
  Future<VaultKeyHeader?> fetchHeader() async => server.header;

  @override
  Future<void> putHeader(
    VaultKeyHeader header, {
    String? recoveryAuthHash,
  }) async {
    server.requestLog.add('putHeader ${header.toJson()}');
    server.header = header;
  }

  @override
  Future<List<RemoteItem>> pullSince(int seq, {int limit = 500}) async {
    final l = server.items.values.where((i) => i.seq > seq).toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));
    return l.take(limit).toList();
  }

  @override
  Future<PushResult> push({
    required String id,
    required Uint8List? payload,
    required bool deleted,
    required int baseRevision,
  }) async {
    server.requestLog.add(
      'push $id ${payload == null ? '-' : String.fromCharCodes(payload)}',
    );
    final cur = server.items[id];
    if (cur == null && baseRevision != 0) {
      return PushResult.conflict(
        RemoteItem(
          id: id,
          payload: null,
          deleted: true,
          revision: 0,
          seq: 0,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    }
    if (cur != null && cur.revision != baseRevision) {
      return PushResult.conflict(cur);
    }
    final next = RemoteItem(
      id: id,
      payload: deleted ? null : payload,
      deleted: deleted,
      revision: (cur?.revision ?? 0) + 1,
      seq: server.nextSeq(),
      updatedAt: DateTime.now().toUtc(),
    );
    server.items[id] = next;
    return PushResult.accepted(next);
  }
}
