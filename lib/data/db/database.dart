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

@DriftDatabase(tables: [VaultItems, KvStore, Favicons])
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

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) await m.createTable(favicons);
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
}
