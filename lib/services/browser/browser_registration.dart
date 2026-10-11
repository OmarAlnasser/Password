import 'dart:convert';
import 'dart:io';

import 'package:khazna_bridge/bridge_protocol.dart';

/// Writes or (with null) removes the registry keys natively; null where that
/// is not available (`PlatformBridge.setNativeMessagingHost`).
typedef SetNativeHost = Future<bool?> Function(String? manifest);

/// Runs a program and returns its result (`Process.run`; tests pass a fake).
typedef RunProcess = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// Tells Chrome, Edge and Brave where the browser helper is (Windows).
///
/// Chrome finds a native messaging host through a registry key under
/// HKEY_CURRENT_USER whose default value is the path of a small JSON manifest.
/// The manifest names the helper's exe and the one extension allowed to start
/// it. Everything is per user: no administrator rights are needed.
class BrowserRegistration {
  BrowserRegistration({
    required this.directory,
    required this.appDirectory,
    this.native,
    RunProcess? run,
  }) : _run = run ?? Process.run;

  /// Where the manifest is written (the bridge folder, see
  /// `bridgeDirectory`).
  final Directory directory;

  /// The folder of the app's exe: the helper and the extension ship there.
  final Directory appDirectory;

  /// Writes the keys from the app's own code; null in tests and where the
  /// native side is missing.
  final SetNativeHost? native;

  /// For reg.exe, when [native] is not there. (From a window app it shows a
  /// console for a moment, which the native way does not.)
  final RunProcess _run;

  /// One key per browser. Chrome reads the first; Edge and Brave read theirs.
  static const List<String> registryKeys = [
    'HKCU\\Software\\Google\\Chrome\\NativeMessagingHosts\\$nativeHostName',
    'HKCU\\Software\\Microsoft\\Edge\\NativeMessagingHosts\\$nativeHostName',
    'HKCU\\Software\\BraveSoftware\\Brave-Browser\\NativeMessagingHosts\\'
        '$nativeHostName',
  ];

  File get manifestFile => File(_join(directory.path, '$nativeHostName.json'));

  File get helperExe => File(_join(appDirectory.path, bridgeExeName));

  /// The unpacked extension the user loads in the browser.
  Directory get extensionFolder =>
      Directory(_join(appDirectory.path, 'extension'));

  /// The helper and the extension are there (not in a development build).
  bool get shipped =>
      helperExe.existsSync() &&
      File(_join(extensionFolder.path, 'manifest.json')).existsSync();

  /// The manifest Chrome reads.
  Map<String, Object?> manifest() => {
    'name': nativeHostName,
    'description': 'Khazna password manager',
    'path': helperExe.path,
    'type': 'stdio',
    'allowed_origins': [extensionOrigin],
  };

  /// Writes the manifest and the registry keys. False if the helper is not
  /// shipped or Chrome's key could not be written.
  ///
  /// Without [force], a manifest that is already up to date is taken to mean
  /// the keys are there too, and nothing runs (this is called at every
  /// start).
  Future<bool> register({bool force = true}) async {
    if (!shipped) return false;
    final text = const JsonEncoder.withIndent('  ').convert(manifest());
    if (!force) {
      try {
        if (await manifestFile.readAsString() == text) return true;
      } on FileSystemException {
        // Not written yet.
      }
    }
    await directory.create(recursive: true);
    final tmp = File('${manifestFile.path}.tmp');
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(manifestFile.path);
    final native = await this.native?.call(manifestFile.path);
    if (native != null) return native;
    var chrome = false;
    for (final key in registryKeys) {
      final r = await _run('reg', [
        'add',
        key,
        '/ve',
        '/t',
        'REG_SZ',
        '/d',
        manifestFile.path,
        '/f',
      ]);
      if (key == registryKeys.first) chrome = r.exitCode == 0;
    }
    return chrome;
  }

  /// Removes the registry keys and the manifest. Missing ones are fine.
  Future<void> unregister() async {
    final native = await this.native?.call(null);
    for (final key in native == null ? registryKeys : const <String>[]) {
      await _run('reg', ['delete', key, '/f']);
    }
    try {
      await manifestFile.delete();
    } on FileSystemException {
      // Not there.
    }
  }

  static String _join(String a, String b) => '$a${Platform.pathSeparator}$b';
}
