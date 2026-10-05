import 'dart:async';

import 'platform_bridge.dart';

/// Copies secrets and clears them again after a timeout.
class ClipboardService {
  ClipboardService(this._bridge, {required Duration Function() clearAfter})
    : _clearAfter = clearAfter; // ignore: prefer_initializing_formals

  final PlatformBridge _bridge;
  final Duration Function() _clearAfter;

  Timer? _timer;
  String? _lastCopied;

  /// Copies [text]; it is cleared after the configured delay (default 30s)
  /// if the clipboard still holds it.
  Future<void> copySecret(String text) async {
    final delay = _clearAfter();
    await _bridge.copySensitive(text, delay);
    _timer?.cancel();
    _lastCopied = text;
    _timer = Timer(delay, clearNow);
  }

  /// Called on timeout and also when the vault locks.
  Future<void> clearNow() async {
    _timer?.cancel();
    _timer = null;
    final last = _lastCopied;
    _lastCopied = null;
    if (last != null) await _bridge.clearClipboardIfMatches(last);
  }

  bool get hasPendingClear => _timer != null;
}
