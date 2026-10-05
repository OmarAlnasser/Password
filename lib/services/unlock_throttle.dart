import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// Thrown when an unlock is attempted before the back-off delay has passed.
class UnlockThrottledException implements Exception {
  const UnlockThrottledException(this.remaining);
  final Duration remaining;
  @override
  String toString() => 'UnlockThrottledException(${remaining.inSeconds}s)';
}

/// Exponential back-off for failed unlock attempts, persisted so that killing
/// the app does not reset it.
///
/// Attempts 1-3 are free, then 1s, 2s, 4s ... capped at 5 minutes. This only
/// slows down someone typing into the UI; an attacker with a copy of the app
/// data attacks Argon2id directly, which is the real protection.
class UnlockThrottle {
  UnlockThrottle(this._file, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final File _file;
  final DateTime Function() _clock;

  int _failures = 0;
  DateTime? _lastFailure;

  static const int freeAttempts = 3;
  static const Duration maxDelay = Duration(minutes: 5);

  int get failures => _failures;

  Future<void> load() async {
    try {
      final j = jsonDecode(await _file.readAsString()) as Map<String, Object?>;
      _failures = (j['n'] as int?) ?? 0;
      final t = j['t'] as int?;
      _lastFailure = t == null ? null : DateTime.fromMillisecondsSinceEpoch(t);
    } on Object {
      // Missing or corrupt file: start fresh. (Deleting the file resets the
      // counter; see docs/SECURITY.md - the UI throttle is not a boundary.)
      _failures = 0;
      _lastFailure = null;
    }
  }

  static Duration delayAfter(int failures) {
    if (failures < freeAttempts) return Duration.zero;
    final seconds = math.min(
      maxDelay.inSeconds,
      1 << math.min(failures - freeAttempts, 20),
    );
    return Duration(seconds: seconds);
  }

  Duration get remaining {
    final last = _lastFailure;
    if (last == null) return Duration.zero;
    final until = last.add(delayAfter(_failures));
    final now = _clock();
    // A clock moved backwards must not unlock early: treat as full delay.
    if (now.isBefore(last)) return delayAfter(_failures);
    return now.isBefore(until) ? until.difference(now) : Duration.zero;
  }

  void check() {
    final r = remaining;
    if (r > Duration.zero) throw UnlockThrottledException(r);
  }

  Future<void> recordFailure() async {
    _failures++;
    _lastFailure = _clock();
    await _save();
  }

  Future<void> recordSuccess() async {
    _failures = 0;
    _lastFailure = null;
    await _save();
  }

  Future<void> _save() async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
      jsonEncode({'n': _failures, 't': _lastFailure?.millisecondsSinceEpoch}),
      flush: true,
    );
  }
}
