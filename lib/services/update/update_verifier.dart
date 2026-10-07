import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium.dart';

import 'update_failure.dart';

/// Checks a detached signature over the exact bytes of a manifest.
abstract interface class ManifestVerifier {
  /// True only if [signature] is a valid signature of [message] by the pinned
  /// key. Never throws: anything unexpected is "not valid".
  bool verify(Uint8List message, Uint8List signature);
}

/// Ed25519 (`crypto_sign_verify_detached`) through libsodium, which the app
/// already ships for the vault.
class SodiumManifestVerifier implements ManifestVerifier {
  SodiumManifestVerifier(this._sodium, Uint8List publicKey)
    : _publicKey = Uint8List.fromList(publicKey);

  final Sodium _sodium;
  final Uint8List _publicKey;

  @override
  bool verify(Uint8List message, Uint8List signature) {
    try {
      final sign = _sodium.crypto.sign;
      // The binding throws on a wrong length; refuse before it gets there.
      if (signature.length != sign.bytes ||
          _publicKey.length != sign.publicKeyBytes) {
        return false;
      }
      return sign.verifyDetached(
        message: message,
        signature: signature,
        publicKey: _publicKey,
      );
    } on Object {
      return false;
    }
  }
}

/// Decodes the content of `update.json.sig`: base64 of the raw 64-byte
/// signature, optionally followed by whitespace (a trailing newline).
///
/// Throws [UpdateFailure.signatureInvalid] for anything else.
Uint8List decodeSignatureFile(Uint8List bytes, {int signatureBytes = 64}) {
  const bad = UpdateException(UpdateFailure.signatureInvalid);
  final String text;
  try {
    text = ascii.decode(bytes).trim();
  } on FormatException {
    throw bad;
  }
  // Canonical padded base64 only.
  final expectedChars = (signatureBytes + 2) ~/ 3 * 4;
  if (text.length != expectedChars) throw bad;
  final Uint8List raw;
  try {
    raw = base64.decode(text);
  } on FormatException {
    throw bad;
  }
  if (raw.length != signatureBytes) throw bad;
  return raw;
}
