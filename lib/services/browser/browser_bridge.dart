import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:khazna_bridge/bridge_protocol.dart';

import '../../data/models/vault_entry.dart';
import '../autofill_matcher.dart';
import '../settings.dart';
import '../vault_session.dart';
import 'browser_activity.dart';
import 'browser_registration.dart';

/// A browser extension waiting for the user to allow it.
class PairingRequest {
  PairingRequest._(this.code, this.browser);

  /// The six digits the extension shows too ([pairingCode]).
  final String code;

  /// What the extension called its browser.
  final String browser;

  final Completer<bool> _answer = Completer<bool>();
}

/// One connection from the browser helper.
class BridgeClient {
  /// The SHA-256 (hex) of the extension's key once it has said hello with a
  /// key the user paired; null before.
  String? keyHash;

  /// The browser it said it runs in ("Chrome", "Edge"...).
  String browser = '';
}

/// The app's end of the browser extension (Windows).
///
/// The extension reaches the app through the browser helper
/// (`browser/bridge`), which connects to a loopback port that only the app's
/// current run knows: [start] writes the port and a fresh random token to
/// `endpoint.json` in [directory] (in the user's profile), and a connection
/// that does not send that token first is closed.
///
/// What the extension may do, and how the app keeps it in check:
///
/// * Nothing before the user pairs it: the app shows the six-digit code the
///   extension shows ([pendingPairing]) and the user allows it. Only a hash
///   of the extension's key is kept ([AppSettings.pairedBrowsers]).
/// * Fill: the extension sends the page's address; the app decides which
///   logins belong to it ([AutofillMatcher], https pages only) and sends a
///   password only for one of those, only while unlocked. The extension
///   stores nothing.
/// * Save or update a login after the user signed in on a page and said yes
///   in the browser. Every fill, save and update goes in the
///   [BrowserActivityLog].
class BrowserBridge extends ChangeNotifier {
  BrowserBridge({
    required this.session,
    required this.settings,
    required this.activity,
    required this.directory,
    this.registration,
    this.showWindow,
    this.appVersion = '',
    this.pairTimeout = const Duration(minutes: 2),
    this.authTimeout = const Duration(seconds: 5),
    Random? random,
  }) : _random = random ?? Random.secure();

  final VaultSession session;
  final AppSettings settings;
  final BrowserActivityLog activity;

  /// Where [start] writes `endpoint.json`; null when there is no profile
  /// folder (then the bridge cannot start).
  final Directory? directory;

  /// Registers the helper with the browsers; null in tests and where the
  /// helper is not shipped.
  final BrowserRegistration? registration;

  /// Brings the app's window to the front (pairing, "Show Khazna").
  final Future<void> Function()? showWindow;

  /// The app's version, told to the extension.
  final String appVersion;
  final Duration pairTimeout;

  /// How long a new connection has to send the token.
  final Duration authTimeout;
  final Random _random;

  /// Connections served at once; more are closed.
  static const int maxConnections = 8;

  /// The largest request the app reads.
  static const int maxRequestBytes = 64 * 1024;

  /// Logins listed for one page at most.
  static const int maxListed = 50;

  ServerSocket? _server;
  String? _token;
  final Set<_Connection> _connections = {};
  PairingRequest? _pending;

  /// Listening for the helper.
  bool get running => _server != null;

  /// Helpers connected now.
  int get connections => _connections.length;

  /// The extension the user is asked to allow, if any.
  PairingRequest? get pendingPairing => _pending;

  /// The port the helper connects to (tests).
  @visibleForTesting
  int? get port => _server?.port;

  // ---------------------------------------------------------------------------
  // Turning it on and off
  // ---------------------------------------------------------------------------

  /// Sets the extension up: registers the helper with the browsers, turns the
  /// setting on and starts listening. False if the helper could not be
  /// registered (a development build without it).
  Future<bool> enable() async {
    final reg = registration;
    if (reg != null && !await reg.register()) return false;
    await settings.update((s) => s.browserExtension = true);
    await start();
    return true;
  }

  /// Turns the extension off: stops listening, unregisters the helper and
  /// forgets every paired browser.
  Future<void> disable() async {
    await stop();
    await registration?.unregister();
    await settings.update((s) {
      s.browserExtension = false;
      s.pairedBrowsers = const [];
    });
  }

  /// At start-up: listens if the user turned the extension on, and registers
  /// the helper again (the app folder may have moved).
  Future<void> resume() async {
    if (!settings.browserExtension) return;
    try {
      await registration?.register(force: false);
      await start();
    } on Object catch (e) {
      debugPrint('BrowserBridge: not started (${e.runtimeType})');
    }
  }

  Future<void> start() async {
    if (_server != null) return;
    final dir = directory;
    if (dir == null) throw StateError('No folder for the endpoint');
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final token = _hex(List.generate(32, (_) => _random.nextInt(256)));
    try {
      await dir.create(recursive: true);
      final file = endpointFile(dir);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
        jsonEncode(
          BridgeEndpoint(port: server.port, token: token, pid: pid).toJson(),
        ),
        flush: true,
      );
      await tmp.rename(file.path);
    } on Object {
      await server.close();
      rethrow;
    }
    _server = server;
    _token = token;
    server.listen(_accept);
    notifyListeners();
  }

  Future<void> stop() async {
    final server = _server;
    if (server == null) return;
    _server = null;
    await server.close();
    for (final c in [..._connections]) {
      c.close();
    }
    _connections.clear();
    _answer(false);
    final dir = directory;
    if (dir != null) {
      final file = endpointFile(dir);
      try {
        final ours = BridgeEndpoint.tryParse(await file.readAsString());
        if (ours?.token == _token) await file.delete();
      } on FileSystemException {
        // Already gone.
      }
    }
    _token = null;
    notifyListeners();
  }

  /// Forgets a paired browser; its connections stop working at once.
  Future<void> unpair(String keyHash) async {
    await settings.update(
      (s) => s.pairedBrowsers = [
        for (final b in s.pairedBrowsers)
          if (b.keyHash != keyHash) b,
      ],
    );
    for (final c in _connections) {
      if (c.client.keyHash == keyHash) c.client.keyHash = null;
    }
  }

  /// The user's answer to [pendingPairing].
  void answerPairing(bool allow) => _answer(allow);

  void _answer(bool allow) {
    final p = _pending;
    if (p == null) return;
    _pending = null;
    if (!p._answer.isCompleted) p._answer.complete(allow);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Connections
  // ---------------------------------------------------------------------------

  void _accept(Socket socket) {
    if (_connections.length >= maxConnections) {
      socket.destroy();
      return;
    }
    final c = _Connection(socket);
    _connections.add(c);
    notifyListeners();
    c.authTimer = Timer(authTimeout, () => _closed(c));
    socket.listen(
      (chunk) => _onData(c, chunk),
      onDone: () => _closed(c),
      onError: (Object _) => _closed(c),
      cancelOnError: true,
    );
  }

  void _onData(_Connection c, List<int> chunk) {
    final List<Map<String, Object?>> frames;
    try {
      frames = c.decoder.add(chunk);
    } on FrameException {
      _closed(c);
      return;
    }
    for (final msg in frames) {
      if (c.closed) return;
      if (!c.authed) {
        final token = _token;
        final sent = msg['token'];
        if (msg['t'] != 'bridge' ||
            token == null ||
            sent is! String ||
            !_sameText(sent, token)) {
          _closed(c);
          return;
        }
        c.authed = true;
        c.authTimer?.cancel();
        continue;
      }
      unawaited(
        handle(c.client, msg).then((reply) {
          if (c.closed) return;
          try {
            c.socket.add(encodeFrame(reply));
          } on Object {
            _closed(c);
          }
        }),
      );
    }
  }

  void _closed(_Connection c) {
    c.close();
    if (_connections.remove(c)) notifyListeners();
    // The browser went away while the user was being asked.
    final p = _pending;
    if (p != null && c.pairing == p) _answer(false);
  }

  // ---------------------------------------------------------------------------
  // Requests
  // ---------------------------------------------------------------------------

  /// Answers one request from the extension. Always returns a reply with the
  /// request's `id`; a failure is `{"ok": false, "error": <code>}`.
  @visibleForTesting
  Future<Map<String, Object?>> handle(
    BridgeClient client,
    Map<String, Object?> msg,
  ) async {
    final id = msg['id'];
    Map<String, Object?> reply;
    try {
      reply = await _dispatch(client, msg);
    } on _Refused catch (e) {
      reply = {'ok': false, 'error': e.code};
    } on Object catch (e) {
      debugPrint('BrowserBridge: request failed (${e.runtimeType})');
      reply = {'ok': false, 'error': 'failed'};
    }
    return {if (id is int || id is String) 'id': id, ...reply};
  }

  Future<Map<String, Object?>> _dispatch(
    BridgeClient client,
    Map<String, Object?> msg,
  ) async {
    switch (msg['t']) {
      case 'hello':
        return _hello(client, msg);
      case 'pair':
        return _pair(client, msg);
    }
    _requirePaired(client);
    switch (msg['t']) {
      case 'status':
        return {'ok': true, 'state': _state()};
      case 'show':
        await showWindow?.call();
        return {'ok': true};
      case 'list':
        return _list(msg);
      case 'fill':
        return _fill(client, msg);
      case 'check':
        return _check(msg);
      case 'save':
        return _save(client, msg);
    }
    throw const _Refused('unknown_request');
  }

  Map<String, Object?> _hello(BridgeClient client, Map<String, Object?> msg) {
    final hash = _keyHash(msg['key']);
    final paired = settings.pairedBrowsers.any((b) => b.keyHash == hash);
    client.keyHash = paired ? hash : null;
    client.browser = _browserName(msg['browser']);
    return {
      'ok': true,
      'paired': paired,
      'app': appVersion,
      if (paired) 'state': _state(),
    };
  }

  Future<Map<String, Object?>> _pair(
    BridgeClient client,
    Map<String, Object?> msg,
  ) async {
    final key = _keyBytes(msg['key']);
    final digest = sha256.convert(key);
    final hash = digest.toString();
    final browser = _browserName(msg['browser']);
    if (settings.pairedBrowsers.any((b) => b.keyHash == hash)) {
      client
        ..keyHash = hash
        ..browser = browser;
      return {'ok': true, 'paired': true, 'state': _state()};
    }
    if (_pending != null) throw const _Refused('busy');
    final request = PairingRequest._(pairingCode(digest.bytes), browser);
    _pending = request;
    for (final c in _connections) {
      if (identical(c.client, client)) c.pairing = request;
    }
    notifyListeners();
    unawaited(showWindow?.call());

    final allowed = await request._answer.future.timeout(
      pairTimeout,
      onTimeout: () {
        if (identical(_pending, request)) _answer(false);
        return false;
      },
    );
    if (!allowed) throw const _Refused('denied');
    await settings.update(
      (s) => s.pairedBrowsers = [
        for (final b in s.pairedBrowsers)
          if (b.keyHash != hash) b,
        PairedBrowser(
          keyHash: hash,
          name: browser,
          pairedAt: DateTime.now().toUtc(),
        ),
      ],
    );
    client
      ..keyHash = hash
      ..browser = browser;
    await activity.add(BrowserActivityKind.paired, host: '', browser: browser);
    return {'ok': true, 'paired': true, 'state': _state()};
  }

  Map<String, Object?> _list(Map<String, Object?> msg) {
    final host = _httpsHost(msg['url']);
    _requireUnlocked();
    final found = _matching(host);
    return {
      'ok': true,
      'entries': [
        for (final e in found.take(maxListed))
          {'id': e.id, 'title': e.title, 'username': e.username},
      ],
    };
  }

  Future<Map<String, Object?>> _fill(
    BridgeClient client,
    Map<String, Object?> msg,
  ) async {
    final host = _httpsHost(msg['url']);
    final id = msg['entry'];
    if (id is! String) throw const _Refused('bad_request');
    _requireUnlocked();
    final entry = _matching(host).where((e) => e.id == id).firstOrNull;
    if (entry == null) throw const _Refused('not_found');
    unawaited(session.markUsed(entry.id));
    await activity.add(
      BrowserActivityKind.filled,
      host: host,
      title: entry.title,
      browser: client.browser,
    );
    return {'ok': true, 'username': entry.username, 'password': entry.password};
  }

  Map<String, Object?> _check(Map<String, Object?> msg) {
    final host = _httpsHost(msg['url']);
    final username = _text(msg['username'], max: 512);
    final password = _text(msg['password'], max: 4096);
    _requireUnlocked();
    if (password.isEmpty) return {'ok': true, 'action': 'none'};
    final sameUser = _matching(host)
        .where((e) => _sameUser(e.username, username))
        .toList();
    if (sameUser.any((e) => e.password == password)) {
      return {'ok': true, 'action': 'none'};
    }
    if (sameUser.isNotEmpty) {
      final e = sameUser.first;
      return {'ok': true, 'action': 'update', 'entry': e.id, 'title': e.title};
    }
    return {'ok': true, 'action': 'save', 'title': _titleFor(host)};
  }

  Future<Map<String, Object?>> _save(
    BridgeClient client,
    Map<String, Object?> msg,
  ) async {
    final host = _httpsHost(msg['url']);
    final username = _text(msg['username'], max: 512).trim();
    final password = _text(msg['password'], max: 4096);
    final id = msg['entry'];
    if (password.isEmpty || (id != null && id is! String)) {
      throw const _Refused('bad_request');
    }
    _requireUnlocked();
    final VaultEntry saved;
    final BrowserActivityKind kind;
    if (id is String) {
      final entry = _matching(host).where((e) => e.id == id).firstOrNull;
      if (entry == null) throw const _Refused('not_found');
      saved = entry.edit(
        password: password,
        username: entry.username.isEmpty && username.isNotEmpty
            ? username
            : null,
      );
      kind = BrowserActivityKind.updated;
    } else {
      saved = VaultEntry(
        id: VaultSession.newId(),
        title: _titleFor(host),
        username: username,
        password: password,
        url: 'https://$host',
      );
      kind = BrowserActivityKind.saved;
    }
    await session.saveEntry(saved);
    await activity.add(
      kind,
      host: host,
      title: saved.title,
      browser: client.browser,
    );
    return {'ok': true, 'entry': saved.id};
  }

  // ---------------------------------------------------------------------------
  // Checks
  // ---------------------------------------------------------------------------

  void _requirePaired(BridgeClient client) {
    final hash = client.keyHash;
    if (hash == null ||
        !settings.pairedBrowsers.any((b) => b.keyHash == hash)) {
      client.keyHash = null;
      throw const _Refused('not_paired');
    }
  }

  void _requireUnlocked() {
    if (!session.isUnlocked) throw const _Refused('locked');
  }

  String _state() => switch (session.state) {
    VaultState.unlocked => 'unlocked',
    VaultState.locked => 'locked',
    VaultState.noVault => 'no_vault',
    VaultState.loading => 'locked',
  };

  /// The logins of [host], most recently used first.
  List<VaultEntry> _matching(String host) {
    final used = session.lastUsedMap;
    int time(VaultEntry e) =>
        (used[e.id] ?? e.updatedAt).millisecondsSinceEpoch;
    return AutofillMatcher.match(session.entries, domain: host)
      ..sort((a, b) => time(b).compareTo(time(a)));
  }

  /// The lower-case host of an https address; anything else is refused.
  static String _httpsHost(Object? url) {
    if (url is! String || url.length > 4096) {
      throw const _Refused('bad_request');
    }
    final uri = Uri.tryParse(url);
    if (uri == null) throw const _Refused('bad_request');
    if (uri.scheme != 'https') throw const _Refused('insecure_page');
    final host = uri.host.toLowerCase();
    if (host.isEmpty) throw const _Refused('bad_request');
    return host;
  }

  static String _text(Object? v, {required int max}) {
    if (v == null) return '';
    if (v is! String || v.length > max) throw const _Refused('bad_request');
    return v;
  }

  static bool _sameUser(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  static String _titleFor(String host) =>
      host.startsWith('www.') ? host.substring(4) : host;

  /// The extension's key: 32 random bytes, base64url without padding.
  static List<int> _keyBytes(Object? key) {
    if (key is! String || !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(key)) {
      throw const _Refused('bad_request');
    }
    return base64Url.decode('$key=');
  }

  static String _keyHash(Object? key) =>
      sha256.convert(_keyBytes(key)).toString();

  static String _browserName(Object? v) {
    if (v is! String) return '';
    final s = v.replaceAll(RegExp(r'[^A-Za-z0-9 ._-]'), '').trim();
    return s.length > 32 ? s.substring(0, 32) : s;
  }

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Compares in time that does not depend on where they differ.
  static bool _sameText(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}

class _Refused implements Exception {
  const _Refused(this.code);

  final String code;
}

class _Connection {
  _Connection(this.socket);

  final Socket socket;
  final BridgeClient client = BridgeClient();
  final FrameDecoder decoder = FrameDecoder(
    maxBytes: BrowserBridge.maxRequestBytes,
  );
  Timer? authTimer;
  bool authed = false;
  bool closed = false;
  PairingRequest? pairing;

  void close() {
    if (closed) return;
    closed = true;
    authTimer?.cancel();
    socket.destroy();
  }
}
