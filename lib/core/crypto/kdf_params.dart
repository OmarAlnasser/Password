import 'crypto_exceptions.dart';

/// Argon2id parameters stored next to the user's salt.
///
/// They are persisted (not hard-coded at the call site) so that we can raise
/// the cost for new passwords later without breaking existing vaults.
/// Parallelism is fixed at 1 by libsodium's `crypto_pwhash`.
class KdfParams {
  const KdfParams({
    required this.version,
    required this.opsLimit,
    required this.memLimitBytes,
  });

  factory KdfParams.fromJson(Map<String, Object?> json) {
    final params = KdfParams(
      version: json['v']! as int,
      opsLimit: json['ops']! as int,
      memLimitBytes: json['mem']! as int,
    );
    params.ensureAtLeastFloor();
    return params;
  }

  /// v1 = Argon2id v1.3, NFKC-normalised UTF-8 password, 16-byte salt.
  final int version;

  /// Argon2 iterations (t).
  final int opsLimit;

  /// Argon2 memory in bytes (m).
  final int memLimitBytes;

  static const int currentVersion = 1;

  /// Default for new accounts: Argon2id, 64 MiB, 3 iterations.
  static const KdfParams recommended = KdfParams(
    version: currentVersion,
    opsLimit: 3,
    memLimitBytes: 64 * 1024 * 1024,
  );

  /// The lowest parameters a client will ever accept.
  ///
  /// KDF parameters come from the server on a new device. A malicious or
  /// compromised server could hand out t=1/m=8KiB so that the auth hash it
  /// receives becomes cheap to brute-force. Refusing anything below the
  /// recommended values closes that downgrade path.
  static const KdfParams floor = recommended;

  void ensureAtLeastFloor() {
    if (version != currentVersion ||
        opsLimit < floor.opsLimit ||
        memLimitBytes < floor.memLimitBytes) {
      throw const WeakKdfParamsException();
    }
  }

  Map<String, Object?> toJson() => {
    'v': version,
    'ops': opsLimit,
    'mem': memLimitBytes,
  };

  @override
  bool operator ==(Object other) =>
      other is KdfParams &&
      other.version == version &&
      other.opsLimit == opsLimit &&
      other.memLimitBytes == memLimitBytes;

  @override
  int get hashCode => Object.hash(version, opsLimit, memLimitBytes);
}
