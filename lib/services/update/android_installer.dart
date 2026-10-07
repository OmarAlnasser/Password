import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'update_installer.dart';

/// Why [AndroidUpdateInstaller.install] did not start the system installer.
/// Only these values are ever kept: never the path, the package name or the
/// native error text.
enum AndroidInstallError {
  /// The staged package could not be copied into the installer's folder
  /// (missing or unreadable source, no space, too large).
  copyFailed,

  /// The vault could not be locked, so nothing was started.
  prepareExitFailed,

  /// The file is not a valid, correctly signed APK.
  apkUnreadable,

  /// The APK is for a different app.
  wrongPackage,

  /// The APK is not a newer build than the installed app.
  notNewer,

  /// The APK is signed with a different key than the installed app, so
  /// Android would refuse it as an update. Happens once for copies installed
  /// from a build that was not signed with the release key.
  signatureMismatch,

  /// The native side refused the file's location (outside its updates folder).
  pathNotAllowed,

  /// The device has no screen that installs packages.
  noInstaller,

  /// Anything else that went wrong on the native side.
  installFailed,
}

/// Installs an update on Android by handing a copy of the APK to the system
/// package installer. The user taps Install; Android itself then checks that
/// the update is signed with the same key as the installed app.
///
/// Steps (the order is part of the contract with `UpdateInstaller`):
///
/// 1. The user's consent to "install unknown apps" for this app. If it is
///    missing the settings page is opened, and nothing else happens (the vault
///    stays unlocked, nothing is copied).
/// 2. The package is copied into the private `updates` folder that the native
///    side prepares (`<cache>/updates/`, emptied first). The copy, not the
///    controller's staging file, is what the system installer may read,
///    through a FileProvider grant for that one file.
/// 3. The native side checks the copy without starting anything: it lies in
///    that folder, parses as an APK of this app that is newer than the
///    installed one and is signed with the installed app's key. A failure
///    here leaves the vault unlocked.
/// 4. `prepareExit` locks the vault.
/// 5. The native side checks the copy again, right before it starts the
///    installer, and starts it.
///
/// The copy is deleted when the hand-over fails. After it has worked, the
/// installer needs the file for a few more seconds; the native side deletes it
/// at the next app start.
///
/// Nothing is logged and nothing throws: every failure is an [InstallOutcome],
/// and [lastError] says which.
class AndroidUpdateInstaller implements UpdateInstaller {
  AndroidUpdateInstaller({
    this._channel = const MethodChannel(channelName),
    this.maxBytes = defaultMaxBytes,
    Random? random,
  }) : _random = random ?? Random.secure();

  /// The native runner's channel (shared with `PlatformBridge`).
  static const String channelName = 'app.vaultsnap/platform';

  /// Same cap as the download.
  static const int defaultMaxBytes = 400 * 1024 * 1024;

  /// Largest package that is copied.
  final int maxBytes;

  final MethodChannel _channel;
  final Random _random;

  AndroidInstallError? _lastError;

  /// Why the last [install] returned [InstallOutcome.failed]; null after a
  /// call that did not fail.
  AndroidInstallError? get lastError => _lastError;

  @override
  Future<InstallOutcome> install(
    File package, {
    required Future<void> Function() prepareExit,
  }) async {
    _lastError = null;
    File? copy;
    var started = false;
    try {
      if (!await _canInstallPackages()) {
        await _openInstallSettings();
        return InstallOutcome.permissionRequired;
      }

      final dir = await _prepareUpdatesDir();
      copy = await _copyInto(dir, package);

      await _checkApk(copy);

      try {
        await prepareExit();
      } on Object {
        return _fail(AndroidInstallError.prepareExitFailed);
      }

      await _startInstaller(copy);
      started = true;
      return InstallOutcome.started;
    } on _Failed catch (e) {
      return _fail(e.error);
    } on MissingPluginException {
      return InstallOutcome.unsupported;
    } on PlatformException catch (e) {
      final outcome = _outcomeForNativeCode(e.code);
      if (outcome == InstallOutcome.permissionRequired) {
        // Consent was taken away between the first check and the hand-over.
        await _openInstallSettings();
      }
      return outcome;
    } on Object {
      return _fail(AndroidInstallError.installFailed);
    } finally {
      if (!started) await _deleteQuietly(copy);
    }
  }

  // --- native calls --------------------------------------------------------

  Future<bool> _canInstallPackages() async {
    final allowed = await _channel.invokeMethod<bool>('canInstallPackages');
    return allowed ?? false;
  }

  /// Best effort: the settings page may not exist on this device.
  Future<void> _openInstallSettings() async {
    try {
      await _channel.invokeMethod<bool>('openInstallSettings');
    } on Object {
      // The caller reports permissionRequired either way.
    }
  }

  Future<Directory> _prepareUpdatesDir() async {
    final path = await _channel.invokeMethod<String>('prepareUpdatesDir');
    if (path == null || path.isEmpty) {
      throw const _Failed(AndroidInstallError.copyFailed);
    }
    return Directory(path);
  }

  /// Native checks only (`verifyOnly`): nothing is started.
  Future<void> _checkApk(File apk) async {
    final answer = await _channel.invokeMethod<String>('installApk', {
      'path': apk.path,
      'verifyOnly': true,
    });
    if (answer != 'verified') {
      throw const _Failed(AndroidInstallError.installFailed);
    }
  }

  Future<void> _startInstaller(File apk) async {
    final answer = await _channel.invokeMethod<String>('installApk', {
      'path': apk.path,
    });
    if (answer != 'installer_started') {
      throw const _Failed(AndroidInstallError.installFailed);
    }
  }

  /// Maps a native error code. Unknown codes are a plain failure.
  InstallOutcome _outcomeForNativeCode(String code) {
    switch (code) {
      case 'permission_denied':
        return InstallOutcome.permissionRequired;
      case 'unsupported':
        return InstallOutcome.unsupported;
      case 'apk_unreadable':
        return _fail(AndroidInstallError.apkUnreadable);
      case 'wrong_package':
        return _fail(AndroidInstallError.wrongPackage);
      case 'not_newer':
        return _fail(AndroidInstallError.notNewer);
      case 'signature_mismatch':
        return _fail(AndroidInstallError.signatureMismatch);
      case 'path_not_allowed':
        return _fail(AndroidInstallError.pathNotAllowed);
      case 'no_installer':
        return _fail(AndroidInstallError.noInstaller);
      default:
        // install_failed, busy, bad_arguments, updates_dir_unavailable, ...
        return _fail(AndroidInstallError.installFailed);
    }
  }

  InstallOutcome _fail(AndroidInstallError error) {
    _lastError = error;
    return InstallOutcome.failed;
  }

  // --- copy ----------------------------------------------------------------

  /// Copies [source] to a new, randomly named file in [dir], streaming and
  /// counting so that a package larger than [maxBytes] stops the copy. The
  /// source is only read. A partial copy is deleted before the error leaves.
  Future<File> _copyInto(Directory dir, File source) async {
    final target = File(p.join(dir.path, '${_randomName()}.apk'));
    RandomAccessFile? input;
    RandomAccessFile? output;
    try {
      input = await source.open();
      output = await target.open(mode: FileMode.writeOnly);
      final buffer = Uint8List(256 * 1024);
      var total = 0;
      while (true) {
        final n = await input.readInto(buffer);
        if (n == 0) break;
        total += n;
        if (total > maxBytes) {
          throw const _Failed(AndroidInstallError.copyFailed);
        }
        await output.writeFrom(buffer, 0, n);
      }
      if (total == 0) throw const _Failed(AndroidInstallError.copyFailed);
      await output.flush();
      await output.close();
      output = null;
      if (await target.length() != total) {
        throw const _Failed(AndroidInstallError.copyFailed);
      }
      return target;
    } on _Failed {
      await _closeQuietly(output);
      await _deleteQuietly(target);
      rethrow;
    } on Object {
      await _closeQuietly(output);
      await _deleteQuietly(target);
      throw const _Failed(AndroidInstallError.copyFailed);
    } finally {
      await _closeQuietly(input);
    }
  }

  String _randomName() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'update-$hex';
  }

  Future<void> _closeQuietly(RandomAccessFile? file) async {
    try {
      await file?.close();
    } on Object {
      // Already closed or broken; nothing more to do.
    }
  }

  Future<void> _deleteQuietly(File? file) async {
    try {
      if (file != null && await file.exists()) await file.delete();
    } on Object {
      // The native side deletes stale copies at the next start.
    }
  }
}

/// Internal: a failure with the reason to keep.
class _Failed implements Exception {
  const _Failed(this.error);

  final AndroidInstallError error;
}
