import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;

import 'base32.dart';
import 'crypto_exceptions.dart';

enum TotpAlgorithm { sha1, sha256, sha512 }

/// RFC 6238 TOTP / RFC 4226 HOTP.
///
/// HMAC comes from `package:crypto` (the Dart team's implementation) because
/// libsodium has no HMAC-SHA1, which almost every TOTP issuer still uses.
/// HMAC-SHA1 remains secure as a PRF; SHA-1 collisions do not affect it.
class Totp {
  Totp({
    required this.secret,
    this.algorithm = TotpAlgorithm.sha1,
    this.digits = 6,
    this.period = 30,
  }) {
    if (secret.isEmpty) {
      throw const InvalidEncodingException('Empty TOTP secret');
    }
    if (digits < 6 || digits > 10) {
      throw const InvalidEncodingException('Unsupported digit count');
    }
    if (period <= 0) {
      throw const InvalidEncodingException('Invalid period');
    }
  }

  /// Builds from a Base32 secret as shown by most sites.
  factory Totp.fromBase32(
    String secret, {
    TotpAlgorithm algorithm = TotpAlgorithm.sha1,
    int digits = 6,
    int period = 30,
  }) => Totp(
    secret: Base32.decode(secret),
    algorithm: algorithm,
    digits: digits,
    period: period,
  );

  /// Parses `otpauth://totp/Label?secret=...&issuer=...&algorithm=...`.
  factory Totp.fromUri(String uri) {
    final parsed = Uri.tryParse(uri.trim());
    if (parsed == null ||
        parsed.scheme != 'otpauth' ||
        parsed.host.toLowerCase() != 'totp') {
      throw const InvalidEncodingException('Not an otpauth TOTP URI');
    }
    final q = parsed.queryParameters;
    final secret = q['secret'];
    if (secret == null) {
      throw const InvalidEncodingException('Missing TOTP secret');
    }
    final alg = switch ((q['algorithm'] ?? 'SHA1').toUpperCase()) {
      'SHA1' => TotpAlgorithm.sha1,
      'SHA256' => TotpAlgorithm.sha256,
      'SHA512' => TotpAlgorithm.sha512,
      _ => throw const InvalidEncodingException('Unsupported TOTP algorithm'),
    };
    return Totp.fromBase32(
      secret,
      algorithm: alg,
      digits: int.tryParse(q['digits'] ?? '') ?? 6,
      period: int.tryParse(q['period'] ?? '') ?? 30,
    );
  }

  final Uint8List secret;
  final TotpAlgorithm algorithm;
  final int digits;
  final int period;

  /// RFC 4226 HOTP for a given counter.
  String hotp(int counter) {
    final msg = ByteData(8)..setUint64(0, counter);
    final mac = _hmac().convert(msg.buffer.asUint8List()).bytes;
    final offset = mac.last & 0x0f;
    final binary =
        ((mac[offset] & 0x7f) << 24) |
        (mac[offset + 1] << 16) |
        (mac[offset + 2] << 8) |
        mac[offset + 3];
    var modulus = 1;
    for (var i = 0; i < digits; i++) {
      modulus *= 10;
    }
    return (binary % modulus).toString().padLeft(digits, '0');
  }

  /// Code for a Unix time in seconds.
  String codeAt(int unixSeconds) => hotp(unixSeconds ~/ period);

  String now() => codeAt(DateTime.now().millisecondsSinceEpoch ~/ 1000);

  /// Seconds until the current code expires (for the countdown ring).
  int secondsRemaining([DateTime? at]) {
    final t = (at ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    return period - (t % period);
  }

  hashes.Hmac _hmac() => hashes.Hmac(switch (algorithm) {
    TotpAlgorithm.sha1 => hashes.sha1,
    TotpAlgorithm.sha256 => hashes.sha256,
    TotpAlgorithm.sha512 => hashes.sha512,
  }, secret);
}
