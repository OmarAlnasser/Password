import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sodium/sodium_sumo.dart';

part 'database.g.dart';

/// One row per entry. `payload` is the XChaCha20-Poly1305 envelope produced by
/// `VaultCrypto.encryptEntry`; it is byte-for-byte what is stored on the
/// server, so sync never needs to re-encrypt.
class VaultItems extends Table {
  TextColumn get id => text()();
  BlobColumn get payload => blob().nullable()(); // null for tombstones
  /// Local edit time (ms since epoch, client clock). Informational only;
  /// conflict resolution uses the server revision.
  IntColumn get localUpdatedAt => integer()();

  /// Last server revision this row is based on (0 = never synced).
  IntColumn get revision => integer().withDefault(const Constant(0))();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  /// Has local changes not yet pushed.
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Small key/value store for non-secret state (sync cursor, etc.).
class KvStore extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Website icons fetched directly from each site (see `FaviconService`).
/// Local only, never synced: which sites the user has accounts with is vault
/// metadata, so it lives inside the encrypted database and nowhere else.
class Favicons extends Table {
  TextColumn get host => text()();

  /// Validated image bytes; null if no usable icon was ever found.
  BlobColumn get bytes => blob().nullable()();
  TextColumn get contentType => text().nullable()();

  /// Time of the last fetch attempt (ms since epoch, client clock).
  IntColumn get fetchedAt => integer()();

  /// The last attempt failed. [bytes] may still hold an older icon.
  BoolColumn get failed => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {host};
}

/// When each entry was last used (copied, opened for autofill, ...), for the
/// "most recently used first" order.
///
/// Local only, on purpose: it is not part of the encrypted entry blob and is
/// never synced. Using a password must not rewrite the entry, wake the sync
/// push, create a conflict, or tell the server (or another device) which
/// accounts are in use. It lives in the encrypted database, like [Favicons],
/// because "which sites I use most" is vault metadata.
///
/// There is deliberately no foreign key to [VaultItems] (foreign keys are off
/// for this database): rows are removed together with their entry in
/// [VaultDatabase.tombstoneItems], inserted only for a live entry in
/// [VaultDatabase.putLastUsed], and orphans left by a remote deletion are
/// removed by [VaultDatabase.pruneLastUsed].
class EntryUsages extends Table {
  TextColumn get entryId => text()();

  /// Time of the last use (ms since epoch, UTC).
  IntColumn get lastUsedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {entryId};
}

@DriftDatabase(tables: [VaultItems, KvStore, Favicons, EntryUsages])
class VaultDatabase extends _$VaultDatabase {
  VaultDatabase(super.e);

  /// Opens (or creates) the SQLCipher database at [file] with a raw 256-bit
  /// key derived from the vault key (`Keyring.databaseKey`).
  factory VaultDatabase.open(File file, SecureKey databaseKey) {
    // SQLCipher only accepts the key as SQL text. Using the raw-key form
    // (x'..') skips SQLCipher's own PBKDF2, since the key is already uniform.
    final keyHex = databaseKey.runUnlockedSync(
      (raw) => raw.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
    );
    return VaultDatabase(
      NativeDatabase.createInBackground(
        file,
        setup: (db) {
          db.execute('PRAGMA key = "x\'$keyHex\'"');
          // Fails immediately with SQLITE_NOTADB if the key is wrong.
          db.select('SELECT count(*) FROM sqlite_master');
          // Zero SQLCipher's internal buffers when freed, overwrite deleted
          // content on disk, and never spill temp tables to unencrypted files.
          db.execute('PRAGMA cipher_memory_security = ON');
          db.execute('PRAGMA secure_delete = ON');
          db.execute('PRAGMA temp_store = MEMORY');
        },
      ),
    );
  }

  /// 1: vault items + key/value store. 2: website icons. 3: last-used times.
  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) await m.createTable(favicons);
      if (from < 3) await m.createTable(entryUsages);
    },
  );

  Future<List<VaultItem>> liveItems() =>
      (select(vaultItems)..where((t) => t.deleted.equals(false))).get();

  Future<List<VaultItem>> allItems() => select(vaultItems).get();

  Future<VaultItem?> item(String id) =>
      (select(vaultItems)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> upsert(VaultItemsCompanion row) =>
      into(vaultItems).insertOnConflictUpdate(row);

  Future<List<VaultItem>> dirtyItems() =>
      (select(vaultItems)..where((t) => t.dirty.equals(true))).get();

  Future<String?> getKv(String key) async => (await (select(
    kvStore,
  )..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  Future<void> setKv(String key, String value) => into(kvStore)
      .insertOnConflictUpdate(KvStoreCompanion.insert(key: key, value: value));

  Future<Favicon?> favicon(String host) =>
      (select(favicons)..where((t) => t.host.equals(host))).getSingleOrNull();

  Future<List<Favicon>> allFavicons() => select(favicons).get();

  /// Inserts or replaces the cached icon for [host]. [fetchedAt] is ms since
  /// epoch.
  Future<void> putFavicon({
    required String host,
    Uint8List? bytes,
    String? contentType,
    required int fetchedAt,
    bool failed = false,
  }) => into(favicons).insertOnConflictUpdate(
    FaviconsCompanion.insert(
      host: host,
      bytes: Value(bytes),
      contentType: Value(contentType),
      fetchedAt: fetchedAt,
      failed: Value(failed),
    ),
  );

  // ---------------------------------------------------------------------------
  // Deleting and last-used times
  // ---------------------------------------------------------------------------

  /// Most ids bound in one `IN (...)` list. SQLite's limit is far higher on
  /// current builds but 999 on old ones.
  static const int _idChunk = 400;

  /// Turns every id in [ids] into a tombstone (payload wiped, `deleted`,
  /// `dirty`, revision kept so the next push is based on what the server
  /// has) and forgets its last-used time, in ONE transaction: either every id
  /// is deleted or none is. This is the only delete path; the single-entry
  /// delete is the same call with one id. [now] is ms since epoch.
  ///
  /// An id with no row yet still gets a tombstone (revision 0), exactly as a
  /// single delete always did; callers decide which ids are worth passing.
  Future<void> tombstoneItems(Iterable<String> ids, {required int now}) {
    final unique = ids.toSet().toList();
    if (unique.isEmpty) return Future.value();
    return transaction(() async {
      for (var i = 0; i < unique.length; i += _idChunk) {
        final chunk = unique.sublist(
          i,
          i + _idChunk > unique.length ? unique.length : i + _idChunk,
        );
        final existing = await (select(
          vaultItems,
        )..where((t) => t.id.isIn(chunk))).get();
        final revisions = {for (final r in existing) r.id: r.revision};
        await batch((b) {
          b.insertAllOnConflictUpdate(vaultItems, [
            for (final id in chunk)
              VaultItemsCompanion(
                id: Value(id),
                payload: const Value(null),
                localUpdatedAt: Value(now),
                revision: Value(revisions[id] ?? 0),
                deleted: const Value(true),
                dirty: const Value(true),
              ),
          ]);
        });
        await (delete(entryUsages)..where((t) => t.entryId.isIn(chunk))).go();
      }
    });
  }

  /// Every stored last-used time: entry id -> ms since epoch.
  Future<Map<String, int>> allLastUsed() async => {
    for (final r in await select(entryUsages).get()) r.entryId: r.lastUsedAt,
  };

  /// Records that [entryId] was used at [ms] (ms since epoch, UTC). One
  /// statement, and only for an entry that exists and is not deleted, so a
  /// use that races a delete can never leave an orphan row behind.
  Future<void> putLastUsed(String entryId, int ms) => customStatement(
    'INSERT INTO entry_usages (entry_id, last_used_at) '
    'SELECT ?1, ?2 '
    'WHERE EXISTS (SELECT 1 FROM vault_items WHERE id = ?1 AND deleted = 0) '
    'ON CONFLICT(entry_id) DO UPDATE SET last_used_at = excluded.last_used_at',
    [entryId, ms],
  );

  /// Drops last-used rows whose entry is gone or deleted. Needed after sync
  /// applied a remote deletion, which never goes through [tombstoneItems].
  Future<void> pruneLastUsed() => customStatement(
    'DELETE FROM entry_usages WHERE entry_id NOT IN '
    '(SELECT id FROM vault_items WHERE deleted = 0)',
  );
}
