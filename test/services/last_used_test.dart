import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/core/crypto/crypto.dart';
import 'package:hisn/data/db/database.dart';
import 'package:hisn/data/models/vault_entry.dart';
import 'package:hisn/services/entry_sort.dart';
import 'package:hisn/services/unlock_throttle.dart';
import 'package:hisn/services/vault_session.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

const _pw = 'violet-harbor-test-71-lantern';

void main() {
  late VaultCrypto crypto;
  late Directory dir;
  late DateTime now;
  late VaultSession s;

  VaultSession newSession() => VaultSession(
    crypto: crypto,
    directory: dir,
    throttle: UnlockThrottle(File('${dir.path}/throttle.json')),
    clock: () => now,
  );

  setUpAll(() async => crypto = VaultCrypto(await loadSodium()));
  setUp(() {
    dir = Directory.systemTemp.createTempSync('vs_lastused');
    now = DateTime.utc(2030, 5, 1, 12);
    s = newSession();
  });
  tearDown(() async {
    await s.lock();
    dir.deleteSync(recursive: true);
  });

  /// Three entries whose own edit times make the untouched "recent" order
  /// c, b, a (newest edit first).
  Future<void> seed() async {
    await s.init();
    await s.createVault(_pw);
    for (final (id, day) in [('a', 1), ('b', 2), ('c', 3)]) {
      await s.saveEntry(
        VaultEntry(
          id: id,
          title: 'Site $id',
          createdAt: DateTime.utc(2020, 1, day),
          updatedAt: DateTime.utc(2020, 1, day),
        ),
      );
    }
  }

  List<String> recentOrder() => [
    for (final e in sortEntries(s.entries, EntrySort.recent, s.lastUsedMap))
      e.id,
  ];

  group('markUsed', () {
    test('puts the most recently used entry on top', () async {
      await seed();
      expect(recentOrder(), ['c', 'b', 'a']);

      await s.markUsed('a');
      expect(recentOrder(), ['a', 'c', 'b']);

      now = now.add(const Duration(minutes: 5));
      await s.markUsed('b');
      expect(recentOrder(), ['b', 'a', 'c']);

      now = now.add(const Duration(minutes: 5));
      await s.markUsed('a');
      expect(recentOrder(), ['a', 'b', 'c']);
    });

    test('stores UTC times, readable by id and as a map', () async {
      await seed();
      expect(s.lastUsedAt('a'), isNull);
      expect(s.lastUsedMap, isEmpty);

      await s.markUsed('a');
      expect(s.lastUsedAt('a'), now);
      expect(s.lastUsedAt('a')!.isUtc, isTrue);
      expect(s.lastUsedMap, {'a': now});
      expect(s.lastUsedAt('b'), isNull);
      expect((await s.db.allLastUsed()), {'a': now.millisecondsSinceEpoch});
    });

    test('the map cannot be edited from outside', () async {
      await seed();
      await s.markUsed('a');
      expect(() => s.lastUsedMap['b'] = DateTime.now(), throwsUnsupportedError);
      expect(() => s.lastUsedMap.remove('a'), throwsUnsupportedError);
      expect(() => s.lastUsedMap.clear(), throwsUnsupportedError);
      expect(s.lastUsedMap.keys, ['a']);
    });

    test(
      'an unknown id is ignored: no state, no row, no notification',
      () async {
        await seed();
        var notified = 0;
        s.addListener(() => notified++);

        await s.markUsed('no-such-entry');
        await s.markUsed('');

        expect(s.lastUsedMap, isEmpty);
        expect(await s.db.allLastUsed(), isEmpty);
        expect(notified, 0);
      },
    );

    test('a deleted entry cannot be marked used', () async {
      await seed();
      await s.deleteEntry('a');
      await s.markUsed('a');
      expect(s.lastUsedAt('a'), isNull);
      expect(await s.db.allLastUsed(), isEmpty);
    });

    test('does nothing while locked', () async {
      await seed();
      await s.lock();
      await s.markUsed('a'); // must not throw
      expect(s.lastUsedMap, isEmpty);
    });

    test('never rewrites the entry and never reaches sync', () async {
      await seed();
      var localChanges = 0;
      s.onLocalChange.add(() => localChanges++);
      final before = (await s.db.item('a'))!;
      final listBefore = s.entries;

      await s.markUsed('a');

      final after = (await s.db.item('a'))!;
      expect(after.payload, before.payload);
      expect(after.localUpdatedAt, before.localUpdatedAt);
      expect(after.revision, before.revision);
      expect(after.dirty, before.dirty);
      expect(s.entries, same(listBefore));
      expect(s.byId('a')!.updatedAt, DateTime.utc(2020, 1, 1));
      expect(localChanges, 0);
    });

    test('notifies only when the order can change', () async {
      await seed(); // order c, b, a
      var notified = 0;
      s.addListener(() => notified++);
      Future<int?> stored(String id) async => (await s.db.allLastUsed())[id];

      // c is already first (its edit is the newest): nothing visible changes.
      await s.markUsed('c');
      expect(notified, 0);
      expect(await stored('c'), now.millisecondsSinceEpoch);

      // a would jump to the top.
      now = now.add(const Duration(minutes: 1));
      await s.markUsed('a');
      expect(notified, 1);

      // a is first and was used 10 s ago: not even written.
      final firstStamp = now.millisecondsSinceEpoch;
      now = now.add(const Duration(seconds: 10));
      await s.markUsed('a');
      expect(notified, 1);
      expect(await stored('a'), firstStamp);
      expect(s.lastUsedAt('a')!.millisecondsSinceEpoch, firstStamp);

      // Long enough later: written, still no order change to announce.
      now = now.add(VaultSession.markUsedDebounce);
      await s.markUsed('a');
      expect(notified, 1);
      expect(await stored('a'), now.millisecondsSinceEpoch);

      // Another entry takes the top again.
      now = now.add(const Duration(seconds: 1));
      await s.markUsed('b');
      expect(notified, 2);
      expect(recentOrder().first, 'b');
    });

    test('a quick repeat on a non-first entry still moves it', () async {
      await seed();
      now = now.add(const Duration(seconds: 1));
      await s.markUsed('a'); // a first
      now = now.add(const Duration(seconds: 1));
      await s.markUsed('b'); // b first
      now = now.add(const Duration(seconds: 1));
      await s.markUsed('a'); // 2 s after a's last use, but a is not first
      expect(recentOrder().first, 'a');
    });

    test('a clock that did not move forward changes nothing', () async {
      await seed();
      await s.markUsed('a');
      final stamp = s.lastUsedAt('a');
      now = now.subtract(const Duration(hours: 1));
      await s.markUsed('a');
      expect(s.lastUsedAt('a'), stamp);
    });
  });

  group('persistence', () {
    test('survives lock and unlock; lock empties the map', () async {
      await seed();
      await s.markUsed('a');
      now = now.add(const Duration(minutes: 1));
      await s.markUsed('b');
      final a = s.lastUsedAt('a');
      final b = s.lastUsedAt('b');

      await s.lock();
      expect(s.lastUsedMap, isEmpty);
      expect(s.lastUsedAt('a'), isNull);

      await s.unlockWithPassword(_pw);
      expect(s.lastUsedMap, {'a': a, 'b': b});
      expect(recentOrder(), ['b', 'a', 'c']);
    });

    test('a fresh session on the same files reads them too', () async {
      await seed();
      await s.markUsed('c');
      final c = s.lastUsedAt('c');
      await s.lock();

      s = newSession();
      await s.init();
      await s.unlockWithPassword(_pw);
      expect(s.lastUsedAt('c'), c);
    });
  });

  group('removal', () {
    test('deleting an entry removes its row and its map entry', () async {
      await seed();
      await s.markUsed('a');
      now = now.add(const Duration(minutes: 1));
      await s.markUsed('b');

      await s.deleteEntry('a');

      expect(s.lastUsedMap.keys, ['b']);
      expect(await s.db.allLastUsed(), {
        'b': s.lastUsedAt('b')!.millisecondsSinceEpoch,
      });
    });

    test(
      'a deletion that arrives from another device is cleaned up on reload',
      () async {
        await seed();
        await s.markUsed('a');
        now = now.add(const Duration(minutes: 1));
        await s.markUsed('b');

        // What SyncService.applyRemote stores for a remote tombstone.
        await s.db.upsert(
          const VaultItemsCompanion(
            id: Value('a'),
            payload: Value(null),
            localUpdatedAt: Value(1),
            revision: Value(5),
            deleted: Value(true),
            dirty: Value(false),
          ),
        );
        await s.reloadFromDatabase();

        expect(s.byId('a'), isNull);
        expect(s.lastUsedMap.keys, ['b']);
        expect((await s.db.allLastUsed()).keys, ['b']);
      },
    );

    test(
      'a row left behind while locked is removed at the next unlock',
      () async {
        await seed();
        await s.markUsed('a');
        await s.db.customStatement(
          'INSERT INTO entry_usages (entry_id, last_used_at) VALUES (?, ?)',
          ['orphan', 1],
        );
        await s.lock();

        await s.unlockWithPassword(_pw);
        expect(s.lastUsedMap.keys, ['a']);
        expect((await s.db.allLastUsed()).keys, ['a']);
      },
    );

    test('erasing the vault leaves nothing for the next vault', () async {
      await seed();
      await s.markUsed('a');
      await s.wipeLocalVault();
      expect(s.lastUsedMap, isEmpty);

      await s.createVault('another-synthetic-pass-42-orbit');
      await s.saveEntry(VaultEntry(id: 'a', title: 'New A'));
      expect(s.lastUsedAt('a'), isNull);
      expect(await s.db.allLastUsed(), isEmpty);
    });
  });

  group('migration', () {
    test('a vault created before last-used existed still opens', () async {
      await seed();
      await s.markUsed('a');
      final keyHex = s.keyring.databaseKey.runUnlockedSync(
        (r) => r.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      );
      await s.lock();

      // Turn the file back into what the previous build wrote: no usage
      // table, schema version 2.
      final old = raw.sqlite3.open('${dir.path}/vault.db');
      try {
        old.execute('''PRAGMA key = "x'$keyHex'"''');
        old.execute('DROP TABLE entry_usages');
        old.execute('PRAGMA user_version = 2');
      } finally {
        old.close();
      }

      await s.unlockWithPassword(_pw);
      expect(s.entries.map((e) => e.id).toSet(), {'a', 'b', 'c'});
      expect(s.lastUsedMap, isEmpty);
      expect(recentOrder(), ['c', 'b', 'a']);

      await s.markUsed('a');
      await s.lock();
      await s.unlockWithPassword(_pw);
      expect(s.lastUsedAt('a'), now);
      expect(
        (await s.db.customSelect('PRAGMA user_version').getSingle())
            .data['user_version'],
        3,
      );
    });
  });
}
