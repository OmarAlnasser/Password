import 'dart:async';

/// Lets the caller stop a check or a download that is under way.
class CancelToken {
  final Completer<void> _completer = Completer<void>();

  /// True once [cancel] was called.
  bool get isCancelled => _completer.isCompleted;

  /// Completes (never with an error) when [cancel] is called.
  Future<void> get whenCancelled => _completer.future;

  /// Idempotent.
  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }
}
