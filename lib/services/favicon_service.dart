import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/db/database.dart';

/// Resolves a hostname to its addresses (injectable for tests).
typedef HostLookup = Future<List<InternetAddress>> Function(String host);

/// Website icons for the entry list.
///
/// Privacy:
/// * Icons come directly from the entry's own site, never from a third-party
///   favicon service (which would learn every site in the vault). The page,
///   every redirect and the icon URL must stay on the entry's registrable
///   domain, over HTTPS.
/// * Requests carry no cookies, no Referer and a generic User-Agent.
/// * Icons are stored only in the SQLCipher database ([Favicons]) and in
///   memory while unlocked. Call [clear] on lock.
///
/// Hosts come from user-imported CSVs and are untrusted. Only public DNS names
/// are fetched (no IP literals, `localhost`, `.local`, `.internal`,
/// single-label names or `androidapp://` entries), and a name that resolves to
/// a loopback, private or link-local address is skipped, so a crafted import
/// cannot point the app at the local network by name. The HTTP client resolves
/// the name again when it connects, so a domain whose DNS answer changes in
/// between (DNS rebinding) can still get a TLS handshake sent to a local
/// address; certificate checks stop it there, which leaves at most a probe of
/// whether something listens on port 443.
///
/// No method throws: anything that goes wrong just means "no icon".
class FaviconService extends ChangeNotifier {
  FaviconService(
    this._client,
    this._db, {
    HostLookup? lookup,
    DateTime Function()? clock,
    bool Function()? enabled,
    this.timeout = const Duration(seconds: 5),
  }) : _lookup = lookup ?? InternetAddress.lookup,
       _clock = clock ?? DateTime.now,
       _enabled = enabled ?? _always;

  final http.Client _client;
  final VaultDatabase Function() _db;
  final HostLookup _lookup;
  final DateTime Function() _clock;

  /// When this returns false (`AppSettings.fetchIcons` off) nothing is
  /// fetched; icons already in the database are still shown.
  final bool Function() _enabled;

  /// Per request, including redirects and reading the body.
  final Duration timeout;

  static const Duration successTtl = Duration(days: 30);
  static const Duration failureTtl = Duration(days: 7);
  static const int maxHtmlBytes = 256 * 1024;
  static const int maxIconBytes = 200 * 1024;
  static const int maxRedirects = 3;

  /// `<link>` icons tried before falling back to `/favicon.ico`.
  static const int maxLinkCandidates = 3;

  /// Says nothing about the device, OS or app.
  static const String userAgent = 'Mozilla/5.0';

  final Map<String, Uint8List?> _cache = {};
  final Map<String, Future<Uint8List?>> _inflight = {};

  /// Bumped by [clear]; work started under an older value is discarded.
  int _epoch = 0;
  bool _notifyScheduled = false;
  bool _disposed = false;

  static bool _always() => true;

  /// Resolved icons by host (null = no icon). Hosts not looked up yet are
  /// absent. Listeners are notified when entries are added.
  Map<String, Uint8List?> get cache => UnmodifiableMapView(_cache);

  /// The icon for [hostOrUrl] if it has already been resolved.
  Uint8List? cached(String hostOrUrl) {
    final host = siteHost(hostOrUrl);
    return host == null ? null : _cache[host];
  }

  /// The icon for [hostOrUrl] (a bare host or an entry URL), loading it from
  /// the database or the site if needed. Pass the entry's URL rather than
  /// `VaultEntry.host` where possible: `androidapp://com.example` has the
  /// host `com.example`, which would otherwise look like a website.
  Future<Uint8List?> iconFor(String hostOrUrl) async {
    try {
      final host = siteHost(hostOrUrl);
      if (host == null) return null;
      if (_cache.containsKey(host)) return _cache[host];
      return await _start(host);
    } on Object {
      return null;
    }
  }

  /// Resolves many hosts at once (e.g. the whole vault after unlock), with at
  /// most [concurrency] sites fetched in parallel.
  Future<void> prefetch(Iterable<String> hosts, {int concurrency = 4}) async {
    try {
      final epoch = _epoch;
      final todo = <String>{
        for (final h in hosts)
          if (siteHost(h) case final host? when !_cache.containsKey(host)) host,
      };
      if (todo.isEmpty) return;
      // One query for all rows instead of one per host.
      final rows = {for (final r in await _db().allFavicons()) r.host: r};
      if (epoch != _epoch) return;
      final queue = <String>[];
      for (final host in todo) {
        final row = rows[host];
        if (row != null && _isFresh(row)) {
          _cache[host] = row.bytes;
        } else {
          queue.add(host);
        }
      }
      if (queue.length < todo.length) _notify();
      var next = 0;
      Future<void> worker() async {
        while (next < queue.length && epoch == _epoch) {
          final host = queue[next++];
          await _start(host, row: rows[host], haveRow: true);
        }
      }

      await Future.wait([
        for (var i = 0; i < concurrency.clamp(1, 16) && i < queue.length; i++)
          worker(),
      ]);
    } on Object {
      // Hosts that could not be resolved stay absent from [cache].
    }
  }

  /// Forgets every icon held in memory and abandons in-flight fetches (their
  /// results are neither shown nor stored). Call on lock, and after
  /// `AppSettings.fetchIcons` changes so hosts are looked up again.
  void clear() {
    _epoch++;
    _cache.clear();
    _inflight.clear();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    super.dispose();
  }

  Future<Uint8List?> _start(String host, {Favicon? row, bool haveRow = false}) {
    final running = _inflight[host];
    if (running != null) return running;
    final f = _load(host, _epoch, row: row, haveRow: haveRow);
    _inflight[host] = f;
    unawaited(
      f.whenComplete(() {
        if (identical(_inflight[host], f)) _inflight.remove(host);
      }),
    );
    return f;
  }

  Future<Uint8List?> _load(
    String host,
    int epoch, {
    Favicon? row,
    bool haveRow = false,
  }) async {
    try {
      final old = haveRow ? row : await _db().favicon(host);
      if (epoch != _epoch) return null;
      if (old != null && _isFresh(old)) return _remember(host, old.bytes);
      if (!_enabled()) return _remember(host, old?.bytes);

      final got = await _fetch(host);
      if (epoch != _epoch) return null;
      final now = _clock().millisecondsSinceEpoch;
      if (got.bytes != null) {
        await _db().putFavicon(
          host: host,
          bytes: got.bytes,
          contentType: got.type,
          fetchedAt: now,
        );
      } else if (!got.transient) {
        // Keep showing an older icon, but don't ask again for failureTtl.
        await _db().putFavicon(
          host: host,
          bytes: old?.bytes,
          contentType: old?.contentType,
          fetchedAt: now,
          failed: true,
        );
      }
      if (epoch != _epoch) return null;
      return _remember(host, got.bytes ?? old?.bytes);
    } on Object {
      // Locked (no database) or closed mid-fetch.
      return null;
    }
  }

  bool _isFresh(Favicon row) {
    final age = _clock().millisecondsSinceEpoch - row.fetchedAt;
    final ttl = row.failed ? failureTtl : successTtl;
    // A negative age means the clock went backwards: refresh.
    return age >= 0 && age < ttl.inMilliseconds;
  }

  Uint8List? _remember(String host, Uint8List? bytes) {
    _cache[host] = bytes;
    _notify();
    return bytes;
  }

  /// Coalesces the many updates of a prefetch into one rebuild per frame.
  void _notify() {
    if (_notifyScheduled || _disposed) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  // --- Fetching ------------------------------------------------------------

  /// `transient` is true when no server ever answered (offline, DNS failure,
  /// timeout before a response). Such failures are not cached.
  Future<({Uint8List? bytes, String? type, bool transient})> _fetch(
    String host,
  ) async {
    final run = _Run(registrableDomain(host));
    final candidates = <Uri>[];
    final page = await _get(
      Uri.https(host, '/'),
      run,
      maxBytes: maxHtmlBytes,
      truncate: true,
      accept: 'text/html,application/xhtml+xml',
    );
    if (page != null) {
      final html = utf8.decode(page.bytes, allowMalformed: true);
      candidates.addAll(
        iconLinks(
          html,
          page.url,
        ).where((u) => _allowedUrl(u, run.site)).take(maxLinkCandidates),
      );
    }
    final fallback = Uri.https(host, '/favicon.ico');
    if (!candidates.contains(fallback)) candidates.add(fallback);

    for (final url in candidates) {
      final body = await _get(
        url,
        run,
        maxBytes: maxIconBytes,
        truncate: false,
        accept: 'image/*',
      );
      final type = body == null ? null : imageType(body.bytes);
      if (type != null) {
        return (bytes: body!.bytes, type: type, transient: false);
      }
    }
    return (bytes: null, type: null, transient: !run.answered);
  }

  /// GET [url] following up to [maxRedirects] redirects, each checked against
  /// the site's rules. Returns the final URL and at most [maxBytes] of the
  /// body (cut off if [truncate], otherwise null when larger), or null.
  Future<({Uri url, Uint8List bytes})?> _get(
    Uri url,
    _Run run, {
    required int maxBytes,
    required bool truncate,
    required String accept,
  }) async {
    final abort = Completer<void>();
    final timer = Timer(timeout, () {
      if (!abort.isCompleted) abort.complete();
    });
    try {
      return await _follow(
        url,
        run,
        maxBytes,
        truncate,
        accept,
        abort.future,
      ).timeout(timeout);
    } on Object {
      return null;
    } finally {
      timer.cancel();
      // Closes a connection that is still open (no-op once complete).
      if (!abort.isCompleted) abort.complete();
    }
  }

  Future<({Uri url, Uint8List bytes})?> _follow(
    Uri url,
    _Run run,
    int maxBytes,
    bool truncate,
    String accept,
    Future<void> abort,
  ) async {
    var uri = url;
    for (var redirects = 0; ; redirects++) {
      if (!_allowedUrl(uri, run.site) ||
          !await _resolvesPublic(uri.host, run)) {
        run.answered = true; // a rule, not the network, said no
        return null;
      }
      // No cookies, no Referer: only these two headers (plus Host and
      // Accept-Encoding added by the HTTP stack).
      final req = http.AbortableRequest('GET', uri, abortTrigger: abort)
        ..followRedirects = false
        ..headers['User-Agent'] = userAgent
        ..headers['Accept'] = accept;
      final res = await _client.send(req);
      run.answered = true;
      final location = res.headers['location'];
      if (_redirectCodes.contains(res.statusCode) && location != null) {
        await _discard(res);
        if (redirects >= maxRedirects) return null;
        uri = uri.resolve(location).removeFragment();
        continue;
      }
      final declared = res.contentLength;
      if (res.statusCode != 200 ||
          (!truncate && declared != null && declared > maxBytes)) {
        await _discard(res);
        return null;
      }
      final bytes = await _read(res.stream, maxBytes, truncate: truncate);
      return bytes == null ? null : (url: uri, bytes: bytes);
    }
  }

  Future<bool> _resolvesPublic(String host, _Run run) async {
    final known = run.resolved[host];
    if (known != null) return known;
    final addresses = await _lookup(host);
    return run.resolved[host] =
        addresses.isNotEmpty && addresses.every(isPublicAddress);
  }

  static const _redirectCodes = {301, 302, 303, 307, 308};

  static Future<void> _discard(http.StreamedResponse res) async {
    try {
      await res.stream.listen(null, onError: (Object _) {}).cancel();
    } on Object {
      // Already closed.
    }
  }

  /// Reads at most [max] bytes and stops downloading there.
  static Future<Uint8List?> _read(
    Stream<List<int>> body,
    int max, {
    required bool truncate,
  }) async {
    final out = BytesBuilder(copy: false);
    await for (final chunk in body) {
      final room = max - out.length;
      if (chunk.length > room) {
        if (!truncate) return null;
        out.add(chunk.sublist(0, room));
        break;
      }
      out.add(chunk);
    }
    return out.takeBytes();
  }

  static bool _allowedUrl(Uri u, String site) =>
      u.scheme == 'https' &&
      u.userInfo.isEmpty &&
      u.port == 443 &&
      isPublicHost(u.host) &&
      registrableDomain(u.host) == site;

  // --- Host rules ----------------------------------------------------------

  /// The host to fetch an icon for, or null when [hostOrUrl] must not be
  /// fetched (non-web scheme such as `androidapp://`, IP literal, local name).
  static String? siteHost(String hostOrUrl) {
    final raw = hostOrUrl.trim();
    if (raw.isEmpty) return null;
    final Uri? uri;
    if (raw.contains('://')) {
      uri = Uri.tryParse(raw);
      if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
        return null;
      }
    } else {
      uri = Uri.tryParse('https://$raw');
    }
    var host = uri?.host.toLowerCase() ?? '';
    if (host.endsWith('.')) host = host.substring(0, host.length - 1);
    return isPublicHost(host) ? host : null;
  }

  static final _label = RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$');
  static final _tld = RegExp(r'^(?:[a-z]{2,63}|xn--[a-z0-9-]{1,59})$');

  /// Special-use and common private-network suffixes.
  static const _localTlds = {
    'localhost',
    'local',
    'internal',
    'intranet',
    'lan',
    'home',
    'corp',
    'private',
    'localdomain',
    'test',
    'invalid',
    'example',
    'onion',
    'arpa',
    'alt',
  };

  /// A lower-case DNS name with at least two labels and an alphabetic,
  /// non-local TLD. IPv4 literals fail the TLD check and IPv6 literals the
  /// label check.
  static bool isPublicHost(String host) {
    if (host.length > 253) return false;
    final labels = host.split('.');
    return labels.length >= 2 &&
        labels.every(_label.hasMatch) &&
        _tld.hasMatch(labels.last) &&
        !_localTlds.contains(labels.last);
  }

  /// Second-level labels under which ccTLDs register names (`example.co.uk`).
  static const _secondLevel = {
    'ac',
    'co',
    'com',
    'edu',
    'gov',
    'net',
    'org',
    'or',
    'ne',
    'go',
    'gob',
    'mil',
    'nic',
    'ltd',
    'plc',
    'sch',
    'nom',
  };

  /// Approximates the registrable domain ("eTLD+1") without the Public Suffix
  /// List: the last two labels, or three for `<x>.<second-level>.<ccTLD>`.
  /// Errs towards treating hosts as different sites (no icon), never towards
  /// leaving the site for an unrelated one.
  static String registrableDomain(String host) {
    final l = host.split('.');
    final n =
        l.length >= 3 &&
            l.last.length == 2 &&
            _secondLevel.contains(l[l.length - 2])
        ? 3
        : 2;
    return l.length <= n ? host : l.sublist(l.length - n).join('.');
  }

  /// False for loopback, private, link-local, CGNAT, multicast and other
  /// non-internet addresses, including IPv4 embedded in IPv6.
  @visibleForTesting
  static bool isPublicAddress(InternetAddress address) {
    final b = address.rawAddress;
    if (address.type == InternetAddressType.IPv4 && b.length == 4) {
      return _isPublicV4(b);
    }
    if (address.type != InternetAddressType.IPv6 || b.length != 16) {
      return false;
    }
    bool zero(int from, int to) => b.sublist(from, to).every((x) => x == 0);
    // ::a.b.c.d (incl. :: and ::1), ::ffff:a.b.c.d and NAT64 64:ff9b::a.b.c.d.
    if (zero(0, 12)) return _isPublicV4(b.sublist(12));
    if (zero(0, 10) && b[10] == 0xff && b[11] == 0xff) {
      return _isPublicV4(b.sublist(12));
    }
    if (b[0] == 0 && b[1] == 0x64 && b[2] == 0xff && b[3] == 0x9b) {
      return zero(4, 12) && _isPublicV4(b.sublist(12));
    }
    return (b[0] & 0xfe) != 0xfc && // fc00::/7 unique local
        !(b[0] == 0xfe && (b[1] & 0x80) == 0x80) && // fe80::/10, fec0::/10
        b[0] != 0xff; // multicast
  }

  static bool _isPublicV4(List<int> b) =>
      !(b[0] == 0 ||
          b[0] == 10 ||
          b[0] == 127 ||
          b[0] >= 224 || // multicast, reserved, broadcast
          (b[0] == 100 && b[1] >= 64 && b[1] < 128) || // CGNAT
          (b[0] == 169 && b[1] == 254) ||
          (b[0] == 172 && b[1] >= 16 && b[1] < 32) ||
          (b[0] == 192 && b[1] == 168) ||
          (b[0] == 192 && b[1] == 0 && b[2] == 0) ||
          (b[0] == 198 && (b[1] == 18 || b[1] == 19)));

  // --- HTML and image parsing ----------------------------------------------
  //
  // The page is attacker-controlled and parsed on the UI isolate, so tags and
  // comments are found with linear scans instead of regexes that could
  // backtrack quadratically on crafted input.

  static final _linkOpen = RegExp(r'<link\b', caseSensitive: false);
  static final _baseOpen = RegExp(r'<base\b', caseSensitive: false);
  static final _attr = RegExp(
    r'''([^\s"'<>/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?''',
  );
  static final _entity = RegExp(
    r'&(#x[0-9a-f]+|#[0-9]+|amp|quot|apos|lt|gt);',
    caseSensitive: false,
  );
  static final _whitespace = RegExp(r'\s+');
  static final _size = RegExp(r'^(\d{1,4})[xX](\d{1,4})$');

  /// Icon URLs declared by `<link rel=...>` in [html], best first: PNGs
  /// before other formats, larger `sizes` first, then document order. SVG
  /// and non-web URLs are skipped; `http:` is upgraded to `https:`. Relative
  /// hrefs resolve against `<base href>` or [pageUrl].
  @visibleForTesting
  static List<Uri> iconLinks(String html, Uri pageUrl) {
    final doc = _withoutComments(html);
    var base = pageUrl;
    final baseTag = _tagBodies(doc, _baseOpen).firstOrNull;
    final baseHref = _attributes(baseTag)['href'];
    if (baseHref != null) {
      final b = _resolve(pageUrl, baseHref);
      if (b != null) base = b;
    }
    final found = <({Uri url, bool png, int size, int order})>[];
    for (final body in _tagBodies(doc, _linkOpen)) {
      final a = _attributes(body);
      final rel = (a['rel'] ?? '').toLowerCase().split(_whitespace);
      final apple =
          rel.contains('apple-touch-icon') ||
          rel.contains('apple-touch-icon-precomposed');
      if (!apple && !rel.contains('icon')) continue; // also skips mask-icon
      final type = (a['type'] ?? '').toLowerCase();
      if (type.contains('svg')) continue;
      final url = _resolve(base, a['href'] ?? '');
      if (url == null) continue;
      final path = url.path.toLowerCase();
      if (path.endsWith('.svg') || path.endsWith('.svgz')) continue;
      found.add((
        url: url,
        png: type == 'image/png' || path.endsWith('.png'),
        // Apple's documented default for an unsized touch icon.
        size: _largestSize(a['sizes']) ?? (apple ? 180 : 0),
        order: found.length,
      ));
    }
    found.sort((x, y) {
      if (x.png != y.png) return x.png ? -1 : 1;
      if (x.size != y.size) return y.size - x.size;
      return x.order - y.order;
    });
    return {for (final f in found) f.url}.toList();
  }

  static String _withoutComments(String html) {
    final out = StringBuffer();
    var i = 0;
    while (true) {
      final start = html.indexOf('<!--', i);
      if (start < 0) {
        out.write(html.substring(i));
        break;
      }
      out.write(html.substring(i, start));
      final end = html.indexOf('-->', start + 4);
      if (end < 0) break; // an unterminated comment runs to the end
      i = end + 3;
    }
    return out.toString();
  }

  /// The text between each match of [open] and the next `>`. Like an HTML
  /// tokenizer, scanning resumes after that `>`.
  static Iterable<String> _tagBodies(String doc, RegExp open) sync* {
    var i = 0;
    while (true) {
      final m = open.allMatches(doc, i).firstOrNull;
      if (m == null) return;
      final end = doc.indexOf('>', m.end);
      if (end < 0) return;
      yield doc.substring(m.end, end);
      i = end + 1;
    }
  }

  static Uri? _resolve(Uri base, String href) {
    final h = href.trim();
    if (h.isEmpty) return null;
    try {
      final u = base.resolve(h).removeFragment();
      if (u.scheme == 'https') return u;
      if (u.scheme == 'http') return u.replace(scheme: 'https');
    } on FormatException {
      // Unparseable href.
    }
    return null; // data:, javascript:, ...
  }

  /// Lower-case attribute names to unescaped values (first one wins).
  static Map<String, String> _attributes(String? tagBody) {
    final out = <String, String>{};
    if (tagBody == null) return out;
    for (final m in _attr.allMatches(tagBody)) {
      final value = m.group(2) ?? m.group(3) ?? m.group(4) ?? '';
      out.putIfAbsent(m.group(1)!.toLowerCase(), () => _unescape(value));
    }
    return out;
  }

  static String _unescape(String s) {
    if (!s.contains('&')) return s;
    return s.replaceAllMapped(_entity, (m) {
      final e = m.group(1)!.toLowerCase();
      final code = e.startsWith('#x')
          ? int.tryParse(e.substring(2), radix: 16)
          : e.startsWith('#')
          ? int.tryParse(e.substring(1))
          : null;
      if (code != null) {
        return code > 0 && code <= 0x10ffff
            ? String.fromCharCode(code)
            : m.group(0)!;
      }
      return const {
        'amp': '&',
        'quot': '"',
        'apos': "'",
        'lt': '<',
        'gt': '>',
      }[e]!;
    });
  }

  /// Largest edge in a `sizes` attribute ("16x16 32x32" -> 32); null if
  /// absent or unparseable ("any" is usually SVG and ranks as 0).
  static int? _largestSize(String? sizes) {
    if (sizes == null) return null;
    int? best;
    for (final token in sizes.trim().split(_whitespace)) {
      if (token.toLowerCase() == 'any') {
        best ??= 0;
        continue;
      }
      final m = _size.firstMatch(token);
      if (m == null) continue;
      final edge = math.max(int.parse(m.group(1)!), int.parse(m.group(2)!));
      best = math.max(best ?? 0, edge);
    }
    return best;
  }

  /// Largest width or height accepted. A few hundred bytes of PNG can declare
  /// a 40000x40000 image that takes gigabytes to decode; once cached, such an
  /// icon would crash the app on every unlock.
  static const int maxIconEdge = 1024;

  /// MIME type of [b] judged by its magic bytes, for the raster formats
  /// Flutter can decode, provided the header declares at most [maxIconEdge]
  /// pixels per side. Anything else (SVG, HTML error pages, image bombs,
  /// unparseable headers) is null, whatever the server's Content-Type said.
  @visibleForTesting
  static String? imageType(Uint8List b) {
    final type = _sniff(b);
    if (type == null) return null;
    final size = _dimensions(b, type);
    final ok =
        size != null &&
        size.w > 0 &&
        size.h > 0 &&
        size.w <= maxIconEdge &&
        size.h <= maxIconEdge;
    return ok ? type : null;
  }

  static bool _at(Uint8List b, int offset, List<int> sig) {
    if (b.length < offset + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (b[offset + i] != sig[i]) return false;
    }
    return true;
  }

  static const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

  static String? _sniff(Uint8List b) {
    if (_at(b, 0, _pngSignature)) return 'image/png';
    if (_at(b, 0, const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (_at(b, 0, 'GIF87a'.codeUnits) || _at(b, 0, 'GIF89a'.codeUnits)) {
      return 'image/gif';
    }
    if (_at(b, 0, 'RIFF'.codeUnits) && _at(b, 8, 'WEBP'.codeUnits)) {
      return 'image/webp';
    }
    // ICONDIR: reserved 0, type 1 (icon, not cursor), image count, then a
    // 16-byte directory entry per image.
    if (_at(b, 0, const [0, 0, 1, 0]) && b.length >= 6) {
      final count = b[4] | (b[5] << 8);
      if (count > 0 && b.length >= 6 + 16 * count) return 'image/x-icon';
    }
    return null;
  }

  /// Pixel size declared in the header of an image of [type].
  static ({int w, int h})? _dimensions(Uint8List b, String type) {
    final d = ByteData.sublistView(b);
    switch (type) {
      case 'image/png':
        // IHDR is always the first chunk.
        if (b.length < 24 || !_at(b, 12, 'IHDR'.codeUnits)) return null;
        return (w: d.getUint32(16), h: d.getUint32(20));
      case 'image/gif':
        if (b.length < 10) return null;
        return (
          w: d.getUint16(6, Endian.little),
          h: d.getUint16(8, Endian.little),
        );
      case 'image/webp':
        if (b.length < 25) return null;
        if (_at(b, 12, 'VP8L'.codeUnits) && b[20] == 0x2f) {
          final bits = d.getUint32(21, Endian.little);
          return (w: (bits & 0x3fff) + 1, h: ((bits >> 14) & 0x3fff) + 1);
        }
        if (b.length < 30) return null;
        if (_at(b, 12, 'VP8X'.codeUnits)) {
          return (
            w: 1 + (b[24] | (b[25] << 8) | (b[26] << 16)),
            h: 1 + (b[27] | (b[28] << 8) | (b[29] << 16)),
          );
        }
        if (_at(b, 12, 'VP8 '.codeUnits) &&
            _at(b, 23, const [0x9d, 0x01, 0x2a])) {
          return (
            w: d.getUint16(26, Endian.little) & 0x3fff,
            h: d.getUint16(28, Endian.little) & 0x3fff,
          );
        }
        return null;
      case 'image/jpeg':
        return _jpegDimensions(b);
      case 'image/x-icon':
        return _icoDimensions(b, d);
    }
    return null;
  }

  /// Walks the marker segments up to the first start-of-frame.
  static ({int w, int h})? _jpegDimensions(Uint8List b) {
    var i = 2;
    while (i + 9 <= b.length) {
      if (b[i] != 0xFF) return null;
      final marker = b[i + 1];
      if (marker == 0xFF) {
        i++; // fill byte
        continue;
      }
      if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD8)) {
        i += 2; // no length field
        continue;
      }
      if (marker == 0xD9 || marker == 0xDA) return null; // no frame header
      // SOF0..SOF15, except DHT (C4), JPG (C8) and DAC (CC).
      if (marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC) {
        return (w: (b[i + 7] << 8) | b[i + 8], h: (b[i + 5] << 8) | b[i + 6]);
      }
      final length = (b[i + 2] << 8) | b[i + 3];
      if (length < 2) return null;
      i += 2 + length;
    }
    return null;
  }

  /// Largest image in the icon. The directory's own size bytes can't be
  /// trusted (an entry says 16x16, its embedded PNG says otherwise), so each
  /// embedded PNG or BMP header is read.
  static ({int w, int h})? _icoDimensions(Uint8List b, ByteData d) {
    var w = 0;
    var h = 0;
    for (var k = 0; k < (b[4] | (b[5] << 8)); k++) {
      final entry = 6 + 16 * k;
      final length = d.getUint32(entry + 8, Endian.little);
      final offset = d.getUint32(entry + 12, Endian.little);
      if (offset >= b.length) return null;
      final image = Uint8List.sublistView(
        b,
        offset,
        math.min(b.length, offset + length),
      );
      final ({int w, int h})? size;
      if (_at(image, 0, _pngSignature)) {
        size = _dimensions(image, 'image/png');
      } else if (image.length >= 12) {
        // BITMAPINFOHEADER; the height covers the XOR and AND masks.
        final bmp = ByteData.sublistView(image);
        size = (
          w: bmp.getInt32(4, Endian.little).abs(),
          h: bmp.getInt32(8, Endian.little).abs() ~/ 2,
        );
      } else {
        size = null;
      }
      if (size == null) return null;
      w = math.max(w, size.w);
      h = math.max(h, size.h);
    }
    return (w: w, h: h);
  }
}

/// State shared by the requests made for one host.
class _Run {
  _Run(this.site);

  /// Registrable domain every URL must stay on.
  final String site;

  /// A server answered, or a rule rejected a URL. A failure is then real (not
  /// a network blip) and is cached for [FaviconService.failureTtl].
  bool answered = false;

  /// Host -> resolves only to public addresses.
  final Map<String, bool> resolved = {};
}
