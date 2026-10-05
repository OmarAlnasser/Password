import 'dart:convert';

import 'package:crypto/crypto.dart' as hashes;
import 'package:http/http.dart' as http;

import '../data/models/vault_entry.dart';
import 'password_generator.dart';

/// Have I Been Pwned "Pwned Passwords" range API (k-anonymity).
///
/// Only the first 5 hex characters of SHA-1(password) are sent. The server
/// returns every suffix with that prefix (~800) and we compare locally. With
/// `Add-Padding: true` the response is padded with fake zero-count entries so
/// its size does not reveal the prefix bucket.
class BreachChecker {
  BreachChecker({http.Client? client, Uri? baseUri})
    : _client = client ?? http.Client(),
      _base = baseUri ?? Uri.parse('https://api.pwnedpasswords.com/range/');

  final http.Client _client;
  final Uri _base;
  final Map<String, Map<String, int>> _cache = {};

  static String sha1Hex(String password) =>
      hashes.sha1.convert(utf8.encode(password)).toString().toUpperCase();

  /// Number of times the password appears in known breaches (0 = not found).
  Future<int> pwnedCount(String password) async {
    final hash = sha1Hex(password);
    final prefix = hash.substring(0, 5);
    final suffix = hash.substring(5);
    final table = _cache[prefix] ??= await _fetch(prefix);
    return table[suffix] ?? 0;
  }

  Future<Map<String, int>> _fetch(String prefix) async {
    final res = await _client.get(
      _base.resolve(prefix),
      headers: const {'Add-Padding': 'true', 'User-Agent': 'VaultSnap'},
    );
    if (res.statusCode != 200) {
      throw http.ClientException('HIBP returned ${res.statusCode}');
    }
    final out = <String, int>{};
    for (final line in const LineSplitter().convert(res.body)) {
      final i = line.indexOf(':');
      if (i != 35) continue; // 35 hex suffix chars
      final count = int.tryParse(line.substring(i + 1).trim()) ?? 0;
      if (count > 0) out[line.substring(0, i).toUpperCase()] = count;
    }
    return out;
  }

  void clearCache() => _cache.clear();
}

class SecurityReport {
  SecurityReport({
    required this.weak,
    required this.reused,
    required this.old,
    this.breached = const {},
  });

  final List<VaultEntry> weak;

  /// Groups of entries sharing the same password (each group >= 2).
  final List<List<VaultEntry>> reused;
  final List<VaultEntry> old;

  /// Entry id -> breach count.
  final Map<String, int> breached;

  int get issueCount =>
      weak.length +
      reused.fold<int>(0, (n, g) => n + g.length) +
      old.length +
      breached.length;
}

/// Offline analysis of the decrypted vault (never leaves the device).
class SecurityAnalyzer {
  SecurityAnalyzer(this._meter);

  final StrengthMeter _meter;

  static const Duration oldAfter = Duration(days: 365);

  SecurityReport analyze(List<VaultEntry> entries, {DateTime? now}) {
    final t = (now ?? DateTime.now()).toUtc();
    final withPw = entries.where((e) => e.password.isNotEmpty).toList();
    final weak = [
      for (final e in withPw)
        if (_meter
                .evaluate(e.password, userInputs: [e.username, e.title, e.host])
                .score <
            3)
          e,
    ];
    final byPw = <String, List<VaultEntry>>{};
    for (final e in withPw) {
      (byPw[e.password] ??= []).add(e);
    }
    final reused = byPw.values.where((g) => g.length > 1).toList();
    final old = [
      for (final e in withPw)
        if (t.difference(e.passwordChangedAt) > oldAfter) e,
    ];
    return SecurityReport(weak: weak, reused: reused, old: old);
  }

  Future<Map<String, int>> checkBreaches(
    List<VaultEntry> entries,
    BreachChecker checker,
  ) async {
    final out = <String, int>{};
    for (final e in entries.where((e) => e.password.isNotEmpty)) {
      final n = await checker.pwnedCount(e.password);
      if (n > 0) out[e.id] = n;
    }
    return out;
  }
}
