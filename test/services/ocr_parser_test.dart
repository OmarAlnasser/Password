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

  // ------------------------------------------------------------------------
  // Raw OCR output of a tiny dark-mode crop: two lines, an address and a
  // 12-character password, read at a few pixels per letter. Everything below
  // is synthetic, shaped after what the engines return.

  void expectLogin(
    OcrResult r, {
    String? email = addr,
    String? password = secret,
    Object? reason,
  }) {
    expect(r.email, email, reason: '$reason');
    expect(r.username, email, reason: '$reason');
    expect(r.password, password, reason: '$reason');
    expect(r.url, isNull, reason: '$reason');
    expect(r.title, isNull, reason: '$reason');
  }

  group('letter-spaced text', () {
    test('both lines letter-spaced', () {
      expectLogin(
        p.parse([
          'a b c d e 0 7 @ h o t m a i l . c o m',
          'x Q m R 4 2 a b C D 5 k',
        ]),
      );
    });

    test('only the address is letter-spaced', () {
      expectLogin(p.parse(['a b c d e 0 7 @ h o t m a i l . c o m', secret]));
    });

    test('only the password is letter-spaced', () {
      expectLogin(p.parse([addr, 'x Q m R 4 2 a b C D 5 k']));
    });

    test('letter-spaced lines with OCR junk after them', () {
      final r = p.parse([
        'a b c d e 0 7 @ h o t m a i l . c o m |',
        'x Q m R 4 2 a b C D 5 k .',
      ]);
      expectLogin(r);
      expect(r.chips, containsAll([addr, secret]));
    });

    test('both letter-spaced values on one line, parted by a gap', () {
      expectLogin(
        p.parse([
          'a b c d e 0 7 @ h o t m a i l . c o m    x Q m R 4 2 a b C D 5 k',
        ]),
      );
      expectLogin(
        p.parse([
          'a b c d e 0 7 @ h o t m a i l . c o m \t x Q m R 4 2 a b C D 5 k',
        ]),
      );
    });

    test('both letter-spaced values on one line with single spaces', () {
      // Nothing parts them but the "com": the address ends there.
      expectLogin(
        p.parse([
          'a b c d e 0 7 @ h o t m a i l . c o m x Q m R 4 2 a b C D 5 k',
        ]),
      );
    });

    test('a letter-spaced label stays a label', () {
      final r = p.parse(['P a s s w o r d :  x Q m R 4 2 a b C D 5 k']);
      expect(r.password, secret);
      expect(r.passwordCandidates, isNot(contains('Password:$secret')));
    });

    test('the letter-spaced value alone', () {
      final pass = p.parse(['x Q m R 4 2 a b C D 5 k']);
      expect(pass.password, secret);
      expect(pass.email, isNull);
      final mail = p.parse(['a b c d e 0 7 @ h o t m a i l . c o m']);
      expect(mail.email, addr);
      expect(mail.password, isNull);
    });

    test('ordinary lines are not closed up', () {
      final r = p.parse([
        'Sign in to your account',
        'a b',
        addr,
        secret,
        'Forgot your password',
      ]);
      expectLogin(r);
      expect(
        r.chips,
        containsAll(['Sign in to your account', 'Forgot your password']),
      );
    });
  });

  group('Unicode spaces and widths', () {
    test('no-break spaces round the values', () {
      expectLogin(p.parse([' $addr ', '  $secret ']));
    });

    test('zero-width and direction marks inside a value', () {
      expectLogin(p.parse(['‏abcde07​@hot­mail.com‎', '﻿xQmR‌42ab‍CD5k⁠']));
    });

    test('an ideographic space parts two values on one line', () {
      expectLogin(p.parse(['$addr　$secret']));
      expectLogin(p.parse(['$addr　　$secret']));
    });

    test('other Unicode spaces count as spaces', () {
      for (final space in [' ', ' ', ' ', ' ', ' ']) {
        expectLogin(p.parse(['$addr$space$space$secret']), reason: space);
        expectLogin(p.parse(['$addr$space$secret']), reason: space);
      }
    });

    test('full-width forms are ASCII', () {
      expectLogin(p.parse(['ａｂｃｄｅ０７＠ｈｏｔｍａｉｌ．ｃｏｍ', 'ｘＱｍＲ４２ａｂＣＤ５ｋ']));
    });

    test('full-width and spaced at once', () {
      expectLogin(
        p.parse([
          'ａ　ｂ　ｃ　ｄ　ｅ　０　７　＠　ｈ　ｏ'
              '　ｔ　ｍ　ａ　ｉ　ｌ　．　ｃ　ｏ　ｍ',
          secret,
        ]),
      );
    });

    test('control characters are dropped, not read as letters', () {
      expectLogin(p.parse(['abc\u0000de07@hotmail.com', 'xQmR42\u0007abCD5k']));
      expectLogin(p.parse(['$addr\u000B$secret']));
    });

    test('a tab parts two values', () {
      expectLogin(p.parse(['$addr\t$secret']));
      expectLogin(p.parse(['$addr\t|\t$secret\t|']));
    });

    test('two or more spaces part two values', () {
      expectLogin(p.parse(['$addr  $secret']));
      expectLogin(p.parse(['$addr          $secret']));
    });

    test('line separators of any kind end a line', () {
      expectLogin(p.parseText('$addr $secret'));
      expectLogin(p.parseText('$addr\r$secret'));
      expectLogin(p.parseText('$addr\u0085$secret'));
    });

    test('ligatures spell out', () {
      expect(p.parse(['ﬁsh12345@hotmail.com']).email, 'fish12345@hotmail.com');
    });
  });

  group('two values on one line', () {
    test('address, one space, password', () {
      expectLogin(p.parse(['$addr $secret']));
    });

    test('password, one space, address', () {
      expectLogin(p.parse(['$secret $addr']));
    });

    test('separators and junk between and after them', () {
      for (final line in [
        '$addr | $secret',
        '$addr | $secret |',
        '| $addr $secret',
        '$addr  |  $secret',
        '- $addr - $secret',
      ]) {
        expectLogin(p.parse([line]), reason: line);
      }
    });

    test('a noisy address and a password that OCR cut in two', () {
      expectLogin(p.parse(['abcde07 @ hotmail .com  xQmR42 abCD5k']));
      expectLogin(p.parse(['$addr  xQmR42 abCD5k']));
    });

    test('an address with a cut TLD and a password', () {
      expectLogin(p.parse(['abcde07@hotmail.co $secret']));
    });

    test('words next to an address are not a password', () {
      for (final line in [
        '$addr Verified',
        'Verified $addr',
        '$addr is not verified',
        'Signed in as $addr',
        '$addr Resend',
      ]) {
        final r = p.parse([line]);
        expect(r.email, addr, reason: line);
        expect(r.password, isNull, reason: line);
      }
    });
  });

  group('junk and bullets round values', () {
    for (final junk in ['|', '_', '.', '~', ',', ';', ' |', ' _', ' .', ' ~']) {
      test('"$junk" after both values', () {
        final r = p.parse(['$addr$junk', '$secret$junk']);
        expectLogin(r, reason: junk);
        expect(r.chips, containsAll([addr, secret]));
      });
    }

    for (final lead in [
      '•',
      '• ',
      '- ',
      '– ',
      '> ',
      '* ',
      '· ',
      '● ',
      '"',
      "'",
    ]) {
      test('"$lead" before both values', () {
        expectLogin(p.parse(['$lead$addr', '$lead$secret']), reason: lead);
      });
    }

    test('quotes round both values', () {
      expectLogin(p.parse(['"$addr"', '"$secret"']));
      expectLogin(p.parse(['“$addr”', '“$secret”']));
      expectLogin(p.parse(["'$addr'", "'$secret'"]));
      expectLogin(p.parse(['($addr)', '($secret)']));
    });

    test('the password as read stays an option', () {
      final r = p.parse([addr, '$secret|']);
      expect(r.password, secret);
      expect(r.passwordCandidates.take(2), [secret, '$secret|']);
      final dot = p.parse([addr, '$secret.']);
      expect(dot.password, secret);
      expect(dot.passwordCandidates, contains('$secret.'));
    });

    test('a line of nothing but junk is skipped', () {
      for (final junk in ['|', '_', '~', '.', '•', '- -', '| |']) {
        expectLogin(p.parse([addr, junk, secret]), reason: junk);
      }
    });
  });

  group('characters that look alike', () {
    test('1, l, I, 0 and O in the local part are kept as read', () {
      for (final local in [
        'abcdel7',
        'abcdeI7',
        'abcde17',
        'abcdeO7',
        'abcde07',
        'l23456',
        'I23456',
        'O0O0O0',
        'ab1lI0O',
      ]) {
        final r = p.parse(['$local@hotmail.com', secret]);
        expectLogin(r, email: '$local@hotmail.com', reason: local);
      }
    });

    test('the same in an address with a dotted local part', () {
      expectLogin(
        p.parse(['i.l0ve1@hotmail.com', secret]),
        email: 'i.l0ve1@hotmail.com',
      );
    });

    test('the provider\'s name is repaired and the local part is not', () {
      for (final domain in [
        'hotmai1.com',
        'hotmaiI.com',
        'h0tmail.com',
        'hotrnail.com',
        'HOTMAIL.COM',
      ]) {
        final r = p.parse(['abcdel7@$domain', secret]);
        expectLogin(r, email: 'abcdel7@hotmail.com', reason: domain);
      }
    });

    test('the unrepaired reading stays an option', () {
      final r = p.parse(['abcde07@hotmai1.com', secret]);
      expect(r.emailCandidates, [addr, 'abcde07@hotmai1.com']);
    });
  });

  group('addresses cut or split by OCR', () {
    test('a cut TLD of a provider is completed', () {
      for (final tld in ['co', 'c', 'cm']) {
        expectLogin(p.parse(['abcde07@hotmail.$tld', secret]), reason: tld);
      }
      expectLogin(
        p.parse(['abcde07@gmail.co', secret]),
        email: 'abcde07@gmail.com',
      );
    });

    test('and the cut one stays an option', () {
      final r = p.parse(['abcde07@hotmail.co', secret]);
      expect(r.emailCandidates.first, addr);
      expect(
        r.emailCandidates,
        containsAll(['abcde07@hotmail.co.uk', 'abcde07@hotmail.co']),
      );
    });

    test('a cut TLD of any other domain is not completed', () {
      expect(
        p.parse(['abcde07@example.co', secret]).email,
        'abcde07@example.co',
      );
      expect(
        p.parse(['abcde07@hotmail.cam', secret]).email,
        'abcde07@hotmail.cam',
      );
    });

    test('a space round the dot of a country code', () {
      for (final raw in [
        'abcde07@hotmail.co. uk',
        'abcde07@hotmail.co .uk',
        'abcde07@hotmail.co . uk',
        'abcde07@hotmail .co.uk',
      ]) {
        final r = p.parse([raw, secret]);
        expectLogin(r, email: 'abcde07@hotmail.co.uk', reason: raw);
      }
    });

    test('a sentence after an address does not become a country code', () {
      expect(p.parse(['abcde07@hotmail.com. Next']).email, addr);
      expect(p.parse(['abcde07@hotmail.co. Next']).email, addr);
    });

    test('the dot lost between provider and TLD', () {
      for (final raw in [
        'abcde07@hotmail com',
        'abcde07@hotmailcom',
        'abcde07@hotmailicom',
        'abcde07@hotmail..com',
        'abcde07@hotmail, com',
      ]) {
        expectLogin(p.parse([raw, secret]), reason: raw);
      }
    });

    test('a space inside the provider\'s name', () {
      for (final raw in [
        'abcde07@h otmail.com',
        'abcde07@hot mail.com',
        'abcde07@hotm ail.com',
        'abcde07 @ hot mail . com',
      ]) {
        expectLogin(p.parse([raw, secret]), reason: raw);
      }
    });

    test('a space in the local part: short ends are joined', () {
      for (final (raw, mail) in [
        ('abcde0 7@hotmail.com', addr),
        ('abcde 07@hotmail.com', addr),
        ('kmnop1 2@hotmail.com', 'kmnop12@hotmail.com'),
        ('zxcvb 56@hotmail.com', 'zxcvb56@hotmail.com'),
        ('qwert-1 4@live.com', 'qwert-14@live.com'),
        ('tyuio2 1@hotmail.es', 'tyuio21@hotmail.es'),
      ]) {
        final r = p.parse([raw, secret]);
        expectLogin(r, email: mail, reason: raw);
        expect(r.emailCandidates.first, mail, reason: raw);
      }
    });

    test('a stray stroke inside the local part does not leave a tail', () {
      // "abcdeO/7": the "7" alone is not the address.
      final r = p.parse(['abcdeO/7@hotmail.com', secret]);
      expect(r.email, 'abcdeO7@hotmail.com');
      expect(r.username, 'abcdeO7@hotmail.com');
      expect(r.password, secret);
      expect(r.emailCandidates, ['abcdeO7@hotmail.com']);
      expect(r.quality, greaterThan(0.99));
      // The stroke's own text is not offered as a password.
      expect(r.passwordCandidates, [secret]);
      for (final raw in [
        'abcdeO|7@hotmail.com',
        'abcdeO!7@hotmail.com',
        'abcdeO/07@hotmail.com',
      ]) {
        final l = p.parse([raw, secret]);
        expect(l.email, startsWith('abcdeO'), reason: raw);
        expect(l.email, endsWith('7@hotmail.com'), reason: raw);
        expect(l.email!.length, greaterThan(12), reason: raw);
      }
      // A longer rest is an address of its own, and a label is no word of it.
      expect(
        p.parse(['abc/de07@hotmail.com', secret]).email,
        endsWith('@hotmail.com'),
      );
      expect(p.parse(['Email/7@hotmail.com', secret]).email, '7@hotmail.com');
    });

    test('the half is still offered as an address', () {
      final r = p.parse(['abcde0 7@hotmail.com', secret]);
      expect(r.emailCandidates, [addr, '7@hotmail.com']);
    });

    test('a longer local part only offers the joined one', () {
      final r = p.parse(['sam ple_mail42@hotmail.com', secret]);
      expect(r.email, 'ple_mail42@hotmail.com');
      expect(r.emailCandidates, contains('sample_mail42@hotmail.com'));
      final dotted = p.parse(['jdoe. test99@hotmail.com', secret]);
      expect(dotted.email, 'test99@hotmail.com');
      expect(dotted.emailCandidates, contains('jdoe.test99@hotmail.com'));
    });

    test('a short address after a password on one line stays apart', () {
      final r = p.parse(['$secret jo@hotmail.com']);
      expect(r.email, 'jo@hotmail.com');
      expect(r.password, secret);
    });

    test('a greeting is not part of the address', () {
      final r = p.parse(['Hello x@hotmail.com']);
      expect(r.password, isNull);
      expect(r.email, isNotNull);
    });

    test('the local part and domain both split', () {
      final r = p.parse(['sample_mail4 2@h otmail.co. uk', 'hG3fE9aXo00l']);
      expect(r.email, 'sample_mail42@hotmail.co.uk');
      expect(r.password, 'hG3fE9aXo00l');
    });

    test('an address damaged by a symbol is offered for correction', () {
      final r = p.parse(['abcde0/@hotmail.com', secret]);
      expect(r.email, 'abcde0/@hotmail.com');
      expect(r.password, secret);
      expect(r.url, isNull);
      expect(r.title, isNull);
      expect(r.emailCandidates, ['abcde0/@hotmail.com']);
    });
  });

  group('a password OCR cut in two', () {
    test('two tokens below an address are one password', () {
      final r = p.parse([addr, 'xQmR42 abCD5k']);
      expectLogin(r);
      expect(r.passwordCandidates, containsAll(['xQmR42', 'abCD5k']));
    });

    test('two tokens above an address', () {
      expectLogin(p.parse(['xQmR42 abCD5k', addr]));
    });

    test('with the address noisy', () {
      expectLogin(p.parse(['abcde07 @ hotmail . com', 'xQmR42 abCD5k']));
    });

    test('three tokens', () {
      final r = p.parse([addr, 'xQmR 42abC D5k']);
      expectLogin(r);
      expect(r.passwordCandidates.first, secret);
    });

    test('any split of a mixed password under an address', () {
      for (var i = 4; i <= 9; i++) {
        final r = p.parse([
          addr,
          '${secret.substring(0, i)} ${secret.substring(i)}',
        ]);
        expectLogin(r, reason: 'split at $i');
      }
    });

    test('next to an address OCR damaged', () {
      for (final broken in [
        'abcde07@hotmail com 2',
        'abcde07Chotmail. com',
        'abcde07( - C hotmail.com',
        'abcde07@',
      ]) {
        final r = p.parse([broken, 'xQmR42 abCD5k']);
        expect(r.password, secret, reason: broken);
        expect(r.url, isNull, reason: broken);
      }
    });

    test('alone, when it only reads as a password joined', () {
      final r = p.parse(['xQmR42 abCD5k']);
      expect(r.password, secret);
      expect(r.email, isNull);
    });

    test('in a crop of a few lines without an address', () {
      final r = p.parse(['abcde07( a . -', 'hotmail.com', 'tH8sNa3D eR9u']);
      expect(r.password, 'tH8sNa3DeR9u');
    });

    test('words under an address stay words', () {
      for (final line in [
        'Forgot password?',
        'Remember me',
        'Notes: none',
        'Meeting 10:45',
        'Show password',
        'Sign in',
        'Next page',
        'Create account',
      ]) {
        expect(p.parse([addr, line]).password, isNull, reason: line);
      }
    });

    test('a line of ordinary text is not joined without an address', () {
      for (final line in ['Invoice 2024', 'Hello world', 'Page 2 of 12']) {
        expect(p.parse([line]).password, isNull, reason: line);
      }
    });
  });

  group('only one of the two is read', () {
    test('only the address', () {
      final r = p.parse([addr]);
      expect(r.email, addr);
      expect(r.username, addr);
      expect(r.password, isNull);
      expect(r.emailCandidates, [addr]);
      expect(r.passwordCandidates, isEmpty);
    });

    test('only the password', () {
      final r = p.parse([secret]);
      expect(r.password, secret);
      expect(r.email, isNull);
      expect(r.username, isNull);
      expect(r.passwordCandidates, [secret]);
      expect(r.emailCandidates, isEmpty);
    });

    test('the lone value with every kind of noise', () {
      for (final raw in [
        '| $secret |',
        '• $secret',
        '"$secret"',
        ' $secret ',
        'x Q m R 4 2 a b C D 5 k',
        'xQmR42 abCD5k',
        'ｘＱｍＲ４２ａｂＣＤ５ｋ',
      ]) {
        final r = p.parse([raw]);
        expect(r.password, secret, reason: raw);
        expect(r.email, isNull, reason: raw);
      }
      for (final raw in [
        '| $addr |',
        '• $addr',
        'abcde07 @ hotmail . com',
        'abcde07©hotmail.com',
        'a b c d e 0 7 @ h o t m a i l . c o m',
        'ａｂｃｄｅ０７＠ｈｏｔｍａｉｌ．ｃｏｍ',
        'abcde07@hotmail.co',
      ]) {
        final r = p.parse([raw]);
        expect(r.email, addr, reason: raw);
        expect(r.password, isNull, reason: raw);
      }
    });

    test('the address with unrelated text', () {
      for (final lines in [
        [addr, 'Sign in'],
        ['Email', addr],
        [addr, 'Next', 'Forgot password?'],
        ['10:45', addr, 'Done'],
      ]) {
        final r = p.parse(lines);
        expect(r.email, addr, reason: '$lines');
        expect(r.password, isNull, reason: '$lines');
      }
    });

    test('a broken address never becomes the password', () {
      for (final raw in [
        'abcde07@hotmail',
        'abcde07@hotmail com',
        'abcde07@hotnail com',
        'abcde07Chotmail. com',
        'abcde07@hotnellcom',
        'abcde07( - C hotmail.com',
        'abcde07@',
      ]) {
        expect(p.parse([raw]).password, isNull, reason: raw);
      }
    });

    test('a password with an "@" is still a password', () {
      expect(p.parse(['P@ssw0rd2024']).password, 'P@ssw0rd2024');
      expect(p.parse([addr, 'P@ssw0rd2024']).password, 'P@ssw0rd2024');
    });
  });

  group('the line beside the address wins', () {
    test('over a longer token elsewhere', () {
      final r = p.parse([
        'Settings',
        'Two-stepverification is turned on',
        addr,
        secret,
        'Last signed in from Windows, Chrome',
      ]);
      expectLogin(r);
    });

    test('over a longer token from a broken address on the same line', () {
      for (final broken in [
        'abcde0/@hotmail.com',
        'abcde07Chotmail. com',
        'abcde07@hotnail com',
        'abcde07@hotnellcom',
      ]) {
        final r = p.parse([broken, secret]);
        expect(r.password, secret, reason: broken);
        expect(r.url, isNull, reason: broken);
      }
    });

    test('the password above the address', () {
      expectLogin(p.parse([secret, addr]));
    });

    test('hyphenated words are not password-like', () {
      final r = p.parse(['Two-stepverification', secret]);
      expect(r.password, secret);
    });

    test('a password alone on its line beats a token inside a sentence', () {
      final r = p.parse(['Welcome Back-Home2024x', 'Pass', 'kP9mQ2vL7wXz']);
      expect(r.password, 'kP9mQ2vL7wXz');
    });

    test('a label with its value glued on is not offered', () {
      final r = p.parse(['Notes', 'Password:$secret']);
      expect(r.password, secret);
      expect(r.passwordCandidates, isNot(contains('Password:$secret')));
    });
  });

  group('candidates', () {
    test('a clean pair has one of each', () {
      final r = p.parse([addr, secret]);
      expect(r.emailCandidates, [addr]);
      expect(r.passwordCandidates, [secret]);
    });

    test('the answer is first and nothing repeats', () {
      for (final lines in [
        [addr, secret],
        ['$addr|', '$secret|'],
        ['abcde07@hotmail.co', 'xQmR42 abCD5k'],
        ['Email: $addr', 'Password: $secret'],
        ['abcde0 7@hotmail.com', secret, 'Zt9LqW3vBOyH'],
      ]) {
        final r = p.parse(lines);
        expect(r.emailCandidates.first, r.email, reason: '$lines');
        expect(r.passwordCandidates.first, r.password, reason: '$lines');
        expect(
          r.emailCandidates.toSet().length,
          r.emailCandidates.length,
          reason: '$lines',
        );
        expect(
          r.passwordCandidates.toSet().length,
          r.passwordCandidates.length,
          reason: '$lines',
        );
      }
    });

    test('nothing found, nothing offered', () {
      final r = p.parse(['Sign in', 'Next']);
      expect(r.emailCandidates, isEmpty);
      expect(r.passwordCandidates, isEmpty);
      final empty = p.parse([]);
      expect(empty.emailCandidates, isEmpty);
      expect(empty.passwordCandidates, isEmpty);
    });

    test('every other address in the text follows the first', () {
      final r = p.parse(['alice@example.com', 'bob@example.org', secret]);
      expect(r.email, 'alice@example.com');
      expect(r.emailCandidates, ['alice@example.com', 'bob@example.org']);
    });

    test('the address of a label comes first, then the other one', () {
      final r = p.parse(['Username: alice@example.com', 'Recovery: $addr']);
      expect(r.username, 'alice@example.com');
      expect(r.emailCandidates, ['alice@example.com', addr]);
    });

    test('other password-like tokens are offered after the first', () {
      final r = p.parse([addr, secret, 'Zt9LqW3vBOyH', 'hG3fE9aXo00l']);
      expect(r.password, secret);
      expect(r.passwordCandidates, [secret, 'Zt9LqW3vBOyH', 'hG3fE9aXo00l']);
    });

    test('the pieces of a joined password are offered last', () {
      final r = p.parse([addr, 'xQmR42 abCD5k']);
      expect(r.passwordCandidates, [secret, 'xQmR42', 'abCD5k']);
    });

    test('a weak word beside the address is offered when nothing else is', () {
      final r = p.parse([addr, 'mangotango']);
      expect(r.password, 'mangotango');
      expect(r.passwordCandidates, ['mangotango']);
    });

    test('neither list passes the cap', () {
      final r = p.parse([
        for (var i = 0; i < 40; i++) 'user$i@example$i.com',
        for (var i = 0; i < 40; i++) 'xQmR42abCD${i}k$i',
      ]);
      expect(r.emailCandidates.length, OcrCredentialParser.maxCandidates);
      expect(r.passwordCandidates.length, OcrCredentialParser.maxCandidates);
    });

    test('the address is never offered as a password', () {
      final r = p.parse([addr, secret, 'abcde07@hotmail .com']);
      expect(r.passwordCandidates, isNot(contains(addr)));
      for (final c in r.passwordCandidates) {
        expect(c.contains('@'), isFalse, reason: c);
      }
    });

    test('OcrResult still builds without them', () {
      const r = OcrResult(chips: ['a'], email: addr, password: secret);
      expect(r.emailCandidates, isEmpty);
      expect(r.passwordCandidates, isEmpty);
      final copy = r.copyWith(
        emailCandidates: [addr],
        passwordCandidates: [secret, 'other'],
      );
      expect(copy.emailCandidates, [addr]);
      expect(copy.passwordCandidates, [secret, 'other']);
      expect(copy.copyWith(title: 'Site').passwordCandidates, [
        secret,
        'other',
      ]);
      expect(copy.email, addr);
    });
  });

  group('quality', () {
    final both = p.parse([addr, secret]);
    final mailOnly = p.parse([addr]);
    final passOnly = p.parse([secret]);
    final none = p.parse(['Sign in', 'Next']);

    test('nothing found scores 0 and a login scores high', () {
      expect(none.quality, 0);
      expect(p.parse([]).quality, 0);
      expect(both.quality, greaterThan(0.9));
      expect(both.quality, lessThanOrEqualTo(1));
    });

    test('both found always beats one of them', () {
      expect(both.quality, greaterThan(mailOnly.quality));
      expect(both.quality, greaterThan(passOnly.quality));
      expect(mailOnly.quality, greaterThan(none.quality));
      expect(passOnly.quality, greaterThan(none.quality));
      // Even a weak pair beats a strong single value.
      final weak = p.parse(['a@b.co', 'abcd']);
      expect(weak.email, isNotNull);
      expect(weak.password, isNotNull);
      expect(weak.quality, greaterThan(mailOnly.quality));
      expect(weak.quality, greaterThan(passOnly.quality));
      expect(mailOnly.quality, lessThanOrEqualTo(0.5));
      expect(passOnly.quality, lessThanOrEqualTo(0.5));
      expect(weak.quality, greaterThanOrEqualTo(0.7));
    });

    test('a plausible password beats a weak one', () {
      final weak = p.parse([addr, 'mango']);
      expect(weak.password, 'mango');
      expect(both.quality, greaterThan(weak.quality));
      final junk = p.parse([addr, '$secret|']);
      expect(junk.password, secret);
      expect(junk.quality, both.quality);
    });

    test('a plausible address beats an odd one', () {
      final odd = p.parse(['abcde0/@hotmail.com', secret]);
      expect(odd.email, isNotNull);
      expect(both.quality, greaterThan(odd.quality));
      final strange = p.parse(['abcde07@unknownhost.zzz', secret]);
      expect(strange.email, isNotNull);
      expect(both.quality, greaterThan(strange.quality));
    });

    test('the pass that read both beats the pass that read one', () {
      final passes = [
        p.parse(['a b c d e 0 7 @ h o t m a i l . c o m']),
        p.parse([addr, secret]),
        p.parse([secret]),
        p.parse(['|']),
      ];
      final best = passes.reduce((a, b) => b.quality > a.quality ? b : a);
      expect(best.email, addr);
      expect(best.password, secret);
    });

    test('it follows the fields of a rebuilt result', () {
      const mail = OcrResult(chips: [], email: addr);
      const full = OcrResult(chips: [], email: addr, password: secret);
      expect(full.quality, greaterThan(mail.quality));
      expect(full.copyWith(title: 'x').quality, full.quality);
      expect(const OcrResult(chips: []).quality, 0);
      expect(
        const OcrResult(
          chips: [],
          username: 'alice_92',
          password: secret,
        ).quality,
        greaterThan(const OcrResult(chips: [], password: secret).quality),
      );
    });

    test('it stays between 0 and 1', () {
      for (final lines in [
        <String>[],
        [''],
        [addr, secret],
        ['$addr $secret', addr, secret],
        ['a' * 300, '@', '@@@@', '....'],
        [for (var i = 0; i < 50; i++) 'user$i@example.com $secret$i'],
      ]) {
        final q = p.parse(lines).quality;
        expect(q, inInclusiveRange(0, 1), reason: '$lines');
      }
    });
  });

  group('realistic raw output of the dark-mode crop', () {
    for (final (lines, email, password) in <(List<String>, String?, String?)>[
      ([addr, secret], addr, secret),
      (['abcde07 @hotmail.com', 'xQmR42 abCD5k'], addr, secret),
      (['abcde07@hotmail .com', secret], addr, secret),
      (['abcde0 7@hotmail.com', secret], addr, secret),
      (
        ['kmnop1 2@hotmail.com', 'Zt9LqW3vBOyH'],
        'kmnop12@hotmail.com',
        'Zt9LqW3vBOyH',
      ),
      (
        ['tyuio2 1@hotmail.es', 'Nb4Jd7QqPpic'],
        'tyuio21@hotmail.es',
        'Nb4Jd7QqPpic',
      ),
      (
        ['zxcvb5 6@hotmail.com', 'tH8sNa3 DeR9u'],
        'zxcvb56@hotmail.com',
        'tH8sNa3DeR9u',
      ),
      (
        ['qwert-14@live.com', 'gBv 5Cz2M xA7j'],
        'qwert-14@live.com',
        'gBv5Cz2MxA7j',
      ),
      (
        ['fghjk88@hot mail.com', 'mMS5uVw2 SsZz'],
        'fghjk88@hotmail.com',
        'mMS5uVw2SsZz',
      ),
      (
        ['jdoe.test99 @h otmail.com', 'pR7wXn2KfL8q'],
        'jdoe.test99@hotmail.com',
        'pR7wXn2KfL8q',
      ),
      (['abcde07@hotmail.co. uk', secret], 'abcde07@hotmail.co.uk', secret),
      (['abcde07@hotmailcom', secret], addr, secret),
      (['abcde07@hotmail com', secret], addr, secret),
      (['abcde07@hotmail.com |', '$secret |'], addr, secret),
      (['• $addr', '• $secret'], addr, secret),
      (['abcde0/@hotmail.com', secret], 'abcde0/@hotmail.com', secret),
      (['abcde07Chotmail. com', secret], null, secret),
      (['abcde07( - C hotmail.com', 'xQmR42 abCD5k'], null, secret),
      (['tyuio2! @hotmail.es', 'Nb4Jd7QqPp 1c'], null, 'Nb4Jd7QqPp1c'),
      (
        [
          'Settings',
          'Account overview',
          'Security',
          'Sign-in methods',
          'Two-stepverification is turned on',
          addr,
          secret,
          'Last signed in from Windows, Chrome',
          'Notifications Billing Privacy Devices',
        ],
        addr,
        secret,
      ),
    ]) {
      test('$lines', () {
        final r = p.parse(lines);
        expect(r.email, email);
        expect(r.password, password);
        expect(r.url, isNull);
        if (email != null) expect(r.emailCandidates.first, email);
        if (password != null) expect(r.passwordCandidates.first, password);
      });
    }
  });

  group('addresses split over two lines', () {
    test('the "@" ends the first line', () {
      expectLogin(p.parse(['abcde07@', 'hotmail.com', secret]));
    });

    test('the TLD starts the second line', () {
      expectLogin(p.parse(['abcde07@hotmail', '.com', secret]));
      expectLogin(p.parse(['abcde07@hotmail.', '.com', secret]));
      expectLogin(p.parse(['abcde07@hotmail', 'com', secret]));
    });

    test('with OCR junk after the first half', () {
      expectLogin(p.parse(['abcde07 @hotmail. - -', '.com', secret]));
      expectLogin(p.parse(['abcde07 @hotmail |', '.com', secret]));
    });

    test('with the password above', () {
      expectLogin(p.parse([secret, 'abcde07@', 'hotmail.com']));
    });

    test('a country code on the second line', () {
      expectLogin(
        p.parse(['abcde07@hotmail', '.co.uk', secret]),
        email: 'abcde07@hotmail.co.uk',
      );
    });

    test('other next lines are not part of the address', () {
      for (final (first, second) in [
        ('abcde07@', 'Next'),
        ('abcde07@', 'Forgot password?'),
        ('abcde07@hotmail', 'Next'),
        ('abcde07@hotmail', 'Sign in'),
        ('abcde07@hotmail', 'Buy'),
        ('Follow us @', 'twitter.com'),
        ('Email abcde07@', 'hotmail.com'),
      ]) {
        final r = p.parse([first, second]);
        expect(r.email, isNull, reason: '$first / $second');
      }
    });
  });

  group('what an engine adds round the two values', () {
    test('wider gaps inside letter-spaced text', () {
      expectLogin(
        p.parse([
          'a b c d e 0 7  @  h o t m a i l . c o m',
          'x Q m R 4 2  a b C D  5 k',
        ]),
      );
    });

    test('a letter-spaced pair parted by a wider gap is still two values', () {
      expectLogin(
        p.parse([
          'a b c d e 0 7 @ h o t m a i l . c o m   x Q m R 4 2 a b C D 5 k',
        ]),
      );
    });

    test('the eye icon of the password field read as a letter', () {
      for (final icon in ['O', 'o', 'Q', '0', '@', '©']) {
        expectLogin(p.parse([addr, '$secret $icon']), reason: icon);
        expectLogin(p.parse([addr, '$icon $secret']), reason: icon);
        expectLogin(p.parse(['$addr $icon', '$secret $icon']), reason: icon);
      }
    });

    test('and the password with the icon stays an option', () {
      final r = p.parse([addr, '$secret O']);
      expect(r.password, secret);
      expect(r.passwordCandidates, contains('${secret}O'));
    });

    test('a last letter that is no icon belongs to the password', () {
      final r = p.parse([addr, 'xQmR42abCD5 k']);
      expect(r.password, secret);
      final b = p.parse([addr, 'x QmR42abCD5k']);
      expect(b.password, secret);
    });

    test('a capital at the start of a provider\'s address is dropped', () {
      for (final raw in ['Abcde07@hotmail.com', 'Abcde07@Hotmail.com']) {
        final r = p.parse([raw, secret]);
        expectLogin(r, reason: raw);
        expect(r.emailCandidates, [addr, 'Abcde07@hotmail.com'], reason: raw);
      }
    });

    test('other capitals are left as read', () {
      for (final mail in [
        'Ibcde07@hotmail.com',
        'Obcde07@hotmail.com',
        'abcdeI7@hotmail.com',
        'AbcdeI7@hotmail.com',
        'ABCDE07@hotmail.com',
        'AbCde07@hotmail.com',
        'Abcde07@example.com',
      ]) {
        expectLogin(p.parse([mail, secret]), email: mail, reason: mail);
      }
    });

    test('plain words are not guessed as the password', () {
      for (final lines in [
        ['Settings', 'Privacy', 'Notifications', 'Sign out'],
        ['Notifications'],
        ['Account Notifications', 'Authentication'],
        ['SETTINGS', 'NOTIFICATIONS'],
        ['notifications'],
      ]) {
        expect(p.parse(lines).password, isNull, reason: '$lines');
      }
    });

    test('a word that is the password still wins beside the address', () {
      expect(p.parse([addr, 'Notifications']).password, 'Notifications');
    });

    test('words that are not the start of a local part stay words', () {
      expect(p.parse(['Email 7@hotmail.com']).email, '7@hotmail.com');
      expect(p.parse(['2024-05-01 7@hotmail.com']).email, '7@hotmail.com');
      expect(p.parse(['10:45 7@hotmail.com']).email, '7@hotmail.com');
    });

    test('a dotted local part cut in the middle of a word', () {
      final r = p.parse(['jdoe.tes t99@ho tmail.com', 'pR7wXn2KfL8q']);
      expectLogin(
        r,
        email: 'jdoe.test99@hotmail.com',
        password: 'pR7wXn2KfL8q',
      );
      expect(r.emailCandidates, contains('t99@hotmail.com'));
    });
  });

  group('bounded work', () {
    test('the new repairs keep text linear', () {
      final watch = Stopwatch()..start();
      for (final line in [
        'abcde07Chotmail. com\n',
        'abcde0 7@h otmail.co. uk\n',
        'gBv 5Cz2M xA7j\n',
        'abcde07@hotmail com\n',
        'a b c d e 0 7 @ h o t m a i l . c o m\n',
        'abc@ ',
        'hotmail hotmail ',
        '${'abcdefghij0123456789 ' * 3}\n',
      ]) {
        final r = p.parseText(line * (OcrCredentialParser.maxInputLength));
        expect(r.chips.length, lessThanOrEqualTo(OcrCredentialParser.maxChips));
        expect(
          r.emailCandidates.length,
          lessThanOrEqualTo(OcrCredentialParser.maxCandidates),
        );
        expect(
          r.passwordCandidates.length,
          lessThanOrEqualTo(OcrCredentialParser.maxCandidates),
        );
      }
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('thousands of short lines', () {
      final watch = Stopwatch()..start();
      final r = p.parse([
        for (var i = 0; i < 6000; i++) i.isEven ? 'a b' : 'x@y',
        addr,
        secret,
      ]);
      expect(r.chips.length, lessThanOrEqualTo(OcrCredentialParser.maxChips));
      expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
    });

    test('the 16 KB cap still holds', () {
      final filler = 'lorem ipsum ' * (OcrCredentialParser.maxInputLength ~/ 6);
      expect(p.parseText('$filler\n$addr\n$secret').email, isNull);
      expect(p.parseText('$addr\n$secret\n$filler'), isA<OcrResult>());
      expectLogin(p.parseText('$addr\n$secret\n$filler'));
    });
  });
}
