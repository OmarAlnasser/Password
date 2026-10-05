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
}
