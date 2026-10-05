import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:vaultsnap/core/crypto/crypto.dart';
import 'package:vaultsnap/data/models/vault_entry.dart';
import 'package:vaultsnap/services/import_export.dart';
import 'package:vaultsnap/services/password_generator.dart';
import 'package:vaultsnap/services/unlock_throttle.dart';

void main() {
  late SodiumSumo sodium;
  setUpAll(() async => sodium = await loadSodium());

  group('UnlockThrottle', () {
    test('delay schedule', () {
      expect(UnlockThrottle.delayAfter(0), Duration.zero);
      expect(UnlockThrottle.delayAfter(2), Duration.zero);
      expect(UnlockThrottle.delayAfter(3), const Duration(seconds: 1));
      expect(UnlockThrottle.delayAfter(6), const Duration(seconds: 8));
      expect(UnlockThrottle.delayAfter(50), const Duration(minutes: 5));
      expect(UnlockThrottle.delayAfter(1 << 40), const Duration(minutes: 5));
    });

    test('persists across restarts and survives clock rollback', () async {
      final dir = Directory.systemTemp.createTempSync('thr');
      var now = DateTime(2026, 1, 1, 12);
      final f = File('${dir.path}/t.json');
      final t = UnlockThrottle(f, clock: () => now);
      await t.load();
      for (var i = 0; i < 5; i++) {
        await t.recordFailure();
      }
      final t2 = UnlockThrottle(f, clock: () => now);
      await t2.load();
      expect(t2.failures, 5);
      expect(t2.remaining, const Duration(seconds: 4));
      now = now.subtract(const Duration(days: 1));
      expect(t2.remaining, const Duration(seconds: 4));
      now = DateTime(2026, 1, 1, 12, 0, 5);
      expect(t2.remaining, Duration.zero);
      dir.deleteSync(recursive: true);
    });
  });

  group('PasswordGenerator', () {
    final words = List.generate(7776, (i) => 'word$i');
    test('respects sets and length', () {
      final g = PasswordGenerator(sodium, words);
      for (var i = 0; i < 200; i++) {
        final pw = g.generate(const GeneratorOptions(length: 24));
        expect(pw.length, 24);
        expect(pw, matches(RegExp('[a-z]')));
        expect(pw, matches(RegExp('[A-Z]')));
        expect(pw, matches(RegExp('[0-9]')));
        expect(pw.split('').any(PasswordGenerator.ambiguous.contains), isFalse);
      }
      final digitsOnly = g.generate(
        const GeneratorOptions(
          length: 4,
          lower: false,
          upper: false,
          symbols: false,
        ),
      );
      expect(
        digitsOnly,
        matches(RegExp(r'^[2-9]{8}$')),
        reason: 'min length 8',
      );
    });

    test('passphrase', () {
      final g = PasswordGenerator(sodium, words);
      final p = g.generate(const GeneratorOptions(passphrase: true, words: 6));
      expect(p.split('-'), hasLength(6));
      expect(
        g.entropyBits(const GeneratorOptions(passphrase: true, words: 6)),
        greaterThan(77),
      );
    });

    test('no duplicates over many generations', () {
      final g = PasswordGenerator(sodium, words);
      final set = {
        for (var i = 0; i < 2000; i++)
          g.generate(const GeneratorOptions(length: 16)),
      };
      expect(set, hasLength(2000));
    });

    test('strength meter', () {
      final m = StrengthMeter();
      expect(m.evaluate('password').score, lessThan(2));
      expect(m.evaluate('Ve7#kq!Lm2@zR9xW').score, 4);
    });
  });

  group('ImportExport', () {
    late ImportExport ie;
    setUpAll(() => ie = ImportExport(VaultCrypto(sodium)));

    test('encrypted export round-trip, wrong password rejected', () async {
      final file = await ie.exportEncrypted([
        VaultEntry(id: '1', title: 'T', password: 'p@ss'),
      ], 'export pw');
      expect(file.contains('p@ss'), isFalse);
      final r = await ie.importEncrypted(file, 'export pw');
      expect(r.entries.single.password, 'p@ss');
      await expectLater(
        ie.importEncrypted(file, 'nope'),
        throwsA(isA<ImportException>()),
      );
    });

    test('Chrome CSV keeps numeric-looking passwords as text', () {
      final r = ie.importCsv(
        'name,url,username,password,note\n'
        'Site,https://a.com,bob,0123,\n'
        'S2,https://b.com,amy,"pa,ss""word",multi\n',
      );
      expect(r.entries.map((e) => e.password), ['0123', 'pa,ss"word']);
    });

    test('Bitwarden CSV', () {
      final r = ie.importCsv(
        'folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp\n'
        'Work,1,login,Mail,,,0,https://mail.example.com,me,secret,JBSWY3DPEHPK3PXP\n'
        ',,note,Secure note,hello,,0,,,,\n',
      );
      expect(r.entries.single.favorite, isTrue);
      expect(r.entries.single.tags, ['Work']);
      expect(r.entries.single.totpSecret, 'JBSWY3DPEHPK3PXP');
      expect(r.skipped, 1);
    });
  });
}
