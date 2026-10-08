import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:hisn/core/crypto/crypto.dart';

import 'test_helpers.dart';

void main() {
  late SodiumSumo sodium;
  late VaultCrypto crypto;
  late SecureKey key;

  setUpAll(() async {
    sodium = await loadSodium();
    crypto = VaultCrypto(sodium);
  });
  setUp(() => key = crypto.randomKey());
  tearDown(() => key.dispose());

  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

  group('envelope', () {
    test('round-trips', () {
      final env = crypto.seal(bytes('hello'), key, 'ctx');
      expect(env[0], VaultCrypto.formatVersion);
      expect(env.length, VaultCrypto.envelopeOverhead + 5);
      expect(utf8.decode(crypto.open(env, key, 'ctx')), 'hello');
    });

    test('uses a fresh random nonce every time', () {
      final nonces = <String>{};
      for (var i = 0; i < 200; i++) {
        final env = crypto.seal(bytes('same'), key, 'ctx');
        nonces.add(toHex(env.sublist(1, 1 + VaultCrypto.nonceBytes)));
      }
      expect(nonces, hasLength(200));
    });

    test('any single flipped bit is detected', () {
      final env = crypto.seal(bytes('secret value'), key, 'ctx');
      // Byte 0 is the version, which fails with a different error.
      for (var i = 1; i < env.length; i++) {
        final tampered = Uint8List.fromList(env)..[i] ^= 0x01;
        expect(
          () => crypto.open(tampered, key, 'ctx'),
          throwsA(isA<DecryptionFailedException>()),
          reason: 'byte $i',
        );
      }
    });

    test('unknown version is rejected', () {
      final env = crypto.seal(bytes('x'), key, 'ctx')..[0] = 2;
      expect(
        () => crypto.open(env, key, 'ctx'),
        throwsA(isA<UnsupportedFormatException>()),
      );
    });

    test('truncated input is rejected', () {
      final env = crypto.seal(bytes('x'), key, 'ctx');
      for (final len in [0, 1, 25, VaultCrypto.envelopeOverhead - 1]) {
        expect(
          () => crypto.open(Uint8List.sublistView(env, 0, len), key, 'ctx'),
          throwsA(isA<DecryptionFailedException>()),
        );
      }
    });

    test('wrong key or wrong context is rejected', () {
      final env = crypto.seal(bytes('x'), key, 'ctx');
      final other = crypto.randomKey();
      expect(
        () => crypto.open(env, other, 'ctx'),
        throwsA(isA<DecryptionFailedException>()),
      );
      expect(
        () => crypto.open(env, key, 'ctx2'),
        throwsA(isA<DecryptionFailedException>()),
      );
      other.dispose();
    });
  });

  group('entries', () {
    test('round-trip', () {
      final pt = bytes('{"title":"Bank","password":"hunter2"}');
      final env = crypto.encryptEntry(
        plaintext: pt,
        entryKey: key,
        entryId: 'a',
      );
      expect(
        crypto.decryptEntry(envelope: env, entryKey: key, entryId: 'a'),
        pt,
      );
    });

    test('ciphertext cannot be moved to another entry id', () {
      final env = crypto.encryptEntry(
        plaintext: bytes('{}'),
        entryKey: key,
        entryId: 'entry-1',
      );
      expect(
        () => crypto.decryptEntry(
          envelope: env,
          entryKey: key,
          entryId: 'entry-2',
        ),
        throwsA(isA<DecryptionFailedException>()),
      );
    });

    test('padding hides plaintext length within a 128-byte bucket', () {
      int size(int n) => crypto
          .encryptEntry(plaintext: Uint8List(n), entryKey: key, entryId: 'a')
          .length;
      expect(size(1), size(100));
      expect(size(0), VaultCrypto.envelopeOverhead + 128);
      expect(size(127), VaultCrypto.envelopeOverhead + 128);
      expect(size(128), VaultCrypto.envelopeOverhead + 256);
    });

    test('empty plaintext round-trips', () {
      final env = crypto.encryptEntry(
        plaintext: Uint8List(0),
        entryKey: key,
        entryId: 'a',
      );
      expect(
        crypto.decryptEntry(envelope: env, entryKey: key, entryId: 'a'),
        isEmpty,
      );
    });
  });

  group('key wrapping', () {
    test('round-trips', () {
      final inner = crypto.randomKey();
      final wrapped = crypto.wrapKey(
        keyToWrap: inner,
        wrappingKey: key,
        purpose: WrapPurpose.masterPassword,
      );
      final unwrapped = crypto.unwrapKey(
        wrapped: wrapped,
        wrappingKey: key,
        purpose: WrapPurpose.masterPassword,
      );
      expect(keyHex(unwrapped), keyHex(inner));
      inner.dispose();
      unwrapped.dispose();
    });

    test('a key wrapped for one purpose cannot be unwrapped as another', () {
      final inner = crypto.randomKey();
      final wrapped = crypto.wrapKey(
        keyToWrap: inner,
        wrappingKey: key,
        purpose: WrapPurpose.biometric,
      );
      expect(
        () => crypto.unwrapKey(
          wrapped: wrapped,
          wrappingKey: key,
          purpose: WrapPurpose.masterPassword,
        ),
        throwsA(isA<WrongCredentialsException>()),
      );
      inner.dispose();
    });

    test('an entry ciphertext is not accepted as a wrapped key', () {
      final env = crypto.seal(Uint8List(32), key, 'entry/x');
      expect(
        () => crypto.unwrapKey(
          wrapped: env,
          wrappingKey: key,
          purpose: WrapPurpose.masterPassword,
        ),
        throwsA(isA<WrongCredentialsException>()),
      );
    });
  });

  test('server auth secret is unpadded base64url of the key', () {
    final k = sodium.secureCopy(Uint8List(32)..fillRange(0, 32, 0xff));
    expect(crypto.serverAuthSecret(k), '_' * 42 + '8');
    k.dispose();
  });

  test('wipe zeroes a buffer', () {
    final b = Uint8List.fromList([1, 2, 3]);
    wipe(b);
    expect(b, [0, 0, 0]);
  });
}
