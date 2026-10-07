import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'app_version.dart';
import 'update_config.dart';
import 'update_failure.dart';

/// A platform that has a downloadable package.
enum UpdatePlatform {
  android('android', '.apk'),
  windows('windows', '.zip');

  const UpdatePlatform(this.key, this.extension);

  /// Key in `assets` of the manifest.
  final String key;

  /// Required file extension of the package.
  final String extension;

  /// The platform this process runs on, or null where updates are not
  /// offered (iOS, macOS, Linux).
  static UpdatePlatform? get current {
    if (Platform.isAndroid) return android;
    if (Platform.isWindows) return windows;
    return null;
  }
}

/// One downloadable package, as described by the signed manifest.
class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.url,
    required this.size,
    required this.sha256,
  });

  /// File name, `[A-Za-z0-9._-]` only, equal to the last segment of [url].
  final String name;

  /// HTTPS URL on the host allow-list.
  final Uri url;

  /// Exact size in bytes.
  final int size;

  /// Lower-case hex SHA-256 of the file.
  final String sha256;
}

/// The signed description of the latest release (`update.json`, schema 1).
///
/// Never parse bytes that have not passed signature verification:
/// `UpdateService.check` does the verification first.
class UpdateManifest {
  UpdateManifest._({
    required this.version,
    required this.publishedAt,
    required this.notes,
    required this.assets,
  });

  /// The only schema this app understands.
  static const int supportedSchema = 1;

  /// `0.2.0` and its build number.
  final AppVersion version;

  /// Release time (UTC).
  final DateTime publishedAt;

  /// Release notes by language code (`en`, `ar`, ...).
  final Map<String, String> notes;

  /// Packages by platform key (`android`, `windows`).
  final Map<String, UpdateAsset> assets;

  int get build => version.build;

  /// The package for [platform], or null.
  UpdateAsset? assetFor(UpdatePlatform platform) => assets[platform.key];

  /// Release notes in [languageCode], else English, else any, else null.
  String? notesFor(String languageCode) =>
      notes[languageCode] ??
      notes['en'] ??
      (notes.isEmpty ? null : notes.values.first);

  // --- Limits ---------------------------------------------------------------

  static const int maxVersionLength = 32;
  static const int maxNotesLanguages = 8;
  static const int maxNotesLength = 4000;
  static const int maxAssets = 8;
  static const int maxNameLength = 100;
  static const int maxUrlLength = 512;

  static final RegExp _langKey = RegExp(r'^[a-z]{2,3}(-[A-Za-z0-9]{2,8})?$');
  static final RegExp _platformKey = RegExp(r'^[a-z][a-z0-9_]{0,15}$');
  static final RegExp _fileName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');
  static final RegExp _sha256 = RegExp(r'^[0-9a-fA-F]{64}$');
  static final RegExp _timestamp = RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$',
  );
  static final RegExp _badControl = RegExp(
    r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]',
  );

  /// Strictly parses [bytes] (already signature-verified).
  ///
  /// Throws [UpdateException] with [UpdateFailure.manifestInvalid] for
  /// anything that does not match the schema, and
  /// [UpdateFailure.unsupportedSchema] for another schema number. Unknown
  /// extra keys are ignored (the signature covers them anyway); every known
  /// key is type- and range-checked.
  static UpdateManifest parse(Uint8List bytes, UpdateConfig config) {
    if (bytes.isEmpty || bytes.length > config.maxManifestBytes) {
      throw const UpdateException(UpdateFailure.manifestInvalid);
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const UpdateException(UpdateFailure.manifestInvalid);
    }
    if (decoded is! Map<String, Object?>) _bad();

    final schema = decoded['schema'];
    if (schema is! int) _bad();
    if (schema != supportedSchema) {
      throw const UpdateException(UpdateFailure.unsupportedSchema);
    }

    final versionText = decoded['version'];
    final buildNumber = decoded['build'];
    if (versionText is! String ||
        versionText.length > maxVersionLength ||
        buildNumber is! int) {
      _bad();
    }
    // The build must be the one the version implies, so a signed manifest
    // cannot carry a version that says one thing and a build that says another.
    final version = AppVersion.tryParse(versionText, build: buildNumber);
    if (version == null) _bad();

    final published = decoded['publishedAt'];
    if (published is! String ||
        published.length > 40 ||
        !_timestamp.hasMatch(published)) {
      _bad();
    }
    final publishedAt = DateTime.tryParse(published);
    if (publishedAt == null || !publishedAt.isUtc) _bad();

    return UpdateManifest._(
      version: version,
      publishedAt: publishedAt,
      notes: _parseNotes(decoded['notes']),
      assets: _parseAssets(decoded['assets'], config),
    );
  }

  static Map<String, String> _parseNotes(Object? raw) {
    if (raw is! Map<String, Object?> || raw.length > maxNotesLanguages) _bad();
    final notes = <String, String>{};
    for (final MapEntry(:key, :value) in raw.entries) {
      if (!_langKey.hasMatch(key) ||
          value is! String ||
          value.length > maxNotesLength ||
          _badControl.hasMatch(value)) {
        _bad();
      }
      notes[key] = value;
    }
    return Map.unmodifiable(notes);
  }

  static Map<String, UpdateAsset> _parseAssets(
    Object? raw,
    UpdateConfig config,
  ) {
    if (raw is! Map<String, Object?> || raw.isEmpty || raw.length > maxAssets) {
      _bad();
    }
    final assets = <String, UpdateAsset>{};
    for (final MapEntry(:key, :value) in raw.entries) {
      if (!_platformKey.hasMatch(key) || value is! Map<String, Object?>) {
        _bad();
      }
      assets[key] = _parseAsset(key, value, config);
    }
    return Map.unmodifiable(assets);
  }

  static UpdateAsset _parseAsset(
    String platformKey,
    Map<String, Object?> j,
    UpdateConfig config,
  ) {
    final name = j['name'];
    final url = j['url'];
    final size = j['size'];
    final hash = j['sha256'];
    if (name is! String ||
        name.isEmpty ||
        name.length > maxNameLength ||
        !_fileName.hasMatch(name) ||
        name.contains('..') ||
        url is! String ||
        url.isEmpty ||
        url.length > maxUrlLength ||
        size is! int ||
        size <= 0 ||
        size > config.maxAssetBytes ||
        hash is! String ||
        !_sha256.hasMatch(hash)) {
      _bad();
    }
    for (final p in UpdatePlatform.values) {
      if (p.key == platformKey && !name.endsWith(p.extension)) _bad();
    }

    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        // The first URL must be the tag-pinned download URL on github.com; the
        // other allow-listed hosts are only ever reached by redirect.
        uri.host != 'github.com' ||
        config.rejectUrl(uri) != null ||
        uri.hasQuery ||
        uri.hasFragment ||
        !uri.path.startsWith(config.assetPathPrefix) ||
        uri.path.substring(uri.path.lastIndexOf('/') + 1) != name) {
      _bad();
    }
    return UpdateAsset(
      name: name,
      url: uri,
      size: size,
      sha256: hash.toLowerCase(),
    );
  }

  static Never _bad() =>
      throw const UpdateException(UpdateFailure.manifestInvalid);
}
