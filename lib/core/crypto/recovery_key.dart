import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import 'base32.dart';
import 'crypto_exceptions.dart';
import 'secure_bytes.dart';
import 'vault_crypto.dart';

/// The one-time recovery key generated at signup.
///
/// It is 256 bits from the OS CSPRNG, so unlike the master password it needs
/// no Argon2 stretching: guessing it is infeasible. It is shown to the user
/// exactly once as 11 groups of 5 Crockford-Base32 characters:
///
///     32 key bytes || 2 checksum bytes  ->  55 chars
///
/// The checksum (first 2 bytes of BLAKE2b(key)) only catches typos; it is not
/// a security feature.
class RecoveryKey {
  RecoveryKey._(this.key);

  /// Raw recovery key in secure memory. Dispose when done.
  final SecureKey key;

  static const int _checksumBytes = 2;
  static const int _groupSize = 5;

  static RecoveryKey generate(SodiumSumo sodium) =>
      RecoveryKey._(sodium.secureRandom(VaultCrypto.keyBytes));

  /// Parses user input. Case, spaces, dashes and the look-alikes O/I/L are
  /// tolerated. Throws [InvalidRecoveryKeyException] on any mistake.
  static RecoveryKey parse(SodiumSumo sodium, String input) {
    Uint8List? decoded;
    try {
      decoded = Base32.decodeCrockford(input);
    } on InvalidEncodingException {
      throw const InvalidRecoveryKeyException();
    }
    try {
      if (decoded.length != VaultCrypto.keyBytes + _checksumBytes) {
        throw const InvalidRecoveryKeyException();
      }
      final raw = Uint8List.sublistView(decoded, 0, VaultCrypto.keyBytes);
      final given = Uint8List.sublistView(decoded, VaultCrypto.keyBytes);
      final expected = _checksum(sodium, raw);
      if (!sodium.memcmp(given, expected)) {
        throw const InvalidRecoveryKeyException();
      }
      return RecoveryKey._(sodium.secureCopy(raw));
    } finally {
      wipe(decoded);
    }
  }

  /// Human-readable form, e.g. `ABCDE-FGHJK-...`. Only call this once, to
  /// show the key at signup; the returned String cannot be wiped.
  String format(SodiumSumo sodium) => key.runUnlockedSync((raw) {
    final withChecksum = Uint8List(raw.length + _checksumBytes)
      ..setAll(0, raw)
      ..setAll(raw.length, _checksum(sodium, raw));
    try {
      final encoded = Base32.encodeCrockford(withChecksum);
      final groups = <String>[
        for (var i = 0; i < encoded.length; i += _groupSize)
          encoded.substring(
            i,
            i + _groupSize > encoded.length ? encoded.length : i + _groupSize,
          ),
      ];
      return groups.join('-');
    } finally {
      wipe(withChecksum);
    }
  });

  static Uint8List _checksum(SodiumSumo sodium, Uint8List raw) =>
      Uint8List.sublistView(
        sodium.crypto.genericHash(message: raw, outLen: 16),
        0,
        _checksumBytes,
      );

  void dispose() => key.dispose();
}
