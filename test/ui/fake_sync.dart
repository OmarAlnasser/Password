import 'package:flutter/foundation.dart';
import 'package:hisn/services/sync/sync_service.dart';

/// Sync that is on, and may be holding a deletion another device made
/// ([pending] entries) until the user applies or keeps it, like
/// `SyncService` after a refused pull.
class FakeSync extends ChangeNotifier implements SyncService {
  FakeSync({this.pending});

  int? pending;
  final calls = <String>[];

  @override
  bool get enabled => true;

  @override
  SyncStatus get status => pending == null ? SyncStatus.idle : SyncStatus.error;

  @override
  DateTime? get lastSync => null;

  @override
  int? get pendingMassDeletion => pending;

  @override
  Future<void> syncNow() async {
    calls.add('sync');
    final n = pending;
    if (n != null) throw MassDeletionException(n);
  }

  @override
  Future<void> applyMassDeletion() async {
    calls.add('apply');
    pending = null;
    notifyListeners();
  }

  @override
  Future<void> keepMassDeletion() async {
    calls.add('keep');
    pending = null;
    notifyListeners();
  }

  @override
  Future<void> disable() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
