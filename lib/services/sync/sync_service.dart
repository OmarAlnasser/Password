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

/// The server tried to delete most of the vault in one pull (another device
/// deleted many entries at once, or it is an attack / bug). Nothing from that
/// pull was applied; this device's own changes were still pushed.
/// [SyncService.pendingMassDeletion] holds [count] until the user chooses
/// [SyncService.applyMassDeletion] or [SyncService.keepMassDeletion].
class MassDeletionException implements Exception {
  const MassDeletionException(this.count);

  /// How many live entries of this device the pull would have deleted.
  final int count;
}

/// What a pass does with a pull that would delete most of the vault.
enum _MassDeletion {
  /// Apply nothing from it and ask the user (the default).
  refuse,

  /// The user confirmed: delete those entries here too.
  apply,

  /// The user wants them: push them back, so every device has them again.
  keep,
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
    session.onWipe.add(_onWipe);
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
  int? _pendingMassDeletion;
  _MassDeletion _nextMassDeletion = _MassDeletion.refuse;
  Timer? _debounce;
  Future<void>? _running;
  Future<void>? _followUp;
  bool _disposed = false;

  SyncStatus get status => _status;
  bool get enabled => _status != SyncStatus.disabled;

  /// How many entries another device deleted in a pull this device refused
  /// (see [MassDeletionException]), or null when nothing waits for the user.
  /// Meanwhile this device still pushes its own changes but takes nothing
  /// newer from the server; [status] is [SyncStatus.error].
  int? get pendingMassDeletion => _pendingMassDeletion;

  /// The user confirmed the refused deletion: syncs again and deletes those
  /// entries on this device too.
  Future<void> applyMassDeletion() => _syncResolving(_MassDeletion.apply);

  /// The user wants to keep the entries another device deleted: syncs again
  /// without deleting them here and pushes them back, so they return on
  /// every device.
  Future<void> keepMassDeletion() => _syncResolving(_MassDeletion.keep);

  /// [syncNow], with the next pass to start taking [choice] for a pull that
  /// would delete most of the vault.
  Future<void> _syncResolving(_MassDeletion choice) {
    _nextMassDeletion = choice;
    return syncNow();
  }

  void _forgetMassDeletion() {
    _pendingMassDeletion = null;
    _nextMassDeletion = _MassDeletion.refuse;
  }

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
    // Asked again at the next unlock if the server still has it.
    _forgetMassDeletion();
    _status = remote.isSignedIn ? SyncStatus.idle : _status;
  }

  /// The local vault was erased. The server session outlives [lock] (it is
  /// only in memory), so sign out: a vault created next must not sync into
  /// the old account or store its refresh token.
  Future<void> _onWipe() async {
    _debounce?.cancel();
    try {
      await remote.signOut();
    } on Object catch (e) {
      // The local session is gone even when revoking it on the server fails.
      debugPrint('Sync sign-out failed: ${e.runtimeType}');
    }
    lastSync = null;
    rejectedItems = 0;
    _forgetMassDeletion();
    _set(SyncStatus.disabled);
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
    session.onWipe.remove(_onWipe);
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
    _forgetMassDeletion();
    _set(SyncStatus.disabled);
  }

  /// Completes when a pass that started after this call has finished, so it
  /// covers every local change saved and every remote change made before the
  /// call. A pass already in flight may have pulled, or read the dirty rows,
  /// before the caller's change; then one follow-up pass is queued behind it,
  /// shared by every caller that arrives in the meantime. Does nothing while
  /// sync is off for this vault ([enabled] is false).
  Future<void> syncNow() {
    if (_disposed || !enabled || !session.isUnlocked || !remote.isSignedIn) {
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

  /// One pass: pull, push, reload. A pull refused as a mass deletion still
  /// pushes this device's own changes (so they are not stuck behind another
  /// device's cleanup), records [pendingMassDeletion] and then throws the
  /// [MassDeletionException] to the caller.
  Future<void> _sync() async {
    final massDeletion = _nextMassDeletion;
    _nextMassDeletion = _MassDeletion.refuse;
    _set(SyncStatus.syncing);
    try {
      MassDeletionException? refused;
      try {
        await _pull(massDeletion);
        _pendingMassDeletion = null;
      } on MassDeletionException catch (e) {
        refused = e;
        _pendingMassDeletion = e.count;
      }
      await _push();
      await session.reloadFromDatabase();
      await _saveRefresh();
      if (refused != null) throw refused;
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

  Future<void> _pull(_MassDeletion massDeletion) async {
    final db = session.db;
    var cursor = int.tryParse(await db.getKv(_kvCursor) ?? '') ?? 0;
    while (true) {
      final batch = await remote.pullSince(cursor);
      if (batch.isEmpty) break;
      final doomed = _massDeletion(batch);
      if (doomed.isNotEmpty && massDeletion == _MassDeletion.refuse) {
        // The cursor stays before this batch: it is offered again.
        throw MassDeletionException(doomed.length);
      }
      for (final item in batch) {
        if (massDeletion == _MassDeletion.keep && doomed.contains(item.id)) {
          await _keepLocal(item);
        } else {
          await applyRemote(item);
        }
        if (item.seq > cursor) cursor = item.seq;
      }
      await db.setKv(_kvCursor, '$cursor');
      if (batch.length < 500) break;
    }
  }

  /// The live entries [batch] deletes, when that is a mass deletion: at
  /// least [massDeleteMin] of them and more than [massDeleteRatio] of the
  /// vault. Empty otherwise.
  Set<String> _massDeletion(List<RemoteItem> batch) {
    final live = {for (final e in session.entries) e.id};
    final doomed = {
      for (final i in batch)
        if (i.deleted && live.contains(i.id)) i.id,
    };
    final n = doomed.length;
    return n >= massDeleteMin && n > live.length * massDeleteRatio
        ? doomed
        : const {};
  }

  /// "Keep them": the server's tombstone [r] is not applied. The local entry
  /// is rebased on the tombstone's revision and marked dirty, so the push
  /// that follows restores it on the server, and from there on every device.
  /// Anything that is not a plain deletion of a live local entry follows the
  /// usual rules.
  Future<void> _keepLocal(RemoteItem r) {
    final db = session.db;
    return db.transaction(() async {
      final local = await db.item(r.id);
      if (local == null ||
          local.deleted ||
          r.payload != null ||
          r.revision <= local.revision) {
        return _applyRemote(r);
      }
      await db.upsert(
        local.copyWith(revision: r.revision, dirty: true).toCompanion(true),
      );
    });
  }

  /// Applies one remote row to the local DB. Public for tests.
  ///
  /// One transaction: the local row it decides on cannot change before it
  /// writes (a save or delete made meanwhile waits, then lands on top as a
  /// dirty row), so a remote row never overwrites a newer local edit.
  @visibleForTesting
  Future<void> applyRemote(RemoteItem remoteItem) {
    final db = session.db;
    return db.transaction(() => _applyRemote(remoteItem));
  }

  Future<void> _applyRemote(RemoteItem remoteItem) async {
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
      for (final listed in dirty) {
        // Read again: an earlier push of this loop took time, and the row
        // may have been edited, deleted or cleaned since it was listed.
        final row = await db.item(listed.id);
        if (row == null || !row.dirty) continue;
        final res = await remote.push(
          id: row.id,
          payload: row.deleted ? null : row.payload,
          deleted: row.deleted,
          baseRevision: row.revision,
        );
        if (res.conflict) {
          await applyRemote(res.current);
        } else {
          // Clean only if nothing was saved while the push was out; a newer
          // edit or delete stays dirty and goes in the next round.
          await db.markPushed(row, revision: res.current.revision);
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
