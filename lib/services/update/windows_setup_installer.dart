import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'update_installer.dart';
import 'windows_installer.dart';

/// Installs an update on Windows by running the verified setup program
/// (`windows-x64-setup.exe`, built with Inno Setup from
/// `installer/windows/setup.iss`) silently.
///
/// The setup is a per-user installer: it runs as the user, never asks for
/// administrator rights, closes the app if it still runs, replaces the files in
/// the install folder (and puts the old ones back if anything fails), then
/// starts the app again. Steps, in this order (the order is part of the
/// contract with `UpdateInstaller`):
///
/// 1. The file is checked: an `.exe` name, a plain file of a sane size that
///    starts with `MZ`. Otherwise [InstallOutcome.failed] with [lastError]
///    `badPackage` and nothing started.
/// 2. The result file and the log of an earlier run are deleted (a file that
///    stays is [WindowsInstallError.helperUnavailable], nothing started).
/// 3. `prepareExit` locks the vault.
/// 4. The setup is started detached with the arguments as a list (never a
///    command line string), see [buildArguments].
/// 5. The setup's own code writes `started` into the result file as soon as
///    it runs (from then on it always writes the outcome and starts the app
///    again). If that does not show up in time (a security product blocked or
///    slowed it, or an earlier setup still runs), the setup and the programs
///    it started are stopped and [InstallOutcome.failed] is returned with the
///    app still running.
/// 6. `exit(0)`. The setup installs, writes `success` or `aborted` into the
///    result file and starts the app (the new version, or the old one after a
///    rollback). [WindowsUpdateInstaller.readHelperResult] reads the result at
///    the next start.
///
/// Nothing is logged here; the setup's own log holds no vault data.
class WindowsSetupInstaller implements UpdateInstaller {
  WindowsSetupInstaller({
    bool? isWindows,
    WindowsProcessStarter? startProcess,
    void Function(int code)? exitProcess,
    Directory? logDirectory,
    Map<String, String>? environment,
    this.stopProcess,
    this.minSetupBytes = defaultMinSetupBytes,
    this.requirePeHeader = true,
    this.setupStartTimeout = const Duration(seconds: 60),
    this.pollInterval = const Duration(milliseconds: 200),
  }) : _isWindows = isWindows ?? Platform.isWindows,
       _startProcess = startProcess ?? _defaultStarter,
       _exit = exitProcess ?? exit,
       _logDirectory = logDirectory ?? Directory.systemTemp,
       _environment = environment ?? Platform.environment;

  /// A real setup holds the whole release (the engine dll alone is tens of MB).
  static const int defaultMinSetupBytes = 1024 * 1024;

  /// Name of the log the setup writes in the temp folder.
  static const String setupLogFileName = 'update-setup.log';

  /// Name of the file the setup writes its result into (`success` or
  /// `aborted`), in the temp folder.
  static const String setupResultFileName = 'update-setup.result';

  /// Smaller files are refused as "not a setup".
  final int minSetupBytes;

  /// Require the `MZ` header. Off only in tests that use synthetic files.
  final bool requirePeHeader;

  /// How long to wait for the setup to report that it runs.
  final Duration setupStartTimeout;

  /// How often to look for it.
  final Duration pollInterval;

  /// Stops a setup that did not report in time, with the programs it started.
  /// Null means `taskkill` (tests replace it).
  final Future<void> Function(Process process)? stopProcess;

  final bool _isWindows;
  final WindowsProcessStarter _startProcess;
  final void Function(int code) _exit;
  final Directory _logDirectory;
  final Map<String, String> _environment;

  bool _busy = false;
  WindowsInstallError? _lastError;

  /// Why the last [install] returned [InstallOutcome.failed]; null after a
  /// call that did not fail.
  WindowsInstallError? get lastError => _lastError;

  @override
  Future<InstallOutcome> install(
    File package, {
    required Future<void> Function() prepareExit,
  }) async {
    if (!_isWindows) return InstallOutcome.unsupported;
    // A second call must not disturb the first one's state.
    if (_busy) return InstallOutcome.failed;
    _busy = true;
    _lastError = null;
    final log = File(p.join(_logDirectory.path, setupLogFileName));
    final result = File(p.join(_logDirectory.path, setupResultFileName));
    var handedOver = false;
    Process? setup;
    try {
      await _checkPackage(package);

      // A result left by an earlier run would pass the check below at once,
      // so a file that cannot be deleted (still open) ends here, before the
      // vault is locked.
      await _deleteQuietly(result);
      await _deleteQuietly(log);
      for (final file in [result, log]) {
        if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
            FileSystemEntityType.notFound) {
          return _fail(WindowsInstallError.helperUnavailable);
        }
      }

      try {
        await prepareExit();
      } on Object {
        return _fail(WindowsInstallError.prepareExitFailed);
      }

      try {
        setup = await _startProcess(
          p.normalize(package.absolute.path),
          buildArguments(logFile: log.path, resultFile: result.path),
          // Not the private folder: the next start deletes it.
          workingDirectory: _logDirectory.path,
          mode: ProcessStartMode.detached,
        );
      } on Object {
        return _fail(WindowsInstallError.helperUnavailable);
      }

      if (!await _setupIsRunning(result)) {
        return _fail(WindowsInstallError.helperNotReady);
      }

      handedOver = true;
      _exit(0);
      // Only reached when `exit` is replaced (tests).
      return InstallOutcome.started;
    } on _BadPackage {
      return _fail(WindowsInstallError.badPackage);
    } on Object {
      return _fail(WindowsInstallError.internal);
    } finally {
      _busy = false;
      // A setup that starts late must not close the app (it is allowed to
      // close it by force) while the user is still using it.
      if (!handedOver && setup != null) await _stopQuietly(setup);
    }
  }

  /// The argument list for the setup. Every value is its own list element:
  /// there is no command line string, so spaces and other characters in a
  /// path cannot change what runs. `/relaunch` and `/result` are read by the
  /// setup's own code (see `installer/windows/setup.iss`).
  static List<String> buildArguments({
    required String logFile,
    required String resultFile,
  }) => [
    '/VERYSILENT',
    '/SUPPRESSMSGBOXES',
    '/NORESTART',
    '/SP-',
    '/NOCANCEL',
    '/CLOSEAPPLICATIONS',
    '/relaunch=1',
    '/LOG=$logFile',
    '/result=$resultFile',
  ];

  // --- Steps ---------------------------------------------------------------

  Future<void> _checkPackage(File package) async {
    if (!p.basename(package.path).toLowerCase().endsWith('.exe') ||
        FileSystemEntity.typeSync(package.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await package.length() < minSetupBytes) {
      throw const _BadPackage();
    }
    if (requirePeHeader) {
      final input = await package.open();
      try {
        final head = await input.read(2);
        if (head.length != 2 || head[0] != 0x4d || head[1] != 0x5a) {
          throw const _BadPackage();
        }
      } finally {
        await input.close();
      }
    }
  }

  /// Waits for the setup to write `started` (or already its outcome) into
  /// the result file. False when the time is up.
  Future<bool> _setupIsRunning(File result) async {
    final clock = Stopwatch()..start();
    while (true) {
      try {
        if (await result.exists() && await result.length() <= 64) {
          final token = (await result.readAsString()).trim();
          if (const {'started', 'success', 'aborted'}.contains(token)) {
            return true;
          }
        }
      } on Object {
        // Still being written; look again.
      }
      if (clock.elapsed >= setupStartTimeout) return false;
      await Future<void>.delayed(pollInterval);
    }
  }

  static Future<Process> _defaultStarter(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) => Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    mode: mode,
  );

  // --- Helpers -------------------------------------------------------------

  InstallOutcome _fail(WindowsInstallError error) {
    _lastError = error;
    return InstallOutcome.failed;
  }

  /// Stops [process] and every program it started. `setup.exe` is only a
  /// small loader: it unpacks and starts the real setup (`setup.tmp`), which
  /// killing the loader alone would leave running. So the whole tree goes,
  /// with the system's `taskkill` by full path (never a bare name, which
  /// Windows would also look for in the app's own folder).
  Future<void> _stopQuietly(Process process) async {
    try {
      final stop = stopProcess;
      if (stop != null) return await stop(process);
      final root = _environment['SystemRoot'] ?? _environment['windir'];
      final taskkill = root == null || root.isEmpty
          ? null
          : p.join(root, 'System32', 'taskkill.exe');
      if (taskkill != null && File(taskkill).existsSync()) {
        await Process.run(taskkill, [
          '/PID',
          '${process.pid}',
          '/T',
          '/F',
        ]).timeout(const Duration(seconds: 10));
      }
    } on Object {
      // At least the loader goes, just below.
    } finally {
      _killQuietly(process);
    }
  }

  void _killQuietly(Process process) {
    try {
      process.kill();
    } on Object {
      // Already gone.
    }
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on Object {
      // In use; the caller looks again.
    }
  }
}

/// Internal: the file is not a setup this installer runs.
class _BadPackage implements Exception {
  const _BadPackage();
}
