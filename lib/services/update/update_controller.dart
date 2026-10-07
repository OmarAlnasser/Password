import 'dart:async';

import 'package:flutter/foundation.dart';

import '../settings.dart';
import 'cancel_token.dart';
import 'update_failure.dart';
import 'update_installer.dart';
import 'update_manifest.dart';
import 'update_service.dart';

/// Where the update flow is. The UI shows one thing per state.
enum UpdateStatus {
  /// Nothing to show.
  idle,

  /// Asking GitHub for the latest signed manifest.
  checking,

  /// A newer signed version exists ([UpdateController.manifest]).
  available,

  /// Downloading ([UpdateController.progress]).
  downloading,

  /// The download finished; checking its size and SHA-256.
  verifying,

  /// Verified and waiting for the user to tap Install.
  readyToInstall,

  /// Handing the package to the platform installer.
  installing,

  /// A manual check found nothing newer.
  upToDate,

  /// Something failed ([UpdateController.failure]).
  error,
}

/// Drives the update flow and holds its state for the UI.
///
/// Wiring (done where the other services are created, `AppServices`; not for
/// the autofill entry point):
///
/// ```dart
/// final updates = UpdateController(
///   service: UpdateService.create(
///     sodium: sodium,
///     // A folder of its own inside the app's data directory, next to (not
///     // inside) the vault folder: `<support>/updates`.
///     workRoot: Directory(p.join(supportDir.path, 'updates')),
///   ),
///   installer: Platform.isAndroid
///       ? AndroidUpdateInstaller()
///       : WindowsUpdateInstaller(),
///   settings: settings,
///   // Lock the vault and wipe its keys before the app exits or hands over to
///   // the system installer.
///   prepareExit: () => session.lock(),
/// );
/// ```
///
/// The UI then
/// * calls `unawaited(updates.checkAutomatically())` once the app is up (and
///   may call it again when the app returns to the foreground: it checks at
///   most once per 24 hours and only when `settings.checkUpdates` is on),
/// * rebuilds from [ListenableBuilder] on [status] (`updates.enabled` is false
///   in development builds, where nothing should be shown at all),
/// * offers [checkNow] (manual check), [startDownload], [installUpdate],
///   [skipThisVersion], [cancel] and [dismiss] as buttons, and the
///   `settings.checkUpdates` switch.
///
/// Automatic checks are silent: they only ever produce [UpdateStatus.available]
/// (and not for a build the user skipped) or nothing. Manual checks report
/// everything, including errors.
class UpdateController extends ChangeNotifier {
  UpdateController({
    required this._service,
    required this._installer,
    required this._settings,
    required this._prepareExit,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final UpdateService _service;
  final UpdateInstaller _installer;
  final AppSettings _settings;
  final Future<void> Function() _prepareExit;
  final DateTime Function() _clock;

  /// Minimum pause after a check that failed for a reason that may be gone
  /// soon (offline, server error), so a flaky connection is not retried on
  /// every foreground event. Not persisted.
  static const Duration retryAfterTransientFailure = Duration(minutes: 30);

  UpdateStatus _status = UpdateStatus.idle;
  UpdateAvailable? _update;
  UpdateFailure? _failure;
  InstallOutcome? _installOutcome;
  double? _progress;
  DownloadedUpdate? _downloaded;
  StagedUpdate? _staged;
  CancelToken? _token;
  int _lastAttemptMs = 0;
  bool _reofferTried = false;
  Future<void>? _sweep;
  bool _disposed = false;

  // --- State for the UI -----------------------------------------------------

  UpdateStatus get status => _status;

  /// False in development builds and on platforms without updates: show
  /// nothing.
  bool get enabled => _service.enabled;

  /// The version on offer (states available to installing).
  UpdateManifest? get manifest => _update?.manifest;

  /// The package for this platform.
  UpdateAsset? get asset => _update?.asset;

  /// Download progress 0..1 while [UpdateStatus.downloading].
  double? get progress => _progress;

  /// Why the last step failed, in [UpdateStatus.error]. Only an enum.
  UpdateFailure? get failure => _failure;

  /// What the platform installer reported last. After
  /// [InstallOutcome.started] on Android the system installer is open; after
  /// [InstallOutcome.permissionRequired] the user must allow installing from
  /// this app and tap Install again.
  InstallOutcome? get installOutcome => _installOutcome;

  /// True while something is running that blocks other actions.
  bool get busy =>
      _status == UpdateStatus.checking ||
      _status == UpdateStatus.downloading ||
      _status == UpdateStatus.verifying ||
      _status == UpdateStatus.installing;

  // --- Throttle -------------------------------------------------------------

  /// True when an automatic check is due: never checked, 24 hours (or
  /// [interval]) have passed, or the clock went backwards.
  static bool isCheckDue({
    required int lastCheckMs,
    required int nowMs,
    Duration interval = const Duration(hours: 24),
  }) =>
      lastCheckMs <= 0 ||
      nowMs < lastCheckMs ||
      nowMs - lastCheckMs >= interval.inMilliseconds;

  /// Whether [checkAutomatically] would check now.
  bool get autoCheckDue {
    final now = _clock().millisecondsSinceEpoch;
    final transientOk =
        _lastAttemptMs <= 0 ||
        now < _lastAttemptMs ||
        now - _lastAttemptMs >= retryAfterTransientFailure.inMilliseconds;
    return transientOk &&
        ((!_reofferTried && _offerWasLost) ||
            isCheckDue(
              lastCheckMs: _settings.lastUpdateCheck,
              nowMs: now,
              interval: _service.config.checkInterval,
            ));
  }

  /// A newer build was found on an earlier run, and it was neither installed
  /// nor skipped. The offer itself lives in memory only, so a restart (the
  /// user tapped Later, went to Android's "install unknown apps" page, a
  /// Windows swap was rolled back) would hide it until the 24 hour limit ran
  /// out. The first automatic check of every run therefore ignores that limit
  /// in this one case; [_reofferTried] keeps it to once per run.
  bool get _offerWasLost {
    final seen = _settings.highestSeenBuild;
    return seen > _service.version.build && seen > _settings.skippedBuild;
  }

  // --- Actions --------------------------------------------------------------

  /// The check the app starts by itself; call it once at start-up (and again
  /// when the app returns to the foreground if you like). Does nothing when
  /// updates are off in this build, when the user turned them off, when one
  /// ran in the last 24 hours (except for the first check of a run when an
  /// earlier run had found a newer build the user has not installed or
  /// skipped: that offer comes back at once), or while an update is on offer,
  /// a message is showing or something is in progress. Never throws.
  Future<void> checkAutomatically() async {
    if (!enabled) return;
    // Also removes the files of the update that was just installed, whether or
    // not a check is due.
    await _ensureSwept();
    if (!_settings.checkUpdates || busy || !autoCheckDue) return;
    if (_status != UpdateStatus.idle) return;
    await _check(manual: false);
  }

  /// The user asked: check now, whatever the clock and the "skip" say, and
  /// show the result (also "up to date" and errors). Never throws.
  Future<void> checkNow() async {
    if (!enabled || busy) return;
    if (_status == UpdateStatus.readyToInstall) return;
    await _check(manual: true);
  }

  /// Downloads and verifies the offered version. Never throws.
  Future<void> startDownload() async {
    final update = _update;
    if (_status != UpdateStatus.available || update == null) return;
    final token = _token = CancelToken();
    _failure = null;
    _progress = 0;
    _set(UpdateStatus.downloading);
    var lastPermille = -1;
    try {
      final downloaded = await _service.download(
        update,
        cancel: token,
        onProgress: (received, total) {
          final permille = total <= 0 ? 0 : received * 1000 ~/ total;
          if (permille == lastPermille) return;
          lastPermille = permille;
          _progress = permille / 1000;
          _notify();
        },
      );
      if (_disposed) {
        await _service.discard(downloaded.directory);
        return;
      }
      _progress = null;
      _set(UpdateStatus.verifying);
      await _service.verify(downloaded);
      _downloaded = downloaded;
      _installOutcome = null;
      _set(UpdateStatus.readyToInstall);
    } on UpdateException catch (e) {
      _progress = null;
      if (e.reason == UpdateFailure.cancelled) {
        _set(UpdateStatus.available);
      } else {
        _fail(e.reason);
      }
    } on Object {
      _progress = null;
      _fail(UpdateFailure.internal);
    } finally {
      if (identical(_token, token)) _token = null;
    }
  }

  /// Installs the verified package. The vault is locked first (through the
  /// installer, which calls `prepareExit` as late as it can). On Windows the
  /// process exits and this never returns to the UI. Never throws.
  Future<void> installUpdate() async {
    final downloaded = _downloaded;
    if (_status != UpdateStatus.readyToInstall || downloaded == null) return;
    _installOutcome = null;
    _set(UpdateStatus.installing);
    try {
      await _discardStaged();
      // Verified again, copied to a fresh private directory, verified again.
      final staged = await _service.stageForInstall(downloaded);
      _staged = staged;
      var prepared = false;
      InstallOutcome outcome;
      try {
        outcome = await _installer.install(
          staged.file,
          prepareExit: () async {
            if (prepared) return;
            await _prepareExit();
            prepared = true;
          },
        );
      } on Object {
        outcome = InstallOutcome.failed;
      }
      _installOutcome = outcome;
      // After `started` the system installer may still be reading the file.
      if (outcome != InstallOutcome.started) await _discardStaged();
      _set(UpdateStatus.readyToInstall);
    } on UpdateException catch (e) {
      // The package on disk no longer matches the signed manifest.
      await _discardAll();
      _fail(e.reason);
    } on Object {
      await _discardAll();
      _fail(UpdateFailure.internal);
    }
  }

  /// "Skip this version": automatic checks stay quiet about this build; a newer
  /// one is offered again. Manual checks still show it.
  Future<void> skipThisVersion() async {
    final build = _update?.latestBuild;
    if (build == null || busy) return;
    await _persist((s) => s.skippedBuild = build);
    await _discardAll();
    _update = null;
    _failure = null;
    _set(UpdateStatus.idle);
  }

  /// Stops a check or a download in progress. A cancelled download returns to
  /// [UpdateStatus.available]; its files are deleted.
  void cancel() => _token?.cancel();

  /// Closes the "up to date" or error message. After an error with a known
  /// update the offer comes back; otherwise the controller goes idle. There is
  /// nothing to close in [UpdateStatus.available] (a UI that wants a "Later"
  /// button hides its own banner; [skipThisVersion] is the persistent "no").
  void dismiss() {
    if (busy) return;
    _failure = null;
    _installOutcome = null;
    _set(
      _update != null && _downloaded == null
          ? UpdateStatus.available
          : _downloaded != null
          ? UpdateStatus.readyToInstall
          : UpdateStatus.idle,
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _token?.cancel();
    super.dispose();
  }

  // --- Internals ------------------------------------------------------------

  /// Deletes what an earlier run left in the updater's folder (a package that
  /// was installed, an abandoned download). Once per controller, before
  /// anything is downloaded.
  Future<void> _ensureSwept() => _sweep ??= _service.cleanup();

  Future<void> _check({required bool manual}) async {
    await _ensureSwept();
    final token = _token = CancelToken();
    _failure = null;
    _installOutcome = null;
    if (_status != UpdateStatus.available || manual) _update = null;
    _set(UpdateStatus.checking);
    _lastAttemptMs = _clock().millisecondsSinceEpoch;
    try {
      final result = await _service.check(
        highestSeenBuild: _settings.highestSeenBuild,
        cancel: token,
      );
      if (_disposed) return;
      switch (result) {
        case UpdateDisabled():
          _set(UpdateStatus.idle);
        case UpdateUpToDate(:final latestBuild):
          await _persist((s) => _recordCheck(s, latestBuild));
          _set(manual ? UpdateStatus.upToDate : UpdateStatus.idle);
        case UpdateAvailable available:
          await _persist((s) => _recordCheck(s, available.latestBuild));
          if (!manual && available.latestBuild <= _settings.skippedBuild) {
            _set(UpdateStatus.idle);
          } else {
            _update = available;
            _set(UpdateStatus.available);
          }
        case UpdateFailed(:final reason):
          if (reason == UpdateFailure.cancelled) {
            _set(UpdateStatus.idle);
            return;
          }
          if (!_isTransient(reason)) {
            _reofferTried = true;
            await _persist((s) => s.lastUpdateCheck = _nowMs);
          }
          if (manual) {
            _fail(reason);
          } else {
            _failure = reason;
            _set(UpdateStatus.idle);
          }
      }
    } finally {
      if (identical(_token, token)) _token = null;
    }
  }

  int get _nowMs => _clock().millisecondsSinceEpoch;

  void _recordCheck(AppSettings s, int build) {
    // A check that reached a verdict: the lost offer, if there was one, has
    // been dealt with for this run. (A transient failure has not; it is
    // retried after the pause.)
    _reofferTried = true;
    s.lastUpdateCheck = _nowMs;
    if (build > s.highestSeenBuild) s.highestSeenBuild = build;
  }

  /// Failures that say nothing about the release itself (no connection, a
  /// server hiccup): the check is not counted, so it is tried again soon.
  static bool _isTransient(UpdateFailure f) =>
      f == UpdateFailure.network ||
      f == UpdateFailure.timeout ||
      f == UpdateFailure.badStatus;

  Future<void> _persist(void Function(AppSettings s) change) async {
    try {
      await _settings.update(change);
    } on Object {
      // The in-memory values are already changed; the file is retried by the
      // next settings change.
    }
  }

  Future<void> _discardStaged() async {
    final staged = _staged;
    _staged = null;
    if (staged != null) await _service.discard(staged.directory);
  }

  Future<void> _discardAll() async {
    await _discardStaged();
    final d = _downloaded;
    _downloaded = null;
    if (d != null) await _service.discard(d.directory);
  }

  void _fail(UpdateFailure reason) {
    _failure = reason;
    _set(UpdateStatus.error);
  }

  void _set(UpdateStatus status) {
    _status = status;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
