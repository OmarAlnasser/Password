// Known-answer tests for the libsodium primitives VaultSnap relies on.
// These prove the bundled libsodium build and its Dart bindings compute the
// standard algorithms, independently of VaultSnap's own format.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:vaultsnap/core/crypto/crypto.dart';

import 'test_helpers.dart';

void main() {
  late SodiumSumo sodium;
  late VaultCrypto crypto;

  setUpAll(() async {
    sodium = await loadSodium();
    crypto = VaultCrypto(sodium);
  });

  group('XChaCha20-Poly1305-IETF', () {
    // libsodium test/default/aead_xchacha20poly1305.c + .exp
    final key = hex(
      '808182838485868788898a8b8c8d8e8f'
      '909192939495969798999a9b9c9d9e9f',
    );
    final nonce = hex(
      '070000004041424344454647'
      '48494a4b4c4d4e4f50515253',
    );
    final ad = hex('50515253c0c1c2c3c4c5c6c7');
    final message = utf8.encode(
      "Ladies and Gentlemen of the class of '99: If I could offer you only "
      'one tip for the future, sunscreen would be it.',
    );
    const expected =
        'f8ebea4875044066fc162a0604e171feecfb3d20425248563bcfd5a155dcc47b'
        'bda70b86e5ab9b55002bd1274c02db35321acd7af8b2e2d25015e136b7679458'
        'e9f43243bf719d639badb5feac03f80a19a96ef10cb1d15333a837b90946ba38'
        '54ee74da3f2585efc7e1e170e17e15e563e77601f4f85cafa8e5877614e143e6'
        '8420';

    test('encrypts libsodium known-answer vector', () {
      final k = sodium.secureCopy(key);
      final ct = sodium.crypto.aeadXChaCha20Poly1305IETF.encrypt(
        message: Uint8List.fromList(message),
        nonce: nonce,
        key: k,
        additionalData: ad,
      );
      expect(toHex(ct), expected);
      k.dispose();
    });

    test('decrypts known-answer vector and rejects a flipped tag bit', () {
      final k = sodium.secureCopy(key);
      final aead = sodium.crypto.aeadXChaCha20Poly1305IETF;
      final ct = hex(expected);
      expect(
        aead.decrypt(cipherText: ct, nonce: nonce, key: k, additionalData: ad),
        message,
      );
      ct[ct.length - 1] ^= 0x01;
      expect(
        () => aead.decrypt(
          cipherText: ct,
          nonce: nonce,
          key: k,
          additionalData: ad,
        ),
        throwsA(isA<SodiumException>()),
      );
      k.dispose();
    });
  });

  group('crypto_kdf (BLAKE2b)', () {
    // libsodium test/default/kdf.c + .exp: master key 00..1f, ctx "KDF test".
    const expected64 = {
      0:
          'a0c724404728c8bb95e5433eb6a9716171144d61efb23e74b873fcbeda51d807'
          '1b5d70aae12066dfc94ce943f145aa176c055040c3dd73b0a15e36254d450614',
      1:
          '02507f144fa9bf19010bf7c70b235b4c2663cc00e074f929602a5e2c10a78075'
          '7d2a3993d06debc378a90efdac196dd841817b977d67b786804f6d3cd585bab5',
      7:
          '15d44b4b44ffa006eeceeb508c98a970aaa573d65905687b9e15854dec6d49c6'
          '12757e149f78268f727660dedf9abce22a9691feb20a01b0525f4b47a3cf19db',
    };

    for (final MapEntry(key: id, value: want) in expected64.entries) {
      test('subkey #$id matches libsodium vector', () {
        final master = sodium.secureCopy(
          Uint8List.fromList(List.generate(32, (i) => i)),
        );
        final sub = crypto.deriveSubkey(
          master,
          'KDF test',
          subkeyId: id,
          length: 64,
        );
        expect(keyHex(sub), want);
        master.dispose();
        sub.dispose();
      });
    }

    test('VaultSnap contexts match hashlib.blake2b', () {
      // Computed with Python hashlib.blake2b(key=0x42*32, salt=LE64(id),
      // person=ctx, digest_size=32) - see tool/gen_crypto_vectors.py.
      const expected = {
        VaultCrypto.ctxKeyEncryption:
            '4ad6c2c1f4de6fcc550a635bcbe29ad777ed82ef768525fe09c1ecf00d3ad993',
        VaultCrypto.ctxServerAuth:
            '6512eab73b6124c10543b99f81a74bcf1020296f3dc0f82832b0ebc62b56eaee',
        VaultCrypto.ctxEntry:
            '820d0d8294da84eb0b0cedfced5766898c293ec942cb46cfcda73fadcc8572d8',
        VaultCrypto.ctxDatabase:
            'fa80b855fdffde75eafef6fe1101cd3d6b4c63ac49066dd0f0e839b96cfef0d4',
        VaultCrypto.ctxRecovery:
            '15deddf287e9173e09c4c1567505233ddee81742ea6ca37af09b9b7e2b318f81',
      };
      final master = sodium.secureCopy(Uint8List(32)..fillRange(0, 32, 0x42));
      for (final MapEntry(key: ctx, value: want) in expected.entries) {
        final sub = crypto.deriveSubkey(master, ctx);
        expect(keyHex(sub), want, reason: ctx);
        sub.dispose();
      }
      master.dispose();
    });
  });

  group('Argon2id (crypto_pwhash)', () {
    // Expected values from argon2-cffi, i.e. the PHC reference
    // implementation, with VaultSnap's parameters: t=3, m=64 MiB, p=1, 32 B.
    test('ASCII password', () {
      final key = crypto.deriveMasterKey(
        passwordUtf8: Uint8List.fromList(
          utf8.encode('correct horse battery staple'),
        ),
        salt: hex('000102030405060708090a0b0c0d0e0f'),
        params: KdfParams.recommended,
      );
      expect(
        keyHex(key),
        '0d1a3c6523c8f06e4e0af9c515aa5b5448cfebd6838f2d52c3d8b6ef8ddc3c2e',
      );
      key.dispose();
    });

    test('mixed Latin/Arabic password', () {
      final key = crypto.deriveMasterKey(
        passwordUtf8: VaultCrypto.passwordBytes('P@ssw0rdمرحبا'),
        salt: Uint8List(16)..fillRange(0, 16, 0xa5),
        params: KdfParams.recommended,
      );
      expect(
        keyHex(key),
        'a8236ae94381082e7897a75ca643fcb0a0e83906a286725d5c12535d06e115e8',
      );
      key.dispose();
    });

    test('background isolate gives the same key', () async {
      final key = await crypto.deriveMasterKeyInBackground(
        passwordUtf8: Uint8List.fromList(
          utf8.encode('correct horse battery staple'),
        ),
        salt: hex('000102030405060708090a0b0c0d0e0f'),
        params: KdfParams.recommended,
      );
      expect(
        keyHex(key),
        '0d1a3c6523c8f06e4e0af9c515aa5b5448cfebd6838f2d52c3d8b6ef8ddc3c2e',
      );
      key.dispose();
    });

    test('refuses parameters below the floor (downgrade protection)', () {
      for (final weak in const [
        KdfParams(version: 1, opsLimit: 1, memLimitBytes: 64 << 20),
        KdfParams(version: 1, opsLimit: 3, memLimitBytes: 8 << 20),
        KdfParams(version: 2, opsLimit: 3, memLimitBytes: 64 << 20),
      ]) {
        expect(
          () => crypto.deriveMasterKey(
            passwordUtf8: Uint8List.fromList([1, 2, 3]),
            salt: Uint8List(16),
            params: weak,
          ),
          throwsA(isA<WeakKdfParamsException>()),
        );
      }
      expect(
        () => KdfParams.fromJson({'v': 1, 'ops': 1, 'mem': 65536}),
        throwsA(isA<WeakKdfParamsException>()),
      );
    });

    test('rejects a salt of the wrong length', () {
      expect(
        () => crypto.deriveMasterKey(
          passwordUtf8: Uint8List.fromList([1]),
          salt: Uint8List(8),
          params: KdfParams.recommended,
        ),
        throwsA(isA<WeakKdfParamsException>()),
      );
    });
  });

  group('password normalisation', () {
    test('Arabic presentation forms normalise to base letters (NFKC)', () {
      const presentation = 'ﻣﺮﺣﺒﺎ';
      const base = 'مرحبا';
      expect(
        VaultCrypto.passwordBytes(presentation),
        VaultCrypto.passwordBytes(base),
      );
    });

    test('composed and decomposed accents give the same bytes', () {
      expect(
        VaultCrypto.passwordBytes('café'),
        VaultCrypto.passwordBytes('café'),
      );
    });
  });
}
