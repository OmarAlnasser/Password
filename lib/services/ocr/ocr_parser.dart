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
    this.emailCandidates = const [],
    this.passwordCandidates = const [],
  });

  /// Every distinct line and token, for the tappable chips UI.
  final List<String> chips;
  final String? title;
  final String? email;
  final String? username;
  final String? password;
  final String? url;

  /// Addresses worth offering, best first: [email], the other readings of it
  /// ("hotmail.co" may be a cut "hotmail.com") and any other address in the
  /// text. Empty when there is none; at most
  /// [OcrCredentialParser.maxCandidates] entries.
  final List<String> emailCandidates;

  /// Passwords worth offering, best first: [password], how it reads with the
  /// OCR junk left on ("abc|", "abc_"), other password-like tokens and the
  /// pieces of a value that OCR split in two. Same cap as [emailCandidates].
  final List<String> passwordCandidates;

  /// How much this reading looks like a login, from 0 (nothing found) to 1
  /// (a plausible address and a plausible password). A scanner that reads the
  /// same image several ways keeps the highest. Both values found always beat
  /// one of them: about 0.7 to 1.0 against at most 0.5. Computed from the
  /// fields, so it stays right after [copyWith] or a rebuilt result.
  double get quality {
    final mail = email;
    final user = username;
    final pass = password;
    var q = 0.0;
    if (mail != null) {
      q += 0.30 + 0.10 * _emailPlausibility(mail);
    } else if (user != null) {
      q += 0.20;
    }
    if (pass != null) q += 0.30 + 0.20 * _passwordPlausibility(pass);
    if ((mail != null || user != null) && pass != null) q += 0.10;
    return q > 1 ? 1.0 : q;
  }

  OcrResult copyWith({
    List<String>? chips,
    String? title,
    String? email,
    String? username,
    String? password,
    String? url,
    List<String>? emailCandidates,
    List<String>? passwordCandidates,
  }) => OcrResult(
    chips: chips ?? this.chips,
    title: title ?? this.title,
    email: email ?? this.email,
    username: username ?? this.username,
    password: password ?? this.password,
    url: url ?? this.url,
    emailCandidates: emailCandidates ?? this.emailCandidates,
    passwordCandidates: passwordCandidates ?? this.passwordCandidates,
  );
}

/// 0..1: a TLD that exists, a well-known provider and a local part with some
/// length all make an address more believable.
double _emailPlausibility(String address) {
  final at = address.lastIndexOf('@');
  if (at < 1) return 0;
  final local = address.substring(0, at);
  final labels = address.substring(at + 1).split('.');
  var s = 0.0;
  if (labels.length >= 2) s += 0.2;
  final tld = labels.last.toLowerCase();
  if (OcrCredentialParser._commonTlds.contains(tld) || tld.length == 2) {
    s += 0.3;
  }
  s += OcrCredentialParser._providers.contains(labels.first.toLowerCase())
      ? 0.3
      : 0.1;
  s += local.length >= 3 ? 0.2 : 0.1;
  // A symbol OCR made of a letter or digit ("abcde0/@hotmail.com").
  if (local.contains(RegExp(r'[^A-Za-z0-9._%+\-]'))) s *= 0.5;
  return s > 1 ? 1.0 : s;
}

/// 0..1: 8 to 32 characters, several character classes and no OCR junk or
/// space left on it make a password more believable.
double _passwordPlausibility(String password) {
  final n = password.length;
  var s = 0.0;
  if (n >= 8 && n <= 32) {
    s += 0.4;
  } else if (n >= 6) {
    s += 0.25;
  } else if (n >= 4 || n > 32) {
    s += 0.1;
  }
  final classes = OcrCredentialParser._classes(password);
  s += classes >= 3
      ? 0.4
      : classes == 2
      ? 0.25
      : 0.1;
  if (!password.contains(RegExp(r'^[|~_.]|[|_.~]$|\s'))) s += 0.2;
  return s > 1 ? 1.0 : s;
}

/// Lines after the clean-up in [OcrCredentialParser.parse].
class _Prepared {
  _Prepared();

  /// The lines the rest of the parser reads.
  final lines = <String>[];

  /// Whether the line at the same index was cut out of a longer line at a
  /// single space ("address password"): too weak to be taken as a password on
  /// position alone.
  final merged = <bool>[];

  /// A password OCR split in two and [OcrCredentialParser._joinable] put back
  /// together, with the two pieces.
  final joinedFrom = <String, List<String>>{};

  /// A token as OCR read it, with its junk ("abc|"), by the token without.
  final rawVariants = <String, Set<String>>{};

  /// Whether the line at the same index is an address OCR damaged beyond
  /// repair ("abcde0/@hotmail.com", "abcde07Chotmail. com"): not an address,
  /// but not a password or a website either.
  final broken = <bool>[];

  /// Every token of the [broken] lines, as read and without its junk.
  final brokenTokens = <String>{};
}

/// An e-mail address in one line: the span OCR produced, the address with the
/// OCR noise repaired and other readings worth offering.
class _EmailHit {
  const _EmailHit(
    this.start,
    this.end,
    this.raw,
    this.address, [
    this.alternatives = const [],
  ]);
  final int start;
  final int end;
  final String raw;
  final String address;

  /// Other addresses the span may have been: the reading before a repair, or
  /// the longer domain a cut one may have had.
  final List<String> alternatives;
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
  static final RegExp _domainDot = RegExp(r'\s*[.,]{1,2}\s*');
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

  /// Consumer mail providers: a domain that OCR spelt "hotmai1" or
  /// "hotrnail" is theirs, and "hotmail.co" at the edge of a crop is
  /// "hotmail.com" with its "m" cut off.
  static const _providers = {
    'hotmail',
    'outlook',
    'live',
    'msn',
    'gmail',
    'yahoo',
    'aol',
    'icloud',
  };

  /// What is left of "com" when the crop cuts the address off.
  static const _cutTlds = {'c', 'co', 'cm'};

  /// Providers that also run "co.uk" addresses.
  static const _coUkProviders = {'hotmail', 'live', 'yahoo', 'outlook'};

  /// "user:pass" after an address, as in pasted combo lists.
  static final RegExp _comboTail = RegExp(r'^\s*[:：|]\s*(\S+)\s*$');
  static final RegExp _comboStart = RegExp(r'^\s*[:：|]');
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

  /// The most entries in [OcrResult.emailCandidates] and
  /// [OcrResult.passwordCandidates].
  static const int maxCandidates = 6;

  /// Text after this many characters is ignored. The clipboard can hold
  /// anything another app or a website put there, and parsing runs on the UI
  /// isolate.
  static const int maxInputLength = 16 * 1024;

  /// Runs without whitespace longer than this are dropped before parsing: no
  /// address (254 characters at most) or password is that long, and long
  /// base64 or hex strings would make the regular expressions below slow.
  static const int maxTokenLength = 256;
  static final RegExp _token = RegExp(r'\S+');
  static final RegExp _ws = RegExp(r'\s+');

  /// A gap OCR leaves between two fields on one line: a tab or two spaces.
  static final RegExp _gap = RegExp(r'\t| {2,}');

  /// A token that is only OCR junk or a bullet: "|", "_", "•", "-", quotes.
  static final RegExp _junkToken = RegExp(
    r'''^[|_.~•·●○◦▪■□◆◇▶►‣⁃*>\-–—"'“”‘’«»,;]+$''',
  );

  /// Bullets glued to the text ("•abcde07@hotmail.com"), and quotes round it.
  static final RegExp _glued = RegExp(r'^[•·●○◦▪■□◆◇▶►‣⁃]+');
  static final RegExp _quoteStart = RegExp(r'''^["'“‘«`]''');
  static final RegExp _quoteEnd = RegExp(r'''["'”’»`]$''');

  /// Punctuation round a token, then the OCR junk that follows a value
  /// ("abc|", "abc_", "abc.", "abc~"). A trailing colon stays: it makes a
  /// label of "Website:".
  static final RegExp _edgePunct = RegExp(
    r'^[,;:"“”()\[\]|~]+|[,;"“”()\[\]|_.~]+$',
  );
  static final RegExp _outer = RegExp(
    r'''^[\s|_.~,;()\[\]{}<>"“”]+|[\s|_.~,;()\[\]{}<>"“”]+$''',
  );
  static final RegExp _labelEnd = RegExp(r'[:：=]$');

  /// Compatibility characters that NFKC would fold to ASCII, plus the dashes
  /// and ideographic stops OCR reads for "-" and ".".
  static const _compat = <int, String>{
    0x00B2: '2',
    0x00B3: '3',
    0x00B9: '1',
    0x2010: '-',
    0x2011: '-',
    0x2012: '-',
    0x2013: '-',
    0x2024: '.',
    0x2025: '..',
    0x2026: '...',
    0x2044: '/',
    0x2070: '0',
    0x2074: '4',
    0x2075: '5',
    0x2076: '6',
    0x2077: '7',
    0x2078: '8',
    0x2079: '9',
    0x2080: '0',
    0x2081: '1',
    0x2082: '2',
    0x2083: '3',
    0x2084: '4',
    0x2085: '5',
    0x2086: '6',
    0x2087: '7',
    0x2088: '8',
    0x2089: '9',
    0x2212: '-',
    0x3002: '.',
    0xFB00: 'ff',
    0xFB01: 'fi',
    0xFB02: 'fl',
    0xFB03: 'ffi',
    0xFB04: 'ffl',
    0xFB05: 'st',
    0xFB06: 'st',
    0xFE50: ',',
    0xFE52: '.',
    0xFE55: ':',
    0xFE63: '-',
    0xFE6B: '@',
    0xFF61: '.',
  };

  /// [parse] for pasted text: one string, any line endings.
  OcrResult parseText(String text) => parse([text]);

  OcrResult parse(List<String> rawLines) {
    final prep = _prepare(rawLines);
    final lines = prep.lines;
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
        if (c.$3 != c.$2) {
          prep.rawVariants.putIfAbsent(c.$2, () => {}).add(c.$3);
        }
      }
      for (final token in lines[i].split(_ws)) {
        final clean = _cleanToken(token);
        chip(clean);
        // "abc|" is "abc" for the chip and the guess, and stays an option.
        final kept = _stripPunct(token);
        if (clean.isNotEmpty && kept != clean) {
          prep.rawVariants.putIfAbsent(clean, () => {}).add(kept);
        }
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

    final emailMatch =
        hits.firstOrNull?.address ??
        _lenientAddress(lines, hitsByLine, prep.broken);
    final combo = [for (final c in combosByLine) ...c].firstOrNull;
    final url = _findUrl(lines, hitsByLine, prep.broken);
    final exclude = {?emailMatch, ...prep.brokenTokens};

    final username =
        labelled(_userLabels, _pickUser) ?? combo?.$1 ?? emailMatch;
    final skip = {...exclude, ?username, ?url};
    final alone = {
      for (final l in lines)
        if (!l.contains(' ')) l,
    };
    final password =
        labelled(_passwordLabels, (v) => _pickPassword(v, hits, prep)) ??
        combo?.$2 ??
        // The line next to the address, when it reads like a password: the
        // two lines of a login are better evidence than any other token.
        _besideAddress(
          lines,
          hitsByLine,
          prep.merged,
          prep.broken,
          exclude: skip,
          likely: true,
        ) ??
        _guessPassword(chips, exclude: skip, emails: hits, alone: alone) ??
        _besideAddress(
          lines,
          hitsByLine,
          prep.merged,
          prep.broken,
          exclude: skip,
        ) ??
        _loneToken(lines);

    return OcrResult(
      chips: chips.toList(),
      email: emailMatch,
      username: username,
      password: password,
      url: url,
      title: _title(url, lines),
      emailCandidates: _emailCandidates(emailMatch, username, hits),
      passwordCandidates: _passwordCandidates(
        password,
        prep,
        chips,
        hitsByLine,
        exclude: skip,
        emails: hits,
        alone: alone,
      ),
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

  // ---------------------------------------------------------------- lines

  /// The lines of [rawLines] as OCR meant them: Unicode spaces and widths
  /// folded, two values on one line apart, letter-spaced text closed up,
  /// bullets, quotes and junk dropped, an address and a password sharing a
  /// line parted and a password OCR split in two put back together.
  static _Prepared _prepare(List<String> rawLines) {
    final prep = _Prepared();
    void add(String line, {bool merged = false}) {
      prep.lines.add(line);
      prep.merged.add(merged);
    }

    for (final raw in _limit(rawLines)) {
      for (final l in _dropLongTokens(raw).split(_lineBreak)) {
        final normal = _normalize(l);
        if (normal.trim().isEmpty) continue;
        for (final part in _gapParts(normal)) {
          var t = _dropIcon(
            _trimJunkTokens(_stripBullets(_despace(part))),
            prep,
          );
          if (t.isEmpty) continue;
          if (!t.contains(' ')) {
            final clean = _cleanToken(t);
            if (clean != t && clean.isNotEmpty) {
              prep.rawVariants.putIfAbsent(clean, () => {}).add(_stripPunct(t));
            }
            t = clean;
            if (t.isEmpty) continue;
          }
          final split = _splitMerged(t, prep);
          if (split == null) {
            add(t);
          } else {
            add(split[0], merged: split[0] != split[1]);
            add(split[1], merged: true);
          }
        }
      }
    }
    _joinSplitAddress(prep);
    _joinSplitPassword(prep);
    for (final l in prep.lines) {
      final damaged = _findEmails(l).isEmpty && _addressish(l);
      prep.broken.add(damaged);
      if (damaged) {
        for (final t in l.split(' ')) {
          prep.brokenTokens
            ..add(t)
            ..add(_cleanToken(t));
        }
      }
    }
    return prep;
  }

  /// A subset of NFKC that matters for OCR: no-break and ideographic spaces
  /// become spaces, zero-width and bidi marks and control characters go,
  /// full-width forms ("ａ＠１") become ASCII and ligatures ("ﬁ") spell out.
  /// A tab stays a tab: it parts two values.
  static String _normalize(String s) {
    StringBuffer? out;
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      String? to;
      if (c < 0x20 || c == 0x7F) {
        to = c == 0x09
            ? null
            : (c == 0x0B || c == 0x0C || (c >= 0x1C && c <= 0x1F) ? ' ' : '');
      } else if (c >= 0x80) {
        to = _foldCompat(c);
      }
      if (to == null) {
        out?.writeCharCode(c);
      } else {
        out ??= StringBuffer(s.substring(0, i));
        out.write(to);
      }
    }
    return out?.toString() ?? s;
  }

  static String? _foldCompat(int c) {
    if (c < 0xA0) return ''; // C1 controls (U+0085 already ended the line)
    if (c == 0xA0 ||
        c == 0x1680 ||
        (c >= 0x2000 && c <= 0x200A) ||
        c == 0x202F ||
        c == 0x205F ||
        c == 0x3000) {
      return ' ';
    }
    if (c == 0xAD ||
        c == 0x061C ||
        c == 0x180E ||
        (c >= 0x200B && c <= 0x200F) ||
        (c >= 0x202A && c <= 0x202E) ||
        (c >= 0x2060 && c <= 0x2064) ||
        (c >= 0x2066 && c <= 0x2069) ||
        c == 0xFEFF) {
      return '';
    }
    if (c >= 0xFF01 && c <= 0xFF5E) return String.fromCharCode(c - 0xFEE0);
    return _compat[c];
  }

  /// [line] cut at each tab or run of spaces, each label joined to its value
  /// ("Password:", then the value) and each address kept whole ("abcde07 @",
  /// then "hotmail.com"). One part when nothing is left to cut.
  static List<String> _gapParts(String line) {
    if (!line.contains(_gap)) return [line.trim()];
    // Letter-spaced text has gaps of its own ("x Q m R 4 2  a b C D  5 k"):
    // there only a tab or a wider gap parts two values.
    final spaced = _letterSpaced(line);
    final parts = [
      for (final p in line.split(spaced ? _wideGap : _gap))
        if (p.trim().isNotEmpty)
          spaced ? p.trim().replaceAll(_spaceRun, ' ') : p.trim(),
    ];
    final out = <String>[];
    var cur = '';
    for (final p in parts) {
      if (cur.isEmpty) {
        cur = p;
      } else if (_joinsNext(cur, p)) {
        cur = '$cur $p';
      } else {
        out.add(cur);
        cur = p;
      }
    }
    if (cur.isNotEmpty) out.add(cur);
    return out;
  }

  static final RegExp _wideGap = RegExp(r'\t| {3,}');
  static final RegExp _spaceRun = RegExp(r' {2,}');

  /// Whether most tokens of [line] are one character: OCR read the letters
  /// of a word one by one.
  static bool _letterSpaced(String line) {
    var tokens = 0;
    var singles = 0;
    for (final t in line.split(_ws)) {
      if (t.isEmpty) continue;
      tokens++;
      if (t.length == 1) singles++;
    }
    return tokens >= 6 && singles * 5 >= tokens * 3;
  }

  static bool _joinsNext(String cur, String next) =>
      cur.endsWith('@') ||
      _labelEnd.hasMatch(cur) ||
      _isLabel(cur) ||
      RegExp(r'^[@.,]').hasMatch(next);

  /// "a b c d e 0 7 @ h o t m a i l . c o m" is how OCR reads letter-spaced
  /// text: when most tokens of a line are one character, close the line up
  /// (a leading label stays apart). Longer tokens are fragments of the same
  /// text unless one is a whole word.
  static String _despace(String line) {
    if (!line.contains(' ')) return line;
    var tokens = line.split(' ');
    String? label;
    final first = tokens.first;
    if (first.length > 1 && (_isLabel(first) || _labelEnd.hasMatch(first))) {
      label = first;
      tokens = tokens.sublist(1);
    }
    if (tokens.length < 4) return line;
    var singles = 0;
    var longest = 0;
    for (final t in tokens) {
      if (t.length == 1) singles++;
      if (t.length > longest) longest = t.length;
    }
    if (singles * 5 < tokens.length * 3 || longest > 8) return line;
    return label == null ? tokens.join() : '$label ${tokens.join()}';
  }

  /// What OCR makes of the eye icon of a password field.
  static const _iconChars = {'O', 'o', 'Q', '0', '@', '©', '®', 'Ø', 'ø'};

  /// "xQmR42abCD5k O": a lone icon letter next to a whole password is not
  /// part of it. The line is the password; the password with the letter stays
  /// an option.
  static String _dropIcon(String line, _Prepared prep) {
    final tokens = line.split(' ');
    if (tokens.length != 2) return line;
    for (final icon in [0, 1]) {
      final keep = tokens[1 - icon];
      final clean = _cleanToken(keep);
      if (_iconChars.contains(tokens[icon]) &&
          clean.length >= 8 &&
          _passwordish(clean)) {
        prep.rawVariants.putIfAbsent(clean, () => {}).add(tokens.join());
        return keep;
      }
    }
    return line;
  }

  /// A bullet glued to the text and quotes round the line.
  static String _stripBullets(String line) {
    var t = line.replaceFirst(_glued, '').trimLeft();
    if (t.length > 1 && _quoteStart.hasMatch(t)) t = t.substring(1);
    if (t.length > 1 && _quoteEnd.hasMatch(t)) {
      t = t.substring(0, t.length - 1);
    }
    return t.trim();
  }

  /// Drops the tokens at either end that are only a bullet or junk: "- abc",
  /// "abc |".
  static String _trimJunkTokens(String line) {
    final tokens = line.split(' ');
    var a = 0;
    var b = tokens.length;
    bool junk(String t) => t.isEmpty || _junkToken.hasMatch(t);
    while (a < b && junk(tokens[a])) {
      a++;
    }
    while (b > a && junk(tokens[b - 1])) {
      b--;
    }
    return a == 0 && b == tokens.length ? line : tokens.sublist(a, b).join(' ');
  }

  /// "abcde07@hotmail.com xQmR42abCD5k" as two lines, in the order they came.
  /// Only when the rest of the line is one token (or two that [_joinable]
  /// puts together) that looks like a password: "Signed in as x@y.com" and
  /// "x@y.com Verified" stay one line. The address span is kept as OCR read
  /// it. A combo ("x@y.com:pass") is left to [_combo].
  static List<String>? _splitMerged(String line, _Prepared prep) {
    if (!line.contains(_atLike)) return null;
    final hits = _findEmails(line);
    if (hits.length != 1) return null;
    final h = hits.first;
    final tail = line.substring(h.end);
    if (_comboStart.hasMatch(tail)) return null;
    final before = line.substring(0, h.start).replaceAll(_outer, '');
    final after = tail.replaceAll(_outer, '');
    if (before.isEmpty == after.isEmpty) return null;
    final rest = before.isEmpty ? after : before;
    if (_labelEnd.hasMatch(rest)) return null;
    final tokens = rest.split(' ');
    String? value;
    if (tokens.length == 1) {
      final t = _cleanToken(tokens[0]);
      if (_passwordish(t)) value = t;
    } else if (tokens.length == 2) {
      final a = _cleanToken(tokens[0]);
      final b = _cleanToken(tokens[1]);
      if (_joinable(a, b)) {
        value = '$a$b';
        prep.joinedFrom[value] = [a, b];
      }
    }
    if (value == null) return null;
    final address = line.substring(h.start, h.end);
    return before.isEmpty ? [address, value] : [value, address];
  }

  /// "abcde07@" over "hotmail.com" and "abcde07@hotmail" over ".com": OCR put
  /// the end of an address on the next line. Joins the two lines.
  static void _joinSplitAddress(_Prepared prep) {
    final lines = prep.lines;
    for (var i = 0; i + 1 < lines.length; i++) {
      final open = _openAddress.firstMatch(lines[i]);
      if (open == null) continue;
      final next = lines[i + 1];
      final label = open[2]!;
      String? joined;
      if (label.isEmpty) {
        if (_domainLine.hasMatch(next)) joined = '${open[1]}@$next';
      } else if (_tldLine.hasMatch(next)) {
        joined = '${open[1]}@$label.${next.replaceFirst(_leadingDot, '')}';
      }
      if (joined == null) continue;
      lines[i] = joined;
      lines.removeAt(i + 1);
      prep.merged.removeAt(i + 1);
    }
  }

  /// A local part, "@" and at most a first label of the domain.
  static final RegExp _openAddress = RegExp(
    r'^([A-Za-z0-9][A-Za-z0-9._%+\-]*) ?[@＠﹫]([A-Za-z0-9\-]*)\.?$',
  );
  static final RegExp _domainLine = RegExp(
    r'^[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}$',
  );
  static final RegExp _tldLine = RegExp(
    r'^(?:\.\s*[a-z]{2,6}|(?:com|corn|net|org))(?:\.[a-z]{2})?$',
    caseSensitive: false,
  );
  static final RegExp _leadingDot = RegExp(r'^\.\s*');

  /// "xQmR42 abCD5k" under an address: OCR put a space in the middle of the
  /// password. Joins the two tokens of the line next to the first address
  /// (below it, else above it), or of the only line there is, when the whole
  /// looks like a password.
  static void _joinSplitPassword(_Prepared prep) {
    final lines = prep.lines;
    var at = lines.indexWhere((l) => _findEmails(l).isNotEmpty);
    // An address OCR damaged ("abcde07@hotmail com") still says where the
    // password is.
    if (at < 0) at = lines.indexWhere(_addressish);
    final List<int> candidates;
    if (at >= 0) {
      candidates = [at + 1, at - 1];
    } else if (lines.length == 1) {
      candidates = [0];
    } else if (lines.length <= _cropLines) {
      // A crop of a few lines and no address: the one line that reads as a
      // password when joined.
      final only = [
        for (var j = 0; j < lines.length; j++)
          if (_joinedLine(lines[j], strict: true) != null) j,
      ];
      candidates = only.length == 1 ? only : const <int>[];
    } else {
      candidates = const <int>[];
    }
    for (final j in candidates) {
      if (j < 0 ||
          j >= lines.length ||
          _findEmails(lines[j]).isNotEmpty ||
          _addressish(lines[j])) {
        continue;
      }
      final joined = _joinedLine(lines[j], strict: at < 0);
      if (joined == null) continue;
      lines[j] = joined.$1;
      prep.joinedFrom[joined.$1] = joined.$2;
      return;
    }
  }

  /// A text this short is a crop of a login, not a page.
  static const int _cropLines = 6;

  /// [line] as one password, with its pieces, when it is two or three tokens
  /// that [_joinableParts] puts together.
  static (String, List<String>)? _joinedLine(
    String line, {
    required bool strict,
  }) {
    final tokens = line.split(' ');
    if (tokens.length < 2 || tokens.length > 3) return null;
    final parts = [for (final t in tokens) _cleanToken(t)];
    return _joinableParts(parts, strict: strict) ? (parts.join(), parts) : null;
  }

  /// Whether [a] and [b] are the two halves of one password: both hold a
  /// letter or digit, they are not labels, times or two passwords of their
  /// own, and together they are 8 to 32 characters of a password's shape:
  /// "xQmR42" and "abCD5k" yes, "Remember" and "me", "Forgot" and "password?",
  /// "Notes:" and "none" or "Meeting" and "10:45" no. With no address nearby
  /// ([strict]) the whole must also have digits and two case changes
  /// ("Invoice 2024" is not a password).
  static bool _joinable(String a, String b, {bool strict = false}) =>
      _joinableParts([a, b], strict: strict);

  /// [_joinable] for two or three pieces: "gBv5Cz 2MxA7j" and "gBv 5Cz2M xA7j"
  /// ([strict] is always on for three, which is more likely to be words).
  static bool _joinableParts(List<String> parts, {bool strict = false}) {
    var long = 0;
    for (final t in parts) {
      if (t.isEmpty || !_alnum.hasMatch(t)) return false;
      if (t.length >= 8) long++;
      final word = t.replaceAll(_sentenceEnd, '');
      if (_isLabel(word) ||
          _uiWords.contains(word.toLowerCase()) ||
          _dateOrTime.hasMatch(t) ||
          _labelEnd.hasMatch(t)) {
        return false;
      }
    }
    if (long > 1) return false;
    final whole = parts.join();
    if (whole.length < 8 || whole.length > 32 || !_passwordish(whole)) {
      return false;
    }
    if (strict || parts.length > 2) {
      return _digit.hasMatch(whole) && _caseJump.allMatches(whole).length >= 2;
    }
    return _classes(whole) >= 3 ||
        (whole.length >= 10 && _digit.hasMatch(whole));
  }

  static final RegExp _alnum = RegExp(r'[A-Za-z0-9]');
  static final RegExp _digit = RegExp(r'[0-9]');
  static final RegExp _lower = RegExp(r'[a-z]');
  static final RegExp _upper = RegExp(r'[A-Z]');
  static final RegExp _symbol = RegExp(r'[^A-Za-z0-9]');
  static final RegExp _caseJump = RegExp(r'[a-z][A-Z]');
  static final RegExp _sentenceEnd = RegExp(r'[?!.]+$');

  /// How many of lower case, upper case, digits and symbols [t] has.
  static int _classes(String t) =>
      (_lower.hasMatch(t) ? 1 : 0) +
      (_upper.hasMatch(t) ? 1 : 0) +
      (_digit.hasMatch(t) ? 1 : 0) +
      (_symbol.hasMatch(t) ? 1 : 0);

  /// Whether [t] could be a password when nothing else says so: 4 to 64
  /// characters, letters with digits, or an upper case letter in the middle
  /// of the word more than once, or a symbol with both cases. Not a word
  /// ("Hello"), a number, a label, a date, an address or a site.
  static bool _passwordish(String t) {
    if (t.length < 4 || t.length > 64 || t.contains(' ')) return false;
    if (RegExp(r'[:：]$').hasMatch(t) || _isLabel(t)) return false;
    if (_uiWords.contains(t.toLowerCase()) || _dateOrTime.hasMatch(t)) {
      return false;
    }
    if (t.contains('://') || _url.hasMatch(t) || email.hasMatch(t)) {
      return false;
    }
    final letter = _lower.hasMatch(t) || _upper.hasMatch(t);
    if (letter && _digit.hasMatch(t)) return true;
    if (_caseJump.allMatches(t).length >= 2) return true;
    // A "?" or "!" at the end is a sentence, not a symbol in a password.
    return _symbol.hasMatch(t.replaceAll(_sentenceEnd, '')) &&
        _lower.hasMatch(t) &&
        _upper.hasMatch(t);
  }

  /// The only token there is, when it could be a password.
  static String? _loneToken(List<String> lines) {
    if (lines.length != 1) return null;
    final t = lines.first;
    // "abcde07@hotmail" is a broken address, not a password.
    if (t.contains(' ') || t.contains(_atLike)) return null;
    return _passwordish(t) ? t : null;
  }

  static final RegExp _atSign = RegExp(r'[@＠﹫]');
  static final RegExp _providerName = RegExp(
    r'hotmail|outlook|gmail|yahoo|icloud',
    caseSensitive: false,
  );
  static final RegExp _domainRest = RegExp(
    r'^\s*[.,:]\s*[A-Za-z]|^\s+[A-Za-z]{2,4}\W*$',
  );
  static final RegExp _comTail = RegExp(r'^[A-Za-z0-9\-]{3,}(?:com|corn)$');
  static final RegExp _tldRest = RegExp(r'^\s*[.,]?\s*[A-Za-z]{0,4}\W*$');

  /// Whether [s] is what is left of an address OCR damaged beyond repair: an
  /// "@" followed by a domain with a dot or a provider's name
  /// ("abcde0/@hotmail.com", "abcde07@hotmail com", "abcde07@"), or a
  /// provider's name that follows what was a local part ("abcde07Chotmail. com",
  /// "abcde07( - C hotmail.com"). Not a password and not a website. A plain
  /// "P@ssw0rd" is neither.
  static bool _addressish(String s) {
    if (s.length < 4 || s.length > 120) return false;
    final at = s.lastIndexOf(_atSign);
    if (at >= 1) {
      final tail = s.substring(at + 1).trimLeft();
      if (tail.isEmpty) return true;
      final label = _domainLabel.matchAsPrefix(tail);
      if (label == null) return false;
      return _domainRest.hasMatch(tail.substring(label.end)) ||
          _providerOf(label[0]!) != null ||
          _comTail.hasMatch(tail);
    }
    final m = _providerName.firstMatch(s);
    if (m == null || !_tldRest.hasMatch(s.substring(m.end))) return false;
    final before = s.substring(0, m.start);
    // Glued to the local part, or only OCR junk between it and the provider.
    if (before.isNotEmpty && before[before.length - 1] != ' ') {
      return before.length >= 3;
    }
    final tokens = before.trimRight().split(' ');
    return tokens.first.length >= 4 &&
        _digit.hasMatch(tokens.first) &&
        tokens.skip(1).every((t) => t.length <= 2);
  }

  static bool _isLabel(String s) {
    final lower = s.toLowerCase().replaceAll(RegExp(r'[:：]'), '').trim();
    return _passwordLabels.contains(lower) || _userLabels.contains(lower);
  }

  static String _stripPunct(String t) =>
      t.replaceAll(RegExp(r'^[,;:"“”()\[\]]+|[,;"“”()\[\]]+$'), '');

  /// [t] without the punctuation round it and the OCR junk after it
  /// ("xQmR42abCD5k|" and "xQmR42abCD5k." are "xQmR42abCD5k").
  static String _cleanToken(String t) => t.replaceAll(_edgePunct, '');

  // --------------------------------------------------------------- emails

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
    var name = first[0]!;
    var nameEnd = first.end;
    // "h otmail.com", "hot mail.com": a space inside a provider's name.
    final more = _spacedLabel.matchAsPrefix(line, nameEnd);
    if (more != null &&
        !_providers.contains(name.toLowerCase()) &&
        _providerOf('$name${more[1]}') != null) {
      name = '$name${more[1]}';
      nameEnd = more.end;
    }
    final labels = [name];
    final ends = [nameEnd];
    var noisy = false;
    final glued = _unglue(name);
    final lost = glued != null;
    if (lost) {
      // "hotmailcom", "hotmailicom": the dot was lost.
      labels
        ..[0] = glued.$1
        ..add(glued.$2);
      ends.add(nameEnd);
      noisy = true;
    }
    while (!lost) {
      final dot = _domainDot.matchAsPrefix(line, ends.last);
      final next = dot == null
          ? null
          : _domainLabel.matchAsPrefix(line, dot.end);
      if (next == null && labels.length == 1) {
        // "hotmail com": a provider's name, a space and the TLD.
        final bare = _spacedTld.matchAsPrefix(line, ends.last);
        if (bare != null && _providerOf(labels.first) != null) {
          labels.add(bare[1]!);
          ends.add(bare.end);
          noisy = true;
        }
        break;
      }
      if (next == null) break;
      if (dot![0] != '.') {
        // Only the first dot may be noisy ("hotmail .com", "hotmail,com"):
        // after a real dot the address is complete, and "x@a.com, Pass" or
        // "x@a.com. Next" must not run on. "hotmail.co. uk" is the one
        // exception: nothing else follows "co." in lower case.
        if (labels.length > 1) {
          if (!_spacedCountry(labels.last, dot[0]!, next[0]!)) break;
        } else {
          noisy = true;
        }
      }
      labels.add(next[0]!);
      ends.add(next.end);
    }
    // "abcde07@hotmail.comxQmR42abCD5k": letter-spaced text closed up with the
    // next value. A provider's address ends at "com".
    if (labels.length == 2 &&
        labels.last.length >= 7 &&
        _commonEnd.hasMatch(labels.last) &&
        _providerOf(labels.first) != null) {
      ends.last -= labels.last.length - 3;
      labels.last = labels.last.substring(0, 3);
    }
    // Drop trailing labels that cannot be a TLD ("x@a.com.5").
    while (labels.length > 1) {
      // "hotmail.c": a provider's address cut off in the middle of "com".
      final cut =
          !noisy &&
          labels.length == 2 &&
          labels.last.toLowerCase() == 'c' &&
          _providerOf(labels.first) != null;
      final tld = cut ? 'c' : _plausibleTld(labels.last, noisy: noisy);
      if (tld != null) {
        labels.last = tld;
        final own = head[1]!.replaceAll(_ws, '');
        // "abcde0 7@hotmail.com": OCR split the local part and the address
        // starts at the "7". A local part this short with a word before it
        // takes the word in; a longer one only offers it.
        final before = line.substring(0, head.start);
        final lead = _leadingFragment(before);
        final join = lead != null && _fragmentOf(lead, own);
        // "abcdeO/7@hotmail.com": a stray stroke inside the local part left
        // only its tail ("7") for the address. The whole word, without the
        // stroke, is the better reading.
        final cut = lead == null ? _cutFragment(before, own) : null;
        final read = join ? '$lead$own' : (cut != null ? '$cut$own' : own);
        // "Abcde07@hotmail.com": an engine's capital at the start of a line.
        final local =
            _providerOf(labels.first) != null && _capitalised.hasMatch(read)
            ? read.toLowerCase()
            : read;
        final plain = '$local@${labels.join('.').toLowerCase()}';
        final (address, alternatives) = _repairDomain(local, labels, plain);
        if (local != read) {
          alternatives.add('$read${address.substring(address.indexOf('@'))}');
        }
        if (lead != null) {
          alternatives.add(
            join
                ? '$own${address.substring(address.indexOf('@'))}'
                : '$lead$address',
          );
        }
        final start = join || cut != null ? 0 : head.start;
        return _EmailHit(
          start,
          ends.last,
          line.substring(start, ends.last),
          address,
          alternatives,
        );
      }
      labels.removeLast();
      ends.removeLast();
    }
    return null;
  }

  static final RegExp _commonEnd = RegExp(
    r'^(?:com|net|org)[A-Za-z0-9]',
    caseSensitive: false,
  );

  /// One capital, the first letter, and not an "I" or "O" that may be an "l"
  /// or a zero.
  static final RegExp _capitalised = RegExp(r'^[A-HJ-NP-Z][^A-Z]*$');
  static final RegExp _spacedLabel = RegExp(r' +([A-Za-z0-9\-]{1,12})');
  static final RegExp _spacedTld = RegExp(r' +(com|corn|c0m)(?![A-Za-z0-9])');

  /// A provider's name and "com" with nothing, or one letter OCR read for the
  /// dot, in between: "hotmailcom" and "hotmailicom" are ("hotmail", "com").
  static (String, String)? _unglue(String name) {
    final lower = name.toLowerCase();
    for (final tld in const ['com', 'corn']) {
      if (!lower.endsWith(tld) || name.length < tld.length + 4) continue;
      final stem = name.substring(0, name.length - tld.length);
      if (_providerOf(stem) != null) return (stem, tld);
      final cut = stem.substring(0, stem.length - 1);
      if ('il1I|!'.contains(stem[stem.length - 1]) &&
          _providerOf(cut) != null) {
        return (cut, tld);
      }
    }
    return null;
  }

  /// "hotmail.co. uk" and "hotmail.co .uk": the space OCR left round the dot
  /// of a country code.
  static bool _spacedCountry(String previous, String dot, String label) =>
      previous.toLowerCase() == 'co' && dot.trim() == '.' && label == 'uk';

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

  /// Whether [lead], the word before an address, is the start of its local
  /// part [own]: the address starts with a very short piece ("7") and the word
  /// is not a label, a date or a password's length of mixed case, or it
  /// starts a little longer piece ("t99") and looks like a local part itself
  /// ("jdoe.tes").
  static bool _fragmentOf(String lead, String own) {
    if (_isLabel(lead) ||
        _uiWords.contains(lead.toLowerCase()) ||
        _dateOrTime.hasMatch(lead)) {
      return false;
    }
    if (own.length <= 2) return lead.length <= 7 || !_upper.hasMatch(lead);
    return own.length <= 4 &&
        _fragmentMark.hasMatch(lead) &&
        !_upper.hasMatch(lead);
  }

  static final RegExp _fragmentMark = RegExp(r'[0-9._%+\-]');

  /// "abcde0" in "abcde0 7@hotmail.com": OCR may have split the local part,
  /// so the one word in front of an address at the start of the line is
  /// offered as part of it.
  static String? _leadingFragment(String prefix) =>
      _fragment.firstMatch(prefix)?[1];

  /// "abcdeO" in "abcdeO/7@hotmail.com": the word at the start of the line
  /// that a stray stroke ("/", "|" or "!") cut off the address, when
  /// what is left of the local part is one or two characters. A longer rest
  /// ("abc/de07@") is a plausible address of its own.
  static String? _cutFragment(String prefix, String own) {
    final word = _cutWord.firstMatch(prefix)?[1];
    return word != null && own.length <= 2 && _fragmentOf(word, own)
        ? word
        : null;
  }

  static final RegExp _cutWord = RegExp(
    r'^([A-Za-z0-9][A-Za-z0-9._%+\-]{0,23})[/\\|!\u00a6]+$',
  );

  static final RegExp _fragment = RegExp(
    r'^([A-Za-z0-9][A-Za-z0-9._%+\-]{0,23}) +$',
  );

  /// The address with a provider's name and a cut TLD put right, and the
  /// readings it replaces. "hotmai1.com" and "hotmaiI.com" are "hotmail.com";
  /// "hotmail.co" at the edge of a crop is "hotmail.com" (or "hotmail.co.uk").
  /// Nothing else changes: the local part is never touched, and "hotmail.cam"
  /// stays what it is.
  static (String, List<String>) _repairDomain(
    String local,
    List<String> labels,
    String plain,
  ) {
    final fixed = [...labels];
    for (var i = 0; i < fixed.length - 1; i++) {
      fixed[i] = _providerOf(fixed[i]) ?? fixed[i];
    }
    final alternatives = <String>[];
    final provider = fixed.first.toLowerCase();
    if (fixed.length == 2 &&
        _providers.contains(provider) &&
        _cutTlds.contains(fixed.last)) {
      final cut = fixed.last;
      if (cut == 'co' && _coUkProviders.contains(provider)) {
        alternatives.add('$local@$provider.co.uk');
      }
      if (cut != 'c') alternatives.add('$local@$provider.$cut');
      fixed.last = 'com';
    }
    final address = '$local@${fixed.join('.').toLowerCase()}';
    if (address != plain &&
        !alternatives.contains(plain) &&
        !plain.endsWith('.c')) {
      alternatives.add(plain);
    }
    return (address, alternatives);
  }

  /// The provider a domain label is a misreading of, or null: "hotmai1",
  /// "hotmaiI" (a capital I), "h0tmail" and "hotrnail" are "hotmail". A label
  /// that already is one is returned as it is.
  static String? _providerOf(String label) {
    final lower = label.toLowerCase();
    if (_providers.contains(lower)) return lower;
    if (label.length < 3 || label.length > 16) return null;
    for (final skeleton in [
      _skeleton(label.replaceAll(RegExp(r'[I|1]'), 'l')),
      _skeleton(lower.replaceAll(RegExp(r'[|1]'), 'l')),
    ]) {
      if (_providers.contains(skeleton)) return skeleton;
    }
    return null;
  }

  static String _skeleton(String s) =>
      s.toLowerCase().replaceAll('0', 'o').replaceAll('rn', 'm');

  // ------------------------------------------------------------- segments

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

  /// "abcde07@hotmail.com:password" from a pasted combo list: the address,
  /// the password with its OCR junk taken off and the password as written.
  /// Only split when the user part is an address: "10:45" or "alice:x" are
  /// not credentials.
  static (String, String, String)? _combo(String segment) {
    final hit = _findEmails(segment).firstOrNull;
    if (hit == null || hit.start != 0) return null;
    final m = _comboTail.firstMatch(segment.substring(hit.end));
    if (m == null || _isLabel(m[1]!)) return null;
    final clean = _cleanToken(m[1]!);
    if (clean.isEmpty) return null;
    return (hit.address, clean, _stripPunct(m[1]!));
  }

  /// The value after a user label: the whole address if one starts there
  /// ("Email: abcde07 @ hotmail.com"), else the first word.
  static String _pickUser(String value) {
    final hit = _findEmails(value).firstOrNull;
    return hit != null && hit.start == 0 ? hit.address : value.split(' ').first;
  }

  /// The first word after a password label, unless it is an address or a
  /// piece of one: login forms put "Password" above both inputs. Two words
  /// that [_joinable] puts together are one password.
  static String? _pickPassword(
    String value,
    List<_EmailHit> hits,
    _Prepared prep,
  ) {
    final words = value.split(' ');
    final v = words.first;
    if (_findEmails(value).firstOrNull?.start == 0) return null;
    if (_atLike.hasMatch(v) && _isEmailPart(v, hits)) return null;
    if (words.length == 2) {
      final a = _cleanToken(words[0]);
      final b = _cleanToken(words[1]);
      if (_joinable(a, b)) {
        prep.joinedFrom['$a$b'] = [a, b];
        return '$a$b';
      }
    }
    final clean = _cleanToken(v);
    return clean.isEmpty ? null : clean;
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

  /// An address that OCR gave a symbol in its local part ("abcde0/@hotmail.com",
  /// a "/" for the "7"): better offered to be corrected than left out. Only
  /// when no other address is found and the line is that address alone.
  static String? _lenientAddress(
    List<String> lines,
    List<List<_EmailHit>> hitsByLine,
    List<bool> broken,
  ) {
    for (var i = 0; i < lines.length; i++) {
      if (!broken[i] || lines[i].contains(' ')) continue;
      final t = _cleanToken(lines[i]);
      if (_lenient.hasMatch(t)) return t;
    }
    return null;
  }

  static final RegExp _lenient = RegExp(
    r'''^[A-Za-z0-9._%+\-/\\&!#$*=?^`'{}~]{2,64}@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}$''',
  );

  /// The first URL or bare domain that is not just the domain of an address:
  /// a hotmail.com address says nothing about which site the account is for.
  static String? _findUrl(
    List<String> lines,
    List<List<_EmailHit>> hits,
    List<bool> broken,
  ) {
    for (var i = 0; i < lines.length; i++) {
      // The domain of an address OCR damaged is no more a website.
      if (broken[i]) continue;
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
    Set<String> alone = const {},
  }) => _rankPasswords(
    chips,
    exclude: exclude,
    emails: emails,
    alone: alone,
  ).firstOrNull;

  /// The tokens [_guessPassword] accepts, best first (earlier first on a tie).
  ///
  /// A token that is a whole line ([alone]) ranks above one of a sentence: a
  /// login screenshot has the password on a line of its own.
  static List<String> _rankPasswords(
    Iterable<String> tokens, {
    Set<String> exclude = const {},
    List<_EmailHit> emails = const [],
    Set<String> alone = const {},
  }) {
    final scored = <(int, int, String)>[];
    var index = 0;
    for (final t in tokens) {
      index++;
      if (t.contains(' ') || t.length < 6 || t.length > 64) continue;
      if (exclude.contains(t) ||
          email.hasMatch(t) ||
          t.contains('://') ||
          _isEmailPart(t, emails)) {
        continue;
      }
      var classes = _classes(t);
      // "Two-stepverification": hyphens and commas join words, they do not
      // make a password.
      if (classes == 3 && !_digit.hasMatch(t) && !t.contains(_notWordPunct)) {
        classes = 2;
      }
      if (classes < 2 || (classes == 2 && t.length < 10)) continue;
      // Pure dates / phone numbers are not passwords.
      if (RegExp(r'^[\d\-/.: +]+$').hasMatch(t)) continue;
      // Neither are field labels ("Website:") or a label with its value
      // glued on ("Password:xQmR42abCD5k").
      if (RegExp(r'^[A-Za-z][a-z]+[:：]$').hasMatch(t) ||
          _inlineLabel.matchAsPrefix(t) != null ||
          _plainWord.hasMatch(t)) {
        continue;
      }
      scored.add((
        classes * 10 + t.length.clamp(0, 20) + (alone.contains(t) ? 6 : 0),
        index,
        t,
      ));
    }
    scored.sort((a, b) => a.$1 != b.$1 ? b.$1 - a.$1 : a.$2 - b.$2);
    return [for (final s in scored) s.$3];
  }

  /// "Notifications", "settings", "SETTINGS": a word, never guessed.
  static final RegExp _plainWord = RegExp(r'^[A-Z]?[a-z]+$|^[A-Z]+$');
  static final RegExp _notWordPunct = RegExp(r"[^A-Za-z\-_.,']");
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
  /// letters only). A line cut out of one with a single space ([merged]) must
  /// look like a password: "Hello x@y.com" is a greeting. With [likely] every
  /// line must. An address OCR damaged ([broken]) is the anchor when there is
  /// no other.
  static String? _besideAddress(
    List<String> lines,
    List<List<_EmailHit>> hitsByLine,
    List<bool> merged,
    List<bool> broken, {
    Set<String> exclude = const {},
    bool likely = false,
  }) {
    var i = hitsByLine.indexWhere((h) => h.isNotEmpty);
    if (i >= 0) {
      // Not after "Email: ..." or inside a sentence; some punctuation is fine.
      final first = hitsByLine[i].first;
      if (first.start > 1 || lines[i].length - first.end > 2) return null;
    } else {
      i = broken.indexOf(true);
      if (i < 0) return null;
    }
    final hits = [for (final h in hitsByLine) ...h];
    for (final j in [i + 1, i - 1]) {
      if (j < 0 || j >= lines.length || hitsByLine[j].isNotEmpty || broken[j]) {
        continue;
      }
      final t = _cleanToken(lines[j]);
      if (t.length < 4 || t.length > 64 || lines[j].contains(RegExp(r'\s'))) {
        continue;
      }
      if (exclude.contains(t) ||
          _isLabel(t) ||
          RegExp(r'[:：]$').hasMatch(t) ||
          _uiWords.contains(t.toLowerCase()) ||
          _dateOrTime.hasMatch(t) ||
          t.contains('://') ||
          _url.hasMatch(t) ||
          _isEmailPart(t, hits) ||
          ((likely || merged[j]) && !_passwordish(t))) {
        continue;
      }
      return t;
    }
    return null;
  }

  // ----------------------------------------------------------- candidates

  /// [email] first, then its other readings, the address of a user label and
  /// every other address, nearest first.
  static List<String> _emailCandidates(
    String? email,
    String? username,
    List<_EmailHit> hits,
  ) {
    final out = <String>[];
    void add(String? s) {
      if (s != null &&
          s.isNotEmpty &&
          out.length < maxCandidates &&
          !out.contains(s)) {
        out.add(s);
      }
    }

    add(email);
    for (final a in hits.firstOrNull?.alternatives ?? const <String>[]) {
      add(a);
    }
    if (username != null && OcrCredentialParser.email.hasMatch(username)) {
      add(username);
    }
    for (final h in hits.skip(1)) {
      add(h.address);
      for (final a in h.alternatives) {
        add(a);
      }
    }
    return out;
  }

  /// [password] first, then how it reads with its OCR junk, the other tokens
  /// that look like a password, a word beside the address, two-token lines
  /// that could be one password and last the pieces of a joined one.
  static List<String> _passwordCandidates(
    String? password,
    _Prepared prep,
    Set<String> chips,
    List<List<_EmailHit>> hitsByLine, {
    required Set<String> exclude,
    required List<_EmailHit> emails,
    required Set<String> alone,
  }) {
    final out = <String>[];
    void add(String? s) {
      if (s != null &&
          s.isNotEmpty &&
          out.length < maxCandidates &&
          !out.contains(s) &&
          !exclude.contains(s)) {
        out.add(s);
      }
    }

    if (password != null) {
      out.add(password);
      for (final raw in prep.rawVariants[password] ?? const <String>{}) {
        add(raw);
      }
    }
    for (final t in _rankPasswords(
      chips,
      exclude: exclude,
      emails: emails,
      alone: alone,
    )) {
      add(t);
    }
    add(
      _besideAddress(
        prep.lines,
        hitsByLine,
        prep.merged,
        prep.broken,
        exclude: exclude,
      ),
    );
    for (var i = 0; i < prep.lines.length; i++) {
      if (hitsByLine[i].isNotEmpty) continue;
      add(_joinedLine(prep.lines[i], strict: true)?.$1);
    }
    for (final part in prep.joinedFrom[password] ?? const <String>[]) {
      add(part);
    }
    return out;
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
