import 'dart:typed_data';

import '../../core/crypto/crypto.dart';

/// One encrypted item as stored on the server.
class RemoteItem {
  const RemoteItem({
    required this.id,
    required this.payload,
    required this.deleted,
    required this.revision,
    required this.seq,
    required this.updatedAt,
  });

  final String id;

  /// XChaCha20-Poly1305 envelope (null for tombstones).
  final Uint8List? payload;
  final bool deleted;

  /// Per-item revision, incremented by the server on every accepted write.
  final int revision;

  /// Global, server-assigned change sequence used as the pull cursor.
  final int seq;

  /// Server time of the last write.
  final DateTime updatedAt;
}

class PushResult {
  const PushResult.accepted(this.current) : conflict = false;
  const PushResult.conflict(this.current) : conflict = true;

  final bool conflict;

  /// The row as it is on the server after the call.
  final RemoteItem current;
}

/// KDF salt + parameters needed before login on a new device.
class PreloginInfo {
  const PreloginInfo(this.salt, this.kdf);
  final Uint8List salt;
  final KdfParams kdf;
}

/// Everything sync needs from the backend. Implemented by
/// `SupabaseRemoteStore` and by an in-memory fake in tests.
///
/// Nothing passed through this interface is secret: payloads are ciphertext,
/// the header holds only wrapped keys + salt, and the auth secret is a
/// one-way subkey of the master key.
abstract class RemoteStore {
  bool get isSignedIn;

  Future<PreloginInfo> prelogin(String email);
  Future<void> signUp(String email, String authSecret);
  Future<void> signIn(String email, String authSecret);
  Future<void> signOut();
  Future<void> updateAuthSecret(String newAuthSecret);

  /// Restores a session from a refresh token kept inside the encrypted DB.
  Future<bool> restoreSession(String refreshToken);
  String? get refreshToken;

  Future<VaultKeyHeader?> fetchHeader();
  Future<void> putHeader(VaultKeyHeader header, {String? recoveryAuthHash});

  Future<List<RemoteItem>> pullSince(int seq, {int limit = 500});

  /// Optimistic concurrency: the write is applied only if the server row's
  /// revision equals [baseRevision] (0 = must not exist yet).
  Future<PushResult> push({
    required String id,
    required Uint8List? payload,
    required bool deleted,
    required int baseRevision,
  });
}
