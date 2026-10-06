import 'package:flutter_test/flutter_test.dart';
import 'package:vaultsnap/core/crypto/crypto.dart';
import 'package:vaultsnap/data/models/vault_entry.dart';
import 'package:vaultsnap/services/autofill_matcher.dart';
import 'package:vaultsnap/services/import/import_review.dart';
import 'package:vaultsnap/services/import_export.dart';

// All credentials below are synthetic.
const email = 'abcde07@hotmail.com';
const pw = 'xQmR42abCD5k';
const pw2 = 'Tz8pLq2wXv9m';
const pw3 = 'Hb5nRw3kYs7d';
const appFacet = 'android://dGVzdC1jZXJ0LWhhc2gtMDA_-AbC==@com.example.app/';

void main() {
  late ImportExport ie;
  setUpAll(() async => ie = ImportExport(VaultCrypto(await loadSodium())));

  final t0 = DateTime.utc(2026, 1, 1);
  var nextId = 0;
  VaultEntry row({
    String title = '',
    String url = 'https://example.com/',
    String username = email,
    String password = pw,
    String notes = '',
    DateTime? updated,
  }) => VaultEntry(
    id: 'imp${nextId++}',
    title: title,
    url: url,
    username: username,
    password: password,
    notes: notes,
    createdAt: updated ?? t0,
    updatedAt: updated ?? t0,
    passwordChangedAt: updated ?? t0,
  );

  List<ReviewItem> review(List<VaultEntry> rows, [List<VaultEntry>? vault]) =>
      ImportReview.review(rows, vault ?? const []);

  ReviewItem single(VaultEntry e, [List<VaultEntry>? vault]) =>
      review([e], vault).single;

  const chromeHeader = 'name,url,username,password,note\n';

  group('ImportUrl', () {
    test('https is reduced to its origin; www only leaves the site key', () {
      final u = ImportUrl.parse(
        'https://accounts.google.com/v3/signin/identifier'
        '?continue=https%3A%2F%2Fmail.google.com&ifkv=AbC123xyz#frag',
      );
      expect(u.url, 'https://accounts.google.com/');
      expect(u.siteKey, 'accounts.google.com');
      expect(u.siteName, 'Google');
      expect(u.insecure, isFalse);
      expect(u.invalid, isFalse);

      final w = ImportUrl.parse('HTTPS://WWW.Amazon.co.uk/ap/signin?x=1');
      expect(w.url, 'https://www.amazon.co.uk/');
      expect(w.siteKey, 'amazon.co.uk');
      expect(w.siteName, 'Amazon');
    });

    test('keeps a non-default port, drops user info', () {
      expect(
        ImportUrl.parse('https://example.com:8443/x?y=1').url,
        'https://example.com:8443/',
      );
      expect(
        ImportUrl.parse('https://example.com:443/').url,
        'https://example.com/',
      );
      final u = ImportUrl.parse('https://abcde07:$pw@example.com/login');
      expect(u.url, 'https://example.com/');
      expect(u.url, isNot(contains(pw)));
    });

    test('http keeps scheme and path, drops query and fragment', () {
      final u = ImportUrl.parse('http://192.168.1.1/admin/index.html?a=1#b');
      expect(u.url, 'http://192.168.1.1/admin/index.html');
      expect(u.insecure, isTrue);
      expect(u.siteKey, '192.168.1.1');
      expect(u.siteName, '192.168.1.1');
      expect(
        ImportUrl.parse('http://router.local').url,
        'http://router.local/',
      );
    });

    test('http paths that may carry tokens are dropped', () {
      for (final raw in [
        'http://example.com/reset-password/abc',
        'http://example.com/login;jsessionid=AB12CD34',
        'http://example.com/auth/callback',
        'http://example.com/u/9f8e7d6c5b4a39281706',
        'http://example.com/a/dGVzdA==',
        'http://example.com/${'x' * 40}',
      ]) {
        final u = ImportUrl.parse(raw);
        expect(u.url, 'http://example.com/', reason: raw);
        expect(u.insecure, isTrue, reason: raw);
      }
    });

    test('scheme-less hosts are https; host:port is not a scheme', () {
      expect(ImportUrl.parse('example.com/login').url, 'https://example.com/');
      final l = ImportUrl.parse('localhost:8080');
      expect(l.url, 'https://localhost:8080/');
      expect(l.siteName, 'Localhost');
      expect(ImportUrl.parse('example.com.').siteKey, 'example.com');
    });

    test('Chrome Android facets become androidapp:// links', () {
      final u = ImportUrl.parse(appFacet);
      expect(u.url, 'androidapp://com.example.app');
      expect(u.siteKey, 'androidapp://com.example.app');
      expect(u.siteName, 'Example');
      expect(u.insecure, isFalse);
      // Standard base64 may contain "/" and "+".
      expect(
        ImportUrl.parse('android://ab/c+d==@org.example.notes').url,
        'androidapp://org.example.notes',
      );
      expect(
        ImportUrl.parse('androidapp://com.example.app').url,
        'androidapp://com.example.app',
      );
      expect(
        ImportUrl.parse('iosapp://com.example.ios').siteKey,
        'iosapp://com.example.ios',
      );
      expect(ImportUrl.isAndroidFacet(appFacet), isTrue);
      expect(ImportUrl.isAndroidFacet('androidapp://com.example.app'), isFalse);
    });

    test('unusable URLs are invalid and lose their query', () {
      for (final raw in [
        'chrome://settings/passwords',
        'about:blank',
        'mailto:$email',
        'intent:#Intent;end',
        'https://exa mple.com/',
        'https://',
        'https://.com/',
        'https://a..b.com/',
        'https://-bad.com/',
        'android://hash@not a package/',
        'android://hash@/',
      ]) {
        final u = ImportUrl.parse(raw);
        expect(u.invalid, isTrue, reason: raw);
        expect(u.siteKey, '', reason: raw);
      }
      expect(
        ImportUrl.parse('chrome://settings?token=abc#x').url,
        'chrome://settings',
      );
      expect(
        ImportUrl.parse('https://abcde07:$pw@exa mple.com/').url,
        'https://exa mple.com/',
      );
      expect(ImportUrl.parse('').invalid, isFalse);
      expect(ImportUrl.parse('  ').url, '');
    });

    test('site names', () {
      expect(ImportUrl.siteNameForHost('mail.yahoo.co.jp'), 'Yahoo');
      expect(ImportUrl.siteNameForHost('my-bank.com.sa'), 'My Bank');
      expect(ImportUrl.siteNameForHost('login.example.de'), 'Example');
      expect(ImportUrl.siteNameForHost('abcde07.github.io'), 'Abcde07');
      expect(ImportUrl.siteNameForHost('github.io'), 'Github');
      expect(ImportUrl.siteNameForHost('10.0.0.1'), '10.0.0.1');
      expect(ImportUrl.siteNameForApp('com.android.chrome'), 'Chrome');
      expect(ImportUrl.siteNameForApp('com.google.android.gm'), 'Google');
      expect(ImportUrl.siteNameForApp('org.telegram.messenger'), 'Telegram');
      expect(ImportUrl.siteNameForApp('com.my_bank.mobile'), 'My Bank');
    });
  });

  group('email check', () {
    test('valid and malformed addresses', () {
      for (final ok in [
        email,
        'First.Last+tag@Example.co.uk',
        'a_b-c@sub.example-mail.com',
        'abcde07@xn--mnchen-3ya.de',
      ]) {
        expect(ImportReview.isEmail(ok), isTrue, reason: ok);
      }
      for (final bad in [
        'abcde07@hotmail',
        'abcde07@@hotmail.com',
        'abcde07@hotmail..com',
        'abcde07 @hotmail.com',
        '.abcde07@hotmail.com',
        'abcde07.@hotmail.com',
        'abcde07@hotmail.c',
        'abcde07@hotmail.123',
        'abcde07@-hotmail.com',
        'abcde07@hotmail,com',
        '@hotmail.com',
        'abcde07@',
      ]) {
        expect(ImportReview.isEmail(bad), isFalse, reason: bad);
      }
    });
  });

  group('normalising rows', () {
    test('Chrome host names become site names, own names are kept', () {
      final r = ie.importCsv(
        '${chromeHeader}accounts.google.com,'
        'https://accounts.google.com/signin/v2/identifier?flowName=GlifWebSignIn,'
        '  $email ,$pw,\n'
        'My Work Mail,https://mail.example.org/owa/,abcde07,$pw2,desk\n'
        ',https://www.shop-example.com/login,$email,$pw3,\n',
      );
      final items = review(r.entries);
      expect(items, hasLength(3));
      expect(items[0].entry.title, 'Google');
      expect(items[0].entry.url, 'https://accounts.google.com/');
      expect(items[0].entry.username, email);
      expect(items[0].entry.password, pw);
      expect(items[0].issues, isEmpty);
      expect(items[0].action, ReviewAction.newEntry);
      expect(items[0].include, isTrue);
      expect(items[0].siteName, 'Google');
      expect(items[1].entry.title, 'My Work Mail');
      expect(items[1].entry.notes, 'desk');
      expect(items[1].siteName, 'Example');
      expect(items[2].entry.title, 'Shop Example');
      expect(items[2].siteKey, 'shop-example.com');
      expect(items[2].entry.url, 'https://www.shop-example.com/');
    });

    test('older Chrome exports without a note column', () {
      final r = ie.importCsv(
        'name,url,username,password\n'
        'example.com,https://example.com/,$email,$pw\n',
      );
      final item = review(r.entries).single;
      expect(item.entry.title, 'Example');
      expect(item.entry.notes, '');
      expect(item.action, ReviewAction.newEntry);
    });

    test('passwords are never trimmed or altered', () {
      final item = single(row(password: ' $pw '));
      expect(item.entry.password, ' $pw ');
      expect(item.issues, isEmpty);
    });

    test('Chrome Android app logins are linked for autofill', () {
      final r = ie.importCsv(
        '$chromeHeader'
        'com.example.app,$appFacet,$email,$pw,\n'
        ',android://aGFzaA==@com.example.wallet/,$email,$pw2,\n'
        'Example Notes,android://aGFzaA==@org.example.notes/,$email,$pw3,\n',
      );
      final items = review(r.entries);
      expect(items.map((i) => i.entry.title), [
        'Example',
        'Example',
        'Example Notes',
      ]);
      expect(items.map((i) => i.entry.url), [
        'androidapp://com.example.app',
        'androidapp://com.example.wallet',
        'androidapp://org.example.notes',
      ]);
      expect(items.every((i) => i.issues.isEmpty), isTrue);
      final saved = ImportReview.apply(items);
      expect(
        AutofillMatcher.match(
          saved,
          appId: 'com.example.app',
        ).map((e) => e.password),
        [pw],
      );
    });

    test('a domain-like or URL name is replaced, a real name kept', () {
      expect(single(row(title: 'example.com')).entry.title, 'Example');
      expect(single(row(title: 'www.example.com')).entry.title, 'Example');
      expect(
        single(row(title: 'https://example.com/login')).entry.title,
        'Example',
      );
      expect(single(row(title: 'Example (old)')).entry.title, 'Example (old)');
    });
  });

  group('issues', () {
    test('missing password needs attention, missing username does not', () {
      final noPw = single(row(password: ''));
      expect(noPw.issues, [ReviewIssue.missingPassword]);
      expect(noPw.action, ReviewAction.needsAttention);
      expect(noPw.include, isFalse);
      expect(noPw.hasBlockingIssue, isTrue);

      expect(single(row(password: '   ')).issues, [
        ReviewIssue.missingPassword,
      ]);

      final noUser = single(row(username: '  '));
      expect(noUser.issues, [ReviewIssue.missingUsername]);
      expect(noUser.entry.username, '');
      expect(noUser.action, ReviewAction.newEntry);
      expect(noUser.include, isTrue);
    });

    test('malformed e-mail usernames are flagged but kept', () {
      for (final u in [
        'abcde07@hotmail',
        'abcde07@@hotmail.com',
        'abcde07@hotmail..com',
        'abcde07 @hotmail.com',
        'abcde07＠hotmail.com',
      ]) {
        final item = single(row(username: u));
        expect(item.issues, [ReviewIssue.invalidEmail], reason: u);
        expect(item.include, isTrue, reason: u);
        expect(item.action, ReviewAction.newEntry, reason: u);
      }
      for (final u in [email, '@abcde07', 'abcde07', 'first.last']) {
        expect(single(row(username: u)).issues, isEmpty, reason: u);
      }
    });

    test('username holding a URL', () {
      for (final u in [
        'https://example.com/login',
        'www.example.com',
        'example.com',
        'example.com/',
        'portal.example.org',
        'example.de/login',
      ]) {
        final item = single(row(username: u));
        expect(item.issues, contains(ReviewIssue.usernameIsUrl), reason: u);
        expect(item.issues, isNot(contains(ReviewIssue.invalidEmail)));
        expect(item.action, ReviewAction.needsAttention, reason: u);
        expect(item.include, isFalse, reason: u);
      }
      expect(
        single(row(url: appFacet, username: 'com.example.app')).issues,
        contains(ReviewIssue.usernameIsUrl),
      );
    });

    test('swapped username and password columns', () {
      final item = single(row(username: pw, password: email));
      expect(item.issues, [
        ReviewIssue.passwordLooksLikeEmail,
        ReviewIssue.usernameLooksLikePassword,
      ]);
      expect(item.action, ReviewAction.needsAttention);
      expect(item.include, isFalse);

      // The e-mail in both columns.
      expect(single(row(password: email.toUpperCase())).issues, [
        ReviewIssue.passwordLooksLikeEmail,
      ]);
      // Shifted row: the password ended up in the username column.
      expect(single(row(username: pw, password: '')).issues, [
        ReviewIssue.missingPassword,
        ReviewIssue.usernameLooksLikePassword,
      ]);
      // Symbols only passwords use.
      expect(single(row(username: 'Ve7#kq!Lm2', password: 'abcde07')).issues, [
        ReviewIssue.usernameLooksLikePassword,
      ]);
    });

    test('ordinary usernames and passwords are not called swapped', () {
      for (final (u, p) in [
        ('JohnSmith1990', pw),
        ('abcde07', pw),
        ('CORP\\jsmith01', pw),
        ('first.last-2024', pw),
        (email, 'P4ss-w0rd!x'),
        (email, email.replaceAll('@', '')),
      ]) {
        expect(
          single(row(username: u, password: p)).issues,
          isEmpty,
          reason: '$u / $p',
        );
      }
    });

    test('invalid URLs need attention; a login without URL keeps its name', () {
      final bad = single(row(url: 'chrome://settings'));
      expect(bad.issues, [ReviewIssue.invalidUrl]);
      expect(bad.action, ReviewAction.needsAttention);
      expect(bad.include, isFalse);
      expect(bad.siteKey, '');

      final anon = single(row(url: '', title: ''));
      expect(anon.issues, [ReviewIssue.invalidUrl]);

      final named = single(row(url: '', title: 'Home router'));
      expect(named.issues, isEmpty);
      expect(named.entry.title, 'Home router');
      expect(named.siteKey, '');
      expect(named.action, ReviewAction.newEntry);
    });

    test('a dropped javascript: URL leaves the row without a website', () {
      final r = ie.importCsv(
        '${chromeHeader}Pay,javascript:alert(1),$email,$pw,\n'
        ',javascript:alert(1),abcde07,$pw2,\n',
      );
      final items = review(r.entries);
      expect(items[0].entry.url, '');
      expect(items[0].issues, isEmpty);
      expect(items[1].issues, [ReviewIssue.invalidUrl]);
    });

    test('plain http is flagged but imported', () {
      final item = single(row(url: 'http://example.com/login?next=%2F'));
      expect(item.issues, [ReviewIssue.insecureHttp]);
      expect(item.entry.url, 'http://example.com/login');
      expect(item.action, ReviewAction.newEntry);
      expect(item.include, isTrue);
    });
  });

  group('duplicates inside the file', () {
    test('same site and username are merged, last row wins', () {
      final r = ie.importCsv(
        '$chromeHeader'
        'example.com,https://example.com/login,$email,$pw,first\n'
        'www.example.com,https://www.example.com/,ABCDE07@Hotmail.com,$pw2,\n'
        'example.com,https://example.com/a,$email,$pw3,last\n'
        'example.com,https://example.com/,other@example.com,$pw,\n',
      );
      final items = review(r.entries);
      expect(items, hasLength(2));
      final merged = items.first;
      expect(merged.action, ReviewAction.mergedDuplicate);
      expect(merged.issues, [ReviewIssue.duplicateInFile]);
      expect(merged.include, isTrue);
      expect(merged.rows, [0, 1, 2]);
      expect(merged.entry.password, pw3);
      expect(merged.entry.id, r.entries[2].id);
      expect(merged.entry.history.map((h) => h.password), [pw2, pw]);
      expect(merged.entry.notes, 'last\nfirst');
      expect(items.last.action, ReviewAction.newEntry);
      expect(items.last.entry.username, 'other@example.com');
    });

    test('a repeated password is not put in history', () {
      final item = review([
        row(password: pw),
        row(password: pw2),
        row(password: pw),
      ]).single;
      expect(item.entry.password, pw);
      expect(item.entry.history.map((h) => h.password), [pw2]);
    });

    test('newest row by timestamp wins over file order', () {
      final item = review([
        row(password: pw, updated: DateTime.utc(2026, 3, 1)),
        row(password: pw2, updated: DateTime.utc(2025, 3, 1)),
      ]).single;
      expect(item.entry.password, pw);
      expect(item.entry.history.single.password, pw2);
      expect(item.entry.history.single.changedAt, DateTime.utc(2025, 3, 1));
    });

    test('a row without password does not win', () {
      final item = review([row(password: pw), row(password: '')]).single;
      expect(item.entry.password, pw);
      expect(item.issues, [ReviewIssue.duplicateInFile]);
      expect(item.action, ReviewAction.mergedDuplicate);
      expect(item.entry.history, isEmpty);
    });

    test('http and https rows of the same login keep the https URL', () {
      final item = review([
        row(url: 'https://example.com/', password: pw),
        row(url: 'http://example.com/', password: pw2),
      ]).single;
      expect(item.entry.url, 'https://example.com/');
      expect(item.issues, [ReviewIssue.duplicateInFile]);
      expect(item.entry.password, pw2);
    });

    test('a name the user chose survives the merge', () {
      final item = review([
        row(title: 'Example shop'),
        row(title: 'example.com', password: pw2),
      ]).single;
      expect(item.entry.title, 'Example shop');
    });

    test('other usernames, sites and non-email case are not merged', () {
      final items = review([
        row(username: 'Abcde07'),
        row(username: 'abcde07'),
        row(url: 'https://accounts.example.com/'),
        row(url: 'https://example.org/'),
        row(url: '', title: 'Router', username: 'admin'),
        row(url: '', title: 'Printer', username: 'admin'),
        row(url: '', title: '', username: 'admin'),
        row(url: '', title: '', username: 'admin'),
      ]);
      expect(items, hasLength(8));
      expect(items.every((i) => i.rows.length == 1), isTrue);
    });

    test('logins without URL merge by name', () {
      final item = review([
        row(url: '', title: 'Router', username: 'admin', password: pw),
        row(url: '', title: 'router', username: 'admin', password: pw2),
      ]).single;
      expect(item.entry.password, pw2);
      expect(item.action, ReviewAction.mergedDuplicate);
    });
  });

  group('compared with the vault', () {
    final created = DateTime.utc(2024, 5, 1);
    VaultEntry stored({
      String id = 'v1',
      String url = 'https://www.example.com/login',
      String username = 'ABCDE07@hotmail.com',
      String password = pw,
      String notes = 'vault note',
      String title = 'My Example',
    }) => VaultEntry(
      id: id,
      title: title,
      url: url,
      username: username,
      password: password,
      notes: notes,
      tags: const ['work'],
      createdAt: created,
      updatedAt: created,
      passwordChangedAt: created,
    );

    test('same password is skipped', () {
      final item = single(row(), [stored()]);
      expect(item.action, ReviewAction.skipIdentical);
      expect(item.include, isFalse);
      expect(item.existingId, 'v1');
      expect(item.issues, isEmpty);
      expect(ImportReview.apply([item]), isEmpty);
    });

    test('different password updates the vault entry', () {
      final now = DateTime.utc(2026, 10, 6, 12);
      final item = single(row(password: pw2, notes: 'from chrome'), [stored()]);
      expect(item.action, ReviewAction.updateExisting);
      expect(item.issues, [ReviewIssue.existsWithDifferentPassword]);
      expect(item.include, isTrue);
      expect(item.existingId, 'v1');

      final saved = ImportReview.apply([item], now: now).single;
      expect(saved.id, 'v1');
      expect(saved.title, 'My Example');
      expect(saved.url, 'https://www.example.com/login');
      expect(saved.username, 'ABCDE07@hotmail.com');
      expect(saved.tags, ['work']);
      expect(saved.password, pw2);
      expect(saved.history.map((h) => h.password), [pw]);
      expect(saved.history.single.changedAt, now);
      expect(saved.notes, 'vault note\nfrom chrome');
      expect(saved.createdAt, created);
      expect(saved.updatedAt, now);
      expect(saved.passwordChangedAt, now);
    });

    test('a note the vault already has is not appended twice', () {
      final saved = ImportReview.apply(
        review([row(password: pw2, notes: 'vault note')], [stored()]),
      ).single;
      expect(saved.notes, 'vault note');
      final again = ImportReview.apply(
        review(
          [row(password: pw3, notes: 'from chrome')],
          [stored(notes: 'vault note\nfrom chrome', password: pw2)],
        ),
      ).single;
      expect(again.notes, 'vault note\nfrom chrome');
      final empty = ImportReview.apply(
        review([row(password: pw2, notes: 'x')], [stored(notes: '')]),
      ).single;
      expect(empty.notes, 'x');
    });

    test('older passwords from the file sit below the replaced one', () {
      final item = review(
        [row(password: pw3), row(password: pw2)],
        [stored()],
      ).single;
      expect(item.action, ReviewAction.updateExisting);
      expect(item.issues, [
        ReviewIssue.duplicateInFile,
        ReviewIssue.existsWithDifferentPassword,
      ]);
      final saved = ImportReview.apply([item]).single;
      expect(saved.password, pw2);
      expect(saved.history.map((h) => h.password), [pw, pw3]);
    });

    test('the identical vault copy is preferred among several matches', () {
      final item = single(row(password: pw2), [
        stored(id: 'a', password: pw),
        stored(id: 'b', password: pw2),
      ]);
      expect(item.action, ReviewAction.skipIdentical);
      expect(item.existingId, 'b');
    });

    test('the newest vault copy is updated when none is identical', () {
      final item = single(row(password: pw3), [
        stored(id: 'a', password: pw),
        VaultEntry(
          id: 'b',
          url: 'https://example.com/',
          username: email,
          password: pw2,
          updatedAt: DateTime.utc(2025, 1, 1),
        ),
      ]);
      expect(item.existingId, 'b');
    });

    test('only the same site key matches', () {
      for (final url in [
        'https://accounts.example.com/',
        'https://example.org/',
        'androidapp://com.example.app',
      ]) {
        final item = single(row(url: url, password: pw2), [stored()]);
        expect(item.action, ReviewAction.newEntry, reason: url);
        expect(item.existing, isNull, reason: url);
      }
    });

    test('Android logins match vault entries saved in either form', () {
      final rawVault = stored(url: appFacet);
      final item = single(row(url: appFacet, password: pw2), [rawVault]);
      expect(item.action, ReviewAction.updateExisting);
      final saved = ImportReview.apply([item]).single;
      expect(saved.url, 'androidapp://com.example.app');

      final linked = stored(url: 'androidapp://com.example.app');
      expect(
        single(row(url: appFacet), [linked]).action,
        ReviewAction.skipIdentical,
      );
    });

    test('a broken row matching the vault never wipes its password', () {
      final item = single(row(password: ''), [stored()]);
      expect(item.action, ReviewAction.needsAttention);
      expect(item.existingId, 'v1');
      expect(item.issues, [ReviewIssue.missingPassword]);
      item.include = true;
      expect(ImportReview.apply([item]), isEmpty);
      final blank = single(row(password: '  '), [stored()])..include = true;
      expect(blank.issues, [ReviewIssue.missingPassword]);
      expect(ImportReview.apply([blank]), isEmpty);
      // "note" is part of "vault note" but not the same line.
      final withNote = single(row(password: '', notes: 'note'), [stored()])
        ..include = true;
      final saved = ImportReview.apply([withNote]).single;
      expect(saved.password, pw);
      expect(saved.notes, 'vault note\nnote');
    });

    test('an included identical item only adds what is new', () {
      final item = single(row(notes: 'chrome note'), [stored()])
        ..include = true;
      final saved = ImportReview.apply([item]).single;
      expect(saved.password, pw);
      expect(saved.history, isEmpty);
      expect(saved.notes, 'vault note\nchrome note');
    });

    test('a duplicate row with a new password is not skipped', () {
      // Chrome keeps one row per signon realm; the later row matches the
      // vault, the other one holds a password the vault has never seen.
      final vault = [stored(url: 'https://example.com/', password: pw2)];
      final rows = [
        row(url: 'https://www.example.com/', password: pw),
        row(url: 'https://example.com/', password: pw2),
      ];
      final item = review(rows, vault).single;
      expect(item.action, ReviewAction.updateExisting);
      expect(item.include, isTrue);
      expect(item.issues, [
        ReviewIssue.duplicateInFile,
        ReviewIssue.existsWithDifferentPassword,
      ]);
      final saved = ImportReview.apply([item]).single;
      expect(saved.id, 'v1');
      expect(saved.password, pw2);
      expect(saved.history.map((h) => h.password), [pw]);

      // Once the vault knows it (an earlier import), there is nothing to do.
      final again = review(rows, [saved]).single;
      expect(again.action, ReviewAction.skipIdentical);
      expect(again.include, isFalse);
      expect(ImportReview.apply([again..include = true]), isEmpty);
    });

    test('logins without URL match the vault by name', () {
      final vault = [
        stored(id: 'r', url: '', title: 'Router', username: 'admin'),
      ];
      final item = single(
        row(url: '', title: 'ROUTER', username: 'admin', password: pw2),
        vault,
      );
      expect(item.action, ReviewAction.updateExisting);
      expect(item.existingId, 'r');
    });

    test('http is not flagged when the vault entry keeps its https URL', () {
      final item = single(row(url: 'http://example.com/', password: pw2), [
        stored(),
      ]);
      expect(item.action, ReviewAction.updateExisting);
      expect(item.issues, [ReviewIssue.existsWithDifferentPassword]);
      expect(
        single(row(url: 'http://example.com/', password: pw2), [
          stored(url: 'http://example.com/'),
        ]).issues,
        [ReviewIssue.insecureHttp, ReviewIssue.existsWithDifferentPassword],
      );
    });

    test('apply starts from the current vault when it changed meanwhile', () {
      final item = single(row(password: pw2), [stored()]);
      final synced = stored().edit(title: 'Renamed', password: pw3);
      final saved = ImportReview.apply([item], current: [synced]).single;
      expect(saved.id, 'v1');
      expect(saved.title, 'Renamed');
      expect(saved.password, pw2);
      expect(saved.history.map((h) => h.password), [pw3, pw]);

      // Deleted on another device: the login is added again as a new entry.
      final readded = ImportReview.apply([item], current: const []).single;
      expect(readded.id, item.entry.id);
      expect(readded.id, isNot('v1'));
      expect(readded.password, pw2);
    });
  });

  group('group, counts and apply', () {
    test('groups by site, sorted by site name, no-website group last', () {
      final items = review([
        row(url: 'https://zeta.example/', username: 'b@example.com'),
        row(url: '', title: 'Router', username: 'admin'),
        row(url: 'https://www.alpha.example/', username: 'z@example.com'),
        row(url: 'https://zeta.example/', username: 'A@example.com'),
        row(url: 'https://alpha.example/x', username: 'a@example.com'),
        row(url: appFacet, username: 'm@example.com'),
      ]);
      final groups = ImportReview.group(items);
      expect(groups.keys, [
        'alpha.example',
        'androidapp://com.example.app',
        'zeta.example',
        '',
      ]);
      expect(groups['alpha.example']!.map((i) => i.entry.username), [
        'a@example.com',
        'z@example.com',
      ]);
      expect(groups['zeta.example']!.map((i) => i.entry.username), [
        'A@example.com',
        'b@example.com',
      ]);
      expect(groups['']!.single.entry.title, 'Router');
    });

    test('counts every action for the summary line', () {
      final vault = [
        VaultEntry(
          id: 's',
          url: 'https://same.example/',
          username: email,
          password: pw,
        ),
        VaultEntry(
          id: 'u',
          url: 'https://upd.example/',
          username: email,
          password: pw,
        ),
      ];
      final items = review([
        row(url: 'https://new.example/'),
        row(url: 'https://same.example/'),
        row(url: 'https://upd.example/', password: pw2),
        row(url: 'https://dup.example/', password: pw),
        row(url: 'https://dup.example/', password: pw2),
        row(url: 'https://bad.example/', password: ''),
        row(url: 'chrome://settings'),
      ], vault);
      expect(ImportReview.counts(items), {
        ReviewAction.newEntry: 1,
        ReviewAction.updateExisting: 1,
        ReviewAction.mergedDuplicate: 1,
        ReviewAction.skipIdentical: 1,
        ReviewAction.needsAttention: 2,
      });
      expect(ImportReview.counts(const []).values.every((n) => n == 0), isTrue);

      final saved = ImportReview.apply(items);
      expect(saved.map((e) => e.url), [
        'https://new.example/',
        'https://upd.example/',
        'https://dup.example/',
      ]);
      expect(saved[1].id, 'u');
    });

    test('apply honours the include toggle', () {
      final items = review([
        row(url: 'https://a.example/'),
        row(url: 'https://b.example/', username: pw, password: email),
      ]);
      expect(items.map((i) => i.include), [true, false]);
      items[0].include = false;
      items[1].include = true;
      final saved = ImportReview.apply(items);
      expect(saved.single.url, 'https://b.example/');
      expect(saved.single.id, items[1].entry.id);
    });

    test('Chrome CSV end to end', () {
      final r = ie.importCsv(
        '$chromeHeader'
        'accounts.google.com,https://accounts.google.com/ServiceLogin?hl=en,$email,$pw,\n'
        'accounts.google.com,https://accounts.google.com/,$email,$pw2,\n'
        'com.example.app,$appFacet,$email,$pw3,\n'
        'old.example,http://old.example/login.php?sid=1,abcde07,$pw,\n'
        'broken.example,https://broken.example/,$pw,$email,\n'
        'github.com,https://github.com/session,abcde07,$pw,\n',
      );
      final vault = [
        VaultEntry(
          id: 'gh',
          url: 'https://github.com/',
          username: 'abcde07',
          password: pw,
        ),
      ];
      final items = review(r.entries, vault);
      expect(items.map((i) => (i.entry.title, i.action)), [
        ('Google', ReviewAction.mergedDuplicate),
        ('Example', ReviewAction.newEntry),
        ('Old', ReviewAction.newEntry),
        ('Broken', ReviewAction.needsAttention),
        ('Github', ReviewAction.skipIdentical),
      ]);
      expect(items[2].entry.url, 'http://old.example/login.php');
      expect(items[2].issues, [ReviewIssue.insecureHttp]);

      final saved = ImportReview.apply(items);
      expect(saved, hasLength(3));
      expect(
        AutofillMatcher.match(
          saved,
          domain: 'accounts.google.com',
        ).single.password,
        pw2,
      );
      expect(
        AutofillMatcher.match(saved, appId: 'com.example.app').single.password,
        pw3,
      );
    });

    test('a large file is reviewed in one pass', () {
      final rows = [
        for (var i = 0; i < 20000; i++)
          row(
            url: 'https://s${i % 10000}.example/',
            password: 'Pw-$i-synthetic',
          ),
      ];
      final vault = [
        for (var i = 0; i < 5000; i++)
          VaultEntry(
            id: 'v$i',
            url: 'https://s$i.example/',
            username: email,
            password: 'old',
          ),
      ];
      final sw = Stopwatch()..start();
      final items = ImportReview.review(rows, vault);
      sw.stop();
      expect(items, hasLength(10000));
      final c = ImportReview.counts(items);
      expect(c[ReviewAction.updateExisting], 5000);
      expect(c[ReviewAction.mergedDuplicate], 5000);
      expect(sw.elapsed, lessThan(const Duration(seconds: 20)));
    });
  });
}
