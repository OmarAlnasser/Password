import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../vault_session.dart';

/// What the browser extension did.
enum BrowserActivityKind {
  /// Filled a login into a page.
  filled,

  /// Saved a new login from a page.
  saved,

  /// Changed the password of a login after the user signed in with a new one.
  updated,

  /// A browser was allowed to use the vault.
  paired,
}

/// One line of the activity log. Never holds a password or a username: only
/// which site, which entry and which browser.
class BrowserActivity {
  const BrowserActivity({
    required this.at,
    required this.kind,
    required this.host,
    this.title = '',
    this.browser = '',
  });

  final DateTime at;
  final BrowserActivityKind kind;
  final String host;

  /// The entry's title when it happened.
  final String title;
  final String browser;

  Map<String, Object?> toJson() => {
    't': at.millisecondsSinceEpoch,
    'k': kind.name,
    'h': host,
    if (title.isNotEmpty) 'n': title,
    if (browser.isNotEmpty) 'b': browser,
  };

  static BrowserActivity? tryParse(Object? j) {
    if (j is! Map) return null;
    final t = j['t'];
    final k = BrowserActivityKind.values.asNameMap()[j['k']];
    final h = j['h'];
    if (t is! int || k == null || h is! String) return null;
    final n = j['n'];
    final b = j['b'];
    return BrowserActivity(
      at: DateTime.fromMillisecondsSinceEpoch(t, isUtc: true),
      kind: k,
      host: h,
      title: n is String ? n : '',
      browser: b is String ? b : '',
    );
  }
}

/// What the browser extension did, newest first, with a count of the lines
/// the user has not seen yet.
///
/// It lives in the encrypted database (which sites were filled is vault
/// metadata), so it is there only while the vault is unlocked; it is local to
/// this device and never synced.
class BrowserActivityLog extends ChangeNotifier {
  BrowserActivityLog(this.session, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    session.addListener(_onSession);
    session.onLock.add(_forget);
    _onSession();
  }

  final VaultSession session;
  final DateTime Function() _clock;

  /// Lines kept; older ones are dropped.
  static const int maxEntries = 200;

  static const _logKey = 'browserActivity';
  static const _seenKey = 'browserActivitySeen';

  List<BrowserActivity> _events = const [];
  int _seenMs = 0;
  bool _loaded = false;
  Future<void>? _loading;

  /// Newest first. Empty while locked.
  List<BrowserActivity> get events => _events;

  /// How many [events] are newer than the last [markSeen].
  int get unseen =>
      _events.where((e) => e.at.millisecondsSinceEpoch > _seenMs).length;

  void _onSession() {
    if (session.isUnlocked && !_loaded && _loading == null) {
      _loading = _load().whenComplete(() => _loading = null);
    }
  }

  Future<void> _load() async {
    final db = session.db;
    try {
      final raw = await db.getKv(_logKey);
      final seen = int.tryParse(await db.getKv(_seenKey) ?? '') ?? 0;
      if (!identical(db, _dbOrNull)) return; // locked meanwhile
      final list = raw == null ? const [] : jsonDecode(raw);
      _events = [
        if (list is List)
          for (final j in list) ?BrowserActivity.tryParse(j),
      ];
      _seenMs = seen;
    } on Object catch (e) {
      debugPrint('BrowserActivityLog: not loaded (${e.runtimeType})');
    }
    _loaded = true;
    notifyListeners();
  }

  Object? get _dbOrNull => session.isUnlocked ? session.db : null;

  void _forget() {
    _events = const [];
    _seenMs = 0;
    _loaded = false;
    notifyListeners();
  }

  /// Adds a line now. Does nothing while locked.
  Future<void> add(
    BrowserActivityKind kind, {
    required String host,
    String title = '',
    String browser = '',
  }) async {
    if (!session.isUnlocked) return;
    await _loading;
    _events = [
      BrowserActivity(
        at: _clock().toUtc(),
        kind: kind,
        host: host,
        title: title,
        browser: browser,
      ),
      ..._events,
    ].take(maxEntries).toList();
    notifyListeners();
    await _save();
  }

  /// The user looked at the log.
  Future<void> markSeen() async {
    if (_events.isEmpty) return;
    final newest = _events.first.at.millisecondsSinceEpoch;
    if (newest <= _seenMs) return;
    _seenMs = newest;
    notifyListeners();
    await _write(_seenKey, '$newest');
  }

  Future<void> clear() async {
    _events = const [];
    notifyListeners();
    await _save();
  }

  Future<void> _save() =>
      _write(_logKey, jsonEncode([for (final e in _events) e.toJson()]));

  Future<void> _write(String key, String value) async {
    if (!session.isUnlocked) return;
    try {
      await session.db.setKv(key, value);
    } on Object catch (e) {
      // A lock can race the write; the line stays in memory until then.
      debugPrint('BrowserActivityLog: not saved (${e.runtimeType})');
    }
  }

  @override
  void dispose() {
    session.removeListener(_onSession);
    session.onLock.remove(_forget);
    super.dispose();
  }
}
