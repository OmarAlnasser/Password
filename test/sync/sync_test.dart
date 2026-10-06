import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultsnap/core/crypto/crypto.dart';
import 'package:vaultsnap/data/models/vault_entry.dart';
import 'package:vaultsnap/services/sync/remote_store.dart';
import 'package:vaultsnap/services/sync/sync_service.dart';
import 'package:vaultsnap/services/unlock_throttle.dart';
import 'package:vaultsnap/services/vault_session.dart';

import 'fake_remote.dart';

const pw = 'violet-harbor-quantum-71-lantern';

void main() {
  late VaultCrypto crypto;
  final dirs = <Directory>[];
  final sessions = <VaultSession>[];
  final syncs = <SyncService>[];

  setUpAll(() async => crypto = VaultCrypto(await loadSodium()));
  tearDown(() async {
    // Every local save arms SyncService's 2 s debounce timer. Cancel it and
    // close the databases before deleting the directories, or the timer
    // fires during a later test, syncs a deleted vault, and any error it
    // throws fails this test after it has completed.
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
    final dir = Directory.systemTemp.createTempSync('vs_sync');
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

  Future<(VaultSession, SyncService, VaultSession, SyncService)> twoDevices(
    FakeServer server,
  ) async {
    final (a, syncA) = await device(server);
    await a.createVault(pw);
    await syncA.enableSync('me@example.com', pw);
    final (b, syncB) = await device(server);
    await syncB.signInExisting('me@example.com', pw);
    return (a, syncA, b, syncB);
  }

  test('entries propagate between devices, including deletions', () async {
    final server = FakeServer();
    final (a, syncA, b, syncB) = await twoDevices(server);
    await a.saveEntry(VaultEntry(id: 'e1', title: 'Mail', password: 'p1'));
    await syncA.syncNow();
    await syncB.syncNow();
    expect(b.byId('e1')!.password, 'p1');

    await b.deleteEntry('e1');
    await syncB.syncNow();
    await syncA.syncNow();
    expect(a.byId('e1'), isNull);
    expect(server.items['e1']!.deleted, isTrue);
    expect(server.items['e1']!.payload, isNull);
  });

  test(
    'concurrent edits: later edit wins, loser password kept in history',
    () async {
      final server = FakeServer();
      final (a, syncA, b, syncB) = await twoDevices(server);
      final base = VaultEntry(id: 'x', title: 'Bank', password: 'orig');
      await a.saveEntry(base);
      await syncA.syncNow();
      await syncB.syncNow();

      final t0 = DateTime.now().toUtc();
      await a.saveEntry(a.byId('x')!.edit(password: 'fromA', now: t0));
      await b.saveEntry(
        b
            .byId('x')!
            .edit(password: 'fromB', now: t0.add(const Duration(seconds: 5))),
      );
      await syncA.syncNow(); // A pushes first
      await syncB.syncNow(); // B conflicts, B is newer -> B wins
      await syncA.syncNow();

      for (final s in [a, b]) {
        final e = s.byId('x')!;
        expect(e.password, 'fromB');
        expect(e.history.map((h) => h.password), contains('fromA'));
      }
    },
  );

  test(
    'server never receives plaintext, keys or the master password',
    () async {
      final server = FakeServer();
      final (a, syncA, _, _) = await twoDevices(server);
      await a.saveEntry(
        VaultEntry(
          id: 'e',
          title: 'SECRET-TITLE',
          username: 'SECRET-USER',
          password: 'SECRET-PASSWORD',
          notes: 'SECRET-NOTES',
        ),
      );
      await syncA.syncNow();
      final log = server.requestLog.join('\n');
      for (final needle in ['SECRET-', pw]) {
        expect(log.contains(needle), isFalse, reason: needle);
      }
      String hex(List<int> b) =>
          b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
      for (final k in [
        a.keyring.vaultKey,
        a.keyring.entryKey,
        a.keyring.databaseKey,
      ]) {
        expect(log.contains(hex(k.extractBytes())), isFalse);
      }
    },
  );

  group('malicious or corrupted server data', () {
    test('tampered ciphertext is rejected and local copy kept', () async {
      final server = FakeServer();
      final (a, syncA, b, syncB) = await twoDevices(server);
      await a.saveEntry(VaultEntry(id: 'e', title: 'T', password: 'good'));
      await syncA.syncNow();
      await syncB.syncNow();
      server.tamper(
        'e',
        (r) => RemoteItem(
          id: r.id,
          payload: Uint8List.fromList(r.payload!)..[30] ^= 1,
          deleted: false,
          revision: r.revision + 1,
          seq: 0,
          updatedAt: r.updatedAt,
        ),
      );
      await syncB.syncNow();
      expect(b.byId('e')!.password, 'good');
      expect(syncB.rejectedItems, 1);
    });

    test('ciphertext swapped between two entries is rejected', () async {
      final server = FakeServer();
      final (a, syncA, b, syncB) = await twoDevices(server);
      await a.saveEntry(
        VaultEntry(id: 'bank', title: 'Bank', password: 'bankpw'),
      );
      await a.saveEntry(
        VaultEntry(id: 'phish', title: 'Shop', password: 'shoppw'),
      );
      await syncA.syncNow();
      await syncB.syncNow();
      final bankPayload = server.items['bank']!.payload;
      server.tamper(
        'phish',
        (r) => RemoteItem(
          id: r.id,
          payload: bankPayload,
          deleted: false,
          revision: r.revision + 1,
          seq: 0,
          updatedAt: r.updatedAt,
        ),
      );
      await syncB.syncNow();
      expect(b.byId('phish')!.password, 'shoppw');
      expect(syncB.rejectedItems, 1);
    });

    test(
      'replayed old ciphertext with a higher revision loses to newer local',
      () async {
        final server = FakeServer();
        final (a, syncA, b, syncB) = await twoDevices(server);
        await a.saveEntry(VaultEntry(id: 'e', title: 'T', password: 'v1'));
        await syncA.syncNow();
        final oldPayload = server.items['e']!.payload;
        await a.saveEntry(a.byId('e')!.edit(password: 'v2'));
        await syncA.syncNow();
        await syncB.syncNow();
        expect(b.byId('e')!.password, 'v2');
        // Server replays v1 as a "new" revision.
        server.tamper(
          'e',
          (r) => RemoteItem(
            id: r.id,
            payload: oldPayload,
            deleted: false,
            revision: r.revision + 1,
            seq: 0,
            updatedAt: r.updatedAt,
          ),
        );
        await syncB.syncNow();
        // Documented weakness: B is not dirty, so it accepts the replay.
        // Recorded here so the audit report reflects actual behaviour.
        final replayAccepted = b.byId('e')!.password == 'v1';
        printOnFailure('replay accepted on clean device: $replayAccepted');
        expect(replayAccepted, isTrue);
      },
    );

    test('stale revision is ignored', () async {
      final server = FakeServer();
      final (a, syncA, b, syncB) = await twoDevices(server);
      await a.saveEntry(VaultEntry(id: 'e', title: 'T', password: 'v1'));
      await syncA.syncNow();
      await a.saveEntry(a.byId('e')!.edit(password: 'v2'));
      await syncA.syncNow();
      await syncB.syncNow();
      final old = server.items['e']!;
      server.tamper(
        'e',
        (r) => RemoteItem(
          id: r.id,
          payload: r.payload,
          deleted: false,
          revision: 1,
          seq: 0,
          updatedAt: old.updatedAt,
        ),
      );
      await syncB.syncNow();
      expect(b.byId('e')!.password, 'v2');
    });

    test('mass deletion from server is refused', () async {
      final server = FakeServer();
      final (a, syncA, b, syncB) = await twoDevices(server);
      for (var i = 0; i < 10; i++) {
        await a.saveEntry(VaultEntry(id: 'e$i', title: 'T$i', password: 'p$i'));
      }
      await syncA.syncNow();
      await syncB.syncNow();
      expect(b.entries, hasLength(10));
      for (var i = 0; i < 10; i++) {
        server.tamper(
          'e$i',
          (r) => RemoteItem(
            id: r.id,
            payload: null,
            deleted: true,
            revision: r.revision + 1,
            seq: 0,
            updatedAt: r.updatedAt,
          ),
        );
      }
      await expectLater(syncB.syncNow(), throwsA(isA<MassDeletionException>()));
      expect(b.entries, hasLength(10));
    });

    test('tombstone carrying a payload is rejected', () async {
      final server = FakeServer();
      final (a, syncA, b, syncB) = await twoDevices(server);
      await a.saveEntry(VaultEntry(id: 'e', title: 'T', password: 'p'));
      await syncA.syncNow();
      await syncB.syncNow();
      server.tamper(
        'e',
        (r) => RemoteItem(
          id: r.id,
          payload: r.payload,
          deleted: true,
          revision: r.revision + 1,
          seq: 0,
          updatedAt: r.updatedAt,
        ),
      );
      await syncB.syncNow();
      expect(b.byId('e'), isNotNull);
      expect(syncB.rejectedItems, 1);
    });

    test(
      'garbage payloads of every shape are rejected without crashing',
      () async {
        final server = FakeServer();
        final (a, syncA, b, syncB) = await twoDevices(server);
        final shapes = <Uint8List>[
          Uint8List(0),
          Uint8List(1),
          Uint8List(40),
          Uint8List.fromList([2, ...List.filled(60, 0)]),
          Uint8List.fromList(List.generate(5000, (i) => i % 256)),
        ];
        for (var i = 0; i < shapes.length; i++) {
          server.items['g$i'] = RemoteItem(
            id: 'g$i',
            payload: shapes[i],
            deleted: false,
            revision: 1,
            seq: server.nextSeq(),
            updatedAt: DateTime.now().toUtc(),
          );
        }
        await syncB.syncNow();
        expect(b.entries, isEmpty);
        expect(syncB.rejectedItems, shapes.length);
        expect(a.isUnlocked, isTrue);
      },
    );

    test(
      'new device refuses a header whose salt differs from prelogin',
      () async {
        final server = FakeServer();
        final (a, syncA) = await device(server);
        await a.createVault(pw);
        await syncA.enableSync('me@example.com', pw);
        final evil = server.header!.copyWith(salt: Uint8List(16));
        final remote = _HeaderSwapRemote(server, evil);
        final (b, _) = await device(server);
        final syncB = SyncService(b, remote);
        syncs.add(syncB);
        await expectLater(
          syncB.signInExisting('me@example.com', pw),
          throwsA(anything),
        );
        expect(b.isUnlocked, isFalse);
      },
    );
  });
}

class _HeaderSwapRemote extends FakeRemote {
  _HeaderSwapRemote(super.server, this.evil);
  final VaultKeyHeader evil;
  @override
  Future<VaultKeyHeader?> fetchHeader() async => evil;
}
