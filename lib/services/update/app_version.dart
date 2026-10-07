/// The installed version, as set at build time.
///
/// The release workflow passes
/// `--dart-define=APP_VERSION=0.2.0 --dart-define=APP_BUILD=2000`
/// (and the same values as `--build-name` / `--build-number`). A build without
/// them (local runs, the test CI builds) is a development build: the updater
/// is disabled and shows nothing.
///
/// The build number is monotonic and derived from the version:
/// `major * 1000000 + minor * 1000 + patch`. It is what versions are compared
/// by, and what the replay protection remembers.
final class AppVersion {
  const AppVersion._(this.version, this.build);

  /// "No version": the updater is off.
  static const AppVersion none = AppVersion._('', 0);

  /// `0.2.0`, or empty when [enabled] is false.
  final String version;

  /// Monotonic build number, 0 when [enabled] is false.
  final int build;

  /// False for development builds.
  bool get enabled => build > 0;

  /// What this build was compiled as. Disabled without `APP_VERSION`.
  static final AppVersion current = AppVersion.fromDefines(
    const String.fromEnvironment('APP_VERSION'),
    const int.fromEnvironment('APP_BUILD'),
  );

  /// Largest numbers that keep [buildOf] unique and inside Android's
  /// `versionCode` (signed 32-bit).
  static const int maxMajor = 2000;
  static const int maxMinorOrPatch = 999;

  static final RegExp _pattern = RegExp(
    r'^(0|[1-9][0-9]{0,3})\.'
    r'(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})$',
  );

  /// The build number for `major.minor.patch`.
  static int buildOf(int major, int minor, int patch) =>
      major * 1000000 + minor * 1000 + patch;

  /// Builds an [AppVersion] from the two compile-time values. A missing or
  /// malformed version, or a [build] that does not match it, gives [none]
  /// (disabled) rather than a half-working updater. A [build] of 0 or less
  /// means "derive it from the version".
  factory AppVersion.fromDefines(String version, int build) =>
      tryParse(version, build: build > 0 ? build : null) ?? none;

  /// Parses a strict `major.minor.patch` (no prefix, no suffix, no leading
  /// zeros, minor and patch up to 999, major up to 2000). When [build] is given
  /// it must equal the number derived from the version. Returns null if not.
  static AppVersion? tryParse(String version, {int? build}) {
    final m = _pattern.firstMatch(version);
    if (m == null) return null;
    final major = int.parse(m.group(1)!);
    final minor = int.parse(m.group(2)!);
    final patch = int.parse(m.group(3)!);
    if (major > maxMajor ||
        minor > maxMinorOrPatch ||
        patch > maxMinorOrPatch) {
      return null;
    }
    final derived = buildOf(major, minor, patch);
    if (derived <= 0) return null; // 0.0.0 is not a release.
    if (build != null && build != derived) return null;
    return AppVersion._(version, derived);
  }

  /// True if this build is newer than [other].
  bool isNewerThan(AppVersion other) => build > other.build;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && other.build == build && other.version == version;

  @override
  int get hashCode => Object.hash(version, build);

  @override
  String toString() => enabled ? version : 'dev';
}
