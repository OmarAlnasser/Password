import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:hisn/core/crypto/crypto.dart';
import 'package:hisn/data/db/database.dart';
import 'package:hisn/services/favicon_service.dart';
import 'package:hisn/services/settings.dart';

typedef Route = FutureOr<http.StreamedResponse> Function(http.BaseRequest req);

http.StreamedResponse respond(
  List<int> body,
  int status, {
  Map<String, String> headers = const {},
}) => http.StreamedResponse(
  Stream.value(body),
  status,
  contentLength: body.length,
  headers: headers,
);

/// Serves fixed routes (everything else is 404) and records every request.
class FakeWeb {
  final routes = <String, Route>{};
  final requests = <http.BaseRequest>[];

  late final http.Client client = MockClient.streaming((req, _) async {
    requests.add(req);
    final route = routes[req.url.toString()];
    return route == null
        ? respond(utf8.encode('not found'), 404)
        : await route(req);
  });

  List<String> get urls => [for (final r in requests) r.url.toString()];

  void route(String url, Route handler) => routes[url] = handler;

  void page(String url, String html) => routes[url] = (_) =>
      respond(utf8.encode(html), 200, headers: {'content-type': 'text/html'});

  void file(String url, List<int> bytes, {String type = 'image/png'}) =>
      routes[url] = (_) => respond(bytes, 200, headers: {'content-type': type});

  void redirect(String url, String to, [int code = 302]) =>
      routes[url] = (_) => respond(const [], code, headers: {'location': to});
}

final png = MockClient.pngResponse().bodyBytes;

List<int> le16(int v) => [v & 0xff, (v >> 8) & 0xff];
List<int> le32(int v) => [...le16(v), ...le16(v >> 16)];
List<int> be16(int v) => [(v >> 8) & 0xff, v & 0xff];
List<int> be32(int v) => [...be16(v >> 16), ...be16(v)];

/// Signature and IHDR chunk declaring [w]x[h] (the CRC is not checked).
Uint8List pngHeader(int w, int h) => Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  ...be32(13), ...'IHDR'.codeUnits, ...be32(w), ...be32(h),
  8, 6, 0, 0, 0, 0, 0, 0, 0,
]);

/// BITMAPINFOHEADER as embedded in an .ico (height covers both masks).
List<int> bmpHeader(int w, int h) => [
  ...le32(40), ...le32(w), ...le32(h * 2), 1, 0, 32, 0, //
  ...List.filled(28, 0),
];

/// An .ico whose single directory entry claims 16x16 and points at [image].
Uint8List icoOf(List<int> image, {int? offset}) => Uint8List.fromList([
  0, 0, 1, 0, 1, 0, //
  16, 16, 0, 0, 1, 0, 32, 0, ...le32(image.length), ...le32(offset ?? 22),
  ...image,
]);

final ico = icoOf(bmpHeader(16, 16));

Uint8List gif(int w, int h) => Uint8List.fromList([
  ...'GIF89a'.codeUnits, ...le16(w), ...le16(h), 0, 0, 0, //
]);

/// SOI, a JFIF APP0 segment, then a baseline SOF0 frame header.
Uint8List jpeg(int w, int h) => Uint8List.fromList([
  0xFF, 0xD8, //
  0xFF, 0xE0, ...be16(16), ...'JFIF'.codeUnits, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0,
  0xFF, 0xC0, ...be16(17), 8, ...be16(h), ...be16(w), 3,
  1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1,
]);

Uint8List webpLossless(int w, int h) => Uint8List.fromList([
  ...'RIFF'.codeUnits, ...le32(30), ...'WEBP'.codeUnits, //
  ...'VP8L'.codeUnits, ...le32(10), 0x2f, ...le32((w - 1) | ((h - 1) << 14)),
  0, 0, 0, 0, 0,
]);

Uint8List webpExtended(int w, int h) => Uint8List.fromList([
  ...'RIFF'.codeUnits, ...le32(22), ...'WEBP'.codeUnits, //
  ...'VP8X'.codeUnits, ...le32(10), 0, 0, 0, 0,
  ...le32(w - 1).take(3), ...le32(h - 1).take(3),
]);

Uint8List bytesOf(String s) => Uint8List.fromList(latin1.encode(s));

Future<List<InternetAddress>> publicDns(String host) async => [
  InternetAddress('203.0.113.7'),
];

void main() {
  late SodiumSumo sodium;
  late Directory dir;
  late SecureKey key;
  late VaultDatabase db;
  late DateTime now;

  setUpAll(() async => sodium = await loadSodium());
  setUp(() {
    dir = Directory.systemTemp.createTempSync('vs_favicon');
    key = sodium.secureRandom(32);
    db = VaultDatabase.open(File('${dir.path}/vault.db'), key);
    now = DateTime.utc(2026, 10, 1);
  });
  tearDown(() async {
    await db.close();
    key.dispose();
    dir.deleteSync(recursive: true);
  });

  FaviconService service(
    http.Client client, {
    HostLookup lookup = publicDns,
    bool Function()? enabled,
    Duration timeout = const Duration(seconds: 5),
  }) => FaviconService(
    client,
    () => db,
    lookup: lookup,
    clock: () => now,
    enabled: enabled,
    timeout: timeout,
  );

  group('host rules', () {
    test('accepts public web hosts and entry URLs', () {
      expect(FaviconService.siteHost('example.com'), 'example.com');
      expect(
        FaviconService.siteHost('https://Login.Example.co.uk/path?q=1'),
        'login.example.co.uk',
      );
      expect(FaviconService.siteHost('http://example.org'), 'example.org');
      expect(
        FaviconService.siteHost('www.example.com/login'),
        'www.example.com',
      );
      expect(FaviconService.siteHost(' example.com. '), 'example.com');
    });

    test('rejects IP literals, local names, single labels and app links', () {
      for (final h in [
        '127.0.0.1',
        'https://192.168.1.1/admin',
        '10.0.0.8',
        '127.1',
        '0x7f.0.0.1',
        '2130706433',
        'https://[::1]/',
        'https://[fe80::1]:8443/',
        '::1',
        'localhost',
        'https://localhost:8080/',
        'api.localhost',
        'printer.local',
        'nas.internal',
        'router.lan',
        'router',
        'intranet',
        'androidapp://com.example.bank',
        'iosapp://com.example.bank',
        'ftp://example.com',
        'file:///etc/hosts',
        'bad_label.example.com',
        '',
        '   ',
      ]) {
        expect(FaviconService.siteHost(h), isNull, reason: h);
      }
    });

    test('registrable domain approximation', () {
      expect(FaviconService.registrableDomain('example.com'), 'example.com');
      expect(
        FaviconService.registrableDomain('a.b.example.com'),
        'example.com',
      );
      expect(
        FaviconService.registrableDomain('www.example.co.uk'),
        'example.co.uk',
      );
      expect(
        FaviconService.registrableDomain('login.example.com.sa'),
        'example.com.sa',
      );
      expect(FaviconService.registrableDomain('example.de'), 'example.de');
    });

    test('only internet addresses count as public', () {
      for (final a in [
        '203.0.113.7',
        '172.32.0.1',
        '2001:db8::5',
        '::ffff:203.0.113.7',
        '64:ff9b::cb00:7107', // NAT64 for 203.0.113.7
      ]) {
        expect(
          FaviconService.isPublicAddress(InternetAddress(a)),
          isTrue,
          reason: a,
        );
      }
      for (final a in [
        '127.0.0.1',
        '10.1.2.3',
        '172.16.0.1',
        '172.31.255.255',
        '192.168.0.10',
        '169.254.169.254',
        '100.64.0.1',
        '0.0.0.0',
        '224.0.0.1',
        '255.255.255.255',
        '::',
        '::1',
        'fe80::1',
        'fec0::1',
        'fc00::1',
        'fd12:3456::1',
        'ff02::1',
        '::ffff:192.168.1.1',
        '::ffff:127.0.0.1',
        '64:ff9b::a00:1', // NAT64 for 10.0.0.1
      ]) {
        expect(
          FaviconService.isPublicAddress(InternetAddress(a)),
          isFalse,
          reason: a,
        );
      }
    });

    test('rejected hosts touch neither the network nor the database', () async {
      final web = FakeWeb();
      var lookups = 0;
      final s = service(
        web.client,
        lookup: (h) {
          lookups++;
          return publicDns(h);
        },
      );
      for (final h in [
        'androidapp://com.example.bank',
        '192.168.1.1',
        'https://[::1]/',
        'printer.local',
        'router',
      ]) {
        expect(await s.iconFor(h), isNull, reason: h);
      }
      await s.prefetch(['10.0.0.1', 'nas.internal']);
      expect(web.requests, isEmpty);
      expect(lookups, 0);
      expect(await db.allFavicons(), isEmpty);
    });

    test('names resolving to private addresses are not fetched', () async {
      final web = FakeWeb()
        ..file('https://router.example.com/favicon.ico', png);
      final s = service(
        web.client,
        lookup: (_) async => [InternetAddress('192.168.1.20')],
      );
      expect(await s.iconFor('router.example.com'), isNull);
      expect(web.requests, isEmpty);
      // A definite answer: not retried for a week.
      expect((await db.favicon('router.example.com'))!.failed, isTrue);
    });

    test('a redirect to a privately resolving name is refused', () async {
      final web = FakeWeb()
        ..redirect('https://example.com/', 'https://intranet.example.com/')
        ..file('https://intranet.example.com/favicon.ico', png);
      final s = service(
        web.client,
        lookup: (h) async => [
          InternetAddress(
            h.startsWith('intranet.') ? '10.0.0.5' : '203.0.113.7',
          ),
        ],
      );
      expect(await s.iconFor('example.com'), isNull);
      expect(web.urls, [
        'https://example.com/',
        'https://example.com/favicon.ico',
      ]);
    });
  });

  group('link parsing', () {
    test('prefers the largest PNG; skips SVG, mask-icon and comments', () {
      const html = '''
<html><head>
<!-- <link rel="icon" type="image/png" sizes="512x512" href="/old.png"> -->
<link rel="icon" href="/favicon.ico">
<link rel="icon" type="image/png" sizes="16x16" href="/icons/16.png">
<link rel="icon" type="image/svg+xml" href="/icon.svg">
<link rel="icon" href="/vector.svg?v=2">
<link rel="mask-icon" href="/mask.png" color="#000000">
<link rel="apple-touch-icon" href="/apple.png">
<link rel="icon" type="image/png" sizes="32x32 192x192" href="/icons/192.png" />
<link rel="shortcut icon" href="/legacy.ico">
<link rel="stylesheet" href="/site.css">
<LINK REL='ICON' HREF=/upper.gif sizes=48x48>
</head><body></body></html>''';
      final links = FaviconService.iconLinks(
        html,
        Uri.parse('https://www.example.com/'),
      );
      expect(links.map((u) => u.path), [
        '/icons/192.png',
        '/apple.png',
        '/icons/16.png',
        '/upper.gif',
        '/favicon.ico',
        '/legacy.ico',
      ]);
    });

    test('resolves relative and protocol-relative hrefs, decodes entities', () {
      const html = '''
<link rel="icon" href="img/a.png?v=1&amp;s=2">
<link rel="icon" href="//cdn.example.com/b.png">
<link rel="icon" href="http://www.example.com/c.png">
<link rel="icon" href="../d.png#frag">
<link rel="icon" href="data:image/png;base64,iVBORw0KGgo=">
<link rel="icon" href="javascript:alert(1)">
<link rel="icon" href="">''';
      final links = FaviconService.iconLinks(
        html,
        Uri.parse('https://www.example.com/app/login.html'),
      );
      expect(links.map((u) => u.toString()), [
        'https://www.example.com/app/img/a.png?v=1&s=2',
        'https://cdn.example.com/b.png',
        'https://www.example.com/c.png',
        'https://www.example.com/d.png',
      ]);
    });

    test('honours <base href>', () {
      const html = '<base href="/static/"><link rel="icon" href="e.png">';
      expect(
        FaviconService.iconLinks(
          html,
          Uri.parse('https://example.com/a/b'),
        ).single.toString(),
        'https://example.com/static/e.png',
      );
    });

    test('crafted markup cannot stall the parser', () {
      final watch = Stopwatch()..start();
      for (final html in [
        '<link' * 50000, // no closing '>'
        '<!--' * 60000, // no closing '-->'
        '<base<link<!--' * 20000,
        '<link rel=icon href="${'&#x' * 30000}">',
        '<link a="${"b='" * 30000}>',
      ]) {
        FaviconService.iconLinks(html, Uri.parse('https://example.com/'));
      }
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });
  });

  group('magic bytes', () {
    test('accepts PNG, JPEG, GIF, WEBP and ICO', () {
      expect(FaviconService.imageType(png), 'image/png');
      expect(FaviconService.imageType(pngHeader(1024, 1024)), 'image/png');
      expect(FaviconService.imageType(jpeg(180, 180)), 'image/jpeg');
      expect(FaviconService.imageType(gif(16, 16)), 'image/gif');
      expect(
        FaviconService.imageType(
          Uint8List.fromList([...'GIF87a'.codeUnits, 32, 0, 32, 0]),
        ),
        'image/gif',
      );
      expect(FaviconService.imageType(webpLossless(64, 48)), 'image/webp');
      expect(FaviconService.imageType(webpExtended(512, 512)), 'image/webp');
      expect(FaviconService.imageType(ico), 'image/x-icon');
      expect(FaviconService.imageType(icoOf(png)), 'image/x-icon');
    });

    test('rejects image bombs by their declared size', () {
      for (final b in [
        pngHeader(40000, 40000),
        pngHeader(1025, 16),
        pngHeader(0, 16),
        jpeg(16, 30000),
        gif(4000, 4000),
        webpLossless(16384, 16384),
        webpExtended(20000, 20000),
        // The directory says 16x16; the embedded images say otherwise.
        icoOf(pngHeader(40000, 40000)),
        icoOf(bmpHeader(5000, 5000)),
        icoOf(bmpHeader(16, 16), offset: 4096),
      ]) {
        expect(FaviconService.imageType(b), isNull);
      }
    });

    test('rejects SVG, HTML, cursors and truncated data', () {
      for (final b in [
        bytesOf('<svg xmlns="http://www.w3.org/2000/svg"></svg>'),
        bytesOf('<?xml version="1.0"?><svg/>'),
        bytesOf('<!DOCTYPE html><html></html>'),
        bytesOf('RIFF\x10\x00\x00\x00WAVEfmt '),
        Uint8List.fromList([0, 0, 2, 0, 1, 0, ...List.filled(16, 0)]), // .cur
        Uint8List.fromList([0, 0, 1, 0, 0, 0]), // no images
        Uint8List.fromList([0, 0, 1, 0, 2, 0, ...List.filled(16, 0)]),
        png.sublist(0, 4),
        Uint8List(0),
      ]) {
        expect(FaviconService.imageType(b), isNull);
      }
    });
  });

  group('fetching', () {
    test('fetches the best icon from the site itself, privately', () async {
      final web = FakeWeb()
        ..page(
          'https://example.com/',
          '<link rel="icon" href="/favicon.ico">'
              '<link rel="apple-touch-icon" href="/apple-touch-icon.png">',
        )
        ..file('https://example.com/apple-touch-icon.png', png);
      final s = service(web.client);
      var notified = 0;
      s.addListener(() => notified++);

      expect(await s.iconFor('https://example.com/login'), png);
      expect(web.urls, [
        'https://example.com/',
        'https://example.com/apple-touch-icon.png',
      ]);
      for (final r in web.requests) {
        expect(r.method, 'GET');
        expect(r.url.scheme, 'https');
        expect(r.followRedirects, isFalse);
        expect(r.headers['User-Agent'], FaviconService.userAgent);
        expect(r.headers.containsKey('Cookie'), isFalse);
        expect(r.headers.containsKey('Referer'), isFalse);
      }
      final row = (await db.favicon('example.com'))!;
      expect(row.bytes, png);
      expect(row.contentType, 'image/png');
      expect(row.failed, isFalse);
      expect(row.fetchedAt, now.millisecondsSinceEpoch);

      await pumpEventQueue();
      expect(notified, greaterThan(0));
      expect(s.cached('example.com'), png);
      expect(s.cache, {'example.com': png});

      // Served from memory now.
      expect(await s.iconFor('example.com'), png);
      expect(web.requests, hasLength(2));
    });

    test('falls back to /favicon.ico', () async {
      final web = FakeWeb()
        ..page('https://example.com/', '<html><head></head></html>')
        ..file('https://example.com/favicon.ico', ico, type: 'image/x-icon');
      final s = service(web.client);
      expect(await s.iconFor('example.com'), ico);
      expect((await db.favicon('example.com'))!.contentType, 'image/x-icon');
    });

    test('never asks a third party for an icon', () async {
      final web = FakeWeb()
        ..page(
          'https://example.com/',
          '<link rel="icon" sizes="512x512" '
              'href="https://www.google.com/s2/favicons?domain=example.com">'
              '<link rel="icon" href="https://icons.example-cdn.net/e.png">'
              '<link rel="icon" href="https://example.com:8443/p.png">',
        )
        ..file('https://example.com/favicon.ico', ico);
      final s = service(web.client);
      expect(await s.iconFor('example.com'), ico);
      expect(web.urls, [
        'https://example.com/',
        'https://example.com/favicon.ico',
      ]);
    });

    test('tries the next candidate when the best one is unusable', () async {
      final web = FakeWeb()
        ..page(
          'https://example.com/',
          '<link rel="icon" sizes="192x192" href="/a.png">'
              '<link rel="icon" sizes="32x32" href="/b.png">',
        )
        ..file('https://example.com/a.png', bytesOf('<svg></svg>'))
        ..file('https://example.com/b.png', png);
      expect(await service(web.client).iconFor('example.com'), png);
    });

    test(
      'rejects icons that are not raster images, whatever the type',
      () async {
        final web = FakeWeb()
          ..page('https://example.com/', '<link rel="icon" href="/icon.png">')
          ..file(
            'https://example.com/icon.png',
            bytesOf('<svg xmlns="http://www.w3.org/2000/svg"/>'),
          )
          ..file(
            'https://example.com/favicon.ico',
            bytesOf('<!DOCTYPE html><title>Home</title>'),
            type: 'image/x-icon',
          );
        expect(await service(web.client).iconFor('example.com'), isNull);
        final row = (await db.favicon('example.com'))!;
        expect(row.failed, isTrue);
        expect(row.bytes, isNull);
      },
    );

    test('an image bomb is not stored', () async {
      final web = FakeWeb()
        ..file('https://example.com/favicon.ico', pngHeader(40000, 40000));
      expect(await service(web.client).iconFor('example.com'), isNull);
      final row = (await db.favicon('example.com'))!;
      expect(row.failed, isTrue);
      expect(row.bytes, isNull);
    });

    test('icons over 200 KB are rejected, with or without length', () async {
      final big = Uint8List.fromList([
        ...png,
        ...List.filled(FaviconService.maxIconBytes, 0),
      ]);
      var pulled = 0;
      Stream<List<int>> endless() async* {
        yield png;
        while (true) {
          pulled++;
          yield Uint8List(64 * 1024);
        }
      }

      final web = FakeWeb()
        ..page('https://example.com/', '<link rel="icon" href="/big.png">')
        ..file('https://example.com/big.png', big)
        ..route(
          'https://example.com/favicon.ico',
          (_) => http.StreamedResponse(endless(), 200),
        );
      expect(await service(web.client).iconFor('example.com'), isNull);
      // Stopped reading at the limit instead of downloading forever.
      expect(pulled, lessThanOrEqualTo(5));
      expect((await db.favicon('example.com'))!.failed, isTrue);
    });

    test('an icon of exactly 200 KB is accepted', () async {
      final exact = Uint8List(FaviconService.maxIconBytes)
        ..setRange(0, png.length, png);
      final web = FakeWeb()..file('https://example.com/favicon.ico', exact);
      expect(await service(web.client).iconFor('example.com'), exact);
    });

    test('reads at most 256 KB of HTML', () async {
      var pulled = 0;
      Stream<List<int>> page(String head) async* {
        yield utf8.encode(head);
        while (true) {
          pulled++;
          yield utf8.encode('<p>${'x' * 65536}</p>');
        }
      }

      // A link near the top is used even though the page never ends.
      final web = FakeWeb()
        ..route(
          'https://example.com/',
          (_) => http.StreamedResponse(
            page('<link rel="icon" href="/top.png">'),
            200,
          ),
        )
        ..file('https://example.com/top.png', png);
      expect(await service(web.client).iconFor('example.com'), png);
      expect(pulled, lessThanOrEqualTo(5));

      // A link beyond the limit is never seen.
      final padding = '<p>${'x' * FaviconService.maxHtmlBytes}</p>';
      final web2 = FakeWeb()
        ..page(
          'https://example.org/',
          '$padding<link rel="icon" href="/x.png">',
        )
        ..file('https://example.org/x.png', png)
        ..file('https://example.org/favicon.ico', ico);
      expect(await service(web2.client).iconFor('example.org'), ico);
      expect(web2.urls, isNot(contains('https://example.org/x.png')));
    });
  });

  group('redirects', () {
    test('follows same-site HTTPS redirects and resolves against the final '
        'URL', () async {
      final web = FakeWeb()
        ..redirect('https://example.com/', 'https://www.example.com/', 301)
        ..redirect('https://www.example.com/', '/home/')
        ..page('https://www.example.com/home/', '<link rel=icon href=i.png>')
        ..file('https://www.example.com/home/i.png', png);
      expect(await service(web.client).iconFor('example.com'), png);
      expect(web.urls, [
        'https://example.com/',
        'https://www.example.com/',
        'https://www.example.com/home/',
        'https://www.example.com/home/i.png',
      ]);
    });

    test('refuses redirects to http, other sites and other ports', () async {
      final web = FakeWeb()
        ..redirect('https://example.com/', 'http://example.com/')
        ..redirect(
          'https://example.com/favicon.ico',
          'http://example.com/f.ico',
        )
        ..redirect('https://example.org/', 'https://example-login.net/')
        ..redirect(
          'https://example.org/favicon.ico',
          'https://cdn.example-icons.net/example.org.ico',
        )
        ..redirect('https://example.net/', 'https://example.net:8443/')
        ..redirect('https://example.info/', 'http://example.info:443/')
        ..file('http://example.com/f.ico', png)
        ..file('https://example-login.net/favicon.ico', png)
        ..file('https://cdn.example-icons.net/example.org.ico', png);
      final s = service(web.client);
      expect(await s.iconFor('example.com'), isNull);
      expect(await s.iconFor('example.org'), isNull);
      expect(await s.iconFor('example.net'), isNull);
      expect(await s.iconFor('example.info'), isNull);
      expect(web.urls, [
        'https://example.com/',
        'https://example.com/favicon.ico',
        'https://example.org/',
        'https://example.org/favicon.ico',
        'https://example.net/',
        'https://example.net/favicon.ico',
        'https://example.info/',
        'https://example.info/favicon.ico',
      ]);
    });

    test('follows at most 3 redirects', () async {
      final web = FakeWeb()
        ..redirect('https://example.com/', '/r1')
        ..redirect('https://example.com/r1', '/r2')
        ..redirect('https://example.com/r2', '/r3')
        ..redirect('https://example.com/r3', '/r4')
        ..file('https://example.com/r4', png);
      expect(await service(web.client).iconFor('example.com'), isNull);
      expect(web.urls, isNot(contains('https://example.com/r4')));
      expect(web.urls, contains('https://example.com/r3'));
    });
  });

  group('caching', () {
    test('failures are kept 7 days, successes 30, old icons survive a failed '
        'refresh', () async {
      var up = false;
      final web = FakeWeb()
        ..route(
          'https://example.com/favicon.ico',
          (_) => up ? respond(png, 200) : respond(const [], 404),
        );

      expect(await service(web.client).iconFor('example.com'), isNull);
      expect(web.requests, hasLength(2));
      var row = (await db.favicon('example.com'))!;
      expect(row.failed, isTrue);
      expect(row.bytes, isNull);

      // Each new service starts with an empty memory cache.
      now = now.add(const Duration(days: 6));
      expect(await service(web.client).iconFor('example.com'), isNull);
      expect(web.requests, hasLength(2));

      now = now.add(const Duration(days: 2));
      up = true;
      expect(await service(web.client).iconFor('example.com'), png);
      expect(web.requests, hasLength(4));
      expect((await db.favicon('example.com'))!.failed, isFalse);

      now = now.add(const Duration(days: 29));
      expect(await service(web.client).iconFor('example.com'), png);
      expect(web.requests, hasLength(4));

      now = now.add(const Duration(days: 2));
      up = false;
      expect(await service(web.client).iconFor('example.com'), png);
      expect(web.requests, hasLength(6));
      row = (await db.favicon('example.com'))!;
      expect(row.failed, isTrue);
      expect(row.bytes, png);
      expect(row.fetchedAt, now.millisecondsSinceEpoch);
    });

    test('network errors are not cached as failures', () async {
      var calls = 0;
      final offline = MockClient((_) async {
        calls++;
        throw http.ClientException('Connection failed');
      });
      expect(await service(offline).iconFor('example.com'), isNull);
      expect(await db.allFavicons(), isEmpty);
      expect(await service(offline).iconFor('example.com'), isNull);
      expect(calls, 4);
    });

    test('timeouts are not cached as failures', () async {
      final hanging = MockClient((_) => Completer<http.Response>().future);
      final s = service(hanging, timeout: const Duration(milliseconds: 50));
      expect(await s.iconFor('example.com'), isNull);
      expect(await db.allFavicons(), isEmpty);
    });

    test('DNS failures are not cached as failures', () async {
      final web = FakeWeb();
      final s = service(
        web.client,
        lookup: (h) async => throw const SocketException('No address'),
      );
      expect(await s.iconFor('example.com'), isNull);
      expect(web.requests, isEmpty);
      expect(await db.allFavicons(), isEmpty);
    });

    test('concurrent lookups of one host share a single fetch', () async {
      final web = FakeWeb()..file('https://example.com/favicon.ico', png);
      final s = service(web.client);
      final results = await Future.wait([
        s.iconFor('example.com'),
        s.iconFor('https://example.com/a'),
        s.iconFor('EXAMPLE.com'),
      ]);
      expect(results, [png, png, png]);
      expect(web.requests, hasLength(2));
    });
  });

  group('database', () {
    test('icons persist inside the encrypted database only', () async {
      final web = FakeWeb()..file('https://example.com/favicon.ico', png);
      expect(await service(web.client).iconFor('example.com'), png);
      await db.close();

      for (final f in dir.listSync().whereType<File>()) {
        final text = latin1.decode(f.readAsBytesSync());
        expect(text.contains('example.com'), isFalse, reason: f.path);
        expect(text.contains('IHDR'), isFalse, reason: f.path);
      }

      db = VaultDatabase.open(File('${dir.path}/vault.db'), key);
      final offline = MockClient((_) async => throw StateError('no network'));
      final s = service(offline);
      expect(await s.iconFor('example.com'), png);
      await s.prefetch(['example.com']);
      expect((await db.allFavicons()).single.host, 'example.com');
    });

    test('a version 1 vault is upgraded without losing entries', () async {
      await db.upsert(
        VaultItemsCompanion.insert(
          id: 'e1',
          payload: Value(Uint8List.fromList([1, 2, 3])),
          localUpdatedAt: 1,
        ),
      );
      await db.customStatement('DROP TABLE favicons');
      await db.customStatement('PRAGMA user_version = 1');
      await db.close();

      db = VaultDatabase.open(File('${dir.path}/vault.db'), key);
      expect((await db.item('e1'))!.payload, [1, 2, 3]);
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      // Upgraded to the current version (3 added the last-used times).
      expect(version.data.values.single, db.schemaVersion);
      expect(await db.allLastUsed(), isEmpty);
      await db.putFavicon(host: 'example.com', bytes: png, fetchedAt: 5);
      expect((await db.favicon('example.com'))!.bytes, png);
    });

    test('a locked vault yields nothing and fetches nothing', () async {
      final web = FakeWeb()..file('https://example.com/favicon.ico', png);
      final s = FaviconService(
        web.client,
        () => throw StateError('Vault is locked'),
        lookup: publicDns,
      );
      expect(await s.iconFor('example.com'), isNull);
      await s.prefetch(['example.com', 'example.org']);
      expect(web.requests, isEmpty);
      expect(s.cache, isEmpty);
    });

    test('clear() discards fetches that are still running', () async {
      final reached = Completer<void>();
      final gate = Completer<void>();
      final web = FakeWeb()
        ..route('https://example.com/favicon.ico', (_) async {
          reached.complete();
          await gate.future;
          return respond(png, 200);
        });
      final s = service(web.client);
      final pending = s.iconFor('example.com');
      await reached.future;
      s.clear();
      gate.complete();
      expect(await pending, isNull);
      expect(s.cache, isEmpty);
      expect(await db.allFavicons(), isEmpty);
    });
  });

  group('prefetch', () {
    test('dedupes, skips rejected hosts and limits concurrency', () async {
      var active = 0;
      var peak = 0;
      final hosts = [for (var i = 0; i < 6; i++) 'site$i.example.com'];
      final client = MockClient((req) async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        active--;
        return req.url.path == '/favicon.ico'
            ? http.Response.bytes(png, 200)
            : http.Response('', 404);
      });
      final s = service(client);
      var notified = 0;
      s.addListener(() => notified++);
      await s.prefetch([
        ...hosts,
        ...hosts.map((h) => 'https://$h/login'),
        'androidapp://com.example.bank',
        '10.0.0.1',
      ], concurrency: 2);
      await pumpEventQueue();
      expect(peak, 2);
      expect(s.cache.keys.toSet(), hosts.toSet());
      expect(s.cache.values, everyElement(png));
      expect(notified, greaterThan(0));
      expect(await db.allFavicons(), hasLength(6));
    });

    test('uses fresh rows without touching the network', () async {
      await db.putFavicon(
        host: 'example.com',
        bytes: png,
        contentType: 'image/png',
        fetchedAt: now
            .subtract(const Duration(days: 29))
            .millisecondsSinceEpoch,
      );
      await db.putFavicon(
        host: 'example.org',
        fetchedAt: now.subtract(const Duration(days: 6)).millisecondsSinceEpoch,
        failed: true,
      );
      final web = FakeWeb();
      final s = service(web.client);
      await s.prefetch(['example.com', 'example.org']);
      expect(web.requests, isEmpty);
      expect(s.cache, {'example.com': png, 'example.org': null});
    });

    test('with fetching turned off only stored icons are used', () async {
      await db.putFavicon(
        host: 'example.com',
        bytes: png,
        fetchedAt: now
            .subtract(const Duration(days: 40))
            .millisecondsSinceEpoch,
      );
      final web = FakeWeb()..file('https://example.org/favicon.ico', png);
      final s = service(web.client, enabled: () => false);
      await s.prefetch(['example.com', 'example.org']);
      expect(web.requests, isEmpty);
      expect(s.cache, {'example.com': png, 'example.org': null});
    });
  });

  test('AppSettings.fetchIcons defaults to on and persists', () async {
    final file = File('${dir.path}/settings.json');
    final a = AppSettings(file);
    await a.load();
    expect(a.fetchIcons, isTrue);
    await a.update((s) => s.fetchIcons = false);
    final b = AppSettings(file);
    await b.load();
    expect(b.fetchIcons, isFalse);
  });
}
