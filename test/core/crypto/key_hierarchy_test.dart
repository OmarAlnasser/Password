import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:hisn/core/crypto/crypto.dart';

import 'golden_vectors.dart';
import 'test_helpers.dart';

void main() {
  late SodiumSumo sodium;
  late VaultCrypto crypto;
  late AccountKeys accounts;

  setUpAll(() async {
    sodium = await loadSodium();
    crypto = VaultCrypto(sodium);
    accounts = AccountKeys(crypto);
  });

  VaultKeyHeader goldenHeader() => VaultKeyHeader(
    kdf: KdfParams.recommended,
    salt: hex(goldenSaltHex),
    vaultKeyByPassword: base64.decode(goldenVkByPassword),
    vaultKeyByRecovery: base64.decode(goldenVkByRecovery),
  );

  group('golden vault (independent Python implementation)', () {
    test('password normalises to the expected bytes', () {
      expect(
        toHex(VaultCrypto.passwordBytes(goldenPassword)),
        goldenPasswordNfkcHex,
      );
    });

    test('master key, KEK and auth secret match', () async {
      final master = crypto.deriveMasterKey(
        passwordUtf8: VaultCrypto.passwordBytes(goldenPassword),
        salt: hex(goldenSaltHex),
        params: KdfParams.recommended,
      );
      expect(keyHex(master), goldenMasterKeyHex);
      master.dispose();

      final keys = await accounts.derivePasswordKeys(
        password: goldenPassword,
        salt: hex(goldenSaltHex),
        params: KdfParams.recommended,
        inBackground: false,
      );
      expect(keyHex(keys.kek), goldenKekHex);
      expect(crypto.serverAuthSecret(keys.authKey), goldenAuthSecret);
      keys.dispose();
    });

    test('unlocks with the password and decrypts the golden entry', () async {
      final keyring = await accounts.unlockWithPassword(
        goldenPassword,
        goldenHeader(),
      );
      expect(keyHex(keyring.vaultKey), goldenVaultKeyHex);
      expect(keyHex(keyring.entryKey), goldenEntryKeyHex);
      expect(keyHex(keyring.databaseKey), goldenDbKeyHex);
      final pt = crypto.decryptEntry(
        envelope: base64.decode(goldenEntryEnvelope),
        entryKey: keyring.entryKey,
        entryId: goldenEntryId,
      );
      expect(toHex(pt), goldenEntryPlaintextHex);
      keyring.lock();
    });

    test('unlocks with the recovery key, tolerating case and look-alikes', () {
      for (final text in [
        goldenRecoveryText,
        goldenRecoveryText.toLowerCase(),
        goldenRecoveryText.replaceAll('-', ' ').replaceAll('0', 'O'),
        goldenRecoveryText.replaceAll('-', '').replaceAll('1', 'l'),
      ]) {
        final keyring = accounts.unlockWithRecoveryKey(text, goldenHeader());
        expect(keyHex(keyring.vaultKey), goldenVaultKeyHex);
        keyring.lock();
      }
    });

    test('recovery auth secret matches', () {
      final rk = RecoveryKey.parse(sodium, goldenRecoveryText);
      expect(accounts.recoveryAuthSecret(rk), goldenRecoveryAuthSecret);
      rk.dispose();
    });
  });

  group('account lifecycle', () {
    test(
      'signup -> lock -> unlock with password and with recovery key',
      () async {
        const password = 'Tr0ub4dor & كلمة سر طويلة';
        final signup = await accounts.createAccount(password);
        final header = VaultKeyHeader.fromJson(
          jsonDecode(jsonEncode(signup.header.toJson()))
              as Map<String, Object?>,
        );
        final entry = crypto.encryptEntry(
          plaintext: Uint8List.fromList(utf8.encode('{"title":"x"}')),
          entryKey: signup.keyring.entryKey,
          entryId: 'e1',
        );
        final vaultKeyHex = keyHex(signup.keyring.vaultKey);
        signup.keyring.lock();

        final byPassword = await accounts.unlockWithPassword(password, header);
        expect(keyHex(byPassword.vaultKey), vaultKeyHex);
        expect(
          utf8.decode(
            crypto.decryptEntry(
              envelope: entry,
              entryKey: byPassword.entryKey,
              entryId: 'e1',
            ),
          ),
          '{"title":"x"}',
        );
        byPassword.lock();

        final byRecovery = accounts.unlockWithRecoveryKey(
          signup.recoveryKeyText,
          header,
        );
        expect(keyHex(byRecovery.vaultKey), vaultKeyHex);
        byRecovery.lock();
      },
    );

    test('recovery key text is 11 groups of 5 Crockford chars', () async {
      final signup = await accounts.createAccount('x' * 12);
      expect(
        signup.recoveryKeyText,
        matches(RegExp(r'^([0-9A-HJKMNP-TV-Z]{5}-){10}[0-9A-HJKMNP-TV-Z]{5}$')),
      );
      signup.keyring.lock();
    });

    test('two signups with the same password share nothing', () async {
      final a = await accounts.createAccount('same password');
      final b = await accounts.createAccount('same password');
      expect(a.header.salt, isNot(b.header.salt));
      expect(a.serverAuthSecret, isNot(b.serverAuthSecret));
      expect(keyHex(a.keyring.vaultKey), isNot(keyHex(b.keyring.vaultKey)));
      a.keyring.lock();
      b.keyring.lock();
    });

    test('auth secret is unrelated to the key-encryption key', () async {
      final keys = await accounts.derivePasswordKeys(
        password: 'pw',
        salt: Uint8List(16),
        params: KdfParams.recommended,
      );
      final authHex = toHex(
        base64Url.decode('${crypto.serverAuthSecret(keys.authKey)}='),
      );
      expect(authHex, isNot(keyHex(keys.kek)));
      keys.dispose();
    });

    test('wrong password fails with WrongCredentialsException', () async {
      expect(
        () => accounts.unlockWithPassword('wrong', goldenHeader()),
        throwsA(isA<WrongCredentialsException>()),
      );
    });

    test(
      'a tampered wrapped key is indistinguishable from a wrong password',
      () async {
        final header = goldenHeader();
        header.vaultKeyByPassword[30] ^= 1;
        expect(
          () => accounts.unlockWithPassword(goldenPassword, header),
          throwsA(isA<WrongCredentialsException>()),
        );
      },
    );

    test('valid but wrong recovery key is rejected', () {
      final other = RecoveryKey.generate(sodium);
      final text = other.format(sodium);
      other.dispose();
      expect(
        () => accounts.unlockWithRecoveryKey(text, goldenHeader()),
        throwsA(isA<WrongCredentialsException>()),
      );
    });

    test(
      'change password keeps the vault key and invalidates the old one',
      () async {
        final keyring = await accounts.unlockWithPassword(
          goldenPassword,
          goldenHeader(),
        );
        final (newHeader, newAuth) = await accounts.changePassword(
          keyring: keyring,
          header: goldenHeader(),
          newPassword: 'a brand new passphrase',
        );
        keyring.lock();

        expect(newHeader.salt, isNot(hex(goldenSaltHex)));
        expect(newAuth, isNot(goldenAuthSecret));
        expect(newHeader.vaultKeyByRecovery, goldenHeader().vaultKeyByRecovery);
        final again = await accounts.unlockWithPassword(
          'a brand new passphrase',
          newHeader,
        );
        expect(keyHex(again.vaultKey), goldenVaultKeyHex);
        again.lock();
        expect(
          () => accounts.unlockWithPassword(goldenPassword, newHeader),
          throwsA(isA<WrongCredentialsException>()),
        );
      },
    );

    test('rotating the recovery key invalidates the old one', () async {
      final keyring = accounts.unlockWithRecoveryKey(
        goldenRecoveryText,
        goldenHeader(),
      );
      final rotated = accounts.rotateRecoveryKey(
        keyring: keyring,
        header: goldenHeader(),
      );
      keyring.lock();
      expect(
        () =>
            accounts.unlockWithRecoveryKey(goldenRecoveryText, rotated.header),
        throwsA(isA<WrongCredentialsException>()),
      );
      final ok = accounts.unlockWithRecoveryKey(
        rotated.recoveryKeyText,
        rotated.header,
      );
      expect(keyHex(ok.vaultKey), goldenVaultKeyHex);
      ok.lock();
    });
  });

  group('lock', () {
    test('all keys become unusable after lock', () async {
      final keyring = await accounts.unlockWithPassword(
        goldenPassword,
        goldenHeader(),
      );
      keyring.lock();
      expect(keyring.isLocked, isTrue);
      expect(() => keyring.vaultKey, throwsStateError);
      expect(() => keyring.entryKey, throwsStateError);
      expect(() => keyring.databaseKey, throwsStateError);
      // lock() also calls sodium_free on each key, which zeroes and unmaps
      // the guarded pages. A leaked SecureKey reference read after that
      // crashes the process (by design), so it cannot be asserted here.
      keyring.lock(); // idempotent
    });
  });

  test('header JSON rejects weak server-supplied KDF params', () {
    final json = goldenHeader().toJson()
      ..['kdf'] = {'v': 1, 'ops': 1, 'mem': 1 << 20};
    expect(
      () => VaultKeyHeader.fromJson(json),
      throwsA(isA<WeakKdfParamsException>()),
    );
  });
}
