import 'dart:io';

/// What happened when a verified package was handed to the platform installer.
enum InstallOutcome {
  /// The hand-over worked. On Android the system package installer is on
  /// screen and the user still has to tap Install; on Windows the swap script
  /// is running and the process is about to exit (so this is rarely seen).
  started,

  /// The OS first needs the user's consent for this app to install packages
  /// (Android "install unknown apps"). The settings page was opened; nothing
  /// was installed. The update stays staged so the user can try again.
  permissionRequired,

  /// The user dismissed the system installer.
  cancelled,

  /// Installing is not possible on this platform or build.
  unsupported,

  /// The hand-over failed (could not copy, could not start the helper, ...).
  failed,
}

/// Installs an update package that [UpdateService] has already downloaded,
/// checked against the signed manifest and staged in a private directory.
///
/// Platform implementations live in `android_installer.dart` and
/// `windows_installer.dart`; tests use [FakeUpdateInstaller].
///
/// Contract for implementations:
///
/// * The file is trusted at the moment it is passed in (size and SHA-256
///   were verified, and it sits in a freshly created private directory). An
///   implementation that copies it somewhere else must not re-download
///   anything and must not parse its contents before the copy is safe.
/// * [prepareExit] locks the vault and wipes its keys. Await it successfully
///   BEFORE anything that can end the process or hand control to another
///   program (spawning the swap script and exiting, starting the system
///   installer), and as late as possible, so that a refused permission does not
///   lock the vault for nothing. If it throws, do not continue: return
///   [InstallOutcome.failed].
/// * Never log the file path, the package name or any error message; those can
///   carry user names. Return an [InstallOutcome] instead of throwing; the
///   controller treats an exception as [InstallOutcome.failed].
/// * Do not delete [package]. The controller deletes its directory when the
///   hand-over did not start, and every start of the app (see
///   `UpdateController.checkAutomatically`) deletes the whole updater folder.
///   A helper that outlives the process (the Windows swap script) must
///   therefore be finished with the file before it starts the new app, and
///   must not rely on the file afterwards. After [InstallOutcome.started] on
///   Android the system installer may keep reading the file for a while, which
///   is why it is not deleted at that point.
abstract interface class UpdateInstaller {
  /// [package] is the APK (Android) or the zip (Windows).
  Future<InstallOutcome> install(
    File package, {
    required Future<void> Function() prepareExit,
  });
}

/// Records calls instead of installing anything. For tests (and for widget
/// tests of the update screens).
class FakeUpdateInstaller implements UpdateInstaller {
  FakeUpdateInstaller({this.outcome = InstallOutcome.started, this.error});

  /// What [install] returns.
  InstallOutcome outcome;

  /// When set, [install] throws it (after calling `prepareExit` if
  /// [callPrepareExit] is true).
  Object? error;

  /// Call `prepareExit` like a real installer would.
  bool callPrepareExit = true;

  /// Packages that were handed over, in order.
  final List<File> installed = [];

  /// Number of times `prepareExit` was awaited.
  int prepareExitCalls = 0;

  /// The bytes of the last package at the time [install] was called.
  List<int>? lastBytes;

  @override
  Future<InstallOutcome> install(
    File package, {
    required Future<void> Function() prepareExit,
  }) async {
    if (callPrepareExit) {
      await prepareExit();
      prepareExitCalls++;
    }
    installed.add(package);
    lastBytes = await package.readAsBytes();
    final e = error;
    if (e != null) throw e;
    return outcome;
  }
}
