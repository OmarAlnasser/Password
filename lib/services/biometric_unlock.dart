import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:biometric_storage/biometric_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as p;
import 'package:sodium/sodium_sumo.dart';

import '../core/crypto/crypto.dart';

/// Biometric unlock.
///
/// A random 256-bit "biometric KEK" is stored with `biometric_storage`:
/// * Android: AES key in the Android Keystore (StrongBox/TEE where available)
///   with setUserAuthenticationRequired + BiometricPrompt CryptoObject, so the
///   OS only releases it after a successful biometric match.
/// * iOS: Keychain item with SecAccessControl `.biometryCurrentSet`; it is
///   invalidated if fingerprints/faces are added.
/// * Windows: Windows Credential Manager (DPAPI-protected), gated by a
///   Windows Hello prompt via `local_auth`. NOTE: on Windows the gate is a UI
///   check, not a cryptographic binding - see docs/SECURITY.md.
///
/// The vault key itself is wrapped by that KEK (XChaCha20-Poly1305, purpose
/// "biometric") and the wrapped blob is kept in an ordinary file. Disabling
/// biometrics deletes both.
class BiometricUnlock {
  BiometricUnlock(this._directory, {LocalAuthentication? localAuth})
    : _localAuth = localAuth ?? LocalAuthentication();

  final Directory _directory;
  final LocalAuthentication _localAuth;

  static const _storageName = 'vaultsnap_bio_kek';
  File get _wrappedFile => File(p.join(_directory.path, 'vault_key.bio'));

  Future<bool> isAvailable() async {
    try {
      final r = await BiometricStorage().canAuthenticate();
      return r == CanAuthenticateResponse.success;
    } on Object {
      return false;
    }
  }

  Future<bool> get isEnabled => _wrappedFile.exists();

  Future<BiometricStorageFile> _storage() => BiometricStorage().getStorage(
    _storageName,
    options: StorageFileInitOptions(
      // Require auth for every use, biometrics only (no device PIN fallback
      // that a shoulder-surfer could reuse).
      authenticationValidityDurationSeconds: -1,
      authenticationRequired: true,
      androidBiometricOnly: true,
      darwinBiometricOnly: true,
    ),
  );

  Future<bool> _windowsGate(String reason) async {
    if (!Platform.isWindows) return true;
    return _localAuth.authenticate(localizedReason: reason);
  }

  Future<void> enable(VaultCrypto crypto, SecureKey vaultKey) async {
    if (!await _windowsGate('Enable Windows Hello unlock for Khazna')) {
      return;
    }
    final kek = crypto.randomKey();
    try {
      final wrapped = crypto.wrapKey(
        keyToWrap: vaultKey,
        wrappingKey: kek,
        purpose: WrapPurpose.biometric,
      );
      final kekB64 = kek.runUnlockedSync(base64.encode);
      await (await _storage()).write(kekB64);
      await _wrappedFile.writeAsBytes(wrapped, flush: true);
    } finally {
      kek.dispose();
    }
  }

  /// Returns the vault key, or null if the user cancelled.
  Future<SecureKey?> unwrapVaultKey(VaultCrypto crypto) async {
    if (!await _wrappedFile.exists()) return null;
    if (!await _windowsGate('Unlock Khazna')) return null;
    final String? kekB64;
    try {
      kekB64 = await (await _storage()).read();
    } on AuthException {
      return null;
    }
    if (kekB64 == null) return null;
    final raw = base64.decode(kekB64);
    final kek = crypto.sodium.secureCopy(raw);
    wipe(raw);
    try {
      return crypto.unwrapKey(
        wrapped: Uint8List.fromList(await _wrappedFile.readAsBytes()),
        wrappingKey: kek,
        purpose: WrapPurpose.biometric,
      );
    } finally {
      kek.dispose();
    }
  }

  Future<void> disable() async {
    if (await _wrappedFile.exists()) await _wrappedFile.delete();
    try {
      await (await _storage()).delete();
    } on Object {
      // Nothing stored.
    }
  }
}
