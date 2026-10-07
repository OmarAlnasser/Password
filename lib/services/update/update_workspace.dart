import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'update_failure.dart';

/// Restricts [dir] to the current user. Best effort, never throws.
typedef DirectoryHardener = Future<void> Function(Directory dir);

/// Where updates are downloaded and staged: a directory that nothing else
/// uses, with one fresh, randomly named, owner-only subdirectory per download.
///
/// [root] must be inside the app's own data directory (`updates` under
/// `getApplicationSupportDirectory()`), never the shared temp directory:
/// * Android: app-private storage, unreachable for other apps.
/// * Windows: `%APPDATA%`/`%LOCALAPPDATA%`, whose default ACL excludes other
///   users. Another program running as the same user can still replace files
///   there, as it could replace the app itself; the SHA-256 is therefore
///   checked again on the final copy right before it is handed to the
///   installer (see `UpdateService.stageForInstall`), and Android checks the
///   signing certificate itself.
///
/// [root] should be a folder of its own. Even so, only the directories this
/// class created (32 hex characters) are ever deleted, so pointing [root] at
/// a folder that holds something else (the vault!) cannot wipe it.
class UpdateWorkspace {
  UpdateWorkspace(this.root, {DirectoryHardener? harden, Random? random})
    : _harden = harden ?? restrictToOwner,
      _random = random ?? Random.secure();

  final Directory root;
  final DirectoryHardener _harden;
  final Random _random;

  /// A new empty directory, mode 700 where the OS has modes.
  Future<Directory> create() async {
    try {
      await root.create(recursive: true);
      // The parent is closed first, so the child is never reachable by others
      // even in the instant before its own mode is set.
      await _harden(root);
      final dir = Directory(p.join(root.path, _randomName()));
      await dir.create();
      await _harden(dir);
      return dir;
    } on Object {
      throw const UpdateException(UpdateFailure.storage);
    }
  }

  static final RegExp _ownName = RegExp(r'^[0-9a-f]{32}$');

  /// Deletes [dir] if it is one of ours (a direct child of [root] that
  /// [create] made). Never throws.
  Future<void> delete(Directory? dir) async {
    if (dir == null ||
        !p.equals(p.dirname(dir.path), root.path) ||
        !_ownName.hasMatch(p.basename(dir.path))) {
      return;
    }
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } on Object {
      // Leftovers are removed by the next deleteAll().
    }
  }

  /// Deletes every directory [create] made under [root]: leftovers of an
  /// earlier run, and the files of a finished update. Never throws.
  Future<void> deleteAll() async {
    try {
      if (!await root.exists()) return;
      await for (final e in root.list(followLinks: false)) {
        if (!_ownName.hasMatch(p.basename(e.path))) continue;
        try {
          await e.delete(recursive: true);
        } on Object {
          // Keep going.
        }
      }
    } on Object {
      // Nothing to clean.
    }
  }

  String _randomName() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// `chmod 700` where that exists (Android, Linux, macOS). On Windows there is
  /// nothing to do from Dart: the directory inherits the per-user ACL of the
  /// application data folder.
  static Future<void> restrictToOwner(Directory dir) async {
    if (Platform.isWindows) return;
    try {
      await Process.run('chmod', ['700', dir.path]);
    } on Object {
      // Still inside the app's private storage.
    }
  }
}
