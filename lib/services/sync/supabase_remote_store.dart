import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/crypto/crypto.dart';
import 'remote_store.dart';

/// Supabase implementation. Supabase is used only for auth and for storing
/// encrypted blobs; see `supabase/migrations` for the schema and RLS.
///
/// The Supabase client is configured (in main.dart) with no session
/// persistence: the refresh token is stored by `SyncService` inside the
/// SQLCipher database, so it is encrypted at rest and unavailable while
/// the vault is locked.
class SupabaseRemoteStore implements RemoteStore {
  SupabaseRemoteStore(this._client);

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  @override
  bool get isSignedIn => _auth.currentSession != null;

  @override
  String? get refreshToken => _auth.currentSession?.refreshToken;

  @override
  Future<PreloginInfo> prelogin(String email) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'prelogin',
      params: {'p_email': email.trim().toLowerCase()},
    );
    return PreloginInfo(
      base64.decode(res['salt'] as String),
      KdfParams.fromJson(
        (res['kdf'] as Map).cast<String, Object?>(),
      ), // enforces the client-side floor
    );
  }

  @override
  Future<void> signUp(String email, String authSecret) async {
    await _auth.signUp(email: email.trim().toLowerCase(), password: authSecret);
  }

  @override
  Future<void> signIn(String email, String authSecret) async {
    await _auth.signInWithPassword(
      email: email.trim().toLowerCase(),
      password: authSecret,
    );
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> updateAuthSecret(String newAuthSecret) async {
    await _auth.updateUser(UserAttributes(password: newAuthSecret));
  }

  @override
  Future<bool> restoreSession(String refreshToken) async {
    if (refreshToken.isEmpty) return false;
    try {
      await _auth.setSession(refreshToken);
      return isSignedIn;
    } on AuthException {
      return false;
    }
  }

  @override
  Future<VaultKeyHeader?> fetchHeader() async {
    final row = await _client
        .from('vault_headers')
        .select('header')
        .maybeSingle();
    if (row == null) return null;
    return VaultKeyHeader.fromJson(
      (row['header'] as Map).cast<String, Object?>(),
    );
  }

  @override
  Future<void> putHeader(
    VaultKeyHeader header, {
    String? recoveryAuthHash,
  }) async {
    await _client.from('vault_headers').upsert({
      'user_id': _auth.currentUser!.id,
      'header': header.toJson(),
      'recovery_auth_hash': ?recoveryAuthHash,
    });
  }

  @override
  Future<List<RemoteItem>> pullSince(int seq, {int limit = 500}) async {
    final rows = await _client
        .from('vault_items')
        .select('id, payload, deleted, revision, seq, updated_at')
        .gt('seq', seq)
        .order('seq')
        .limit(limit);
    return rows.map(_toItem).toList();
  }

  @override
  Future<PushResult> push({
    required String id,
    required Uint8List? payload,
    required bool deleted,
    required int baseRevision,
  }) async {
    final res = await _client.rpc<List<dynamic>>(
      'push_item',
      params: {
        'p_id': id,
        'p_payload': payload == null ? null : base64.encode(payload),
        'p_deleted': deleted,
        'p_base_revision': baseRevision,
      },
    );
    final row = (res.single as Map).cast<String, dynamic>();
    final item = _toItem(row);
    return row['conflict'] == true
        ? PushResult.conflict(item)
        : PushResult.accepted(item);
  }

  static RemoteItem _toItem(Map<String, dynamic> r) => RemoteItem(
    id: r['id'] as String,
    payload: r['payload'] == null
        ? null
        : base64.decode(r['payload'] as String),
    deleted: r['deleted'] as bool,
    revision: (r['revision'] as num).toInt(),
    seq: (r['seq'] as num).toInt(),
    updatedAt: DateTime.parse(r['updated_at'] as String).toUtc(),
  );
}

/// Supabase session storage that persists nothing (see class doc above).
class InMemoryOnlyStorage extends LocalStorage {
  const InMemoryOnlyStorage();
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => false;
  @override
  Future<String?> accessToken() async => null;
  @override
  Future<void> removePersistedSession() async {}
  @override
  Future<void> persistSession(String persistSessionString) async {}
}
