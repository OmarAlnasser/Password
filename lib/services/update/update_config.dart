import 'dart:convert';
import 'dart:typed_data';

import 'update_failure.dart';
import 'update_public_key.dart';

/// Everything fixed about where updates come from and how far they are
/// trusted. Tests build their own with a throwaway key and smaller limits.
class UpdateConfig {
  UpdateConfig({
    this.repo = defaultRepo,
    String publicKeyBase64 = updatePublicKeyBase64,
    Set<String> allowedHosts = defaultAllowedHosts,
    this.maxManifestBytes = 64 * 1024,
    this.maxSignatureBytes = 1024,
    this.maxAssetBytes = 400 * 1024 * 1024,
    this.maxRedirects = 5,
    this.requestTimeout = const Duration(seconds: 20),
    this.stallTimeout = const Duration(seconds: 30),
    this.checkInterval = const Duration(hours: 24),
  }) : publicKey = _decodeKey(publicKeyBase64),
       allowedHosts = Set.unmodifiable(allowedHosts) {
    if (!_repoPattern.hasMatch(repo) ||
        repo.split('/').any((part) => part.startsWith('.'))) {
      throw ArgumentError.value(repo, 'repo', 'must be owner/name');
    }
  }

  /// The public GitHub repository that publishes releases.
  static const String defaultRepo = 'OmarAlnasser/Password';

  /// Hosts a request may ever go to, on the first request and on every
  /// redirect hop. Exact names only, no wildcard:
  /// * `github.com` serves the `releases/latest/download/` and
  ///   `releases/download/<tag>/` URLs and redirects from them.
  /// * `release-assets.githubusercontent.com` is where GitHub now redirects
  ///   release downloads to (since 2025); `objects.githubusercontent.com` is
  ///   where it redirected before and still does for older assets.
  /// Other `githubusercontent.com` hosts are left out on purpose: `raw.`,
  /// `gist.`, `avatars.` and friends serve content that anyone can upload.
  static const Set<String> defaultAllowedHosts = {
    'github.com',
    'objects.githubusercontent.com',
    'release-assets.githubusercontent.com',
  };

  static const String manifestFileName = 'update.json';
  static const String signatureFileName = 'update.json.sig';

  static final RegExp _repoPattern = RegExp(
    r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$',
  );

  /// `owner/name`.
  final String repo;

  /// Raw 32-byte Ed25519 public key that signs the manifest.
  final Uint8List publicKey;

  /// See [defaultAllowedHosts].
  final Set<String> allowedHosts;

  /// The manifest is at most this big (checked while streaming).
  final int maxManifestBytes;

  /// The detached signature (base64, 88 characters) is at most this big.
  final int maxSignatureBytes;

  /// A package is at most this big, whatever the manifest says (checked while
  /// streaming).
  final int maxAssetBytes;

  /// Redirect hops followed per request.
  final int maxRedirects;

  /// Time to the response headers, per request.
  final Duration requestTimeout;

  /// Longest pause between two chunks of a body.
  final Duration stallTimeout;

  /// Minimum time between two automatic checks.
  final Duration checkInterval;

  /// Latest release's manifest. GitHub redirects `latest` to the newest
  /// release that is not a draft or pre-release.
  Uri get manifestUri => Uri.https(
    'github.com',
    '/$repo/releases/latest/download/$manifestFileName',
  );

  /// Its detached signature.
  Uri get signatureUri => Uri.https(
    'github.com',
    '/$repo/releases/latest/download/$signatureFileName',
  );

  /// Every package URL in the manifest must start with this path on
  /// `github.com` (the tag-pinned download URL of this repository).
  String get assetPathPrefix => '/$repo/releases/download/';

  /// Null if [url] may be requested; otherwise why not. Applies to the first
  /// request and to every redirect target.
  UpdateFailure? rejectUrl(Uri url) {
    if (url.scheme == 'http') return UpdateFailure.insecureUrl;
    if (url.scheme != 'https') return UpdateFailure.hostNotAllowed;
    if (url.userInfo.isNotEmpty) return UpdateFailure.hostNotAllowed;
    if (url.hasPort && url.port != 443) return UpdateFailure.hostNotAllowed;
    if (!allowedHosts.contains(url.host)) return UpdateFailure.hostNotAllowed;
    if (url.toString().length > 4096) return UpdateFailure.hostNotAllowed;
    return null;
  }

  static Uint8List _decodeKey(String b64) {
    final Uint8List bytes;
    try {
      bytes = base64.decode(b64.trim());
    } on FormatException {
      throw ArgumentError.value('<redacted>', 'publicKeyBase64', 'not base64');
    }
    if (bytes.length != 32) {
      throw ArgumentError.value(
        '<redacted>',
        'publicKeyBase64',
        'not 32 bytes',
      );
    }
    return bytes;
  }
}
