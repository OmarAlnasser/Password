// AUDIT attack tests. Each test asserts the SECURE behaviour; a failing
// test is a finding (IDs refer to docs/SECURITY_AUDIT.md). Tagged so the
// regular suite can run without them: flutter test --exclude-tags finding
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultsnap/core/crypto/crypto.dart';
import 'package:vaultsnap/data/models/vault_entry.dart';
import 'package:vaultsnap/services/import_export.dart';
import 'package:vaultsnap/services/password_generator.dart';
import 'package:vaultsnap/services/sync/remote_store.dart';
import 'package:vaultsnap/services/sync/sync_service.dart';
import 'package:vaultsnap/services/unlock_throttle.dart';
import 'package:vaultsnap/services/vault_session.dart';

import '../sync/fake_remote.dart';

const pw = 'violet-harbor-quantum-71-lantern';

void main() {
  late VaultCrypto crypto;
  final dirs = <Directory>[];
  final sessions = <VaultSession>[];
  final syncs = <SyncService>[];
  setUpAll(() async => crypto = VaultCrypto(await loadSodium()));
  tearDown(() async {
    // Cancel debounced background syncs and close the databases before the
    // directories go away (see test/sync/sync_test.dart).
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
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    dirs.clear();
  });

  Future<VaultSession> newSession() async {
    final dir = Directory.systemTemp.createTempSync('audit');
    dirs.add(dir);
    final s = VaultSession(
      crypto: crypto,
      directory: dir,
      throttle: UnlockThrottle(File('${dir.path}/throttle.json')),
    );
    await s.init();
    sessions.add(s);
    return s;
  }

  // ===================================================================
  group('brute-force unlock', () {
    test('Argon2id cost per guess is measurable (parameters applied)', () async {
      final sw = Stopwatch()..start();
      const n = 3;
      for (var i = 0; i < n; i++) {
        crypto
            .deriveMasterKey(
              passwordUtf8: Uint8List.fromList(utf8.encode('guess$i')),
              salt: Uint8List(16),
              params: KdfParams.recommended,
            )
            .dispose();
      }
      final perGuess = sw.elapsedMilliseconds / n;
      // ignore: avoid_print
      print(
        'AUDIT argon2id per guess: ${perGuess.toStringAsFixed(0)} ms '
        '(~${(1000 / perGuess).toStringAsFixed(1)} guesses/s/core, 64 MiB each)',
      );
      // Sanity check that the 64 MiB / t=3 parameters are really applied.
      expect(perGuess, greaterThan(50));
    });

    test('online guessing is throttled after 3 failures', () async {
      final s = await newSession();
      await s.createVault(pw);
      await s.lock();
      var throttled = 0;
      for (var i = 0; i < 6; i++) {
        try {
          await s.unlockWithPassword('wrong$i');
        } on UnlockThrottledException {
          throttled++;
        } on WrongCredentialsException {
          // counted
        }
      }
      expect(throttled, greaterThan(0));
    });

    test('recovery-key guessing shares the same throttle', () async {
      final s = await newSession();
      await s.createVault(pw);
      await s.lock();
      final fake = RecoveryKey.generate(crypto.sodium);
      final text = fake.format(crypto.sodium);
      fake.dispose();
      for (var i = 0; i < 3; i++) {
        await expectLater(
          s.unlockWithRecoveryKey(text),
          throwsA(isA<WrongCredentialsException>()),
        );
      }
      await expectLater(
        s.unlockWithRecoveryKey(text),
        throwsA(isA<UnlockThrottledException>()),
      );
    });

    test(
      'FINDING L-1: deleting throttle.json must not reset the back-off',
      tags: ['finding'],
      () async {
        final s = await newSession();
        await s.createVault(pw);
        await s.lock();
        for (var i = 0; i < 6; i++) {
          try {
            await s.unlockWithPassword('wrong');
          } on Object {
            // ignore
          }
        }
        File('${s.directory.path}/throttle.json').deleteSync();
        final s2 = VaultSession(
          crypto: crypto,
          directory: s.directory,
          throttle: UnlockThrottle(File('${s.directory.path}/throttle.json')),
        );
        await s2.init();
        expect(s2.throttle.remaining, greaterThan(Duration.zero));
      },
    );
  });

  // ===================================================================
  group('KDF parameter abuse', () {
    test(
      'FINDING M-3: absurd KDF parameters from server/file are rejected',
      tags: ['finding'],
      () {
        for (final j in [
          {'v': 1, 'ops': 1 << 30, 'mem': 64 << 20}, // hours of CPU
          {'v': 1, 'ops': 3, 'mem': 1 << 42}, // 4 TiB of RAM
        ]) {
          expect(
            () => KdfParams.fromJson(j),
            throwsA(isA<WeakKdfParamsException>()),
            reason: '$j',
          );
        }
      },
    );
  });

  // ===================================================================
  group('strength meter denial of service', () {
    test(
      'FINDING M-4: strength check of a 256-char password finishes in < 10 s',
      tags: ['finding'],
      () async {
        final done = ReceivePort();
        final iso = await Isolate.spawn((SendPort p) {
          final s = List.generate(
            256,
            (i) => String.fromCharCode(33 + (i * 7919) % 90),
          ).join();
          StrengthMeter().evaluate(s);
          p.send(true);
        }, done.sendPort);
        final finished = await done.first.timeout(
          const Duration(seconds: 10),
          onTimeout: () => false,
        );
        iso.kill(priority: Isolate.immediate);
        done.close();
        expect(finished, isTrue, reason: 'zxcvbn still running after 10 s');
      },
    );
  });

  // ===================================================================
  group('malformed imports', () {
    late ImportExport ie;
    setUpAll(() => ie = ImportExport(crypto));

    test('2000 random CSV inputs never crash (only ImportException)', () {
      final rnd = Random(42);
      const alphabet = 'ab,"\n\r;\t\u0000\u202E\uFEFFpassword,username';
      for (var i = 0; i < 2000; i++) {
        final len = rnd.nextInt(400);
        final s = String.fromCharCodes(
          List.generate(
            len,
            (_) => alphabet.codeUnitAt(rnd.nextInt(alphabet.length)),
          ),
        );
        final input = i.isEven ? 'name,url,username,password,note\n$s' : s;
        try {
          ie.importCsv(input);
        } on ImportException {
          // fine
        }
      }
    });

    test(
      'CSV: control and bidi characters are stripped, javascript: dropped',
      () {
        final r = ie.importCsv(
          'name,url,username,password,note\n'
          '"Pay\u202Epal",javascript:alert(1),"bob\u0000",pw,"a\u2066b"\n',
        );
        final e = r.entries.single;
        expect(e.title, 'Paypal');
        expect(e.username, 'bob');
        expect(e.url, '');
        expect(e.notes, 'ab');
      },
    );

    test('CSV: 100k columns / 50k rows does not hang', () {
      final wide =
          'name,url,username,password,note\n${List.filled(100000, 'x').join(',')}\n';
      expect(ie.importCsv(wide).entries, hasLength(1));
      final tall = StringBuffer('name,url,username,password,note\n');
      for (var i = 0; i < 50000; i++) {
        tall.writeln('n$i,https://x$i.com,u$i,p$i,');
      }
      expect(ie.importCsv(tall.toString()).entries, hasLength(50000));
    });

    test(
      'encrypted import: truncated, bit-flipped, wrong format, deep JSON',
      () async {
        final good = await ie.exportEncrypted([
          VaultEntry(id: '1', title: 't'),
        ], 'pw');
        final j = jsonDecode(good) as Map<String, dynamic>;
        final data = base64.decode(j['data'] as String);
        final cases = <String>[
          good.substring(0, good.length ~/ 2),
          jsonEncode({
            ...j,
            'data': base64.encode(Uint8List.fromList(data)..[40] ^= 1),
          }),
          jsonEncode({...j, 'format': 'other'}),
          jsonEncode({...j, 'salt': base64.encode(Uint8List(3))}),
          jsonEncode({
            ...j,
            'kdf': {'v': 1, 'ops': 1, 'mem': 8192},
          }),
          '${'[' * 100000}${']' * 100000}',
          'not json at all',
          '',
        ];
        for (final c in cases) {
          await expectLater(
            ie.importEncrypted(c, 'pw'),
            throwsA(isA<ImportException>()),
            reason: c.length > 60 ? c.substring(0, 60) : c,
          );
        }
      },
    );
  });

  // ===================================================================
  group('sync: server-side attacks', () {
    Future<(VaultSession, SyncService, VaultSession, SyncService)> two(
      FakeServer server,
    ) async {
      final a = await newSession();
      final syncA = SyncService(a, FakeRemote(server));
      syncs.add(syncA);
      await a.createVault(pw);
      await syncA.enableSync('me@example.com', pw);
      final b = await newSession();
      final syncB = SyncService(b, FakeRemote(server));
      syncs.add(syncB);
      await syncB.signInExisting('me@example.com', pw);
      return (a, syncA, b, syncB);
    }

    test(
      'FINDING H-2: server cannot forge a deletion (tombstones are unauthenticated)',
      tags: ['finding'],
      () async {
        final server = FakeServer();
        final (a, syncA, b, syncB) = await two(server);
        await a.saveEntry(VaultEntry(id: 'bank', title: 'Bank', password: 'p'));
        await syncA.syncNow();
        await syncB.syncNow();
        server.tamper(
          'bank',
          (r) => RemoteItem(
            id: r.id,
            payload: null,
            deleted: true,
            revision: r.revision + 1,
            seq: 0,
            updatedAt: r.updatedAt,
          ),
        );
        await syncB.syncNow();
        expect(
          b.byId('bank'),
          isNotNull,
          reason: 'forged tombstone was applied',
        );
      },
    );

    test(
      'FINDING H-2b: mass-deletion guard cannot be bypassed in small batches',
      tags: ['finding'],
      () async {
        final server = FakeServer();
        final (a, syncA, b, syncB) = await two(server);
        for (var i = 0; i < 12; i++) {
          await a.saveEntry(
            VaultEntry(id: 'e$i', title: 'T$i', password: 'p$i'),
          );
        }
        await syncA.syncNow();
        await syncB.syncNow();
        for (var round = 0; round < 3; round++) {
          for (var i = round * 4; i < round * 4 + 4; i++) {
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
          try {
            await syncB.syncNow();
          } on MassDeletionException {
            // guard fired
          }
        }
        expect(
          b.entries.length,
          greaterThan(6),
          reason: 'whole vault deleted in 3 rounds',
        );
      },
    );

    test(
      'FINDING M-1: replayed old ciphertext is rejected on a clean device',
      tags: ['finding'],
      () async {
        final server = FakeServer();
        final (a, syncA, b, syncB) = await two(server);
        await a.saveEntry(VaultEntry(id: 'e', title: 'T', password: 'v1'));
        await syncA.syncNow();
        final old = server.items['e']!.payload;
        await a.saveEntry(a.byId('e')!.edit(password: 'v2'));
        await syncA.syncNow();
        await syncB.syncNow();
        server.tamper(
          'e',
          (r) => RemoteItem(
            id: r.id,
            payload: old,
            deleted: false,
            revision: r.revision + 1,
            seq: 0,
            updatedAt: r.updatedAt,
          ),
        );
        await syncB.syncNow();
        expect(b.byId('e')!.password, 'v2');
      },
    );

    test(
      'FINDING H-1: more than 500 pending changes are all pulled',
      tags: ['finding'],
      () async {
        // Reproduces SupabaseRemoteStore.pullSince: postgrest-dart's
        // .order('seq') defaults to DESCENDING, so a page holds the newest
        // 500 rows and the cursor jumps past everything older.
        final server = FakeServer();
        final (a, syncA, _, _) = await two(server);
        for (var i = 0; i < 600; i++) {
          await a.saveEntry(
            VaultEntry(id: 'e$i', title: 'T$i', password: 'p$i'),
          );
        }
        await syncA.syncNow();
        final c = await newSession();
        final syncC = SyncService(c, _DescendingRemote(server));
        syncs.add(syncC);
        await syncC.signInExisting('me@example.com', pw);
        expect(
          c.entries.length,
          600,
          reason: 'pulled ${c.entries.length} of 600',
        );
      },
    );
  });
}

/// FakeRemote with the same ordering as the production Supabase query.
class _DescendingRemote extends FakeRemote {
  _DescendingRemote(super.server);
  @override
  Future<List<RemoteItem>> pullSince(int seq, {int limit = 500}) async {
    final l = server.items.values.where((i) => i.seq > seq).toList()
      ..sort((x, y) => y.seq.compareTo(x.seq)); // order=seq.desc
    return l.take(limit).toList();
  }
}
