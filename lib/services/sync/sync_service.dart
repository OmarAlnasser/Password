import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as hashes;
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../../core/crypto/crypto.dart';
import '../../data/db/database.dart';
import '../../data/models/vault_entry.dart';
import '../vault_session.dart';
import 'remote_store.dart';

enum SyncStatus { disabled, idle, syncing, error, needsSignIn }

/// The server tried to delete most of the vault in one pull. Nothing was
/// applied; the user must confirm (or it is an attack / bug).
class MassDeletionException implements Exception {
  const MassDeletionException(this.count);
  final int count;
}

class SyncException implements Exception {
  const SyncException(this.message);
  final String message;
  @override
  String toString() => 'SyncException: $message';
}

/// Two-way sync of encrypted entries.
///
/// * Pull: rows with `seq` > cursor. Each payload is authenticated
///   (decrypted with the entry key and its id) before it touches the local
///   DB; anything that fails is rejected and counted, never stored.
/// * Rollback guard: a remote row whose revision is not newer than the local
///   one is ignored.
/// * Conflicts (local row dirty and remote newer): last-write-wins on the
///   edit time stored *inside* the ciphertext (so the server cannot forge
///   it); the losing password is appended to the winner's history.
/// * Deletions are tombstones (payload null, deleted=true).
/// * Push: optimistic concurrency on the item revision.
class SyncService extends ChangeNotifier {
  SyncService(this.session, this.remote) {
    session.onLocalChange.add(_scheduleSync);
    session.onLock.add(_onLock);
  }

  final VaultSession session;
  final RemoteStore remote;

  static const _kvCursor = 'sync_seq';
  static const _kvRefresh = 'sync_refresh';
  static const _kvEmail = 'sync_email';
  static const _kvRecoveryHash = 'recovery_auth_hash';

  /// Refuse a pull that tombstones more than this share of live entries.
  static const double massDeleteRatio = 0.5;
  static const int massDeleteMin = 5;

  SyncStatus _status = SyncStatus.disabled;
  DateTime? lastSync;
  int rejectedItems = 0;
  Timer? _debounce;
  Future<void>? _running;
  Future<void>? _followUp;
  bool _disposed = false;

  SyncStatus get status => _status;
  bool get enabled => _status != SyncStatus.disabled;

  void _set(SyncStatus s) {
    _status = s;
    // A pass still in flight when the service is disposed must not notify.
    if (!_disposed) notifyListeners();
  }

  void _scheduleSync() {
    if (_disposed || !enabled) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), _syncInBackground);
  }

  /// A sync nobody awaits (debounce timer, after unlock). A refused mass
  /// deletion is already reported through [status]; it must not escape as an
  /// uncaught async error. Every other error is handled inside [_sync].
  void _syncInBackground() {
    unawaited(
      syncNow().catchError(
        (Object _) {},
        test: (e) => e is MassDeletionException,
      ),
    );
  }

  Future<void> _onLock() async {
    _debounce?.cancel();
    _status = remote.isSignedIn ? SyncStatus.idle : _status;
  }

  /// Stops reacting to local changes and cancels a pending debounced sync. A
  /// pass already in flight finishes on its own; await [idle] to wait for it.
  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _debounce = null;
    session.onLocalChange.remove(_scheduleSync);
    session.onLock.remove(_onLock);
    super.dispose();
  }

  /// Completes once no sync pass is running or queued.
  Future<void> get idle async {
    for (var f = _followUp ?? _running; f != null; f = _followUp ?? _running) {
      await f.then<void>((_) {}, onError: (Object _) {});
    }
  }

  static String hashRecoveryAuth(String recoveryAuth) =>
      hashes.sha256.convert(utf8.encode(recoveryAuth)).toString();

  /// Remember the recovery-auth hash for when sync is enabled later. Stored
  /// in the encrypted DB; it is a hash of a 256-bit random secret.
  Future<void> rememberRecoveryAuth(String recoveryAuth) =>
      storeRecoveryAuthHash(session, recoveryAuth);

  static Future<void> storeRecoveryAuthHash(
    VaultSession session,
    String recoveryAuth,
  ) => session.db.setKv(_kvRecoveryHash, hashRecoveryAuth(recoveryAuth));

  /// Called after unlock: restore the server session from the refresh token
  /// stored in the encrypted database, then sync.
  Future<void> onUnlocked() async {
    final token = await session.db.getKv(_kvRefresh);
    if (token == null) {
      _set(SyncStatus.disabled);
      return;
    }
    if (await remote.restoreSession(token)) {
      _set(SyncStatus.idle);
      await _saveRefresh();
      _syncInBackground();
    } else {
      _set(SyncStatus.needsSignIn);
    }
  }

  Future<void> _saveRefresh() async {
    final t = remote.refreshToken;
    if (t != null && session.isUnlocked) await session.db.setKv(_kvRefresh, t);
  }

  /// Registers the local vault on the server (first device).
  Future<void> enableSync(String email, String masterPassword) async {
    final header = session.header!;
    final keys = await session.accounts.derivePasswordKeys(
      password: masterPassword,
      salt: header.salt,
      params: header.kdf,
    );
    try {
      // Verify the password locally first.
      session.accounts.unlockWithPasswordKeys(keys, header).lock();
      await remote.signUp(email, session.crypto.serverAuthSecret(keys.authKey));
    } finally {
      keys.dispose();
    }
    await remote.putHeader(
      header,
      recoveryAuthHash: await session.db.getKv(_kvRecoveryHash),
    );
    await session.db.setKv(_kvEmail, email);
    await _saveRefresh();
    _set(SyncStatus.idle);
    await syncNow();
  }

  /// Signs in on a new device and installs the remote vault locally.
  Future<void> signInExisting(String email, String masterPassword) async {
    final pre = await remote.prelogin(email);
    final keys = await session.accounts.derivePasswordKeys(
      password: masterPassword,
      salt: pre.salt,
      params: pre.kdf,
    );
    final Keyring keyring;
    final VaultKeyHeader header;
    try {
      await remote.signIn(email, session.crypto.serverAuthSecret(keys.authKey));
      final h = await remote.fetchHeader();
      if (h == null) throw const SyncException('No vault on server');
      // The header must use the same salt/params we derived with (otherwise
      // the server is inconsistent or malicious).
      if (!_sameBytes(h.salt, pre.salt) || h.kdf != pre.kdf) {
        throw const SyncException('Header mismatch');
      }
      header = h;
      keyring = session.accounts.unlockWithPasswordKeys(keys, header);
    } finally {
      keys.dispose();
    }
    await session.adoptRemoteVault(header, keyring);
    await session.db.setKv(_kvEmail, email);
    await _saveRefresh();
    _set(SyncStatus.idle);
    await syncNow();
  }

  /// After a master password change or recovery reset on this device.
  Future<void> onPasswordReset({
    required String newAuthSecret,
    String? newRecoveryAuth,
  }) async {
    if (newRecoveryAuth != null) await rememberRecoveryAuth(newRecoveryAuth);
    if (!remote.isSignedIn) return;
    await remote.updateAuthSecret(newAuthSecret);
    await remote.putHeader(
      session.header!,
      recoveryAuthHash: await session.db.getKv(_kvRecoveryHash),
    );
    await _saveRefresh();
  }

  Future<void> disable() async {
    await remote.signOut();
    if (session.isUnlocked) {
      await session.db.setKv(_kvRefresh, '');
    }
    _set(SyncStatus.disabled);
  }

  /// Completes when a pass that started after this call has finished, so it
  /// covers every local change saved and every remote change made before the
  /// call. A pass already in flight may have pulled, or read the dirty rows,
  /// before the caller's change; then one follow-up pass is queued behind it,
  /// shared by every caller that arrives in the meantime.
  Future<void> syncNow() {
    if (_disposed || !session.isUnlocked || !remote.isSignedIn) {
      return Future.value();
    }
    final running = _running;
    if (running == null) {
      return _running = _sync().whenComplete(() => _running = null);
    }
    return _followUp ??= running
        // The in-flight pass reports its own error to its own callers.
        .then<void>((_) {}, onError: (Object _) {})
        .then((_) {
          _followUp = null;
          return syncNow();
        });
  }

  Future<void> _sync() async {
    _set(SyncStatus.syncing);
    try {
      await _pull();
      await _push();
      await session.reloadFromDatabase();
      await _saveRefresh();
      lastSync = DateTime.now();
      _set(SyncStatus.idle);
    } on MassDeletionException {
      _set(SyncStatus.error);
      rethrow;
    } on Object catch (e) {
      // Never include payloads or keys in the message.
      debugPrint('Sync failed: ${e.runtimeType}');
      _set(SyncStatus.error);
    }
  }

  // ---------------------------------------------------------------------------

  Future<void> _pull() async {
    final db = session.db;
    var cursor = int.tryParse(await db.getKv(_kvCursor) ?? '') ?? 0;
    while (true) {
      final batch = await remote.pullSince(cursor);
      if (batch.isEmpty) break;
      await _guardMassDeletion(batch);
      for (final item in batch) {
        await applyRemote(item);
        if (item.seq > cursor) cursor = item.seq;
      }
      await db.setKv(_kvCursor, '$cursor');
      if (batch.length < 500) break;
    }
  }

  Future<void> _guardMassDeletion(List<RemoteItem> batch) async {
    final live = {for (final e in session.entries) e.id};
    final deletions = batch.where((i) => i.deleted && live.contains(i.id));
    final n = deletions.length;
    if (n >= massDeleteMin && n > live.length * massDeleteRatio) {
      throw MassDeletionException(n);
    }
  }

  /// Applies one remote row to the local DB. Public for tests.
  @visibleForTesting
  Future<void> applyRemote(RemoteItem remoteItem) async {
    final db = session.db;
    final local = await db.item(remoteItem.id);

    // Authenticate before trusting anything in the row.
    VaultEntry? remoteEntry;
    if (!remoteItem.deleted) {
      final payload = remoteItem.payload;
      remoteEntry = payload == null
          ? null
          : session.decryptBlob(remoteItem.id, payload);
      if (remoteEntry == null) {
        rejectedItems++;
        return;
      }
    } else if (remoteItem.payload != null) {
      rejectedItems++;
      return;
    }

    if (local != null && remoteItem.revision <= local.revision) {
      return; // stale or replayed
    }

    if (local == null || !local.dirty) {
      await _store(remoteItem, dirty: false);
      return;
    }

    // Conflict: local has unpushed edits and the server moved on.
    final localEntry = local.deleted || local.payload == null
        ? null
        : session.decryptBlob(local.id, local.payload!);
    final localTime =
        localEntry?.updatedAt ??
        DateTime.fromMillisecondsSinceEpoch(local.localUpdatedAt, isUtc: true);
    final remoteTime = remoteEntry?.updatedAt ?? remoteItem.updatedAt;

    final remoteWins = !remoteTime.isBefore(localTime);
    if (remoteWins) {
      if (remoteEntry != null &&
          localEntry != null &&
          localEntry.password != remoteEntry.password) {
        final merged = remoteEntry.withHistoryPassword(
          localEntry.password,
          DateTime.now().toUtc(),
        );
        await _storeEntry(merged, revision: remoteItem.revision, dirty: true);
      } else {
        await _store(remoteItem, dirty: false);
      }
    } else {
      // Local wins; rebase it on the remote revision and keep the remote
      // password in history.
      if (localEntry != null) {
        final merged = remoteEntry == null
            ? localEntry
            : localEntry.withHistoryPassword(
                remoteEntry.password,
                DateTime.now().toUtc(),
              );
        await _storeEntry(merged, revision: remoteItem.revision, dirty: true);
      } else {
        await db.upsert(
          local
              .copyWith(revision: remoteItem.revision, dirty: true)
              .toCompanion(true),
        );
      }
    }
  }

  Future<void> _store(RemoteItem r, {required bool dirty}) => session.db.upsert(
    VaultItemsCompanion(
      id: Value(r.id),
      payload: Value(r.deleted ? null : r.payload),
      deleted: Value(r.deleted),
      revision: Value(r.revision),
      localUpdatedAt: Value(r.updatedAt.millisecondsSinceEpoch),
      dirty: Value(dirty),
    ),
  );

  Future<void> _storeEntry(
    VaultEntry e, {
    required int revision,
    required bool dirty,
  }) => session.db.upsert(
    VaultItemsCompanion(
      id: Value(e.id),
      payload: Value(session.encryptEntry(e)),
      deleted: const Value(false),
      revision: Value(revision),
      localUpdatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      dirty: Value(dirty),
    ),
  );

  Future<void> _push() async {
    final db = session.db;
    for (var attempt = 0; attempt < 3; attempt++) {
      final dirty = await db.dirtyItems();
      if (dirty.isEmpty) return;
      for (final row in dirty) {
        final res = await remote.push(
          id: row.id,
          payload: row.deleted ? null : row.payload,
          deleted: row.deleted,
          baseRevision: row.revision,
        );
        if (res.conflict) {
          await applyRemote(res.current);
        } else {
          await db.upsert(
            row
                .copyWith(revision: res.current.revision, dirty: false)
                .toCompanion(true),
          );
        }
      }
    }
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
