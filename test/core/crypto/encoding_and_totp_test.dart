import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:vaultsnap/core/crypto/crypto.dart';

import 'golden_vectors.dart';

void main() {
  group('Base32 (RFC 4648 section 10 vectors)', () {
    const vectors = {
      '': '',
      'f': 'MY',
      'fo': 'MZXQ',
      'foo': 'MZXW6',
      'foob': 'MZXW6YQ',
      'fooba': 'MZXW6YTB',
      'foobar': 'MZXW6YTBOI',
    };
    vectors.forEach((plain, encoded) {
      test('"$plain"', () {
        expect(Base32.encode(Uint8List.fromList(utf8.encode(plain))), encoded);
        expect(utf8.decode(Base32.decode(encoded)), plain);
      });
    });

    test('accepts padding, lowercase and spaces', () {
      expect(utf8.decode(Base32.decode('mzxw 6ytb oi======')), 'foobar');
    });

    test('rejects invalid characters and lengths', () {
      expect(
        () => Base32.decode('MZ1'),
        throwsA(isA<InvalidEncodingException>()),
      );
      expect(
        () => Base32.decode('M'),
        throwsA(isA<InvalidEncodingException>()),
      );
      // Non-zero trailing bits mean a truncated / mistyped secret.
      expect(
        () => Base32.decode('MZ'),
        throwsA(isA<InvalidEncodingException>()),
      );
    });
  });

  group('recovery key', () {
    late SodiumSumo sodium;
    setUpAll(() async => sodium = await loadSodium());

    test('format and parse round-trip', () {
      final rk = RecoveryKey.generate(sodium);
      final text = rk.format(sodium);
      final parsed = RecoveryKey.parse(sodium, text);
      expect(parsed.key.extractBytes(), rk.key.extractBytes());
      rk.dispose();
      parsed.dispose();
    });

    test('golden recovery key parses to bytes 01..20', () {
      final rk = RecoveryKey.parse(sodium, goldenRecoveryText);
      expect(rk.key.extractBytes(), List.generate(32, (i) => i + 1));
      rk.dispose();
    });

    test('every single-character typo is caught', () {
      final compact = goldenRecoveryText.replaceAll('-', '');
      var caught = 0;
      var total = 0;
      for (var i = 0; i < compact.length; i++) {
        final replacement = compact[i] == 'X' ? 'Y' : 'X';
        final typo = compact.replaceRange(i, i + 1, replacement);
        total++;
        try {
          RecoveryKey.parse(sodium, typo).dispose();
        } on InvalidRecoveryKeyException {
          caught++;
        }
      }
      // A 16-bit checksum misses a random typo with probability 2^-16; for
      // this fixed key and substitution every position is detected.
      expect(caught, total);
    });

    test('wrong length / garbage is rejected', () {
      for (final bad in ['', 'ABCDE', '${goldenRecoveryText}0', 'U' * 55]) {
        expect(
          () => RecoveryKey.parse(sodium, bad),
          throwsA(isA<InvalidRecoveryKeyException>()),
        );
      }
    });
  });

  group('TOTP (RFC 6238 Appendix B)', () {
    final seed20 = Uint8List.fromList(utf8.encode('12345678901234567890'));
    final seed32 = Uint8List.fromList(
      utf8.encode('12345678901234567890123456789012'),
    );
    final seed64 = Uint8List.fromList(
      utf8.encode(
        '1234567890123456789012345678901234567890123456789012345678901234',
      ),
    );
    const times = [
      59,
      1111111109,
      1111111111,
      1234567890,
      2000000000,
      20000000000,
    ];
    const expected = {
      TotpAlgorithm.sha1: [
        '94287082',
        '07081804',
        '14050471',
        '89005924',
        '69279037',
        '65353130',
      ],
      TotpAlgorithm.sha256: [
        '46119246',
        '68084774',
        '67062674',
        '91819424',
        '90698825',
        '77737706',
      ],
      TotpAlgorithm.sha512: [
        '90693936',
        '25091201',
        '99943326',
        '93441116',
        '38618901',
        '47863826',
      ],
    };
    final seeds = {
      TotpAlgorithm.sha1: seed20,
      TotpAlgorithm.sha256: seed32,
      TotpAlgorithm.sha512: seed64,
    };

    for (final alg in TotpAlgorithm.values) {
      test(alg.name, () {
        final totp = Totp(secret: seeds[alg]!, algorithm: alg, digits: 8);
        for (var i = 0; i < times.length; i++) {
          expect(
            totp.codeAt(times[i]),
            expected[alg]![i],
            reason: 't=${times[i]}',
          );
        }
      });
    }

    test('HOTP RFC 4226 Appendix D', () {
      const codes = [
        '755224',
        '287082',
        '359152',
        '969429',
        '338314',
        '254676',
        '287922',
        '162583',
        '399871',
        '520489',
      ];
      final hotp = Totp(secret: seed20);
      for (var c = 0; c < codes.length; c++) {
        expect(hotp.hotp(c), codes[c]);
      }
    });

    test('otpauth URI parsing', () {
      final secret = Base32.encode(seed20);
      final totp = Totp.fromUri(
        'otpauth://totp/ACME:alice@example.com?secret=$secret'
        '&issuer=ACME&algorithm=SHA1&digits=8&period=30',
      );
      expect(totp.codeAt(59), '94287082');
      expect(
        Totp.fromUri('otpauth://totp/x?secret=${secret.toLowerCase()}').digits,
        6,
      );
      expect(
        () => Totp.fromUri('otpauth://hotp/x?secret=$secret'),
        throwsA(isA<InvalidEncodingException>()),
      );
      expect(
        () => Totp.fromUri('otpauth://totp/x'),
        throwsA(isA<InvalidEncodingException>()),
      );
      expect(
        () => Totp.fromUri('otpauth://totp/x?secret=$secret&algorithm=MD5'),
        throwsA(isA<InvalidEncodingException>()),
      );
    });

    test('countdown', () {
      final totp = Totp(secret: seed20);
      expect(
        totp.secondsRemaining(DateTime.fromMillisecondsSinceEpoch(59000)),
        1,
      );
      expect(
        totp.secondsRemaining(DateTime.fromMillisecondsSinceEpoch(60000)),
        30,
      );
    });
  });
}
