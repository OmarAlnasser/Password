import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'crypto_exceptions.dart';
import 'kdf_params.dart';
import 'secure_bytes.dart';

/// What a wrapped key is wrapped *for*. Bound into the AEAD associated data
/// so a blob wrapped for one purpose can never be accepted as another.
enum WrapPurpose { masterPassword, recoveryKey, biometric, export }

/// Low-level Khazna primitives on top of libsodium.
///
/// Every operation is a direct libsodium call:
/// * Argon2id (`crypto_pwhash`) to stretch the master password.
/// * BLAKE2b (`crypto_kdf`) to split one key into independent subkeys.
/// * XChaCha20-Poly1305-IETF (`crypto_aead_xchacha20poly1305_ietf`) for all
///   encryption, with a fresh 192-bit random nonce every time.
///
/// Keys are handled as [SecureKey]s (libsodium guarded, mlock'ed memory that
/// is zeroed on `dispose`). Raw key bytes only touch Dart memory inside
/// `runUnlockedSync` callbacks, and temporary buffers are wiped.
class VaultCrypto {
  VaultCrypto(this.sodium);

  final SodiumSumo sodium;

  static const int keyBytes = 32;
  static const int saltBytes = 16;
  static const int nonceBytes = 24;
  static const int macBytes = 16;

  /// Ciphertext envelope: `version(1) || nonce(24) || ciphertext || tag(16)`.
  static const int formatVersion = 1;
  static const int envelopeOverhead = 1 + nonceBytes + macBytes;

  /// Entry plaintexts are padded (ISO/IEC 7816-4 via `sodium_pad`) to a
  /// multiple of this many bytes so the server cannot infer exact password
  /// lengths from ciphertext sizes.
  static const int entryPadBlock = 128;

  // crypto_kdf contexts: exactly 8 ASCII bytes, one per derived purpose.
  static const String ctxKeyEncryption = 'VSnapKEK';
  static const String ctxServerAuth = 'VSnapAUT';
  static const String ctxEntry = 'VSnapENT';
  static const String ctxDatabase = 'VSnapDB_';
  static const String ctxRecovery = 'VSnapRCV';

  Aead get _aead => sodium.crypto.aeadXChaCha20Poly1305IETF;

  // ---------------------------------------------------------------------------
  // Password handling
  // ---------------------------------------------------------------------------

  /// Converts a typed password into the exact bytes fed to Argon2id.
  ///
  /// NFKC normalisation makes the same visible password produce the same key
  /// across keyboards and platforms (e.g. Arabic presentation forms vs base
  /// letters, full-width vs ASCII digits, composed vs decomposed accents).
  /// The caller must [wipe] the returned buffer.
  static Uint8List passwordBytes(String password) =>
      Uint8List.fromList(utf8.encode(unorm.nfkc(password)));

  Uint8List newSalt() => sodium.randombytes.buf(saltBytes);

  /// Argon2id(password, salt) -> 256-bit master key.
  ///
  /// The master key is never stored and never leaves this process; callers
  /// immediately split it with [deriveSubkey] and dispose it.
  SecureKey deriveMasterKey({
    required Uint8List passwordUtf8,
    required Uint8List salt,
    required KdfParams params,
  }) {
    params.ensureAtLeastFloor();
    if (salt.length != saltBytes) throw const WeakKdfParamsException();
    return sodium.crypto.pwhash.callRaw(
      outLen: keyBytes,
      password: Int8List.sublistView(passwordUtf8),
      salt: salt,
      opsLimit: params.opsLimit,
      memLimit: params.memLimitBytes,
      alg: CryptoPwhashAlgorithm.argon2id13,
    );
  }

  /// Same as [deriveMasterKey] but runs Argon2id (~64 MiB, hundreds of ms)
  /// on a background isolate so the UI does not freeze. The result is moved
  /// back as a transferable secure key, never as a plain Dart list.
  Future<SecureKey> deriveMasterKeyInBackground({
    required Uint8List passwordUtf8,
    required Uint8List salt,
    required KdfParams params,
  }) async {
    params.ensureAtLeastFloor();
    // The password is moved to the isolate inside a SecureKey as well.
    final passwordKey = sodium.secureCopy(passwordUtf8);
    try {
      final transferable = await sodium.runIsolated((secureKeys, _) {
        final pw = secureKeys.single;
        final master = pw.runUnlockedSync(
          (raw) => VaultCrypto(sodium)
              .deriveMasterKey(passwordUtf8: raw, salt: salt, params: params),
        );
        return sodium.createTransferrableSecureKey(master);
      }, secureKeys: [passwordKey]);
      return sodium.materializeTransferrableSecureKey(transferable);
    } finally {
      passwordKey.dispose();
    }
  }

  /// BLAKE2b-based `crypto_kdf_derive_from_key`. One-way: knowing a subkey
  /// reveals nothing about the parent key or its sibling subkeys.
  SecureKey deriveSubkey(
    SecureKey parent,
    String context, {
    int subkeyId = 1,
    int length = keyBytes,
  }) => sodium.crypto.kdf.deriveFromKey(
    masterKey: parent,
    context: context,
    subkeyId: BigInt.from(subkeyId),
    subkeyLen: length,
  );

  SecureKey randomKey() => sodium.secureRandom(keyBytes);

  // ---------------------------------------------------------------------------
  // Authenticated encryption
  // ---------------------------------------------------------------------------

  /// Encrypts [plaintext] into a self-describing envelope.
  ///
  /// [context] is authenticated (not encrypted) and must be supplied again on
  /// decryption; it binds the ciphertext to where it belongs.
  Uint8List seal(Uint8List plaintext, SecureKey key, String context) {
    final nonce = sodium.randombytes.buf(nonceBytes);
    final ad = _associatedData(formatVersion, context);
    final ct = _aead.encrypt(
      message: plaintext,
      nonce: nonce,
      key: key,
      additionalData: ad,
    );
    return concatBytes([
      Uint8List.fromList([formatVersion]),
      nonce,
      ct,
    ]);
  }

  /// Decrypts an envelope produced by [seal]. The caller owns (and must
  /// [wipe]) the returned plaintext.
  Uint8List open(Uint8List envelope, SecureKey key, String context) {
    if (envelope.length < envelopeOverhead) {
      throw const DecryptionFailedException();
    }
    final version = envelope[0];
    if (version != formatVersion) throw const UnsupportedFormatException();
    final nonce = Uint8List.sublistView(envelope, 1, 1 + nonceBytes);
    final ct = Uint8List.sublistView(envelope, 1 + nonceBytes);
    try {
      return _aead.decrypt(
        cipherText: ct,
        nonce: nonce,
        key: key,
        additionalData: _associatedData(version, context),
      );
    } on SodiumException {
      throw const DecryptionFailedException();
    }
  }

  static Uint8List _associatedData(int version, String context) =>
      Uint8List.fromList(utf8.encode('vaultsnap/v$version/$context'));

  // ---------------------------------------------------------------------------
  // Key wrapping
  // ---------------------------------------------------------------------------

  Uint8List wrapKey({
    required SecureKey keyToWrap,
    required SecureKey wrappingKey,
    required WrapPurpose purpose,
  }) => keyToWrap.runUnlockedSync(
    (raw) => seal(raw, wrappingKey, 'wrap/${purpose.name}'),
  );

  /// Unwraps a key into secure memory. Throws [WrongCredentialsException] if
  /// the wrapping key is wrong or the blob was modified.
  SecureKey unwrapKey({
    required Uint8List wrapped,
    required SecureKey wrappingKey,
    required WrapPurpose purpose,
  }) {
    final Uint8List raw;
    try {
      raw = open(wrapped, wrappingKey, 'wrap/${purpose.name}');
    } on DecryptionFailedException {
      throw const WrongCredentialsException();
    }
    try {
      if (raw.length != keyBytes) throw const WrongCredentialsException();
      return sodium.secureCopy(raw);
    } finally {
      wipe(raw);
    }
  }

  // ---------------------------------------------------------------------------
  // Entries
  // ---------------------------------------------------------------------------

  /// Encrypts one serialised vault entry.
  ///
  /// The entry id is part of the associated data, so the server cannot swap
  /// the ciphertexts of two entries (e.g. move your bank password into the
  /// record autofill uses for a phishing domain) without detection.
  Uint8List encryptEntry({
    required Uint8List plaintext,
    required SecureKey entryKey,
    required String entryId,
  }) {
    final padded = sodium.pad(plaintext, entryPadBlock);
    try {
      return seal(padded, entryKey, 'entry/$entryId');
    } finally {
      wipe(padded);
    }
  }

  Uint8List decryptEntry({
    required Uint8List envelope,
    required SecureKey entryKey,
    required String entryId,
  }) {
    final padded = open(envelope, entryKey, 'entry/$entryId');
    try {
      // Copy out of the padded buffer so wiping it doesn't wipe the result.
      return Uint8List.fromList(sodium.unpad(padded, entryPadBlock));
    } on SodiumException {
      throw const DecryptionFailedException();
    } finally {
      wipe(padded);
    }
  }

  /// Converts the server-auth subkey to the string sent to Supabase Auth as
  /// the account "password". Supabase stores only a bcrypt hash of it.
  /// 32 bytes -> 43 base64url chars, under bcrypt's 72-byte limit.
  String serverAuthSecret(SecureKey authKey) => authKey.runUnlockedSync(
    (raw) => base64Url.encode(raw).replaceAll('=', ''),
  );
}
