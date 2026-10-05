import 'dart:math' as math;

import 'package:sodium/sodium_sumo.dart';
import 'package:zxcvbn/zxcvbn.dart';

class GeneratorOptions {
  const GeneratorOptions({
    this.length = 20,
    this.lower = true,
    this.upper = true,
    this.digits = true,
    this.symbols = true,
    this.excludeAmbiguous = true,
    this.passphrase = false,
    this.words = 5,
    this.separator = '-',
    this.capitalize = true,
    this.includeNumber = true,
  });

  final int length;
  final bool lower;
  final bool upper;
  final bool digits;
  final bool symbols;
  final bool excludeAmbiguous;
  final bool passphrase;
  final int words;
  final String separator;
  final bool capitalize;
  final bool includeNumber;

  GeneratorOptions copyWith({
    int? length,
    bool? lower,
    bool? upper,
    bool? digits,
    bool? symbols,
    bool? excludeAmbiguous,
    bool? passphrase,
    int? words,
    String? separator,
    bool? capitalize,
    bool? includeNumber,
  }) => GeneratorOptions(
    length: length ?? this.length,
    lower: lower ?? this.lower,
    upper: upper ?? this.upper,
    digits: digits ?? this.digits,
    symbols: symbols ?? this.symbols,
    excludeAmbiguous: excludeAmbiguous ?? this.excludeAmbiguous,
    passphrase: passphrase ?? this.passphrase,
    words: words ?? this.words,
    separator: separator ?? this.separator,
    capitalize: capitalize ?? this.capitalize,
    includeNumber: includeNumber ?? this.includeNumber,
  );
}

/// Password / passphrase generator.
///
/// Randomness comes only from libsodium's `randombytes_uniform`, which is a
/// CSPRNG with no modulo bias. `dart:math`'s Random is never used.
class PasswordGenerator {
  PasswordGenerator(this._sodium, this._wordlist);

  final SodiumSumo _sodium;
  final List<String> _wordlist;

  static const _lower = 'abcdefghijklmnopqrstuvwxyz';
  static const _upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const _digits = '0123456789';
  static const _symbols = r'!@#$%^&*()-_=+[]{};:,.?/~';
  static const ambiguous = '0OoIl1|`\'"';

  int _uniform(int n) => _sodium.randombytes.uniform(n);

  String generate(GeneratorOptions o) =>
      o.passphrase ? _passphrase(o) : _password(o);

  String _password(GeneratorOptions o) {
    String strip(String s) => o.excludeAmbiguous
        ? s.split('').where((c) => !ambiguous.contains(c)).join()
        : s;
    final sets = [
      if (o.lower) strip(_lower),
      if (o.upper) strip(_upper),
      if (o.digits) strip(_digits),
      if (o.symbols) strip(_symbols),
    ];
    if (sets.isEmpty) sets.add(strip(_lower));
    final length = o.length.clamp(math.max(8, sets.length), 128);
    final all = sets.join();
    // One character from each selected set, the rest from the union, then a
    // Fisher-Yates shuffle so the guaranteed characters are not positional.
    final chars = <String>[
      for (final s in sets) s[_uniform(s.length)],
      for (var i = sets.length; i < length; i++) all[_uniform(all.length)],
    ];
    for (var i = chars.length - 1; i > 0; i--) {
      final j = _uniform(i + 1);
      final tmp = chars[i];
      chars[i] = chars[j];
      chars[j] = tmp;
    }
    return chars.join();
  }

  String _passphrase(GeneratorOptions o) {
    final n = o.words.clamp(3, 12);
    final words = [
      for (var i = 0; i < n; i++) _wordlist[_uniform(_wordlist.length)],
    ];
    if (o.capitalize) {
      for (var i = 0; i < words.length; i++) {
        words[i] = words[i][0].toUpperCase() + words[i].substring(1);
      }
    }
    if (o.includeNumber) {
      final i = _uniform(words.length);
      words[i] = '${words[i]}${_uniform(10)}';
    }
    return words.join(o.separator);
  }

  /// Entropy in bits of what [generate] produces for [o] (approximate for
  /// the "at least one of each set" rule).
  double entropyBits(GeneratorOptions o) {
    if (o.passphrase) {
      final n = o.words.clamp(3, 12);
      return n * _log2(_wordlist.length.toDouble()) +
          (o.includeNumber ? _log2(10.0 * n) : 0);
    }
    var pool = 0;
    if (o.lower) pool += 26;
    if (o.upper) pool += 26;
    if (o.digits) pool += 10;
    if (o.symbols) pool += _symbols.length;
    return o.length * _log2(pool == 0 ? 26.0 : pool.toDouble());
  }

  static double _log2(double x) => math.log(x) / math.ln2;
}

/// Strength assessment with zxcvbn.
class StrengthResult {
  const StrengthResult(this.score, this.crackTimeDisplay, this.warning);

  /// 0 (very weak) .. 4 (very strong).
  final int score;
  final String crackTimeDisplay;
  final String? warning;
}

class StrengthMeter {
  final Zxcvbn _z = Zxcvbn();

  StrengthResult evaluate(
    String password, {
    List<String> userInputs = const [],
  }) {
    if (password.isEmpty) return const StrengthResult(0, '', null);
    final r = _z.evaluate(password, userInputs: userInputs);
    return StrengthResult(
      (r.score ?? 0).toInt(),
      r.crack_times_display?['offline_slow_hashing_1e4_per_second']
              ?.toString() ??
          '',
      r.feedback.warning,
    );
  }
}
