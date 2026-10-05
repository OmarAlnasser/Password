import 'package:flutter_test/flutter_test.dart';
import 'package:vaultsnap/data/models/vault_entry.dart';
import 'package:vaultsnap/services/autofill_matcher.dart';

void main() {
  final entries = [
    VaultEntry(id: '1', title: 'Example', url: 'https://example.com/login'),
    VaultEntry(id: '2', title: 'Bank app', url: 'androidapp://com.bank.app'),
    VaultEntry(id: '3', title: 'Bare', url: 'mail.example.org'),
    VaultEntry(id: '4', title: 'Localhost', url: 'http://localhost'),
  ];
  List<String> ids(List<VaultEntry> l) => l.map((e) => e.id).toList();

  test('exact and subdomain matches', () {
    expect(ids(AutofillMatcher.match(entries, domain: 'example.com')), ['1']);
    expect(ids(AutofillMatcher.match(entries, domain: 'www.example.com')), [
      '1',
    ]);
    expect(
      ids(AutofillMatcher.match(entries, domain: 'accounts.example.com')),
      ['1'],
    );
    expect(ids(AutofillMatcher.match(entries, domain: 'mail.example.org')), [
      '3',
    ]);
  });

  test('look-alike domains do not match', () {
    for (final d in [
      'evil-example.com',
      'example.com.evil.io',
      'xample.com',
      'example.co',
      'example.org',
    ]) {
      expect(AutofillMatcher.match(entries, domain: d), isEmpty, reason: d);
    }
  });

  test('apps only match explicitly linked entries', () {
    expect(ids(AutofillMatcher.match(entries, appId: 'com.bank.app')), ['2']);
    expect(AutofillMatcher.match(entries, appId: 'com.bank.app.evil'), isEmpty);
    expect(AutofillMatcher.match(entries, appId: 'com.example'), isEmpty);
  });

  test('single-label hosts never match', () {
    expect(AutofillMatcher.match(entries, domain: 'localhost'), isEmpty);
  });
}
