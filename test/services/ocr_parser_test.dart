import 'package:flutter_test/flutter_test.dart';
import 'package:vaultsnap/services/ocr/ocr_parser.dart';

void main() {
  final p = OcrCredentialParser();

  test('labelled credentials on the same line', () {
    final r = p.parse([
      'Welcome to Example',
      'https://accounts.example.com/login',
      'Username: alice_92',
      'Password: Tr0ub4dor&3x',
    ]);
    expect(r.username, 'alice_92');
    expect(r.password, 'Tr0ub4dor&3x');
    expect(r.url, 'https://accounts.example.com/login');
    expect(r.title, 'Example');
  });

  test('value on the next line and email detection', () {
    final r = p.parse([
      'Email',
      'bob@mail.example.org',
      'Password',
      'kP9#mQ2!vL',
    ]);
    expect(r.email, 'bob@mail.example.org');
    expect(r.username, 'bob@mail.example.org');
    expect(r.password, 'kP9#mQ2!vL');
  });

  test('Arabic labels', () {
    final r = p.parse(['اسم المستخدم: omar', 'كلمة المرور: Zx8!pQ4r']);
    expect(r.username, 'omar');
    expect(r.password, 'Zx8!pQ4r');
  });

  test('unlabelled: picks the most password-like token', () {
    final r = p.parse(['Wi-Fi', 'Network HomeNet 2024-05-01', 'aB3dE5fG7h!']);
    expect(r.password, 'aB3dE5fG7h!');
  });

  test('ignores dates, plain words and emails as passwords', () {
    final r = p.parse(['2024-05-01', 'hello world', 'me@x.io']);
    expect(r.password, isNull);
  });

  test('chips are deduplicated and capped', () {
    final r = p.parse(List.generate(500, (i) => 'tok$i other$i'));
    expect(r.chips.length, lessThanOrEqualTo(OcrCredentialParser.maxChips + 2));
    expect(r.chips.toSet().length, r.chips.length);
  });

  test('empty input', () {
    final r = p.parse(['', '  ']);
    expect(r.chips, isEmpty);
    expect(r.password, isNull);
  });

  test('label must be a whole word (Passport is not Password)', () {
    final r = p.parse(['Passport: X1234567', 'Pass: Qw3!rty9Zz']);
    expect(r.password, 'Qw3!rty9Zz');
  });

  // Synthetic credentials only.
  const addr = 'abcde07@hotmail.com';
  const secret = 'xQmR42abCD5k';

  group('OCR noise in e-mail addresses', () {
    for (final raw in [
      'abcde07 @ hotmail.com',
      'abcde07@ hotmail.com',
      'abcde07 @hotmail.com',
      'abcde07@hotmail .com',
      'abcde07@hotmail. com',
      'abcde07 @ hotmail . com',
      'abcde07©hotmail.com',
      'abcde07®hotmail.com',
      'abcde07＠hotmail.com',
      'abcde07(at)hotmail.com',
      'abcde07 [at] hotmail.com',
      'abcde07 (AT) hotmail.com',
      'abcde07@hotmail,com',
      'abcde07@hotmail , com',
      'abcde07@hotmail.corn',
      'abcde07@hotmail.c0m',
      'abcde07@hotmail .corn',
      'abcde07@hotmail.com.',
      'abcde07@hotmail.com,',
      '(abcde07@hotmail.com);',
      'abcde07@Hotmail.COM',
    ]) {
      test('"$raw" next to a password line', () {
        final r = p.parse([raw, secret]);
        expect(r.email, addr);
        expect(r.username, addr);
        expect(r.password, secret);
        expect(r.url, isNull);
        expect(r.title, isNull);
        expect(r.chips, contains(addr));
      });
    }

    test('the dark-mode screenshot: two lines, address first', () {
      final r = p.parse(['abcde07@hotmail.com', 'xQmR42abCD5k']);
      expect(r.username, addr);
      expect(r.password, secret);
    });

    test('a broken address is never the password', () {
      final r = p.parse(['abcde07@hotmail .com']);
      expect(r.email, addr);
      expect(r.password, isNull);
      for (final raw in ['abcde07©hotmail .com', 'abcde07@hotmail,corn']) {
        expect(p.parse([raw]).password, isNull, reason: raw);
      }
    });

    test('labelled address with OCR noise', () {
      final r = p.parse(['Email: abcde07 @ hotmail .com', 'Password: $secret']);
      expect(r.username, addr);
      expect(r.password, secret);
      final next = p.parse(['E-mail', 'abcde07©hotmail.com', 'Pass', secret]);
      expect(next.username, addr);
      expect(next.password, secret);
    });

    test('dotted local part split by OCR', () {
      expect(
        p.parse(['first .last07@hotmail.com']).email,
        'first.last07@hotmail.com',
      );
      // "Hello. x@y" is a sentence, not one address.
      expect(p.parse(['Hello. abcde07@hotmail.com']).email, addr);
    });

    test('ambiguous or real TLDs are left alone', () {
      expect(p.parse(['abcde07@hotmail.cam']).email, 'abcde07@hotmail.cam');
      expect(p.parse(['abcde07@mail.co.uk']).email, 'abcde07@mail.co.uk');
      expect(p.parse(['abcde07@corn.com']).email, 'abcde07@corn.com');
    });

    test('look-alikes and loose dots do not invent addresses', () {
      for (final line in [
        'Outlook® mail.com',
        'Copyright © 2024 Example',
        'Meet me @ 10.30',
        'abcde07@hotmail. Password',
        'abcde07@hotmail. My account',
        'abcde07@hotmail',
        'Follow @vaultsnap',
      ]) {
        expect(p.parse([line]).email, isNull, reason: line);
      }
    });

    test('a sentence after an address does not run on', () {
      final r = p.parse(['Signed in as abcde07@hotmail.com. Pass: $secret']);
      expect(r.email, addr);
      final c = p.parse(['abcde07@hotmail.com, welcome back']);
      expect(c.email, addr);
    });
  });

  group('url and title', () {
    test('an address domain is not the website', () {
      final r = p.parse([addr, secret]);
      expect(r.url, isNull);
      expect(r.title, isNull);
    });

    test('a site shown outside the address still counts', () {
      final r = p.parse(['outlook.live.com', addr, secret]);
      expect(r.url, 'outlook.live.com');
      expect(r.title, 'Live');
      expect(r.username, addr);
      expect(r.password, secret);
    });

    test('a URL that carries an address is kept', () {
      final r = p.parse(['https://example.com/reset?e=$addr']);
      expect(r.url, 'https://example.com/reset?e=$addr');
      expect(r.title, 'Example');
    });
  });

  group('pasted text', () {
    test('multi-line text in one string', () {
      final r = p.parseText(
        'Site: https://example.com\r\nEmail: $addr\nPassword: $secret\n',
      );
      expect(r.url, 'https://example.com');
      expect(r.title, 'Example');
      expect(r.username, addr);
      expect(r.password, secret);
      expect(r.chips, isNot(contains('Site: https://example.com\r')));
    });

    test('labels on one line', () {
      for (final line in [
        'email: $addr / password: $secret',
        'Email: $addr, Password: $secret',
        'Email: $addr | Password: $secret',
        'Email = $addr; Password = $secret',
        'Password: $secret Email: $addr',
        'Username: alice_92 Password: $secret',
      ]) {
        final r = p.parse([line]);
        expect(r.password, secret, reason: line);
        expect(
          r.username,
          line.contains('alice') ? 'alice_92' : addr,
          reason: line,
        );
      }
    });

    test('Arabic labels on one line', () {
      final r = p.parseText('البريد الإلكتروني: $addr كلمة المرور: $secret');
      expect(r.username, addr);
      expect(r.password, secret);
    });

    test('email:password combo lines', () {
      for (final line in [
        '$addr:$secret',
        '$addr : $secret',
        '$addr|$secret',
        'abcde07 @ hotmail.com:$secret',
      ]) {
        final r = p.parseText('Accounts\n$line\n');
        expect(r.username, addr, reason: line);
        expect(r.password, secret, reason: line);
        expect(r.url, isNull, reason: line);
        expect(r.chips, containsAll([addr, secret]), reason: line);
      }
    });

    test('user:pass is only split when the user is an address', () {
      final r = p.parse(['alice:$secret']);
      expect(r.username, isNull);
      expect(r.email, isNull);
      final t = p.parse(['Meeting 10:45']);
      expect(t.username, isNull);
      expect(t.password, isNull);
    });

    test('a combo is not a label value', () {
      final r = p.parse(['$addr: Password']);
      expect(r.username, addr);
      expect(r.password, isNull);
    });
  });

  group('no regressions', () {
    test('"Password" above the address line is not the password', () {
      final r = p.parse(['Email', 'Password', addr, secret]);
      expect(r.username, addr);
      expect(r.password, secret);
    });

    test('a username label beats an address elsewhere', () {
      final r = p.parse(['Username: alice_92', 'Recovery: $addr', secret]);
      expect(r.username, 'alice_92');
      expect(r.email, addr);
      expect(r.password, secret);
    });

    test('"Email address:" label', () {
      final r = p.parse(['Email address: $addr', 'Password: $secret']);
      expect(r.username, addr);
    });

    test('Arabic label followed by an address with OCR noise', () {
      final r = p.parse(['البريد الإلكتروني', 'abcde07 @ hotmail.com']);
      expect(r.username, addr);
    });

    test('short labelled PIN that also occurs in the address', () {
      final r = p.parse(['PIN: 0707', 'abcde0707@hotmail.com']);
      expect(r.password, '0707');
    });

    test('lines that are not labels are not split', () {
      final r = p.parse(['My password: $secret']);
      expect(r.password, secret);
      expect(r.chips, contains('My password: $secret'));
    });

    test('a field label is not guessed as the password', () {
      final r = p.parseText('Website: github.com\n$addr\nNotes: none');
      expect(r.url, 'github.com');
      expect(r.username, addr);
      expect(r.password, isNull);
    });

    test('a weak password on the line next to a lone address', () {
      for (final (lines, expected) in [
        (['abcde07@hotmail.com', 'mango12'], 'mango12'),
        (['abcde07@hotmail.com', 'mangotango'], 'mangotango'),
        (['abcde07@hotmail.com', '12345678'], '12345678'),
        (
          ['10:45', 'Notes', 'abcde07@hotmail.com', 'mango123', 'Done'],
          'mango123',
        ),
        (['mango12', 'abcde07@hotmail.com'], 'mango12'),
      ]) {
        final r = p.parse(lines);
        expect(r.username, addr, reason: '$lines');
        expect(r.password, expected, reason: '$lines');
      }
    });

    test('no positional guess next to a label, a sentence or a UI word', () {
      for (final lines in [
        ['Email: abcde07@hotmail.com', 'Verified'],
        ['Write to abcde07@hotmail.com today', 'mango12'],
        ['abcde07@hotmail.com', 'Done'],
        ['abcde07@hotmail.com', '10:45'],
        ['abcde07@hotmail.com', 'Website:'],
        ['abcde07@hotmail.com', 'example.com'],
        ['abcde07@hotmail.com', 'hotmail'],
        ['abcde07@hotmail.com', 'abc'],
      ]) {
        expect(p.parse(lines).password, isNull, reason: '$lines');
      }
    });

    test('long runs without spaces are skipped, and quickly', () {
      final jwt = 'eyJhbGciOiJIUzI1NiJ9${'a' * 5000}';
      final watch = Stopwatch()..start();
      final r = p.parseText('$jwt\n$addr\n$secret\n$jwt');
      expect(r.username, addr);
      expect(r.password, secret);
      expect(r.chips.every((c) => c.length <= 256), isTrue);
      // Whitespace-separated words up to the token cap, past the input cap.
      p.parseText(
        List.filled(1000, 'a' * OcrCredentialParser.maxTokenLength).join(' '),
      );
      p.parseText(List.filled(5000, 'x@a ').join());
      p.parseText('a' * 40000);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('text past the input cap is ignored', () {
      final filler = 'lorem ipsum ' * (OcrCredentialParser.maxInputLength ~/ 6);
      expect(p.parseText('$filler\n$addr\n$secret').username, isNull);
      expect(p.parseText('$addr\n$secret\n$filler').password, secret);
    });

    test('chips never exceed the cap', () {
      final r = p.parse([
        for (var i = 0; i < 300; i++) 'user$i@example$i.com tok$i x$i',
      ]);
      expect(r.chips.length, lessThanOrEqualTo(OcrCredentialParser.maxChips));
    });
  });
}
