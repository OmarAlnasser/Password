import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import 'kdf_params.dart';
import 'recovery_key.dart';
import 'secure_bytes.dart';
import 'vault_crypto.dart';

// Key hierarchy
// =============
//
//   master password ──NFKC──Argon2id(salt, 64 MiB, t=3)──▶ master key (never stored)
//        master key ──BLAKE2b "VSnapKEK"──▶ password KEK   (wraps vault key)
//        master key ──BLAKE2b "VSnapAUT"──▶ server auth key (Supabase password)
//
//      recovery key ──BLAKE2b "VSnapRCV"#1──▶ recovery KEK  (wraps vault key)
//      recovery key ──BLAKE2b "VSnapRCV"#2──▶ recovery auth secret (phase 4)
//
//         vault key (random) ──BLAKE2b "VSnapENT"──▶ entry key (XChaCha20-Poly1305)
//         vault key          ──BLAKE2b "VSnapDB_"──▶ SQLCipher database key
//
// The server sees: salt, KDF params, both wrapped vault keys, the auth key
// (over TLS, stored as bcrypt by Supabase), and encrypted entries. Because the
// auth key and the KEK are independent one-way derivations of the master key,
// knowing the auth key does not help decrypt anything.

/// Non-secret key material persisted locally and on the server.
class VaultKeyHeader {
  const VaultKeyHeader({
    required this.kdf,
    required this.salt,
    required this.vaultKeyByPassword,
    required this.vaultKeyByRecovery,
  });

  factory VaultKeyHeader.fromJson(Map<String, Object?> json) => VaultKeyHeader(
    kdf: KdfParams.fromJson((json['kdf']! as Map).cast<String, Object?>()),
    salt: base64.decode(json['salt']! as String),
    vaultKeyByPassword: base64.decode(json['vk_pw']! as String),
    vaultKeyByRecovery: base64.decode(json['vk_rc']! as String),
  );

  final KdfParams kdf;
  final Uint8List salt;
  final Uint8List vaultKeyByPassword;
  final Uint8List vaultKeyByRecovery;

  VaultKeyHeader copyWith({
    KdfParams? kdf,
    Uint8List? salt,
    Uint8List? vaultKeyByPassword,
    Uint8List? vaultKeyByRecovery,
  }) => VaultKeyHeader(
    kdf: kdf ?? this.kdf,
    salt: salt ?? this.salt,
    vaultKeyByPassword: vaultKeyByPassword ?? this.vaultKeyByPassword,
    vaultKeyByRecovery: vaultKeyByRecovery ?? this.vaultKeyByRecovery,
  );

  Map<String, Object?> toJson() => {
    'kdf': kdf.toJson(),
    'salt': base64.encode(salt),
    'vk_pw': base64.encode(vaultKeyByPassword),
    'vk_rc': base64.encode(vaultKeyByRecovery),
  };
}

/// Keys held while the vault is unlocked. [lock] wipes all of them.
class Keyring {
  Keyring._(this._vaultKey, this._entryKey, this._databaseKey);

  factory Keyring.fromVaultKey(VaultCrypto crypto, SecureKey vaultKey) =>
      Keyring._(
        vaultKey,
        crypto.deriveSubkey(vaultKey, VaultCrypto.ctxEntry),
        crypto.deriveSubkey(vaultKey, VaultCrypto.ctxDatabase),
      );

  final SecureKey _vaultKey;
  final SecureKey _entryKey;
  final SecureKey _databaseKey;
  bool _locked = false;

  bool get isLocked => _locked;

  /// Root key; only needed to re-wrap (password change, biometrics, export).
  SecureKey get vaultKey => _check(_vaultKey);

  /// Encrypts/decrypts individual entries.
  SecureKey get entryKey => _check(_entryKey);

  /// Opens the local SQLCipher database.
  SecureKey get databaseKey => _check(_databaseKey);

  SecureKey _check(SecureKey key) {
    if (_locked) throw StateError('Vault is locked');
    return key;
  }

  /// Zeroes and frees every key (sodium_free wipes the guarded pages).
  void lock() {
    if (_locked) return;
    _locked = true;
    _vaultKey.dispose();
    _entryKey.dispose();
    _databaseKey.dispose();
  }
}

/// Keys derived from the master password. Short-lived: dispose right after
/// unlocking / logging in.
class PasswordKeys {
  PasswordKeys._(this.kek, this.authKey);

  final SecureKey kek;
  final SecureKey authKey;

  void dispose() {
    kek.dispose();
    authKey.dispose();
  }
}

class SignupResult {
  SignupResult._({
    required this.header,
    required this.keyring,
    required this.serverAuthSecret,
    required this.recoveryAuthSecret,
    required this.recoveryKeyText,
  });

  final VaultKeyHeader header;
  final Keyring keyring;

  /// Sent to Supabase Auth as the account password.
  final String serverAuthSecret;

  /// Lets the server verify a recovery attempt without learning the recovery
  /// KEK (used by the recovery flow in phase 4).
  final String recoveryAuthSecret;

  /// Display once, require confirmation, then drop the reference.
  final String recoveryKeyText;
}

/// High-level operations on the key hierarchy.
class AccountKeys {
  AccountKeys(this.crypto);

  final VaultCrypto crypto;

  SodiumSumo get _sodium => crypto.sodium;

  /// Derives the password KEK and server-auth key. The master key itself
  /// exists only inside this method.
  Future<PasswordKeys> derivePasswordKeys({
    required String password,
    required Uint8List salt,
    required KdfParams params,
    bool inBackground = true,
  }) async {
    final pw = VaultCrypto.passwordBytes(password);
    final SecureKey master;
    try {
      master = inBackground
          ? await crypto.deriveMasterKeyInBackground(
              passwordUtf8: pw,
              salt: salt,
              params: params,
            )
          : crypto.deriveMasterKey(
              passwordUtf8: pw,
              salt: salt,
              params: params,
            );
    } finally {
      wipe(pw);
    }
    try {
      return PasswordKeys._(
        crypto.deriveSubkey(master, VaultCrypto.ctxKeyEncryption),
        crypto.deriveSubkey(master, VaultCrypto.ctxServerAuth),
      );
    } finally {
      master.dispose();
    }
  }

  /// Creates a brand-new vault: random salt, random vault key, recovery key.
  Future<SignupResult> createAccount(
    String password, {
    KdfParams params = KdfParams.recommended,
    bool inBackground = true,
  }) async {
    final salt = crypto.newSalt();
    final pwKeys = await derivePasswordKeys(
      password: password,
      salt: salt,
      params: params,
      inBackground: inBackground,
    );
    final vaultKey = crypto.randomKey();
    final recovery = RecoveryKey.generate(_sodium);
    try {
      final header = VaultKeyHeader(
        kdf: params,
        salt: salt,
        vaultKeyByPassword: crypto.wrapKey(
          keyToWrap: vaultKey,
          wrappingKey: pwKeys.kek,
          purpose: WrapPurpose.masterPassword,
        ),
        vaultKeyByRecovery: _wrapForRecovery(vaultKey, recovery),
      );
      return SignupResult._(
        header: header,
        keyring: Keyring.fromVaultKey(crypto, vaultKey),
        serverAuthSecret: crypto.serverAuthSecret(pwKeys.authKey),
        recoveryAuthSecret: recoveryAuthSecret(recovery),
        recoveryKeyText: recovery.format(_sodium),
      );
    } catch (_) {
      vaultKey.dispose();
      rethrow;
    } finally {
      pwKeys.dispose();
      recovery.dispose();
    }
  }

  /// Unwraps the vault key with already-derived password keys.
  Keyring unlockWithPasswordKeys(PasswordKeys keys, VaultKeyHeader header) =>
      Keyring.fromVaultKey(
        crypto,
        crypto.unwrapKey(
          wrapped: header.vaultKeyByPassword,
          wrappingKey: keys.kek,
          purpose: WrapPurpose.masterPassword,
        ),
      );

  /// Local, offline unlock. Throws `WrongCredentialsException`.
  Future<Keyring> unlockWithPassword(
    String password,
    VaultKeyHeader header, {
    bool inBackground = true,
  }) async {
    final keys = await derivePasswordKeys(
      password: password,
      salt: header.salt,
      params: header.kdf,
      inBackground: inBackground,
    );
    try {
      return unlockWithPasswordKeys(keys, header);
    } finally {
      keys.dispose();
    }
  }

  /// Unlock with the recovery key. Throws `InvalidRecoveryKeyException` for
  /// typos and `WrongCredentialsException` for a valid-looking wrong key.
  Keyring unlockWithRecoveryKey(String recoveryText, VaultKeyHeader header) {
    final recovery = RecoveryKey.parse(_sodium, recoveryText);
    final kek = crypto.deriveSubkey(
      recovery.key,
      VaultCrypto.ctxRecovery,
      subkeyId: 1,
    );
    try {
      return Keyring.fromVaultKey(
        crypto,
        crypto.unwrapKey(
          wrapped: header.vaultKeyByRecovery,
          wrappingKey: kek,
          purpose: WrapPurpose.recoveryKey,
        ),
      );
    } finally {
      kek.dispose();
      recovery.dispose();
    }
  }

  /// Re-wraps the (unchanged) vault key under a new password with a fresh
  /// salt. No entry needs re-encryption. Returns the new header and the new
  /// server auth secret.
  Future<(VaultKeyHeader, String)> changePassword({
    required Keyring keyring,
    required VaultKeyHeader header,
    required String newPassword,
    KdfParams params = KdfParams.recommended,
    bool inBackground = true,
  }) async {
    final salt = crypto.newSalt();
    final keys = await derivePasswordKeys(
      password: newPassword,
      salt: salt,
      params: params,
      inBackground: inBackground,
    );
    try {
      final newHeader = header.copyWith(
        kdf: params,
        salt: salt,
        vaultKeyByPassword: crypto.wrapKey(
          keyToWrap: keyring.vaultKey,
          wrappingKey: keys.kek,
          purpose: WrapPurpose.masterPassword,
        ),
      );
      return (newHeader, crypto.serverAuthSecret(keys.authKey));
    } finally {
      keys.dispose();
    }
  }

  /// Replaces the recovery key (e.g. after it was used or exposed). The old
  /// recovery key stops working once the new header is saved everywhere.
  ({VaultKeyHeader header, String recoveryKeyText, String recoveryAuthSecret})
  rotateRecoveryKey({
    required Keyring keyring,
    required VaultKeyHeader header,
  }) {
    final recovery = RecoveryKey.generate(_sodium);
    try {
      return (
        header: header.copyWith(
          vaultKeyByRecovery: _wrapForRecovery(keyring.vaultKey, recovery),
        ),
        recoveryKeyText: recovery.format(_sodium),
        recoveryAuthSecret: recoveryAuthSecret(recovery),
      );
    } finally {
      recovery.dispose();
    }
  }

  String recoveryAuthSecret(RecoveryKey recovery) {
    final key = crypto.deriveSubkey(
      recovery.key,
      VaultCrypto.ctxRecovery,
      subkeyId: 2,
    );
    try {
      return crypto.serverAuthSecret(key);
    } finally {
      key.dispose();
    }
  }

  Uint8List _wrapForRecovery(SecureKey vaultKey, RecoveryKey recovery) {
    final kek = crypto.deriveSubkey(
      recovery.key,
      VaultCrypto.ctxRecovery,
      subkeyId: 1,
    );
    try {
      return crypto.wrapKey(
        keyToWrap: vaultKey,
        wrappingKey: kek,
        purpose: WrapPurpose.recoveryKey,
      );
    } finally {
      kek.dispose();
    }
  }
}
