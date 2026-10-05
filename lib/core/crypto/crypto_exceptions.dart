/// Errors raised by the crypto layer.
///
/// Messages are deliberately generic and constant: they must never contain
/// key material, plaintext, passwords or ciphertext, because exceptions end up
/// in logs and crash reports.
sealed class VaultCryptoException implements Exception {
  const VaultCryptoException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The master password (or recovery key) did not unwrap the vault key.
///
/// Raised for both "wrong password" and "tampered header"; the two are
/// indistinguishable by design (AEAD authentication failure).
final class WrongCredentialsException extends VaultCryptoException {
  const WrongCredentialsException() : super('Invalid credentials');
}

/// A ciphertext failed authentication, was truncated, or was bound to a
/// different entry / purpose.
final class DecryptionFailedException extends VaultCryptoException {
  const DecryptionFailedException() : super('Decryption failed');
}

/// The ciphertext uses a format version this build does not understand.
final class UnsupportedFormatException extends VaultCryptoException {
  const UnsupportedFormatException() : super('Unsupported format version');
}

/// KDF parameters are below the security floor (possible downgrade attack).
final class WeakKdfParamsException extends VaultCryptoException {
  const WeakKdfParamsException() : super('KDF parameters below minimum');
}

/// A recovery key could not be parsed (typo or checksum mismatch).
final class InvalidRecoveryKeyException extends VaultCryptoException {
  const InvalidRecoveryKeyException() : super('Invalid recovery key');
}

/// Input that is not a valid Base32 / otpauth / TOTP value.
final class InvalidEncodingException extends VaultCryptoException {
  const InvalidEncodingException(super.message);
}
