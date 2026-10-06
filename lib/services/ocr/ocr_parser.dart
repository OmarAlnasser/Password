/// Extracts likely credentials from OCR'd or pasted text. Pure Dart, no I/O:
/// the image never leaves the device and the text never leaves this
/// function's caller.
class OcrResult {
  const OcrResult({
    required this.chips,
    this.title,
    this.email,
    this.username,
    this.password,
    this.url,
  });

  /// Every distinct line and token, for the tappable chips UI.
  final List<String> chips;
  final String? title;
  final String? email;
  final String? username;
  final String? password;
  final String? url;
}

/// An e-mail address in one line: the span OCR produced and the address with
/// the OCR noise repaired.
class _EmailHit {
  const _EmailHit(this.start, this.end, this.raw, this.address);
  final int start;
  final int end;
  final String raw;
  final String address;
}

class OcrCredentialParser {
  static final RegExp email = RegExp(
    r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}',
  );
  static final RegExp _url = RegExp(
    r'''(https?://[^\s'"<>]+)|\b((?:[a-z0-9-]+\.)+(?:com|net|org|io|app|dev|co|me|edu|gov|sa|ae|eg|uk|de|fr|info|biz)(?:/[^\s]*)?)\b''',
    caseSensitive: false,
  );

  /// The local part and "@" of an address as OCR reads it: spaces around the
  /// "@" or before a dot ("abcde07 @ hotmail", "first .last@"), a full-width
  /// "＠", "(at)", or "©"/"®", which only count when glued to the local part
  /// and the domain so "Outlook® mail.com" stays text.
  ///
  /// The repetitions are bounded (a local part has at most 64 characters) so
  /// that the search stays linear on long text without an "@".
  static final RegExp _emailHead = RegExp(
    r'([A-Za-z0-9_%+\-][A-Za-z0-9._%+\-]{0,63}'
    r'(?:\s+\.\s*[A-Za-z0-9_%+\-][A-Za-z0-9._%+\-]{0,63}){0,3})'
    r'(?:\s*[@＠﹫]\s*|[©®]|\s*[(\[{]\s*at\s*[)\]}]\s*)',
    caseSensitive: false,
  );
  static final RegExp _atLike = RegExp(
    r'[@＠﹫©®]|[(\[{]\s*at\s*[)\]}]',
    caseSensitive: false,
  );
  static final RegExp _domainLabel = RegExp(
    r'[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?',
  );
  static final RegExp _domainDot = RegExp(r'\s*[.,]\s*');
  static final RegExp _tld = RegExp(r'^[a-z]{2,24}$');

  /// TLD misreads that cannot be real TLDs: digits never occur in one, and
  /// "rn" is how OCR usually reads a narrow "m".
  static const _tldMisreads = {
    'corn': 'com',
    'c0m': 'com',
    'c0rn': 'com',
    '0rg': 'org',
  };

  /// TLDs accepted after a noisy dot ("hotmail .com", "hotmail,com"), next to
  /// any two-letter country code.
  static const _commonTlds = {
    'com',
    'net',
    'org',
    'edu',
    'gov',
    'mil',
    'int',
    'info',
    'biz',
    'app',
    'dev',
    'xyz',
    'online',
    'site',
    'tech',
    'store',
    'shop',
    'cloud',
    'email',
    'live',
    'pro',
    'name',
    'mobi',
  };

  /// "user:pass" after an address, as in pasted combo lists.
  static final RegExp _comboTail = RegExp(r'^\s*[:：|]\s*(\S+)\s*$');
  static final RegExp _lineBreak = RegExp(r'\r\n|[\r\n\u0085  ]');

  static const _passwordLabels = [
    'password',
    'passwd',
    'pass',
    'pwd',
    'pin',
    'mot de passe',
    'contraseña',
    'كلمة المرور',
    'كلمة السر',
    'الرقم السري',
    'رمز المرور',
  ];
  static const _userLabels = [
    'username',
    'user name',
    'user id',
    'userid',
    'user',
    'login',
    'account',
    'email address',
    'e-mail address',
    'email',
    'e-mail',
    'اسم المستخدم',
    'المستخدم',
    'عنوان البريد الإلكتروني',
    'البريد الإلكتروني',
    'البريد',
    'الحساب',
  ];

  /// A label followed by ":" or "=", at a word start. Longest first, so
  /// "اسم المستخدم" is not read as "المستخدم".
  static final RegExp _inlineLabel = RegExp(
    '(?<=^|[\\s|;,])(?:${([..._passwordLabels, ..._userLabels]..sort((a, b) => b.length - a.length)).map(RegExp.escape).join('|')})\\s*[:：=]',
    caseSensitive: false,
  );
  static final RegExp _segmentTail = RegExp(r'(?:\s+[/|;,]|[|;,])?\s*$');

  static const int maxChips = 200;

  /// Text after this many characters is ignored. The clipboard can hold
  /// anything another app or a website put there, and parsing runs on the UI
  /// isolate.
  static const int maxInputLength = 16 * 1024;

  /// Runs without whitespace longer than this are dropped before parsing: no
  /// address (254 characters at most) or password is that long, and long
  /// base64 or hex strings would make the regular expressions below slow.
  static const int maxTokenLength = 256;
  static final RegExp _token = RegExp(r'\S+');

  /// [parse] for pasted text: one string, any line endings.
  OcrResult parseText(String text) => parse([text]);

  OcrResult parse(List<String> rawLines) {
    final lines = [
      for (final raw in _limit(rawLines))
        for (final l in _dropLongTokens(raw).split(_lineBreak))
          if (l.trim().isNotEmpty) l.trim(),
    ];
    final hitsByLine = [for (final l in lines) _findEmails(l)];
    final segmentsByLine = [for (final l in lines) _segments(l)];
    final combosByLine = [
      for (final segments in segmentsByLine)
        [for (final s in segments) ?_combo(s)],
    ];
    final hits = [for (final h in hitsByLine) ...h];
    final segments = [for (final s in segmentsByLine) ...s];

    final chips = <String>{};
    void chip(String s) {
      if (s.isNotEmpty && chips.length < maxChips) chips.add(s);
    }

    for (var i = 0; i < lines.length && chips.length < maxChips; i++) {
      chip(lines[i]);
      // The repaired address and a combo's password are what the user wants
      // to tap, not "abcde07", "@" and "hotmail".
      for (final h in hitsByLine[i]) {
        chip(h.address);
      }
      for (final c in combosByLine[i]) {
        chip(c.$2);
      }
      for (final token in lines[i].split(RegExp(r'\s+'))) {
        chip(_stripPunct(token));
      }
    }

    String? labelled(List<String> labels, String? Function(String) pick) {
      for (var i = 0; i < segments.length; i++) {
        for (final label in labels) {
          // The label must start the line ("Password: x", "Password").
          final m = RegExp(
            '^${RegExp.escape(label)}(?=\$|[\\s:：=\\-–])\\s*[:：=\\-–]?\\s*(.*)\$',
            caseSensitive: false,
          ).firstMatch(segments[i]);
          if (m == null) continue;
          final rest = m.group(1)!.trim();
          String? value;
          // "Password: value" on the same line.
          if (rest.isNotEmpty && !_isLabel(rest)) value = pick(rest);
          // "Password" then the value on the next line.
          if (rest.isEmpty &&
              i + 1 < segments.length &&
              !_isLabel(segments[i + 1])) {
            value = pick(segments[i + 1]);
          }
          if (value != null) return value;
        }
      }
      return null;
    }

    final emailMatch = hits.firstOrNull?.address;
    final combo = [for (final c in combosByLine) ...c].firstOrNull;
    final url = _findUrl(lines, hitsByLine);

    final username =
        labelled(_userLabels, _pickUser) ?? combo?.$1 ?? emailMatch;
    final password =
        labelled(_passwordLabels, (v) => _pickPassword(v, hits)) ??
        combo?.$2 ??
        _guessPassword(
          chips,
          exclude: {?emailMatch, ?username, ?url},
          emails: hits,
        ) ??
        _besideAddress(lines, hitsByLine, exclude: {?username, ?url});

    return OcrResult(
      chips: chips.toList(),
      email: emailMatch,
      username: username,
      password: password,
      url: url,
      title: _title(url, lines),
    );
  }

  /// The first [maxInputLength] characters of [rawLines].
  static List<String> _limit(List<String> rawLines) {
    var left = maxInputLength;
    final out = <String>[];
    for (final raw in rawLines) {
      if (left <= 0) break;
      out.add(raw.length > left ? raw.substring(0, left) : raw);
      left -= raw.length;
    }
    return out;
  }

  static String _dropLongTokens(String s) => s.length <= maxTokenLength
      ? s
      : s.replaceAllMapped(
          _token,
          (m) => m[0]!.length > maxTokenLength ? ' ' : m[0]!,
        );

  static bool _isLabel(String s) {
    final lower = s.toLowerCase().replaceAll(RegExp(r'[:：]'), '').trim();
    return _passwordLabels.contains(lower) || _userLabels.contains(lower);
  }

  static String _stripPunct(String t) =>
      t.replaceAll(RegExp(r'^[,;:"“”()\[\]]+|[,;"“”()\[\]]+$'), '');

  /// Every address in [line], OCR noise repaired: "abcde07 @ hotmail .com",
  /// "abcde07©hotmail.com" and "abcde07@hotmail,corn" are all
  /// "abcde07@hotmail.com".
  static List<_EmailHit> _findEmails(String line) {
    if (!line.contains(_atLike)) return const [];
    final hits = <_EmailHit>[];
    var pos = 0;
    while (pos < line.length) {
      final head = _emailHead.allMatches(line, pos).firstOrNull;
      if (head == null) break;
      final hit = _emailAt(line, head);
      if (hit != null) hits.add(hit);
      pos = hit?.end ?? head.end;
    }
    return hits;
  }

  static _EmailHit? _emailAt(String line, Match head) {
    final first = _domainLabel.matchAsPrefix(line, head.end);
    if (first == null) return null;
    final labels = [first[0]!];
    final ends = [first.end];
    var noisy = false;
    while (true) {
      final dot = _domainDot.matchAsPrefix(line, ends.last);
      final next = dot == null
          ? null
          : _domainLabel.matchAsPrefix(line, dot.end);
      if (next == null) break;
      if (dot![0] != '.') {
        // Only the first dot may be noisy ("hotmail .com", "hotmail,com"):
        // after a real dot the address is complete, and "x@a.com, Pass" or
        // "x@a.com. Next" must not run on.
        if (labels.length > 1) break;
        noisy = true;
      }
      labels.add(next[0]!);
      ends.add(next.end);
    }
    // Drop trailing labels that cannot be a TLD ("x@a.com.5").
    while (labels.length > 1) {
      final tld = _plausibleTld(labels.last, noisy: noisy);
      if (tld != null) {
        labels.last = tld;
        final local = head[1]!.replaceAll(RegExp(r'\s+'), '');
        return _EmailHit(
          head.start,
          ends.last,
          line.substring(head.start, ends.last),
          '$local@${labels.join('.').toLowerCase()}',
        );
      }
      labels.removeLast();
      ends.removeLast();
    }
    return null;
  }

  static String? _plausibleTld(String raw, {required bool noisy}) {
    final lower = raw.toLowerCase();
    final tld = _tldMisreads[lower] ?? lower;
    if (!_tld.hasMatch(tld)) return null;
    if (!noisy) return tld;
    // After a space or comma only a real TLD in one case counts, so
    // "x@hotmail. Pass" and "x@hotmail. My" stay text.
    final oneCase = raw == lower || raw == raw.toUpperCase();
    return oneCase && (tld.length == 2 || _commonTlds.contains(tld))
        ? tld
        : null;
  }

  /// Splits a line that starts with a label at each further label, so pasted
  /// "Email: x / Password: y" reads like two lines.
  static List<String> _segments(String line) {
    final starts = [for (final m in _inlineLabel.allMatches(line)) m.start];
    if (starts.length < 2 || starts.first != 0) return [line];
    return [
      for (var i = 0; i < starts.length; i++)
        if (i + 1 < starts.length)
          line
              .substring(starts[i], starts[i + 1])
              .replaceFirst(_segmentTail, '')
        else
          line.substring(starts[i]),
    ];
  }

  /// "abcde07@hotmail.com:password" from a pasted combo list. Only split when
  /// the user part is an address: "10:45" or "alice:x" are not credentials.
  static (String, String)? _combo(String segment) {
    final hit = _findEmails(segment).firstOrNull;
    if (hit == null || hit.start != 0) return null;
    final m = _comboTail.firstMatch(segment.substring(hit.end));
    if (m == null || _isLabel(m[1]!)) return null;
    return (hit.address, m[1]!);
  }

  /// The value after a user label: the whole address if one starts there
  /// ("Email: abcde07 @ hotmail.com"), else the first word.
  static String _pickUser(String value) {
    final hit = _findEmails(value).firstOrNull;
    return hit != null && hit.start == 0 ? hit.address : value.split(' ').first;
  }

  /// The first word after a password label, unless it is an address or a
  /// piece of one: login forms put "Password" above both inputs.
  static String? _pickPassword(String value, List<_EmailHit> hits) {
    final v = value.split(' ').first;
    if (_findEmails(value).firstOrNull?.start == 0) return null;
    if (_atLike.hasMatch(v) && _isEmailPart(v, hits)) return null;
    return v;
  }

  /// Whether [token] is an address found in the text, a piece of one
  /// ("abcde07@hotmail" from "abcde07@hotmail .com", "hotmail.com") or
  /// contains one ("abcde07@hotmail.com:password").
  static bool _isEmailPart(String token, List<_EmailHit> hits) {
    final t = _fold(token);
    if (t.isEmpty) return false;
    for (final h in hits) {
      final address = h.address.toLowerCase();
      if (t.contains(address) ||
          address.contains(t) ||
          _fold(h.raw).contains(t)) {
        return true;
      }
    }
    return false;
  }

  static String _fold(String s) => s
      .toLowerCase()
      .replaceAll(_atLike, '@')
      .replaceAll(',', '.')
      .replaceAll(RegExp(r'\s+'), '');

  /// The first URL or bare domain that is not just the domain of an address:
  /// a hotmail.com address says nothing about which site the account is for.
  static String? _findUrl(List<String> lines, List<List<_EmailHit>> hits) {
    for (var i = 0; i < lines.length; i++) {
      for (final m in _url.allMatches(lines[i])) {
        if (hits[i].any((h) => m.start >= h.start && m.end <= h.end)) continue;
        return m.group(1) ?? m.group(2);
      }
    }
    return null;
  }

  /// Scores tokens that look like passwords: no spaces, 6-64 chars, several
  /// character classes, not an email/URL/plain word or number.
  static String? _guessPassword(
    Set<String> chips, {
    Set<String> exclude = const {},
    List<_EmailHit> emails = const [],
  }) {
    String? best;
    var bestScore = 0;
    for (final t in chips) {
      if (t.contains(' ') || t.length < 6 || t.length > 64) continue;
      if (exclude.contains(t) ||
          email.hasMatch(t) ||
          t.contains('://') ||
          _isEmailPart(t, emails)) {
        continue;
      }
      var classes = 0;
      if (RegExp('[a-z]').hasMatch(t)) classes++;
      if (RegExp('[A-Z]').hasMatch(t)) classes++;
      if (RegExp('[0-9]').hasMatch(t)) classes++;
      if (RegExp(r'[^A-Za-z0-9]').hasMatch(t)) classes++;
      if (classes < 2 || (classes == 2 && t.length < 10)) continue;
      // Pure dates / phone numbers are not passwords.
      if (RegExp(r'^[\d\-/.: +]+$').hasMatch(t)) continue;
      // Neither are field labels ("Website:").
      if (RegExp(r'^[A-Za-z][a-z]+[:：]$').hasMatch(t)) continue;
      final score = classes * 10 + t.length.clamp(0, 20);
      if (score > bestScore) {
        bestScore = score;
        best = t;
      }
    }
    return best;
  }

  static final RegExp _dateOrTime = RegExp(r'^\d+(?:[-/.:]\d+)+$');
  static const _uiWords = {
    'back',
    'cancel',
    'close',
    'copy',
    'delete',
    'done',
    'edit',
    'menu',
    'more',
    'next',
    'notes',
    'reply',
    'save',
    'search',
    'send',
    'settings',
    'share',
    'submit',
  };

  /// The line right below the first address, else the one above, when the
  /// address stands alone on its line and the other line is a single word.
  /// A screenshot of a login is often just those two lines, and
  /// [_guessPassword] passes over weak passwords ("mango12", "12345678",
  /// letters only).
  static String? _besideAddress(
    List<String> lines,
    List<List<_EmailHit>> hitsByLine, {
    Set<String> exclude = const {},
  }) {
    final i = hitsByLine.indexWhere((h) => h.isNotEmpty);
    if (i < 0) return null;
    // Not after "Email: ..." or inside a sentence; some punctuation is fine.
    final first = hitsByLine[i].first;
    if (first.start > 1 || lines[i].length - first.end > 2) return null;
    final hits = [for (final h in hitsByLine) ...h];
    for (final j in [i + 1, i - 1]) {
      if (j < 0 || j >= lines.length || hitsByLine[j].isNotEmpty) continue;
      final t = lines[j];
      if (t.length < 4 || t.length > 64 || t.contains(RegExp(r'\s'))) {
        continue;
      }
      if (exclude.contains(t) ||
          _isLabel(t) ||
          RegExp(r'[:：]$').hasMatch(t) ||
          _uiWords.contains(t.toLowerCase()) ||
          _dateOrTime.hasMatch(t) ||
          t.contains('://') ||
          _url.hasMatch(t) ||
          _isEmailPart(t, hits)) {
        continue;
      }
      return t;
    }
    return null;
  }

  static String? _title(String? url, List<String> lines) {
    if (url != null) {
      final uri = Uri.tryParse(url.contains('://') ? url : 'https://$url');
      final host = uri?.host ?? '';
      final parts = host.split('.').where((p) => p != 'www').toList();
      if (parts.length >= 2) {
        final name = parts[parts.length - 2];
        return name[0].toUpperCase() + name.substring(1);
      }
    }
    return null;
  }
}
