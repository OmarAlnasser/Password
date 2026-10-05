import '../data/models/vault_entry.dart';

/// Decides which entries may be offered for an autofill request.
///
/// * Web (domain known, only reported by trusted browsers): exact host or a
///   subdomain of the entry's host. `accounts.example.com` matches an entry
///   for `example.com`; `example.com.evil.io` and `evil-example.com` do not.
/// * Native apps: only entries explicitly linked with
///   `androidapp://<package>` (or `iosapp://<bundle id>`).
class AutofillMatcher {
  static List<VaultEntry> match(
    List<VaultEntry> entries, {
    String? domain,
    String? appId,
  }) {
    final d = _normHost(domain);
    return [
      for (final e in entries)
        if (_matches(e, d, appId)) e,
    ];
  }

  static bool _matches(VaultEntry e, String? domain, String? appId) {
    final url = e.url.trim().toLowerCase();
    if (appId != null && appId.isNotEmpty) {
      if (url == 'androidapp://${appId.toLowerCase()}' ||
          url == 'iosapp://${appId.toLowerCase()}') {
        return true;
      }
    }
    if (domain == null || domain.isEmpty) return false;
    final host = _normHost(e.host);
    if (host == null || host.isEmpty || !host.contains('.')) return false;
    return domain == host || domain.endsWith('.$host');
  }

  static String? _normHost(String? h) {
    if (h == null) return null;
    var s = h.trim().toLowerCase();
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    if (s.startsWith('www.')) s = s.substring(4);
    return s;
  }
}
