import '../../data/models/vault_entry.dart';

/// What applying a [ReviewItem] does to the vault.
enum ReviewAction {
  /// Not in the vault yet: added as a new entry.
  newEntry,

  /// Same site and username as a vault entry but a different password: the
  /// vault entry gets the imported password and keeps the old one in its
  /// history. Also used when the file has other passwords for a login the
  /// vault already has with the same password; they go to its history.
  updateExisting,

  /// Several rows of the file for the same login, merged into one new entry.
  mergedDuplicate,

  /// Already in the vault with the same password, and every other password
  /// the file has for it is in the vault entry's history: nothing to do.
  skipIdentical,

  /// The row looks broken (see [ReviewIssue.isBlocking]). It is left out
  /// unless the user includes it.
  needsAttention,
}

enum ReviewIssue {
  missingPassword,
  missingUsername,

  /// Contains an "@" like an e-mail address but is not a valid one.
  invalidEmail,
  usernameIsUrl,

  /// The password column holds an e-mail address (columns swapped).
  passwordLooksLikeEmail,

  /// The username column holds what looks like a password (columns swapped
  /// or shifted).
  usernameLooksLikePassword,

  /// No usable website or app: unparseable, a non-web scheme, or neither a
  /// URL nor a name to tell which site the password belongs to.
  invalidUrl,
  insecureHttp,
  duplicateInFile,
  existsWithDifferentPassword;

  /// Issues that suggest the row is not a usable login. Items with one start
  /// excluded and get [ReviewAction.needsAttention].
  bool get isBlocking => switch (this) {
    ReviewIssue.missingPassword ||
    ReviewIssue.usernameIsUrl ||
    ReviewIssue.passwordLooksLikeEmail ||
    ReviewIssue.usernameLooksLikePassword ||
    ReviewIssue.invalidUrl => true,
    _ => false,
  };
}

/// An imported URL reduced to what the vault needs.
///
/// * `https://accounts.google.com/signin?continue=...` →
///   `https://accounts.google.com/` (origin only).
/// * `http://` keeps its scheme and path ([insecure]); query, fragment, user
///   info and paths that look like they carry tokens are dropped.
/// * Chrome on Android's `android://<cert hash>@com.example.app/` →
///   `androidapp://com.example.app`, the form `AutofillMatcher` links apps by.
class ImportUrl {
  const ImportUrl({
    required this.url,
    required this.siteKey,
    required this.siteName,
    this.insecure = false,
    this.invalid = false,
  });

  /// The URL to store. For an [invalid] one, the input without query and
  /// fragment so the user can see what it was.
  final String url;

  /// Identifies the site: the lower-cased host without `www.`, or
  /// `androidapp://<package>` / `iosapp://<bundle id>`. Empty when there is
  /// no usable website.
  final String siteKey;

  /// Display name of the site, e.g. "Google" for `accounts.google.com`.
  final String siteName;
  final bool insecure;
  final bool invalid;

  static const _empty = ImportUrl(url: '', siteKey: '', siteName: '');

  // Schemes that name a host we can show and match on. Anything else
  // (chrome:, about:, mailto:, intent:, ...) is not a login site.
  static const _schemes = {'https', 'http', 'ftp', 'ftps', 'sftp', 'ssh'};
  static final _bareScheme = RegExp(
    r'^[a-z][a-z0-9+.-]*:(?![0-9])',
    caseSensitive: false,
  );
  static final _package = RegExp(
    r'^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$',
  );
  static final _hostLabel = RegExp(
    r'^[\p{L}\p{N}](?:[\p{L}\p{N}_-]*[\p{L}\p{N}])?$',
    unicode: true,
  );
  static final _ipv4 = RegExp(r'^[0-9.]+$');
  static final _digit = RegExp('[0-9]');
  static final _letter = RegExp('[A-Za-z]');
  static final _tokenWord = RegExp(
    'token|sess|sid|auth|reset|verif|confirm|magic|ticket|otp|jwt|sso|saml|'
    'key|code|secret|sig',
    caseSensitive: false,
  );

  static ImportUrl parse(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return _empty;
    final lower = s.toLowerCase();
    if (lower.startsWith('android://') ||
        lower.startsWith('androidapp://') ||
        lower.startsWith('iosapp://')) {
      return _app(s, ios: lower.startsWith('iosapp://'));
    }
    // "mailto:a@b.com" or "about:blank" must not turn into https://b.com/;
    // "localhost:8080" is a host and port.
    if (!s.contains('://') && _bareScheme.hasMatch(s)) return _invalid(s);
    final uri = Uri.tryParse(s.contains('://') ? s : 'https://$s');
    if (uri == null || !_schemes.contains(uri.scheme)) return _invalid(s);
    final host = _host(uri);
    if (host == null) return _invalid(s);
    final authority =
        '${host.contains(':') ? '[$host]' : host}'
        '${uri.hasPort ? ':${uri.port}' : ''}';
    final origin = '${uri.scheme}://$authority/';
    return ImportUrl(
      url: uri.scheme == 'https' ? origin : '$origin${_safePath(uri.path)}',
      siteKey: host.startsWith('www.') ? host.substring(4) : host,
      siteName: siteNameForHost(host),
      insecure: uri.scheme == 'http',
    );
  }

  /// True for Chrome's raw Android facet form, which autofill cannot match.
  static bool isAndroidFacet(String url) =>
      url.trim().toLowerCase().startsWith('android://');

  static ImportUrl _app(String s, {required bool ios}) {
    // android://<base64 cert hash>@<package>/ ; the hash may contain "/" in
    // non-URL-safe base64, so take everything after the last "@".
    var rest = s.substring(s.indexOf('://') + 3);
    final at = rest.lastIndexOf('@');
    if (at >= 0) rest = rest.substring(at + 1);
    rest = rest.split(RegExp('[/?#]')).first;
    if (!_package.hasMatch(rest)) return _invalid(s);
    final url = '${ios ? 'iosapp' : 'androidapp'}://$rest';
    return ImportUrl(
      url: url,
      siteKey: url.toLowerCase(),
      siteName: siteNameForApp(rest),
    );
  }

  static final _userInfo = RegExp(r'^([A-Za-z][A-Za-z0-9+.-]*://)[^/?#]*@');

  static ImportUrl _invalid(String s) => ImportUrl(
    url: s
        .split(RegExp('[?#]'))
        .first
        .replaceFirstMapped(_userInfo, (m) => m[1]!),
    siteKey: '',
    siteName: '',
    invalid: true,
  );

  static String? _host(Uri uri) {
    String h;
    try {
      h = Uri.decodeComponent(uri.host).toLowerCase();
    } on Object {
      return null;
    }
    if (h.endsWith('.')) h = h.substring(0, h.length - 1);
    if (h.isEmpty) return null;
    // IPv6 literal; Uri has already validated it.
    if (h.contains(':')) return h;
    final labels = h.split('.');
    if (labels.any((l) => l.length > 63 || !_hostLabel.hasMatch(l))) {
      return null;
    }
    return h;
  }

  /// The path without its leading "/", or '' when any part of it could be a
  /// session, reset or sign-in token.
  static String _safePath(String path) {
    if (path.length <= 1 || path.length > 200 || _tokenWord.hasMatch(path)) {
      return '';
    }
    final segments = path.substring(1).split('/');
    final tokenLike = segments.any(
      (seg) =>
          seg.length >= 32 ||
          seg.contains('=') ||
          seg.contains(';') ||
          (seg.length >= 16 && seg.contains(_digit) && seg.contains(_letter)),
    );
    return tokenLike ? '' : path.substring(1);
  }

  // Second-level labels under a country code that are not the site's name:
  // amazon.co.uk, google.com.sa, yahoo.co.jp.
  static const _secondLevel = {
    'ac', 'co', 'com', 'edu', 'gen', 'go', 'gob', 'gouv', 'gov', 'ind', //
    'ltd', 'me', 'mil', 'ne', 'net', 'nic', 'nom', 'or', 'org', 'plc', 'sch',
  };

  // Shared hosting suffixes where the site's name is the label in front.
  static const _privateSuffixes = {
    'appspot.com',
    'azurewebsites.net',
    'blogspot.com',
    'firebaseapp.com',
    'github.io',
    'gitlab.io',
    'herokuapp.com',
    'netlify.app',
    'pages.dev',
    'vercel.app',
    'web.app',
    'wordpress.com',
  };

  /// "Google" for `accounts.google.com`, "Amazon" for `www.amazon.co.uk`,
  /// "My Bank" for `my-bank.com.sa`. IP addresses are returned unchanged.
  static String siteNameForHost(String host) {
    final h = host.toLowerCase();
    if (h.isEmpty || h.contains(':') || _ipv4.hasMatch(h)) {
      return h;
    }
    final labels = h.split('.').where((l) => l.isNotEmpty).toList();
    if (labels.isEmpty) return h;
    final n = labels.length;
    final int i;
    if (n >= 3 &&
        (_privateSuffixes.contains('${labels[n - 2]}.${labels[n - 1]}') ||
            (labels[n - 1].length == 2 &&
                _secondLevel.contains(labels[n - 2])))) {
      i = n - 3;
    } else {
      i = n >= 2 ? n - 2 : 0;
    }
    return _pretty(labels[i]);
  }

  // Package segments that say nothing about which app it is.
  static const _genericAppWords = {
    'android', 'app', 'apps', 'application', 'client', 'free', 'lite', //
    'main', 'mobile', 'pro',
  };

  /// "Example" for `com.example.app`, "Chrome" for `com.android.chrome`.
  static String siteNameForApp(String package) {
    final parts = package.toLowerCase().split('.');
    // Reverse-domain names start with a TLD (com., org., io., tv., ...).
    final start = parts.length > 1 && parts.first.length <= 3 ? 1 : 0;
    for (var i = start; i < parts.length; i++) {
      if (!_genericAppWords.contains(parts[i])) return _pretty(parts[i]);
    }
    return _pretty(parts.last);
  }

  static String _pretty(String label) {
    if (label.startsWith('xn--')) return label;
    return label
        .split(RegExp('[-_]+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}

/// One login of the import, after normalisation, merging and comparison with
/// the vault.
class ReviewItem {
  ReviewItem({
    required this.entry,
    required this.action,
    required this.issues,
    required this.siteKey,
    required this.siteName,
    this.existing,
    this.rows = const [],
    bool? include,
  }) : include =
           include ??
           (action != ReviewAction.skipIdentical &&
               !issues.any((i) => i.isBlocking));

  /// The imported login, normalised (site title, trimmed username, canonical
  /// URL). Merged duplicates carry the other passwords in its history.
  final VaultEntry entry;
  final ReviewAction action;

  /// In [ReviewIssue] declaration order.
  final List<ReviewIssue> issues;

  /// See [ImportUrl.siteKey]; '' when the login has no usable website.
  final String siteKey;

  /// Display name of the site for group headers; '' without a website.
  final String siteName;

  /// The vault entry with the same site and username, if any.
  final VaultEntry? existing;

  /// Indexes into the imported list of the rows this item was made from.
  final List<int> rows;

  /// Whether [ImportReview.apply] saves this item. The review screen toggles
  /// it.
  bool include;

  String? get existingId => existing?.id;
  bool get hasBlockingIssue => issues.any((i) => i.isBlocking);
}

class _Row {
  _Row(this.index, this.entry, this.url, this.issues, this.customTitle);

  final int index;
  final VaultEntry entry;
  final ImportUrl url;
  final Set<ReviewIssue> issues;

  /// The title came from the file (not a host or package name Chrome filled
  /// in), so it is kept.
  final bool customTitle;

  bool get blocking => issues.any((i) => i.isBlocking);
}

/// Checks a CSV import (Chrome, Bitwarden) before it touches the vault:
/// normalises each row, flags rows whose password, username and website do
/// not fit together, merges duplicates inside the file and compares every
/// login with the vault. Pure Dart, no I/O, no logging.
///
/// A login is identified by its site key plus its username (e-mail addresses
/// compared case-insensitively). Logins without a website fall back to their
/// title.
class ImportReview {
  /// Builds one [ReviewItem] per distinct login, in file order.
  ///
  /// Rows of the same login are merged: the newest row (latest `updatedAt`,
  /// then the later row) wins, preferring rows without a blocking issue, and
  /// the other distinct passwords go to its history.
  static List<ReviewItem> review(
    List<VaultEntry> imported,
    List<VaultEntry> vault,
  ) {
    final index = <String, List<VaultEntry>>{};
    for (final v in vault) {
      final id = _identity(ImportUrl.parse(v.url).siteKey, v.title, v.username);
      if (id != null) (index[id] ??= []).add(v);
    }
    final logins = <String, List<_Row>>{};
    for (var i = 0; i < imported.length; i++) {
      final row = _normalize(i, imported[i]);
      final id =
          _identity(row.url.siteKey, row.entry.title, row.entry.username) ??
          '\u0000row$i';
      (logins[id] ??= []).add(row);
    }
    return [
      for (final MapEntry(key: id, value: rows) in logins.entries)
        _item(rows, index[id]),
    ];
  }

  /// Items grouped by [ReviewItem.siteKey], groups sorted by site name with
  /// the group without a website ('') last, items by username.
  static Map<String, List<ReviewItem>> group(Iterable<ReviewItem> items) {
    final groups = <String, List<ReviewItem>>{};
    for (final item in items) {
      (groups[item.siteKey] ??= []).add(item);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) {
        if (a.isEmpty || b.isEmpty) return a.isEmpty ? (b.isEmpty ? 0 : 1) : -1;
        final byName = groups[a]!.first.siteName.toLowerCase().compareTo(
          groups[b]!.first.siteName.toLowerCase(),
        );
        return byName != 0 ? byName : a.compareTo(b);
      });
    return {
      for (final k in keys)
        k: groups[k]!
          ..sort(
            (a, b) => a.entry.username.toLowerCase().compareTo(
              b.entry.username.toLowerCase(),
            ),
          ),
    };
  }

  /// Number of items per action (every action present, possibly 0).
  static Map<ReviewAction, int> counts(Iterable<ReviewItem> items) {
    final out = {for (final a in ReviewAction.values) a: 0};
    for (final item in items) {
      out[item.action] = out[item.action]! + 1;
    }
    return out;
  }

  /// The entries to save for the included items.
  ///
  /// New logins are saved as reviewed. A login already in the vault keeps its
  /// id, title, URL, tags and notes (a raw Chrome `android://` URL becomes
  /// the `androidapp://` link); it gets the imported password through
  /// [VaultEntry.edit], so the old one lands in its history, plus the
  /// imported note when the vault entry does not have it yet. An empty
  /// imported password never replaces a stored one, and an existing entry
  /// that would not change is left out.
  ///
  /// Pass the vault as it is now in [current] when it may have changed since
  /// [review] (a sync while the review screen was open): updates then start
  /// from the current version of each entry instead of overwriting it, and a
  /// login whose vault entry was deleted in the meantime is added as new.
  static List<VaultEntry> apply(
    Iterable<ReviewItem> items, {
    List<VaultEntry>? current,
    DateTime? now,
  }) {
    final t = (now ?? DateTime.now()).toUtc();
    final byId = current == null ? null : {for (final e in current) e.id: e};
    final out = <VaultEntry>[];
    for (final item in items) {
      if (!item.include) continue;
      final existing = item.existing == null
          ? null
          : byId == null
          ? item.existing
          : byId[item.existing!.id];
      if (existing == null) {
        out.add(item.entry);
        continue;
      }
      final updated = _update(existing, item.entry, t);
      if (updated != null) out.add(updated);
    }
    return out;
  }

  static VaultEntry? _update(
    VaultEntry existing,
    VaultEntry imported,
    DateTime now,
  ) {
    final note = imported.notes.trim();
    // Already there as whole lines (e.g. from an earlier import).
    final known = '\n${existing.notes.trim()}\n'.contains('\n$note\n');
    final notes = note.isEmpty || known
        ? existing.notes
        : existing.notes.trim().isEmpty
        ? note
        : '${existing.notes}\n$note';
    // Older passwords from the file first, so the one the import replaces
    // ends up on top of the history.
    var base = existing;
    for (final h in imported.history.reversed) {
      base = base.withHistoryPassword(h.password, h.changedAt);
    }
    final out = base.edit(
      password: imported.password.trim().isEmpty ? null : imported.password,
      notes: notes,
      url: ImportUrl.isAndroidFacet(existing.url) ? imported.url : null,
      totpSecret: existing.totpSecret.isEmpty ? imported.totpSecret : null,
      now: now,
    );
    final unchanged =
        out.password == existing.password &&
        out.notes == existing.notes &&
        out.url == existing.url &&
        out.totpSecret == existing.totpSecret &&
        out.history.length == existing.history.length &&
        Iterable.generate(
          out.history.length,
        ).every((i) => out.history[i].password == existing.history[i].password);
    return unchanged ? null : out;
  }

  static ReviewItem _item(List<_Row> rows, List<VaultEntry>? candidates) {
    final ranked = [...rows]
      ..sort((a, b) {
        if (a.blocking != b.blocking) return a.blocking ? 1 : -1;
        final byTime = b.entry.updatedAt.compareTo(a.entry.updatedAt);
        return byTime != 0 ? byTime : b.index.compareTo(a.index);
      });
    final winner = ranked.first;
    final issues = {...winner.issues};
    var entry = winner.entry;
    if (rows.length > 1) {
      issues.add(ReviewIssue.duplicateInFile);
      final others = ranked.skip(1).toList();
      var url = entry.url;
      if (winner.url.insecure) {
        for (final r in others) {
          if (r.url.url.startsWith('https://')) {
            url = r.url.url;
            issues.remove(ReviewIssue.insecureHttp);
            break;
          }
        }
      }
      var title = entry.title;
      if (!winner.customTitle) {
        for (final r in others) {
          if (r.customTitle) {
            title = r.entry.title;
            break;
          }
        }
      }
      var totp = entry.totpSecret;
      for (final r in others) {
        if (totp.isEmpty) totp = r.entry.totpSecret;
      }
      entry = _copy(
        entry,
        title: title,
        url: url,
        notes: _distinct([entry.notes, for (final r in others) r.entry.notes])
            .join('\n'),
        tags: _distinct([
          ...entry.tags,
          for (final r in others) ...r.entry.tags,
        ]),
        favorite: rows.any((r) => r.entry.favorite),
        totpSecret: totp,
      );
      // Oldest first: withHistoryPassword prepends, so the most recent of
      // the replaced passwords ends up on top.
      for (final r in others.reversed) {
        for (final h in r.entry.history.reversed) {
          entry = entry.withHistoryPassword(h.password, h.changedAt);
        }
        entry = entry.withHistoryPassword(
          r.entry.password,
          r.entry.passwordChangedAt,
        );
      }
    }

    VaultEntry? existing;
    if (candidates != null) {
      for (final c in candidates) {
        if (c.password == entry.password) existing = c;
      }
      existing ??= candidates.reduce(
        (a, b) => b.updatedAt.isAfter(a.updatedAt) ? b : a,
      );
    }
    final blocking = issues.any((i) => i.isBlocking);
    // A duplicate row can hold a password the vault has never seen even when
    // the winning row matches it (Chrome keeps www.example.com and
    // example.com apart). It must reach the vault entry's history.
    final unknown =
        existing != null &&
        _passwords(entry).difference(_passwords(existing)).isNotEmpty;
    if (existing != null &&
        ((entry.password.trim().isNotEmpty &&
                existing.password != entry.password) ||
            unknown)) {
      issues.add(ReviewIssue.existsWithDifferentPassword);
    }
    // An update keeps the vault entry's URL.
    if (existing != null && !ImportUrl.parse(existing.url).insecure) {
      issues.remove(ReviewIssue.insecureHttp);
    }
    final ReviewAction action;
    if (existing != null && existing.password == entry.password && !unknown) {
      action = ReviewAction.skipIdentical;
    } else if (blocking) {
      action = ReviewAction.needsAttention;
    } else if (existing != null) {
      action = ReviewAction.updateExisting;
    } else if (rows.length > 1) {
      action = ReviewAction.mergedDuplicate;
    } else {
      action = ReviewAction.newEntry;
    }
    return ReviewItem(
      entry: entry,
      action: action,
      issues: ReviewIssue.values.where(issues.contains).toList(),
      siteKey: winner.url.siteKey,
      siteName: winner.url.siteName,
      existing: existing,
      rows: [for (final r in rows) r.index],
    );
  }

  /// The current and past passwords of [e], without empty ones.
  static Set<String> _passwords(VaultEntry e) => {
    for (final p in [e.password, for (final h in e.history) h.password])
      if (p.trim().isNotEmpty) p,
  };

  static _Row _normalize(int index, VaultEntry e) {
    final url = ImportUrl.parse(e.url);
    final username = e.username.trim();
    final rawTitle = e.title.trim();
    final custom = _isCustomTitle(rawTitle, e.url, url);
    final title = custom || url.siteName.isEmpty ? rawTitle : url.siteName;
    final password = e.password.trim();
    final userIsUrl = username.isNotEmpty && _looksLikeUrl(username, url);
    final userIsEmail = isEmail(username);
    final issues = <ReviewIssue>{
      if (password.isEmpty) ReviewIssue.missingPassword,
      if (username.isEmpty) ReviewIssue.missingUsername,
      if (userIsUrl) ReviewIssue.usernameIsUrl,
      if (!userIsUrl && !userIsEmail && _looksLikeEmail(username))
        ReviewIssue.invalidEmail,
      if (isEmail(password) &&
          (!userIsEmail || password.toLowerCase() == username.toLowerCase()))
        ReviewIssue.passwordLooksLikeEmail,
      if (!userIsUrl && _looksLikePassword(username, password))
        ReviewIssue.usernameLooksLikePassword,
      if (url.invalid || (url.url.isEmpty && title.isEmpty))
        ReviewIssue.invalidUrl,
      if (url.insecure) ReviewIssue.insecureHttp,
    };
    return _Row(
      index,
      _copy(e, title: title, username: username, url: url.url),
      url,
      issues,
      custom,
    );
  }

  /// Site + username, or null when the login cannot be told apart from
  /// others (no website and no title).
  static String? _identity(String siteKey, String title, String username) {
    final t = title.trim().toLowerCase();
    final site = siteKey.isNotEmpty
        ? siteKey
        : t.isNotEmpty
        ? 'title:$t'
        : null;
    if (site == null) return null;
    final u = username.trim();
    return '$site\u0000${u.contains('@') ? u.toLowerCase() : u}';
  }

  static final _dottedName = RegExp(
    r'^(?:[\p{L}\p{N}_-]+\.)+[\p{L}\p{N}_-]+\.?$',
    unicode: true,
  );

  /// Chrome fills the name column with the host (or the package for apps),
  /// and the CSV import falls back to the host for empty names. Only a name
  /// the user chose is worth keeping over the derived site name.
  static bool _isCustomTitle(String title, String rawUrl, ImportUrl url) {
    if (title.isEmpty) return false;
    final t = title.toLowerCase();
    if (t.contains('://') || _dottedName.hasMatch(t)) return false;
    final raw = rawUrl.trim();
    final rawHost =
        Uri.tryParse(raw.contains('://') ? raw : 'https://$raw')?.host
            .toLowerCase() ??
        '';
    return t != rawHost && t != raw.toLowerCase();
  }

  static final _space = RegExp(r'\s');
  static final _appScheme = RegExp('^[a-z]+://');
  static final _common = RegExp(
    r'^(?:[a-z0-9-]+\.)+(?:com|net|org|io|edu|gov)(?::\d+)?/?$',
  );
  static final _withPath = RegExp(r'^(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?/\S*$');

  static bool _looksLikeUrl(String username, ImportUrl url) {
    final s = username.toLowerCase();
    if (s.contains('://') || s.startsWith('www.')) return true;
    if (s.contains('@') || s.contains(_space)) return false;
    final bare = s.endsWith('/') ? s.substring(0, s.length - 1) : s;
    final site = url.siteKey.replaceFirst(_appScheme, '');
    return (site.isNotEmpty && (bare == site || bare == 'www.$site')) ||
        _common.hasMatch(s) ||
        _withPath.hasMatch(s);
  }

  static final _emailLocal = RegExp(
    r"^[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+)*$",
  );
  static final _domainLabel = RegExp(
    r'^[\p{L}\p{N}](?:[\p{L}\p{N}-]*[\p{L}\p{N}])?$',
    unicode: true,
  );
  static final _tld = RegExp(r'^(?:\p{L}{2,}|xn--[a-z0-9-]+)$', unicode: true);

  /// A syntactically valid e-mail address (dot-atom local part, a domain with
  /// at least two labels and an alphabetic TLD).
  static bool isEmail(String s) {
    if (s.length > 254) return false;
    final at = s.indexOf('@');
    if (at < 1 || at != s.lastIndexOf('@')) return false;
    final local = s.substring(0, at);
    final labels = s.substring(at + 1).split('.');
    return local.length <= 64 &&
        _emailLocal.hasMatch(local) &&
        labels.length >= 2 &&
        labels.every((l) => l.length <= 63 && _domainLabel.hasMatch(l)) &&
        _tld.hasMatch(labels.last.toLowerCase());
  }

  static final _atSign = RegExp('[@＠]');

  /// Something with an "@" after some text: "abcde07@hotmail", "a@@b.com",
  /// "a @b.com". A leading "@" is a social handle, not an address.
  static bool _looksLikeEmail(String s) => s.indexOf(_atSign) > 0;

  static final _lower = RegExp('[a-z]');
  static final _upper = RegExp('[A-Z]');
  // Characters common in passwords but not in usernames ("+", "-", "_", "."
  // and "\" appear in real usernames, so they do not count).
  static final _pwSymbol = RegExp(r'''[!#$%^&*()=\[\]{}|;:'",<>?`~]''');

  static bool _looksLikePassword(String username, String password) {
    if (username.length < 8 ||
        username.contains('@') ||
        username.contains(_space)) {
      return false;
    }
    final lower = username.contains(_lower);
    final upper = username.contains(_upper);
    final digit = username.contains(ImportUrl._digit);
    if (!(lower || upper) || !digit) return false;
    if (_pwSymbol.hasMatch(username)) return true;
    // Mixed case and digits alone is a normal username ("JohnSmith1990")
    // unless the password column is empty or holds the e-mail address.
    return lower && upper && (password.isEmpty || isEmail(password));
  }

  static List<String> _distinct(Iterable<String> values) {
    final seen = <String>{};
    return [
      for (final v in values)
        if (v.trim().isNotEmpty && seen.add(v.trim())) v.trim(),
    ];
  }

  static VaultEntry _copy(
    VaultEntry e, {
    String? title,
    String? username,
    String? url,
    String? notes,
    List<String>? tags,
    bool? favorite,
    String? totpSecret,
  }) => VaultEntry(
    id: e.id,
    title: title ?? e.title,
    username: username ?? e.username,
    password: e.password,
    url: url ?? e.url,
    notes: notes ?? e.notes,
    tags: tags ?? e.tags,
    favorite: favorite ?? e.favorite,
    totpSecret: totpSecret ?? e.totpSecret,
    history: e.history,
    createdAt: e.createdAt,
    updatedAt: e.updatedAt,
    passwordChangedAt: e.passwordChangedAt,
  );
}
