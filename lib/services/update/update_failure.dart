/// Why an update step failed. Only this value is ever reported or shown: no
/// URL, path, header or server text goes with it, because those can carry user
/// names or leak what was fetched.
enum UpdateFailure {
  /// No connection, DNS or TLS failure, connection dropped.
  network,

  /// The server did not answer, or stopped sending data, in time.
  timeout,

  /// The server answered with something other than 200 (and no redirect).
  badStatus,

  /// A body was larger than its cap (manifest, signature or package).
  tooLarge,

  /// The package ended before the size in the signed manifest.
  truncated,

  /// More than the allowed number of redirects, or a redirect loop.
  tooManyRedirects,

  /// A URL (start or redirect target) was not HTTPS.
  insecureUrl,

  /// A URL (start or redirect target) was not on the host allow-list, or had
  /// credentials or a non-standard port.
  hostNotAllowed,

  /// The manifest signature is missing, malformed or does not verify with the
  /// pinned key.
  signatureInvalid,

  /// The (correctly signed) manifest does not follow the schema.
  manifestInvalid,

  /// The manifest declares a schema this app does not know.
  unsupportedSchema,

  /// A signed manifest older than one already seen (replay of an old release).
  rollback,

  /// The manifest has no package for this platform.
  noAsset,

  /// The package's size or SHA-256 differs from the signed manifest.
  hashMismatch,

  /// A local file could not be written, read, copied or deleted.
  storage,

  /// The user cancelled.
  cancelled,

  /// The platform installer could not be started.
  installFailed,

  /// Updates are not available in this build (no `APP_VERSION`) or on this
  /// platform.
  disabled,

  /// A bug: something unexpected happened.
  internal,
}

/// Thrown by the update layer. [toString] carries only the reason.
class UpdateException implements Exception {
  const UpdateException(this.reason);

  final UpdateFailure reason;

  @override
  String toString() => 'UpdateException(${reason.name})';
}
