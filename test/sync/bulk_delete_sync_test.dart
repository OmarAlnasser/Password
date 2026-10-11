import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/core/crypto/crypto.dart';
import 'package:hisn/data/models/vault_entry.dart';
import 'package:hisn/services/sync/sync_service.dart';
import 'package:hisn/services/unlock_throttle.dart';
import 'package:hisn/services/vault_session.dart';

import 'fake_remote.dart';

const pw = 'violet-harbor-test-71-lantern';

/// Bulk delete and "last used" against the same fake server the sync tests
/// use: tombstones must travel like single deletes, last-used times must not
/// travel at all.
void main() {
  late VaultCrypto crypto;
  final dirs = <Directory>[];
  final sessions = <VaultSession>[];
  final syncs = <SyncService>[];

  setUpAll(() async => crypto = VaultCrypto(await loadSodium()));
  tearDown(() async {
    // See sync_test.dart: stop the debounce timers and close the databases
    // before the directories go away.
    for (final s in syncs) {
      s.dispose();
      await s.idle;
    }
    syncs.clear();
    for (final s in sessions) {
      await s.lock();
    }
    sessions.clear();
    for (final d in dirs) {
      d.deleteSync(recursive: true);
    }
    dirs.clear();
  });

  Future<(VaultSession, SyncService)> device(FakeServer server) async {
    final dir = Directory.systemTemp.createTempSync('vs_bulk_sync');
    dirs.add(dir);
    final s = VaultSession(
      crypto: crypto,
      directory: dir,
      throttle: UnlockThrottle(File('${dir.path}/t.json')),
    );
    await s.init();
    sessions.add(s);
    final sync = SyncService(s, FakeRemote(server));
    syncs.add(sync);
    return (s, sync);
  }

  /// Two devices on one account, both holding entries e0..e(n-1).
  Future<(VaultSession, SyncService, VaultSession, SyncService)> twoDevices(
    FakeServer server,
    int n,
  ) async {
    final (a, syncA) = await device(server);
    await a.createVault(pw);
    await syncA.enableSync('me@example.com', pw);
    final (b, syncB) = await device(server);
    await syncB.signInExisting('me@example.com', pw);
    for (var i = 0; i < n; i++) {
      await a.saveEntry(
        VaultEntry(id: 'e$i', title: 'Site $i', password: 'hunter-test-$i'),
      );
    }
    await syncA.syncNow();
    await syncB.syncNow();
    expect(b.entries, hasLength(n));
    return (a, syncA, b, syncB);
  }

  List<String> ids(VaultSession s) =>
      s.entries.map((e) => e.id).toList()..sort();

  test('a bulk delete reaches the server and the other device', () async {
    final server = FakeServer();
    final (a, syncA, b, syncB) = await twoDevices(server, 12);

    // 5 of 12: more than the guard's minimum, but not more than half.
    final doomed = ['e0', 'e2', 'e4', 'e6', 'e8'];
    expect(await a.deleteEntries(doomed), 5);
    await syncA.syncNow();

    for (final id in doomed) {
      final remote = server.items[id]!;
      expect(remote.deleted, isTrue, reason: id);
      expect(remote.payload, isNull, reason: id);
      // Based on the revision the server had, so it was accepted rather than
      // reported as a conflict.
      expect(remote.revision, 2, reason: id);
    }
    expect(server.items['e1']!.deleted, isFalse);

    await syncB.syncNow();
    expect(ids(b), ['e1', 'e10', 'e11', 'e3', 'e5', 'e7', 'e9']);
    expect(ids(b), ids(a));
    expect(syncB.status, SyncStatus.idle);
  });

  test('the pushes are the same as for single deletes', () async {
    final server = FakeServer();
    final (a, syncA, _, _) = await twoDevices(server, 4);
    server.requestLog.clear();

    await a.deleteEntries(['e0', 'e1']);
    await syncA.syncNow();
    final bulk = server.requestLog.where((l) => l.startsWith('push')).toList();

    await a.deleteEntry('e2');
    await a.deleteEntry('e3');
    await syncA.syncNow();
    final all = server.requestLog.where((l) => l.startsWith('push')).toList();

    // A tombstone is logged as "push <id> -".
    expect(bulk.toSet(), {'push e0 -', 'push e1 -'});
    expect(all.skip(bulk.length).toSet(), {'push e2 -', 'push e3 -'});
  });

  test(
    'deleting a lot at once is still judged by the receiving device guard',
    () async {
      final server = FakeServer();
      final (a, syncA, b, syncB) = await twoDevices(server, 10);

      // 7 of 10: at least 5 and more than half of what device B has.
      expect(await a.deleteEntries([for (var i = 0; i < 7; i++) 'e$i']), 7);
      await syncA.syncNow();
      expect(syncA.status, SyncStatus.idle);
      expect(server.items.values.where((i) => i.deleted), hasLength(7));

      // The existing guard treats them like any other batch of tombstones.
      await expectLater(syncB.syncNow(), throwsA(isA<MassDeletionException>()));
      expect(b.entries, hasLength(10));
      expect(syncB.status, SyncStatus.error);
      expect(syncB.pendingMassDeletion, 7);
    },
  );

  group('a refused mass deletion', () {
    /// Device A deletes 6 of 10 (enough to trip B's guard), B refuses it.
    Future<(VaultSession, SyncService, VaultSession, SyncService)> refused(
      FakeServer server,
    ) async {
      final (a, syncA, b, syncB) = await twoDevices(server, 10);
      await a.deleteEntries([for (var i = 0; i < 6; i++) 'e$i']);
      await syncA.syncNow();
      await expectLater(syncB.syncNow(), throwsA(isA<MassDeletionException>()));
      expect(syncB.pendingMassDeletion, 6);
      expect(b.entries, hasLength(10));
      return (a, syncA, b, syncB);
    }

    test('does not stop the device from pushing its own changes', () async {
      final server = FakeServer();
      final (_, _, b, syncB) = await refused(server);

      await b.saveEntry(
        VaultEntry(id: 'new-on-b', title: 'Made on B', password: 'hunter-x'),
      );
      await b.saveEntry(b.byId('e8')!.edit(title: 'Renamed on B'));
      await expectLater(syncB.syncNow(), throwsA(isA<MassDeletionException>()));

      expect(server.items['new-on-b']!.deleted, isFalse);
      expect(await b.db.dirtyItems(), isEmpty);
      // Still asking, still nothing deleted.
      expect(syncB.pendingMassDeletion, 6);
      expect(b.entries, hasLength(11));
    });

    test('"delete here too" applies it and sync is back to normal', () async {
      final server = FakeServer();
      final (a, _, b, syncB) = await refused(server);
      await b.saveEntry(
        VaultEntry(id: 'new-on-b', title: 'Made on B', password: 'hunter-x'),
      );

      await syncB.applyMassDeletion();
      expect(syncB.pendingMassDeletion, isNull);
      expect(syncB.status, SyncStatus.idle);
      expect(ids(b), ['e6', 'e7', 'e8', 'e9', 'new-on-b']);
      expect(server.items['new-on-b']!.deleted, isFalse);

      // The next pass is an ordinary one.
      await syncB.syncNow();
      expect(syncB.status, SyncStatus.idle);
      expect(a.entries, hasLength(4));
    });

    test(
      '"keep them" restores them on the server and the other device',
      () async {
        final server = FakeServer();
        final (a, syncA, b, syncB) = await refused(server);

        await syncB.keepMassDeletion();
        expect(syncB.pendingMassDeletion, isNull);
        expect(syncB.status, SyncStatus.idle);
        expect(b.entries, hasLength(10));
        for (var i = 0; i < 6; i++) {
          expect(server.items['e$i']!.deleted, isFalse, reason: 'e$i');
        }
        expect(await b.db.dirtyItems(), isEmpty);

        await syncA.syncNow();
        expect(ids(a), ids(b));
        expect(a.byId('e0')!.password, 'hunter-test-0');
        // Nothing left to ask about on either side.
        await syncB.syncNow();
        expect(syncB.status, SyncStatus.idle);
      },
    );

    test('is asked again after a lock, not forgotten', () async {
      final server = FakeServer();
      final (_, _, b, syncB) = await refused(server);
      await b.lock();
      expect(syncB.pendingMassDeletion, isNull);
      await b.unlockWithPassword(pw);
      await expectLater(syncB.syncNow(), throwsA(isA<MassDeletionException>()));
      expect(syncB.pendingMassDeletion, 6);
      expect(b.entries, hasLength(10));
    });
  });

  test('a delete pending while offline is pushed later, once', () async {
    final server = FakeServer();
    final (a, syncA, b, syncB) = await twoDevices(server, 6);
    await a.deleteEntries(['e1', 'e2']);
    // Not synced yet: the server still has them live.
    expect(server.items['e1']!.deleted, isFalse);
    expect((await a.db.dirtyItems()).map((r) => r.id).toSet(), {'e1', 'e2'});

    await syncA.syncNow();
    expect((await a.db.dirtyItems()), isEmpty);
    await syncB.syncNow();
    expect(ids(b), ['e0', 'e3', 'e4', 'e5']);
  });

  group('last used does not sync', () {
    test('using an entry pushes nothing and leaves no dirty row', () async {
      final server = FakeServer();
      final (a, syncA, _, _) = await twoDevices(server, 3);
      server.requestLog.clear();
      var localChanges = 0;
      a.onLocalChange.add(() => localChanges++);

      await a.markUsed('e0');
      await a.markUsed('e1');
      await syncA.syncNow();

      expect(localChanges, 0);
      expect(await a.db.dirtyItems(), isEmpty);
      expect(server.requestLog.where((l) => l.startsWith('push')), isEmpty);
      expect(a.lastUsedMap.keys.toSet(), {'e0', 'e1'});
    });

    test('another device does not learn when an entry was used', () async {
      final server = FakeServer();
      final (a, syncA, b, syncB) = await twoDevices(server, 3);
      await a.markUsed('e0');
      await syncA.syncNow();
      await syncB.syncNow();
      expect(b.lastUsedMap, isEmpty);
      expect(a.lastUsedAt('e0'), isNotNull);
    });

    test('a deletion made on another device removes the local time', () async {
      final server = FakeServer();
      final (a, syncA, b, syncB) = await twoDevices(server, 4);
      await b.markUsed('e1');
      await b.markUsed('e2');
      expect(b.lastUsedMap.keys.toSet(), {'e1', 'e2'});

      await a.deleteEntries(['e1']);
      await syncA.syncNow();
      await syncB.syncNow();

      expect(b.byId('e1'), isNull);
      expect(b.lastUsedMap.keys.toSet(), {'e2'});
      expect((await b.db.allLastUsed()).keys.toSet(), {'e2'});
    });
  });
}
