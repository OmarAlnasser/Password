import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sodium/sodium_sumo.dart';
import 'package:uuid/uuid.dart';

import '../core/crypto/crypto.dart';
import '../data/db/database.dart';
import '../data/models/vault_entry.dart';
import 'biometric_unlock.dart';
import 'unlock_throttle.dart';

enum VaultState { loading, noVault, locked, unlocked }

/// Owns the key hierarchy, the encrypted database and the decrypted entries.
///
/// Decrypted entries exist only in [entries] while unlocked. [lock] closes the
/// database, wipes every key (`Keyring.lock`) and drops all plaintext
/// references so the GC can reclaim them.
class VaultSession extends ChangeNotifier {
  VaultSession({
    required this.crypto,
    required this.directory,
    required this.throttle,
    this.biometrics,
    DateTime Function()? clock,
  }) : accounts = AccountKeys(crypto),
       _clock = clock ?? DateTime.now;

  final VaultCrypto crypto;
  final AccountKeys accounts;
  final Directory directory;
  final UnlockThrottle throttle;
  final BiometricUnlock? biometrics;

  /// The time source for [markUsed]; tests pass a fake one.
  final DateTime Function() _clock;

  /// Called after every local change; the sync service hooks in here.
  final List<void Function()> onLocalChange = [];

  /// Called just before keys are wiped (clipboard clear, UI reset, ...).
  final List<FutureOr<void> Function()> onLock = [];

  /// Called after [wipeLocalVault] has deleted the vault. Anything tied to
  /// the old vault (the sync account, ...) lets go of it here, so a vault
  /// created afterwards starts clean.
  final List<FutureOr<void> Function()> onWipe = [];

  VaultState _state = VaultState.loading;
  VaultKeyHeader? _header;
  Keyring? _keyring;
  VaultDatabase? _db;
  List<VaultEntry> _entries = const [];

  /// Entry id -> last use (UTC). Local-only; see [markUsed]. Loaded at unlock
  /// and emptied by [lock].
  final Map<String, DateTime> _lastUsed = {};
  late final Map<String, DateTime> _lastUsedView = UnmodifiableMapView(
    _lastUsed,
  );

  /// True after a recovery-key unlock; the UI then forces a new master
  /// password via [setPasswordAfterRecovery].
  bool unlockedViaRecovery = false;

  VaultState get state => _state;
  VaultKeyHeader? get header => _header;
  List<VaultEntry> get entries => _entries;
  bool get isUnlocked => _state == VaultState.unlocked;

  /// When each entry was last used, by entry id (UTC); entries never used are
  /// absent. A read-only live view: it is empty while locked and changes with
  /// [markUsed] (listeners are told when that can change the order).
  Map<String, DateTime> get lastUsedMap => _lastUsedView;

  /// When [entryId] was last used, or null if never (or unknown, or locked).
  DateTime? lastUsedAt(String entryId) => _lastUsed[entryId];

  SodiumSumo get sodium => crypto.sodium;

  File get _headerFile => File(p.join(directory.path, 'vault_header.json'));
  File get _dbFile => File(p.join(directory.path, 'vault.db'));

  Keyring get keyring => _keyring ?? (throw StateError('Vault is locked'));
  VaultDatabase get db => _db ?? (throw StateError('Vault is locked'));

  Future<void> init() async {
    await throttle.load();
    if (await _headerFile.exists()) {
      _header = VaultKeyHeader.fromJson(
        jsonDecode(await _headerFile.readAsString()) as Map<String, Object?>,
      );
      _state = VaultState.locked;
    } else {
      _state = VaultState.noVault;
    }
    notifyListeners();
  }

  /// Creates a new local vault. Returns the signup result so the UI can show
  /// the recovery key once and sync can register the account.
  Future<SignupResult> createVault(String password) async {
    if (_header != null) throw StateError('Vault already exists');
    final result = await accounts.createAccount(password);
    await _openWith(result.keyring, result.header, fresh: true);
    return result;
  }

  /// Installs a header + keyring obtained elsewhere (sign-in on a new device).
  Future<void> adoptRemoteVault(VaultKeyHeader header, Keyring keyring) =>
      _openWith(keyring, header, fresh: true);

  Future<void> unlockWithPassword(String password) async {
    final header = _requireHeader();
    throttle.check();
    final Keyring keyring;
    try {
      keyring = await accounts.unlockWithPassword(password, header);
    } on WrongCredentialsException {
      await throttle.recordFailure();
      rethrow;
    }
    await throttle.recordSuccess();
    await _openWith(keyring, header);
  }

  Future<void> unlockWithRecoveryKey(String recoveryText) async {
    final header = _requireHeader();
    throttle.check();
    final Keyring keyring;
    try {
      keyring = accounts.unlockWithRecoveryKey(recoveryText, header);
    } on VaultCryptoException {
      await throttle.recordFailure();
      rethrow;
    }
    await throttle.recordSuccess();
    await _openWith(keyring, header);
    unlockedViaRecovery = true;
    notifyListeners();
  }

  Future<void> unlockWithBiometrics() async {
    final bio = biometrics;
    if (bio == null) throw StateError('Biometrics unavailable');
    final vaultKey = await bio.unwrapVaultKey(crypto);
    if (vaultKey == null) return; // cancelled
    await _openWith(Keyring.fromVaultKey(crypto, vaultKey), _requireHeader());
  }

  VaultKeyHeader _requireHeader() =>
      _header ?? (throw StateError('No vault on this device'));

  Future<void> _openWith(
    Keyring keyring,
    VaultKeyHeader header, {
    bool fresh = false,
  }) async {
    try {
      if (fresh) {
        await directory.create(recursive: true);
        if (await _dbFile.exists()) await _dbFile.delete();
        await saveHeader(header);
      }
      final db = VaultDatabase.open(_dbFile, keyring.databaseKey);
      final rows = await db.liveItems();
      final entries = <VaultEntry>[];
      for (final row in rows) {
        final e = _decryptRow(row, keyring);
        if (e != null) entries.add(e);
      }
      // A deletion applied by sync while this device was locked left rows
      // behind; they would otherwise stay in the database forever.
      await db.pruneLastUsed();
      final used = await db.allLastUsed();
      _keyring = keyring;
      _db = db;
      _header = header;
      _entries = _sorted(entries);
      _lastUsed
        ..clear()
        ..addAll({for (final u in used.entries) u.key: _utc(u.value)});
      _state = VaultState.unlocked;
      notifyListeners();
    } catch (_) {
      keyring.lock();
      rethrow;
    }
  }

  VaultEntry? _decryptRow(VaultItem row, Keyring keyring) {
    final blob = row.payload;
    if (blob == null) return null;
    Uint8List? pt;
    try {
      pt = crypto.decryptEntry(
        envelope: blob,
        entryKey: keyring.entryKey,
        entryId: row.id,
      );
      final entry = VaultEntry.fromBytes(pt);
      // The id inside the plaintext must match the authenticated row id.
      return entry.id == row.id ? entry : null;
    } on Object {
      // Corrupt or tampered row: skip it rather than refusing to open the
      // whole vault. Never log the content.
      debugPrint('VaultSession: skipped undecryptable entry');
      return null;
    } finally {
      wipe(pt);
    }
  }

  Future<void> saveHeader(VaultKeyHeader header) async {
    _header = header;
    final tmp = File('${_headerFile.path}.tmp');
    await tmp.writeAsString(jsonEncode(header.toJson()), flush: true);
    await tmp.rename(_headerFile.path);
  }

  Future<void> lock() async {
    if (_state != VaultState.unlocked) return;
    for (final cb in onLock) {
      await cb();
    }
    await _db?.close();
    _db = null;
    _keyring?.lock();
    _keyring = null;
    _entries = const [];
    _lastUsed.clear();
    unlockedViaRecovery = false;
    _state = VaultState.locked;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Entries
  // ---------------------------------------------------------------------------

  static String newId() => const Uuid().v4();

  VaultEntry? byId(String id) {
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  Uint8List encryptEntry(VaultEntry e) {
    final pt = e.toBytes();
    try {
      return crypto.encryptEntry(
        plaintext: pt,
        entryKey: keyring.entryKey,
        entryId: e.id,
      );
    } finally {
      wipe(pt);
    }
  }

  VaultEntry? decryptBlob(String id, Uint8List blob) {
    Uint8List? pt;
    try {
      pt = crypto.decryptEntry(
        envelope: blob,
        entryKey: keyring.entryKey,
        entryId: id,
      );
      final e = VaultEntry.fromBytes(pt);
      return e.id == id ? e : null;
    } on Object {
      return null;
    } finally {
      wipe(pt);
    }
  }

  Future<void> saveEntry(VaultEntry entry) async {
    final existing = await db.item(entry.id);
    await db.upsert(
      VaultItemsCompanion(
        id: Value(entry.id),
        payload: Value(encryptEntry(entry)),
        localUpdatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        revision: Value(existing?.revision ?? 0),
        deleted: const Value(false),
        dirty: const Value(true),
      ),
    );
    _entries = _sorted([..._entries.where((e) => e.id != entry.id), entry]);
    notifyListeners();
    _changed();
  }

  Future<void> saveEntries(Iterable<VaultEntry> list) async {
    for (final e in list) {
      await saveEntry(e);
    }
  }

  /// Deletes an entry, keeping a tombstone so other devices learn about it.
  /// Its last-used time goes with it.
  Future<void> deleteEntry(String id) async {
    final db = this.db;
    await db.tombstoneItems([id], now: DateTime.now().millisecondsSinceEpoch);
    _entries = _entries.where((e) => e.id != id).toList();
    _lastUsed.remove(id);
    notifyListeners();
    _changed();
  }

  /// Deletes every entry in [ids] that exists and returns how many that was.
  /// Ids that are unknown, already deleted or repeated are ignored.
  ///
  /// This is [deleteEntry] for many entries: the same tombstones (so sync
  /// pushes them and other devices delete them), written in ONE database
  /// transaction, so a failure leaves every entry untouched and throws. On
  /// success the list is updated, listeners are told once and sync is told
  /// once.
  ///
  /// Other devices receive these as ordinary deletions, so their mass-deletion
  /// guard (`SyncService.massDeleteMin` / `massDeleteRatio`) judges them like
  /// any other batch of tombstones: deleting at least five entries and more
  /// than half of the vault in one go makes a synced device refuse the batch.
  Future<int> deleteEntries(Iterable<String> ids) async {
    final db = this.db;
    final live = {for (final e in _entries) e.id};
    final doomed = {
      for (final id in ids)
        if (live.contains(id)) id,
    };
    if (doomed.isEmpty) return 0;
    await db.tombstoneItems(doomed, now: DateTime.now().millisecondsSinceEpoch);
    // Locked while the transaction ran: the lock already dropped everything.
    if (!identical(_db, db)) return doomed.length;
    _entries = _entries.where((e) => !doomed.contains(e.id)).toList();
    _lastUsed.removeWhere((id, _) => doomed.contains(id));
    notifyListeners();
    _changed();
    return doomed.length;
  }

  /// Replaces the in-memory list after sync applied remote changes.
  Future<void> reloadFromDatabase() async {
    final db = this.db;
    final rows = await db.liveItems();
    _entries = _sorted([for (final r in rows) ?_decryptRow(r, keyring)]);
    // A deletion that came from another device never passed through
    // deleteEntry/deleteEntries: forget its last-used time here.
    final live = {for (final r in rows) r.id};
    if (_lastUsed.keys.any((id) => !live.contains(id))) {
      _lastUsed.removeWhere((id, _) => !live.contains(id));
      await db.pruneLastUsed();
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Last used
  // ---------------------------------------------------------------------------

  /// A second use of the entry that is already first, within this long of the
  /// last one, is not recorded.
  static const markUsedDebounce = Duration(seconds: 30);

  /// Records that [entryId] was just used (its password or username was
  /// copied, filled or revealed), for the "most recently used" order.
  ///
  /// Local metadata only: the entry is never rewritten, nothing is pushed to
  /// sync (`onLocalChange` is not called) and nothing leaves the device.
  /// Quietly does nothing for an unknown id, while locked, or when the clock
  /// did not move forward. Listeners are notified only when the entry is not
  /// already first in the recent order (when it is, nothing visible changes),
  /// and a repeat use of the first entry within [markUsedDebounce] is not
  /// even written to the database.
  Future<void> markUsed(String entryId) async {
    final db = _db;
    if (db == null || !isUnlocked) return;
    final entry = byId(entryId);
    if (entry == null) return;

    final nowMs = _clock().toUtc().millisecondsSinceEpoch;
    final before = _lastUsed[entryId]?.millisecondsSinceEpoch;
    if (before != null && nowMs <= before) return;

    final beforeOrder = before ?? entry.updatedAt.millisecondsSinceEpoch;
    final alreadyFirst = _entries.every(
      (o) =>
          o.id == entryId ||
          (_lastUsed[o.id]?.millisecondsSinceEpoch ??
                  o.updatedAt.millisecondsSinceEpoch) <
              beforeOrder,
    );
    if (alreadyFirst &&
        before != null &&
        nowMs - before < markUsedDebounce.inMilliseconds) {
      return;
    }

    _lastUsed[entryId] = _utc(nowMs);
    if (!alreadyFirst) notifyListeners();
    try {
      await db.putLastUsed(entryId, nowMs);
    } on Object catch (e) {
      // Losing a last-used time is harmless (a lock or a closing database can
      // race this). Never log more than the type.
      debugPrint('VaultSession: could not record usage (${e.runtimeType})');
    }
  }

  static DateTime _utc(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

  void _changed() {
    for (final cb in onLocalChange) {
      cb();
    }
  }

  static List<VaultEntry> _sorted(List<VaultEntry> list) => list
    ..sort((a, b) {
      if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

  Set<String> get allTags => {for (final e in _entries) ...e.tags};

  // ---------------------------------------------------------------------------
  // Account maintenance
  // ---------------------------------------------------------------------------

  /// Changes the master password. Requires the current one (re-verified) so
  /// an unattended unlocked device cannot be used to take over the vault.
  /// Returns the new server auth secret for sync.
  Future<String> changePassword(String current, String next) async {
    final header = _requireHeader();
    final check = await accounts.unlockWithPassword(current, header);
    check.lock();
    final (newHeader, auth) = await accounts.changePassword(
      keyring: keyring,
      header: header,
      newPassword: next,
    );
    await saveHeader(newHeader);
    notifyListeners();
    return auth;
  }

  /// Sets a new master password after a recovery-key unlock, and rotates
  /// the recovery key (the old one was just used and may be exposed).
  /// Returns (server auth secret, new recovery key text, recovery auth).
  Future<({String auth, String recoveryText, String recoveryAuth})>
  setPasswordAfterRecovery(String next) async {
    if (!unlockedViaRecovery) throw StateError('Not a recovery session');
    final (newHeader, auth) = await accounts.changePassword(
      keyring: keyring,
      header: _requireHeader(),
      newPassword: next,
    );
    final rotated = accounts.rotateRecoveryKey(
      keyring: keyring,
      header: newHeader,
    );
    await saveHeader(rotated.header);
    unlockedViaRecovery = false;
    notifyListeners();
    return (
      auth: auth,
      recoveryText: rotated.recoveryKeyText,
      recoveryAuth: rotated.recoveryAuthSecret,
    );
  }

  /// Destroys the local vault (keys, database, header). Irreversible. Also
  /// resets the unlock throttle and runs [onWipe].
  Future<void> wipeLocalVault() async {
    await lock();
    for (final f in [_dbFile, _headerFile]) {
      if (await f.exists()) await f.delete();
    }
    await biometrics?.disable();
    _header = null;
    // Failed guesses at the old password must not slow down the new vault.
    await throttle.recordSuccess();
    for (final cb in onWipe) {
      await cb();
    }
    _state = VaultState.noVault;
    notifyListeners();
  }
}
