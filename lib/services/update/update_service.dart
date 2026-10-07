import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sodium/sodium.dart';

import 'app_version.dart';
import 'cancel_token.dart';
import 'secure_downloader.dart';
import 'update_config.dart';
import 'update_failure.dart';
import 'update_manifest.dart';
import 'update_verifier.dart';
import 'update_workspace.dart';

/// Outcome of [UpdateService.check].
sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

/// Development build or unsupported platform: nothing was requested.
final class UpdateDisabled extends UpdateCheckResult {
  const UpdateDisabled();
}

/// The latest signed release is not newer than the installed build.
final class UpdateUpToDate extends UpdateCheckResult {
  const UpdateUpToDate(this.latestBuild);

  /// Build of the verified manifest. Remember the highest one seen.
  final int latestBuild;
}

/// A newer, correctly signed release with a package for this platform.
final class UpdateAvailable extends UpdateCheckResult {
  const UpdateAvailable(this.manifest, this.asset);

  final UpdateManifest manifest;
  final UpdateAsset asset;

  /// Build of the verified manifest. Remember the highest one seen.
  int get latestBuild => manifest.build;
}

/// The check did not finish. Only the reason is kept.
final class UpdateFailed extends UpdateCheckResult {
  const UpdateFailed(this.reason);

  final UpdateFailure reason;
}

/// A package on disk, downloaded but not yet verified or installed.
class DownloadedUpdate {
  DownloadedUpdate({
    required this.manifest,
    required this.asset,
    required this.file,
    required this.directory,
  });

  final UpdateManifest manifest;
  final UpdateAsset asset;
  final File file;

  /// The private directory that holds [file]; removed as a whole.
  final Directory directory;
}

/// A copy of a verified package, in its own private directory, ready to be
/// handed to an `UpdateInstaller`.
class StagedUpdate {
  StagedUpdate({required this.file, required this.directory});

  final File file;
  final Directory directory;
}

/// Checks for, downloads and verifies updates. No UI, no state: see
/// `UpdateController` for that.
///
/// Trust chain (each step must hold before the next one runs):
/// 1. `update.json.sig` and `update.json` are fetched over HTTPS from GitHub
///    (size capped, hosts and redirects checked by [SecureDownloader]).
/// 2. The Ed25519 signature is verified over the exact bytes of the manifest
///    with the key pinned in the app. Only then is the manifest parsed.
/// 3. The signed build number must be newer than the installed build, and not
///    older than the highest signed build ever seen (replay protection).
/// 4. The package URL, file name, size and SHA-256 come from the signed
///    manifest. The download is capped at the signed size while streaming and
///    its SHA-256 is checked on the finished file.
/// 5. Just before installing, the file is checked again and copied into a new
///    private directory, and the copy is checked (TOCTOU).
class UpdateService {
  UpdateService({
    required this.config,
    required this.downloader,
    required this.verifier,
    required this.workspace,
    required this.version,
    required this.platform,
    Future<void> Function(File from, String to)? copyFile,
  }) : _copyFile = copyFile ?? ((from, to) => from.copy(to));

  /// The production wiring: GitHub, the pinned key, libsodium for the
  /// signature, [workRoot] (a folder inside the app's own data directory that
  /// nothing else uses) for files.
  factory UpdateService.create({
    required Sodium sodium,
    required Directory workRoot,
    http.Client? client,
    UpdateConfig? config,
    AppVersion? version,
    UpdatePlatform? platform,
  }) {
    final cfg = config ?? UpdateConfig();
    return UpdateService(
      config: cfg,
      downloader: SecureDownloader(client ?? http.Client(), cfg),
      verifier: SodiumManifestVerifier(sodium, cfg.publicKey),
      workspace: UpdateWorkspace(workRoot),
      version: version ?? AppVersion.current,
      platform: platform ?? UpdatePlatform.current,
    );
  }

  final UpdateConfig config;
  final SecureDownloader downloader;
  final ManifestVerifier verifier;
  final UpdateWorkspace workspace;

  /// The installed version.
  final AppVersion version;

  /// This platform, or null where updates are not offered.
  final UpdatePlatform? platform;

  /// Copies the package for staging (replaceable in tests).
  final Future<void> Function(File from, String to) _copyFile;

  /// False in development builds and on unsupported platforms. Nothing is
  /// requested then.
  bool get enabled => version.enabled && platform != null;

  /// Fetches the signed manifest and decides what to do. Never throws.
  ///
  /// [highestSeenBuild] is the highest signed build this install has ever
  /// seen (persisted by the caller). A signed manifest that is newer than the
  /// installed build but older than that is a replay and fails with
  /// [UpdateFailure.rollback].
  Future<UpdateCheckResult> check({
    int highestSeenBuild = 0,
    CancelToken? cancel,
  }) async {
    final platform = this.platform;
    if (!enabled || platform == null) return const UpdateDisabled();
    try {
      final signatureFile = await downloader.fetchBytes(
        config.signatureUri,
        maxBytes: config.maxSignatureBytes,
        cancel: cancel,
      );
      final manifestBytes = await downloader.fetchBytes(
        config.manifestUri,
        maxBytes: config.maxManifestBytes,
        cancel: cancel,
      );

      // Signature first: until it verifies, the bytes are just bytes.
      final signature = decodeSignatureFile(signatureFile);
      if (!verifier.verify(manifestBytes, signature)) {
        throw const UpdateException(UpdateFailure.signatureInvalid);
      }
      final manifest = UpdateManifest.parse(manifestBytes, config);

      if (!manifest.version.isNewerThan(version)) {
        return UpdateUpToDate(manifest.build);
      }
      if (manifest.build < highestSeenBuild) {
        throw const UpdateException(UpdateFailure.rollback);
      }
      final asset = manifest.assetFor(platform);
      if (asset == null) throw const UpdateException(UpdateFailure.noAsset);
      return UpdateAvailable(manifest, asset);
    } on UpdateException catch (e) {
      return UpdateFailed(e.reason);
    } on Object {
      return const UpdateFailed(UpdateFailure.internal);
    }
  }

  /// Downloads the package of [update] into a new private directory. The size
  /// and host rules are enforced while streaming. Call [verify] next.
  ///
  /// Throws [UpdateException]. On any failure, or if [cancel] fires, nothing
  /// is left on disk.
  Future<DownloadedUpdate> download(
    UpdateAvailable update, {
    DownloadProgress? onProgress,
    CancelToken? cancel,
  }) async {
    if (!enabled) throw const UpdateException(UpdateFailure.disabled);
    final asset = update.asset;
    // The parser already guarantees this; a bug elsewhere must not turn the
    // name into a path.
    if (asset.name.isEmpty ||
        asset.name.startsWith('.') ||
        p.basename(asset.name) != asset.name ||
        asset.name.contains(RegExp(r'[\\/:]'))) {
      throw const UpdateException(UpdateFailure.manifestInvalid);
    }
    final dir = await workspace.create();
    try {
      final file = File(p.join(dir.path, asset.name));
      await downloader.downloadToFile(
        asset.url,
        file,
        expectedSize: asset.size,
        onProgress: onProgress,
        cancel: cancel,
      );
      return DownloadedUpdate(
        manifest: update.manifest,
        asset: asset,
        file: file,
        directory: dir,
      );
    } on Object {
      await workspace.delete(dir);
      rethrow;
    }
  }

  /// Checks the finished file against the signed manifest (size and SHA-256).
  /// Throws [UpdateException]; the files are deleted if it does not match.
  Future<void> verify(DownloadedUpdate download) async {
    try {
      await verifyFile(download.file, download.asset);
    } on Object {
      await workspace.delete(download.directory);
      rethrow;
    }
  }

  /// Size and SHA-256 of [file] against [asset]. Throws
  /// [UpdateFailure.hashMismatch] when they differ (or when [file] is not a
  /// plain file), [UpdateFailure.storage] when it cannot be read.
  Future<void> verifyFile(File file, UpdateAsset asset) async {
    try {
      if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const UpdateException(UpdateFailure.hashMismatch);
      }
      if (await file.length() != asset.size) {
        throw const UpdateException(UpdateFailure.hashMismatch);
      }
      final digest = await crypto.sha256.bind(file.openRead()).first;
      if (digest.toString() != asset.sha256) {
        throw const UpdateException(UpdateFailure.hashMismatch);
      }
    } on UpdateException {
      rethrow;
    } on Object {
      throw const UpdateException(UpdateFailure.storage);
    }
  }

  /// Right before installing: copies [download] into a brand new private
  /// directory and verifies the COPY against the signed manifest (size and
  /// SHA-256). The copy is what the installer must read, so what was checked is
  /// what is installed, and nothing without access to that directory can swap
  /// the file in between. (Checking the original first would add nothing: a
  /// swapped original fails the check of the copy.)
  ///
  /// Throws [UpdateException]; nothing is left behind on failure.
  Future<StagedUpdate> stageForInstall(DownloadedUpdate download) async {
    final dir = await workspace.create();
    try {
      final staged = File(p.join(dir.path, download.asset.name));
      try {
        await _copyFile(download.file, staged.path);
      } on Object {
        throw const UpdateException(UpdateFailure.storage);
      }
      await verifyFile(staged, download.asset);
      return StagedUpdate(file: staged, directory: dir);
    } on Object {
      await workspace.delete(dir);
      rethrow;
    }
  }

  /// Removes one download or staging directory.
  Future<void> discard(Directory? directory) => workspace.delete(directory);

  /// Removes everything the updater has on disk. Call at start-up (leftovers of
  /// an update that just finished) and when an update is abandoned.
  Future<void> cleanup() => workspace.deleteAll();
}
