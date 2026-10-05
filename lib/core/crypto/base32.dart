import 'dart:typed_data';

import 'crypto_exceptions.dart';

/// Base32 codecs. Encoding only — no cryptography here.
abstract final class Base32 {
  /// RFC 4648 alphabet, used by TOTP secrets (`otpauth://` URIs).
  static const String rfc4648Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /// Crockford alphabet, used for recovery keys. It omits I, L, O and U so a
  /// handwritten key cannot be confused with 1, 1, 0 and V.
  static const String crockfordAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// Encodes [data] with the RFC 4648 alphabet, without padding.
  static String encode(Uint8List data) => _encode(data, rfc4648Alphabet);

  /// Decodes RFC 4648 Base32. Accepts lowercase, spaces, dashes and `=`
  /// padding, because TOTP secrets are often typed in or OCR'd by hand.
  static Uint8List decode(String input) {
    final cleaned = input.toUpperCase().replaceAll(RegExp(r'[\s\-=]'), '');
    return _decode(cleaned, (c) => rfc4648Alphabet.indexOf(c));
  }

  static String encodeCrockford(Uint8List data) =>
      _encode(data, crockfordAlphabet);

  /// Decodes Crockford Base32, normalising the look-alike characters
  /// O→0 and I/L→1 so users can type what they think they see.
  static Uint8List decodeCrockford(String input) {
    final cleaned = input
        .toUpperCase()
        .replaceAll(RegExp(r'[\s\-]'), '')
        .replaceAll('O', '0')
        .replaceAll(RegExp('[IL]'), '1');
    return _decode(cleaned, (c) => crockfordAlphabet.indexOf(c));
  }

  static String _encode(Uint8List data, String alphabet) {
    final out = StringBuffer();
    var buffer = 0;
    var bits = 0;
    for (final byte in data) {
      buffer = (buffer << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        out.write(alphabet[(buffer >> bits) & 0x1f]);
      }
      buffer &= (1 << bits) - 1;
    }
    if (bits > 0) {
      out.write(alphabet[(buffer << (5 - bits)) & 0x1f]);
    }
    return out.toString();
  }

  static Uint8List _decode(String input, int Function(String) indexOf) {
    final out = BytesBuilder(copy: false);
    var buffer = 0;
    var bits = 0;
    for (var i = 0; i < input.length; i++) {
      final value = indexOf(input[i]);
      if (value < 0) {
        throw const InvalidEncodingException('Invalid Base32 character');
      }
      buffer = (buffer << 5) | value;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.addByte((buffer >> bits) & 0xff);
      }
      buffer &= (1 << bits) - 1;
    }
    // Leftover bits must be zero padding (< 5 bits), otherwise the string
    // was truncated or has an extra character.
    if (bits >= 5 || buffer != 0) {
      throw const InvalidEncodingException('Invalid Base32 length');
    }
    return out.takeBytes();
  }
}
