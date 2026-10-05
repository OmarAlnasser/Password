/// Extracts likely credentials from OCR'd text. Pure Dart, no I/O: the image
/// never leaves the device and the text never leaves this function's caller.
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

class OcrCredentialParser {
  static final RegExp email = RegExp(
    r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}',
  );
  static final RegExp _url = RegExp(
    r'''(https?://[^\s'"<>]+)|\b((?:[a-z0-9-]+\.)+(?:com|net|org|io|app|dev|co|me|edu|gov|sa|ae|eg|uk|de|fr|info|biz)(?:/[^\s]*)?)\b''',
    caseSensitive: false,
  );

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
    'email',
    'e-mail',
    'اسم المستخدم',
    'المستخدم',
    'البريد الإلكتروني',
    'البريد',
    'الحساب',
  ];

  static const int maxChips = 200;

  OcrResult parse(List<String> rawLines) {
    final lines = [
      for (final l in rawLines)
        if (l.trim().isNotEmpty) l.trim(),
    ];
    final chips = <String>{};
    for (final line in lines) {
      chips.add(line);
      for (final token in line.split(RegExp(r'\s+'))) {
        final t = _stripPunct(token);
        if (t.isNotEmpty) chips.add(t);
      }
      if (chips.length >= maxChips) break;
    }

    String? labelled(List<String> labels) {
      for (var i = 0; i < lines.length; i++) {
        for (final label in labels) {
          // The label must start the line ("Password: x", "Password").
          final m = RegExp(
            '^${RegExp.escape(label)}(?=\$|[\\s:：=\\-–])\\s*[:：=\\-–]?\\s*(.*)\$',
            caseSensitive: false,
          ).firstMatch(lines[i]);
          if (m == null) continue;
          final rest = m.group(1)!.trim();
          // "Password: value" on the same line.
          if (rest.isNotEmpty && !_isLabel(rest)) return rest.split(' ').first;
          // "Password" then the value on the next line.
          if (rest.isEmpty && i + 1 < lines.length && !_isLabel(lines[i + 1])) {
            return lines[i + 1].split(' ').first;
          }
        }
      }
      return null;
    }

    final emailMatch = email.firstMatch(lines.join('\n'))?.group(0);
    final urlMatch = _url.firstMatch(lines.join('\n'));
    final url = urlMatch == null
        ? null
        : (urlMatch.group(1) ?? urlMatch.group(2));

    var password = labelled(_passwordLabels);
    final labelledUser = labelled(_userLabels);
    final username = labelledUser ?? emailMatch;
    password ??= _guessPassword(chips, exclude: {?emailMatch, ?username, ?url});

    return OcrResult(
      chips: chips.toList(),
      email: emailMatch,
      username: username,
      password: password,
      url: url,
      title: _title(url, lines),
    );
  }

  static bool _isLabel(String s) {
    final lower = s.toLowerCase().replaceAll(RegExp(r'[:：]'), '').trim();
    return _passwordLabels.contains(lower) || _userLabels.contains(lower);
  }

  static String _stripPunct(String t) =>
      t.replaceAll(RegExp(r'^[,;:"“”()\[\]]+|[,;"“”()\[\]]+$'), '');

  /// Scores tokens that look like passwords: no spaces, 6-64 chars, several
  /// character classes, not an email/URL/plain word or number.
  static String? _guessPassword(
    Set<String> chips, {
    Set<String> exclude = const {},
  }) {
    String? best;
    var bestScore = 0;
    for (final t in chips) {
      if (t.contains(' ') || t.length < 6 || t.length > 64) continue;
      if (exclude.contains(t) || email.hasMatch(t) || t.contains('://')) {
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
      final score = classes * 10 + t.length.clamp(0, 20);
      if (score > bestScore) {
        bestScore = score;
        best = t;
      }
    }
    return best;
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
