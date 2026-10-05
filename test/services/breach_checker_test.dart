import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vaultsnap/data/models/vault_entry.dart';
import 'package:vaultsnap/services/breach_checker.dart';
import 'package:vaultsnap/services/password_generator.dart';

void main() {
  test('sends only the 5-char SHA-1 prefix with padding header', () async {
    final requests = <http.Request>[];
    // SHA1("password") = 5BAA61E4C9B93F3F0682250B6CF8331B7EE68FD8
    final client = MockClient((req) async {
      requests.add(req);
      return http.Response(
        '1E4C9B93F3F0682250B6CF8331B7EE68FD8:9659365\r\n'
        '0018A45C4D1DEF81644B54AB7F969B88D65:0\r\n'
        'garbage line\r\n',
        200,
      );
    });
    final checker = BreachChecker(client: client);
    expect(await checker.pwnedCount('password'), 9659365);
    expect(
      requests.single.url.toString(),
      'https://api.pwnedpasswords.com/range/5BAA6',
    );
    expect(requests.single.headers['Add-Padding'], 'true');
    expect(requests.single.body, isEmpty);
    // Nothing but the prefix appears anywhere in the request.
    final wire = '${requests.single.url.path}${requests.single.headers}';
    expect(wire.contains('password'), isFalse);
    expect(wire.contains('1E4C9B93'), isFalse);
  });

  test('padding entries (count 0) are not reported as breaches', () async {
    final client = MockClient(
      (_) async => http.Response(
        '${BreachChecker.sha1Hex('x').substring(5)}:0\r\n',
        200,
      ),
    );
    expect(await BreachChecker(client: client).pwnedCount('x'), 0);
  });

  test('prefix responses are cached per run', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('', 200);
    });
    final c = BreachChecker(client: client);
    await c.pwnedCount('password');
    await c.pwnedCount('password');
    expect(calls, 1);
  });

  test('analyzer flags weak, reused and old passwords', () {
    final now = DateTime.utc(2026, 10, 1);
    final entries = [
      VaultEntry(id: '1', title: 'a', password: 'password1'),
      VaultEntry(id: '2', title: 'b', password: 'Gq7!xLm2#pRt9@vZ'),
      VaultEntry(id: '3', title: 'c', password: 'Gq7!xLm2#pRt9@vZ'),
      VaultEntry(
        id: '4',
        title: 'd',
        password: 'Yw3\$kPq8!nBv6&Hs',
        passwordChangedAt: DateTime.utc(2024, 1, 1),
      ),
    ];
    final r = SecurityAnalyzer(StrengthMeter()).analyze(entries, now: now);
    expect(r.weak.map((e) => e.id), ['1']);
    expect(r.reused.single.map((e) => e.id), ['2', '3']);
    expect(r.old.map((e) => e.id), ['4']);
  });
}
