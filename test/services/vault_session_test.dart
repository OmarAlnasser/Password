import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultsnap/core/crypto/crypto.dart';
import 'package:vaultsnap/data/models/vault_entry.dart';
import 'package:vaultsnap/services/unlock_throttle.dart';
import 'package:vaultsnap/services/vault_session.dart';

void main() {
  late VaultCrypto crypto;
  late Directory dir;

  setUpAll(() async => crypto = VaultCrypto(await loadSodium()));
  setUp(() => dir = Directory.systemTemp.createTempSync('vs_session'));
  tearDown(() => dir.deleteSync(recursive: true));

  VaultSession newSession() => VaultSession(
    crypto: crypto,
    directory: dir,
    throttle: UnlockThrottle(File('${dir.path}/throttle.json')),
  );

  test('create, add, lock, unlock persists entries encrypted', () async {
    final s = newSession();
    await s.init();
    expect(s.state, VaultState.noVault);
    final signup = await s.createVault('correct horse battery staple 9');
    expect(signup.recoveryKeyText, isNotEmpty);
    expect(s.state, VaultState.unlocked);

    await s.saveEntry(
      VaultEntry(
        id: 'e1',
        title: 'Bank',
        username: 'alice@example.com',
        password: 'MARKER-hunter2-MARKER',
        tags: ['finance'],
      ),
    );
    await s.lock();
    expect(s.state, VaultState.locked);
    expect(s.entries, isEmpty);
    expect(() => s.keyring, throwsStateError);

    // Nothing readable on disk.
    for (final f in dir.listSync().whereType<File>()) {
      final bytes = f.readAsBytesSync();
      final text = String.fromCharCodes(bytes);
      expect(text.contains('MARKER'), isFalse, reason: f.path);
      expect(text.contains('alice@example.com'), isFalse, reason: f.path);
    }

    final s2 = newSession();
    await s2.init();
    expect(s2.state, VaultState.locked);
    await s2.unlockWithPassword('correct horse battery staple 9');
    expect(s2.entries.single.password, 'MARKER-hunter2-MARKER');
    expect(s2.allTags, {'finance'});
    await s2.lock();

    await s2.unlockWithRecoveryKey(signup.recoveryKeyText);
    expect(s2.entries.single.title, 'Bank');
    await s2.lock();
  });

  test('delete leaves a tombstone row', () async {
    final s = newSession();
    await s.init();
    await s.createVault('pw pw pw pw pw pw');
    await s.saveEntry(VaultEntry(id: 'x', title: 'X'));
    await s.deleteEntry('x');
    expect(s.entries, isEmpty);
    final row = await s.db.item('x');
    expect(row!.deleted, isTrue);
    expect(row.payload, isNull);
    expect(row.dirty, isTrue);
    await s.lock();
  });

  test('wrong password increments throttle and then blocks', () async {
    final s = newSession();
    await s.init();
    await s.createVault('right password here');
    await s.lock();
    for (var i = 0; i < UnlockThrottle.freeAttempts; i++) {
      await expectLater(
        s.unlockWithPassword('wrong'),
        throwsA(isA<WrongCredentialsException>()),
      );
    }
    // 4th attempt is immediately throttled (1s delay), even with the right pw.
    await expectLater(
      s.unlockWithPassword('right password here'),
      throwsA(isA<UnlockThrottledException>()),
    );
    expect(s.state, VaultState.locked);
  });

  test('change password requires the current password', () async {
    final s = newSession();
    await s.init();
    await s.createVault('old password 123');
    await expectLater(
      s.changePassword('not it', 'new password 456'),
      throwsA(isA<WrongCredentialsException>()),
    );
    await s.changePassword('old password 123', 'new password 456');
    await s.lock();
    await s.unlockWithPassword('new password 456');
    expect(s.isUnlocked, isTrue);
    await s.lock();
  });

  test('entry with tampered ciphertext is skipped, not fatal', () async {
    final s = newSession();
    await s.init();
    await s.createVault('pw pw pw pw pw pw');
    await s.saveEntry(VaultEntry(id: 'a', title: 'A'));
    await s.saveEntry(VaultEntry(id: 'b', title: 'B'));
    final row = (await s.db.item('a'))!;
    final bad = row.payload!..[40] ^= 1;
    await s.db.upsert(row.copyWith(payload: Value(bad)).toCompanion(true));
    await s.lock();
    await s.unlockWithPassword('pw pw pw pw pw pw');
    expect(s.entries.map((e) => e.id), ['b']);
    await s.lock();
  });
}
