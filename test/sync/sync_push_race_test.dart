import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/core/crypto/crypto.dart';
import 'package:hisn/data/models/vault_entry.dart';
import 'package:hisn/services/sync/remote_store.dart';
import 'package:hisn/services/sync/sync_service.dart';
import 'package:hisn/services/unlock_throttle.dart';
import 'package:hisn/services/vault_session.dart';

import 'fake_remote.dart';

const pw = 'violet-harbor-test-71-lantern';

/// A server whose first push waits until the test opens [gate], so the test
/// can change the vault while that push is on the network.
class _GatedRemote extends FakeRemote {
  _GatedRemote(super.server);

  Completer<void>? gate;
  final reached = Completer<void>();

  @override
  Future<PushResult> push({
    required String id,
    required Uint8List? payload,
    required bool deleted,
    required int baseRevision,
  }) async {
    final g = gate;
    if (g != null) {
      if (!reached.isCompleted) reached.complete();
      await g.future;
    }
    return super.push(
      id: id,
      payload: payload,
      deleted: deleted,
      baseRevision: baseRevision,
    );
  }
}

/// Edits and deletes saved while a push is in flight must survive it: the
/// push used to mark the row clean with the copy it had read before, which
/// silently undid the newer change.
void main() {
  late VaultCrypto crypto;
  late Directory dir;
  late VaultSession session;
  late _GatedRemote remote;
  late SyncService sync;
  late FakeServer server;

  setUpAll(() async => crypto = VaultCrypto(await loadSodium()));

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vs_push_race');
    session = VaultSession(
      crypto: crypto,
      directory: dir,
      throttle: UnlockThrottle(File('${dir.path}/t.json')),
    );
    await session.init();
    await session.createVault(pw);
    server = FakeServer();
    remote = _GatedRemote(server);
    sync = SyncService(session, remote);
    await sync.enableSync('me@example.test', pw);
  });

  tearDown(() async {
    sync.dispose();
    await sync.idle;
    await session.lock();
    dir.deleteSync(recursive: true);
  });

  /// The pass started by [pushInFlight].
  late Future<void> pass;

  /// Starts a pass and waits until its first push is on the network.
  Future<void> pushInFlight() async {
    remote.gate = Completer<void>();
    pass = sync.syncNow();
    await remote.reached.future;
  }

  /// Lets the push through, then lets a follow-up pass run.
  Future<void> finish() async {
    remote.gate!.complete();
    remote.gate = null;
    await pass;
    await sync.idle;
    await sync.syncNow();
  }

  List<String> ids() => session.entries.map((e) => e.id).toList()..sort();

  test('a bulk delete made during a push is kept and pushed', () async {
    for (var i = 0; i < 6; i++) {
      await session.saveEntry(
        VaultEntry(id: 'e$i', title: 'Dup $i', password: 'hunter-test-$i'),
      );
    }
    await pushInFlight();
    expect(await session.deleteEntries(['e0', 'e1', 'e2']), 3);
    await finish();

    expect(ids(), ['e3', 'e4', 'e5']);
    final onServer = server.items.values.where((i) => i.deleted);
    expect(onServer.map((i) => i.id).toSet(), {'e0', 'e1', 'e2'});
    expect(await session.db.dirtyItems(), isEmpty);
    // A fresh read of the database agrees.
    await session.reloadFromDatabase();
    expect(ids(), ['e3', 'e4', 'e5']);
  });

  test('an edit made during a push is kept and pushed', () async {
    for (var i = 0; i < 3; i++) {
      await session.saveEntry(
        VaultEntry(id: 'e$i', title: 'Site $i', password: 'hunter-test-old-$i'),
      );
    }
    await pushInFlight();
    await session.saveEntry(
      session.byId('e1')!.edit(password: 'hunter-test-new-1'),
    );
    await finish();

    await session.reloadFromDatabase();
    expect(session.byId('e1')!.password, 'hunter-test-new-1');
    expect(await session.db.dirtyItems(), isEmpty);
    final pushed = session.decryptBlob('e1', server.items['e1']!.payload!);
    expect(pushed!.password, 'hunter-test-new-1');
  });

  test('a row pushed unchanged is marked clean on the new revision', () async {
    await session.saveEntry(
      VaultEntry(id: 'e0', title: 'Site', password: 'hunter-test-0'),
    );
    await sync.syncNow();
    final row = await session.db.item('e0');
    expect(row!.dirty, isFalse);
    expect(row.revision, server.items['e0']!.revision);
  });
}
