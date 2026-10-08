import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/core/crypto/crypto.dart';
import 'package:hisn/data/db/database.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

/// The database layer of "last used" and bulk delete, against a real SQLCipher
/// file, plus the schema migration from the two older versions.
void main() {
  late SodiumSumo sodium;
  late Directory dir;
  late SecureKey key;
  late File file;
  VaultDatabase? db;

  setUpAll(() async => sodium = await loadSodium());
  setUp(() {
    dir = Directory.systemTemp.createTempSync('vs_usage_db');
    key = sodium.secureRandom(32);
    file = File('${dir.path}/vault.db');
  });
  tearDown(() async {
    await db?.close();
    db = null;
    key.dispose();
    dir.deleteSync(recursive: true);
  });

  VaultDatabase open() => db = VaultDatabase.open(file, key);

  String keyHex() => key.runUnlockedSync(
    (r) => r.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
  );

  Future<void> addLive(VaultDatabase d, String id, {int revision = 0}) =>
      d.upsert(
        VaultItemsCompanion(
          id: Value(id),
          payload: Value(Uint8List.fromList([1, 2, 3])),
          localUpdatedAt: const Value(1000),
          revision: Value(revision),
          deleted: const Value(false),
          dirty: const Value(false),
        ),
      );

  Future<int> userVersion(VaultDatabase d) async =>
      (await d.customSelect('PRAGMA user_version').getSingle())
              .data['user_version']!
          as int;

  group('last-used rows', () {
    test('a new database is at schema 3 and has the table', () async {
      final d = open();
      expect(d.schemaVersion, 3);
      expect(await userVersion(d), 3);
      expect(await d.allLastUsed(), isEmpty);
    });

    test('only a live entry gets a row; a later use replaces it', () async {
      final d = open();
      await addLive(d, 'live');
      await d.putLastUsed('live', 1000);
      await d.putLastUsed('ghost', 2000); // no such item
      expect(await d.allLastUsed(), {'live': 1000});

      await d.putLastUsed('live', 5000);
      expect(await d.allLastUsed(), {'live': 5000});

      // A use that races a delete cannot resurrect a row.
      await d.tombstoneItems(['live'], now: 6000);
      await d.putLastUsed('live', 7000);
      expect(await d.allLastUsed(), isEmpty);
    });

    test(
      'pruneLastUsed drops rows of deleted or missing entries only',
      () async {
        final d = open();
        await addLive(d, 'keep');
        await addLive(d, 'gone');
        await d.putLastUsed('keep', 10);
        await d.putLastUsed('gone', 20);
        // A remote deletion: the tombstone is stored by sync, not by
        // tombstoneItems, so the usage row is still there.
        await d.upsert(
          const VaultItemsCompanion(
            id: Value('gone'),
            payload: Value(null),
            localUpdatedAt: Value(1),
            deleted: Value(true),
          ),
        );
        await d.customStatement(
          'INSERT INTO entry_usages (entry_id, last_used_at) VALUES (?, ?)',
          ['never-existed', 30],
        );
        expect(await d.allLastUsed(), hasLength(3));

        await d.pruneLastUsed();
        expect(await d.allLastUsed(), {'keep': 10});
      },
    );
  });

  group('tombstoneItems', () {
    test(
      'wipes the payload, keeps the revision, marks dirty, drops usage',
      () async {
        final d = open();
        await addLive(d, 'a', revision: 7);
        await addLive(d, 'b', revision: 3);
        await addLive(d, 'c', revision: 1);
        await d.putLastUsed('a', 1);
        await d.putLastUsed('c', 2);

        await d.tombstoneItems(['a', 'b'], now: 4242);

        for (final (id, rev) in [('a', 7), ('b', 3)]) {
          final row = (await d.item(id))!;
          expect(row.deleted, isTrue, reason: id);
          expect(row.payload, isNull, reason: id);
          expect(row.dirty, isTrue, reason: id);
          expect(row.revision, rev, reason: id);
          expect(row.localUpdatedAt, 4242, reason: id);
        }
        final c = (await d.item('c'))!;
        expect(c.deleted, isFalse);
        expect(c.payload, isNotNull);
        expect(await d.allLastUsed(), {'c': 2});
      },
    );

    test('an id with no row still gets a tombstone at revision 0', () async {
      final d = open();
      await d.tombstoneItems(['never-saved'], now: 1);
      final row = (await d.item('never-saved'))!;
      expect(row.deleted, isTrue);
      expect(row.revision, 0);
    });

    test('nothing to do for no ids, repeated ids count once', () async {
      final d = open();
      await d.tombstoneItems(const [], now: 1);
      expect(await d.allItems(), isEmpty);
      await addLive(d, 'a');
      await d.tombstoneItems(['a', 'a', 'a'], now: 1);
      expect((await d.allItems()).single.deleted, isTrue);
    });

    test('more ids than fit in one statement chunk', () async {
      final d = open();
      final ids = [for (var i = 0; i < 1000; i++) 'id$i'];
      await d.batch((b) {
        b.insertAll(d.vaultItems, [
          for (final id in ids)
            VaultItemsCompanion(
              id: Value(id),
              payload: Value(Uint8List.fromList([9])),
              localUpdatedAt: const Value(1),
              revision: const Value(2),
            ),
        ]);
      });
      for (final id in ids.take(5)) {
        await d.putLastUsed(id, 5);
      }
      await d.tombstoneItems(ids, now: 77);
      final rows = await d.allItems();
      expect(rows, hasLength(1000));
      expect(rows.every((r) => r.deleted && r.payload == null), isTrue);
      expect(rows.every((r) => r.revision == 2 && r.dirty), isTrue);
      expect(await d.allLastUsed(), isEmpty);
    });

    test(
      'all or nothing: a failure in a later chunk undoes the earlier ones',
      () async {
        final d = open();
        final ids = [for (var i = 0; i < 900; i++) 'id$i'];
        await d.batch((b) {
          b.insertAll(d.vaultItems, [
            for (final id in ids)
              VaultItemsCompanion(
                id: Value(id),
                payload: Value(Uint8List.fromList([9])),
                localUpdatedAt: const Value(1),
                dirty: const Value(false),
              ),
          ]);
        });
        await d.putLastUsed('id0', 11);
        await d.putLastUsed('id899', 12);
        // The last id lives in the third chunk of 400, after two chunks were
        // already written inside the transaction.
        await d.customStatement(
          'CREATE TRIGGER boom BEFORE UPDATE ON vault_items '
          "WHEN NEW.id = 'id899' BEGIN SELECT RAISE(ABORT, 'boom'); END",
        );

        await expectLater(d.tombstoneItems(ids, now: 5), throwsA(anything));

        final rows = await d.allItems();
        expect(rows.where((r) => r.deleted), isEmpty);
        expect(rows.every((r) => r.payload != null && !r.dirty), isTrue);
        expect(await d.allLastUsed(), {'id0': 11, 'id899': 12});

        // The database is still usable after the rollback.
        await d.customStatement('DROP TRIGGER boom');
        await d.tombstoneItems(['id0'], now: 6);
        expect((await d.item('id0'))!.deleted, isTrue);
      },
    );
  });

  // The two DDL blocks are frozen copies of what drift generated for those
  // schema versions. They must not be regenerated from the current code, or
  // the test would stop testing an upgrade.
  group('migration', () {
    const v1 = [
      'CREATE TABLE "kv_store" ("key" TEXT NOT NULL, "value" TEXT NOT NULL, '
          'PRIMARY KEY ("key"))',
      'CREATE TABLE "vault_items" ("id" TEXT NOT NULL, "payload" BLOB NULL, '
          '"local_updated_at" INTEGER NOT NULL, "revision" INTEGER NOT NULL '
          'DEFAULT 0, "deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("deleted" '
          'IN (0, 1)), "dirty" INTEGER NOT NULL DEFAULT 1 CHECK ("dirty" IN '
          '(0, 1)), PRIMARY KEY ("id"))',
    ];
    const favicons =
        'CREATE TABLE "favicons" ("host" TEXT NOT NULL, "bytes" BLOB NULL, '
        '"content_type" TEXT NULL, "fetched_at" INTEGER NOT NULL, "failed" '
        'INTEGER NOT NULL DEFAULT 0 CHECK ("failed" IN (0, 1)), PRIMARY KEY '
        '("host"))';

    /// Writes an encrypted database file the way an older build left it.
    void createOldVault(int version) {
      final old = raw.sqlite3.open(file.path);
      try {
        old.execute('''PRAGMA key = "x'${keyHex()}'"''');
        for (final ddl in [...v1, if (version >= 2) favicons]) {
          old.execute(ddl);
        }
        old.execute(
          'INSERT INTO vault_items (id, payload, local_updated_at, revision, '
          "deleted, dirty) VALUES ('old-live', x'010203', 1234, 4, 0, 0), "
          "('old-gone', NULL, 1235, 2, 1, 1)",
        );
        old.execute("INSERT INTO kv_store VALUES ('sync_seq', '41')");
        if (version >= 2) {
          old.execute(
            'INSERT INTO favicons (host, bytes, content_type, fetched_at, '
            "failed) VALUES ('example.test', x'0a0b', 'image/png', 99, 0)",
          );
        }
        old.execute('PRAGMA user_version = $version');
      } finally {
        old.dispose();
      }
    }

    Future<void> expectUpgraded(
      VaultDatabase d, {
      required bool favicon,
    }) async {
      expect(await userVersion(d), 3);

      // Everything that was there is still there, unchanged.
      final live = (await d.item('old-live'))!;
      expect(live.payload, [1, 2, 3]);
      expect(live.revision, 4);
      expect(live.deleted, isFalse);
      expect(live.dirty, isFalse);
      final gone = (await d.item('old-gone'))!;
      expect(gone.deleted, isTrue);
      expect(gone.dirty, isTrue);
      expect(await d.getKv('sync_seq'), '41');
      if (favicon) {
        final f = (await d.favicon('example.test'))!;
        expect(f.bytes, [10, 11]);
        expect(f.contentType, 'image/png');
      }

      // The new table exists, starts empty and works.
      expect(await d.allLastUsed(), isEmpty);
      await d.putLastUsed('old-live', 555);
      await d.putLastUsed('old-gone', 556); // deleted: no row
      expect(await d.allLastUsed(), {'old-live': 555});
      await d.tombstoneItems(['old-live'], now: 1);
      expect(await d.allLastUsed(), isEmpty);
    }

    test(
      'a version 2 database opens, keeps its data and gains the table',
      () async {
        createOldVault(2);
        // A plain (unkeyed) SQLite would make this assertion fail: the file
        // really is the SQLCipher one the app uses.
        expect(
          String.fromCharCodes(file.readAsBytesSync().take(15)),
          isNot('SQLite format 3'),
        );
        final d = open();
        await expectUpgraded(d, favicon: true);
        // Opening it again is a no-op, not a second migration.
        await d.close();
        final again = open();
        expect(await userVersion(again), 3);
        expect(await again.item('old-live'), isNotNull);
      },
    );

    test('a version 1 database upgrades through every step', () async {
      createOldVault(1);
      final d = open();
      await expectUpgraded(d, favicon: false);
      // The version 2 step ran as well.
      expect(await d.allFavicons(), isEmpty);
    });
  });
}
