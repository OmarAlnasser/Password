import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/core/crypto/crypto.dart';
import 'package:hisn/data/models/vault_entry.dart';
import 'package:hisn/services/unlock_throttle.dart';
import 'package:hisn/services/vault_session.dart';

const _pw = 'violet-harbor-test-71-lantern';

void main() {
  late VaultCrypto crypto;
  late Directory dir;
  late DateTime now;
  late VaultSession s;
  late int notified;
  late int localChanges;

  VaultSession newSession() => VaultSession(
    crypto: crypto,
    directory: dir,
    throttle: UnlockThrottle(File('${dir.path}/throttle.json')),
    clock: () => now,
  );

  setUpAll(() async => crypto = VaultCrypto(await loadSodium()));
  setUp(() {
    dir = Directory.systemTemp.createTempSync('vs_bulkdel');
    now = DateTime.utc(2030, 5, 1, 12);
    s = newSession();
  });
  tearDown(() async {
    await s.lock();
    dir.deleteSync(recursive: true);
  });

  /// Entries e0..e(n-1) with synthetic content. Counters start after seeding.
  Future<void> seed(int n) async {
    await s.init();
    await s.createVault(_pw);
    for (var i = 0; i < n; i++) {
      await s.saveEntry(
        VaultEntry(
          id: 'e$i',
          title: 'Site $i',
          username: 'user$i@example.test',
          password: 'hunter-test-$i',
        ),
      );
    }
    notified = 0;
    localChanges = 0;
    s.addListener(() => notified++);
    s.onLocalChange.add(() => localChanges++);
  }

  Set<String> ids() => s.entries.map((e) => e.id).toSet();

  test('deletes every given entry and returns how many', () async {
    await seed(6);
    final n = await s.deleteEntries(['e1', 'e3', 'e4']);
    expect(n, 3);
    expect(ids(), {'e0', 'e2', 'e5'});
    expect(s.byId('e3'), isNull);
  });

  test('leaves the same tombstones as a single delete', () async {
    await seed(4);
    // Give two rows a known server revision, as after a sync.
    for (final id in ['e0', 'e1']) {
      final row = (await s.db.item(id))!;
      await s.db.upsert(
        row.copyWith(revision: 9, dirty: false).toCompanion(true),
      );
    }

    await s.deleteEntry('e0');
    await s.deleteEntries(['e1']);

    final single = (await s.db.item('e0'))!;
    final bulk = (await s.db.item('e1'))!;
    for (final r in [single, bulk]) {
      expect(r.deleted, isTrue, reason: r.id);
      expect(r.payload, isNull, reason: r.id);
      expect(r.dirty, isTrue, reason: r.id);
      expect(r.revision, 9, reason: r.id);
    }
    expect(bulk.localUpdatedAt, greaterThan(0));
    // Sync pushes both: they are among the dirty rows.
    expect((await s.db.dirtyItems()).where((r) => r.deleted), hasLength(2));
  });

  test('ignores unknown, repeated and already deleted ids', () async {
    await seed(4);
    await s.deleteEntry('e0');
    notified = 0;
    localChanges = 0;

    final n = await s.deleteEntries(['e1', 'e1', 'ghost', 'e0', '']);
    expect(n, 1);
    expect(ids(), {'e2', 'e3'});
    // A tombstone is not created for an id the vault never had.
    expect(await s.db.item('ghost'), isNull);
    expect(await s.db.item(''), isNull);
    expect(notified, 1);
  });

  test('nothing to delete: returns 0 and touches nothing', () async {
    await seed(3);
    final before = await s.db.allItems();

    expect(await s.deleteEntries(const []), 0);
    expect(await s.deleteEntries(['ghost', 'other']), 0);

    expect(ids(), {'e0', 'e1', 'e2'});
    expect((await s.db.allItems()).length, before.length);
    expect(notified, 0);
    expect(localChanges, 0);
  });

  test('accepts any iterable, including a lazy one', () async {
    await seed(5);
    final n = await s.deleteEntries(
      s.entries
          .where((e) => e.title.endsWith('2') || e.title.endsWith('4'))
          .map((e) => e.id),
    );
    expect(n, 2);
    expect(ids(), {'e0', 'e1', 'e3'});
  });

  test('listeners and sync are told exactly once', () async {
    await seed(8);
    await s.deleteEntries(['e0', 'e1', 'e2', 'e3', 'e4']);
    expect(notified, 1);
    expect(localChanges, 1);
  });

  test('forgets the last-used time of the deleted entries only', () async {
    await seed(4);
    for (final id in ['e0', 'e1', 'e2']) {
      now = now.add(const Duration(minutes: 1));
      await s.markUsed(id);
    }
    final kept = s.lastUsedAt('e2');

    await s.deleteEntries(['e0', 'e1']);

    expect(s.lastUsedMap, {'e2': kept});
    expect(await s.db.allLastUsed(), {'e2': kept!.millisecondsSinceEpoch});
  });

  test('all or none: a failure rolls everything back and throws', () async {
    await seed(6);
    for (final id in ['e0', 'e1', 'e2']) {
      now = now.add(const Duration(minutes: 1));
      await s.markUsed(id);
    }
    final usedBefore = Map.of(s.lastUsedMap);
    final listBefore = s.entries;
    final rowsBefore = {for (final r in await s.db.allItems()) r.id: r.payload};
    // The database refuses to touch e4, the last one of the batch.
    await s.db.customStatement(
      'CREATE TRIGGER refuse BEFORE UPDATE ON vault_items '
      "WHEN NEW.id = 'e4' BEGIN SELECT RAISE(ABORT, 'refused'); END",
    );
    notified = 0;
    localChanges = 0;

    await expectLater(
      s.deleteEntries(['e0', 'e1', 'e2', 'e3', 'e4']),
      throwsA(anything),
    );

    // Nothing changed in memory ...
    expect(s.entries, same(listBefore));
    expect(s.lastUsedMap, usedBefore);
    expect(notified, 0);
    expect(localChanges, 0);
    // ... or in the database.
    final rowsAfter = await s.db.allItems();
    expect(rowsAfter.where((r) => r.deleted), isEmpty);
    expect({for (final r in rowsAfter) r.id: r.payload}, rowsBefore);
    expect(await s.db.allLastUsed(), hasLength(3));

    // After the problem is gone the same call works.
    await s.db.customStatement('DROP TRIGGER refuse');
    expect(await s.deleteEntries(['e0', 'e1', 'e2', 'e3', 'e4']), 5);
    expect(ids(), {'e5'});
  });

  test('deleted entries stay deleted after a lock and unlock', () async {
    await seed(4);
    await s.deleteEntries(['e0', 'e2']);
    await s.lock();
    await s.unlockWithPassword(_pw);
    expect(ids(), {'e1', 'e3'});
    // The tombstones are still there for sync.
    expect(
      (await s.db.allItems()).where((r) => r.deleted).map((r) => r.id).toSet(),
      {'e0', 'e2'},
    );
  });

  test('a locked vault refuses, like a single delete', () async {
    await seed(2);
    await s.lock();
    await expectLater(s.deleteEntries(['e0']), throwsStateError);
    await expectLater(s.deleteEntry('e0'), throwsStateError);
  });

  test('a large batch is one pass', () async {
    await seed(0);
    await s.saveEntries([
      for (var i = 0; i < 450; i++) VaultEntry(id: 'bulk$i', title: 'T$i'),
    ]);
    notified = 0;
    final n = await s.deleteEntries([for (var i = 0; i < 449; i++) 'bulk$i']);
    expect(n, 449);
    expect(ids(), {'bulk449'});
    expect(notified, 1);
    expect((await s.db.allItems()).where((r) => r.deleted), hasLength(449));
  });

  test('ids are matched exactly, not as patterns', () async {
    await seed(0);
    await s.saveEntry(VaultEntry(id: 'a%', title: 'pct'));
    await s.saveEntry(VaultEntry(id: 'ab', title: 'ab'));
    await s.saveEntry(VaultEntry(id: "x'y", title: 'quote'));
    expect(await s.deleteEntries(['a%', "x'y"]), 2);
    expect(ids(), {'ab'});
  });
}
