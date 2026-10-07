import '../../l10n/app_localizations.dart';

const String _lri = '\u2066';
const String _pdi = '\u2069';

/// Keeps [text] (a version, a date, a number) in one left-to-right run, so it
/// reads the same inside an Arabic sentence and punctuation around it does not
/// jump to the wrong side (DESIGN section 10, rule 3).
String isolateLtr(String text) => '$_lri$text$_pdi';

/// "12.3 MB" / "480 KB" in the active language. Western digits in both.
String formatUpdateSize(AppLocalizations l, int bytes) {
  const mb = 1024 * 1024;
  if (bytes >= mb) {
    final value = bytes / mb;
    return l.updateSizeMb(
      value >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1),
    );
  }
  final kb = (bytes / 1024).ceil();
  return l.updateSizeKb((kb < 1 ? 1 : kb).toString());
}

/// Whole percent (0 to 100) of [fraction], rounded down.
int updatePercent(double? fraction) =>
    ((fraction ?? 0).clamp(0.0, 1.0) * 100).floor();

String _two(int n) => n.toString().padLeft(2, '0');

/// `2026-10-07`, the same order in both languages (DESIGN section 10, rule 6).
String formatUpdateDate(DateTime time) =>
    '${time.year.toString().padLeft(4, '0')}-${_two(time.month)}-${_two(time.day)}';

/// `2026-10-07 14:05` in local time.
String formatUpdateStamp(DateTime time) {
  final local = time.toLocal();
  return '${formatUpdateDate(local)} ${_two(local.hour)}:${_two(local.minute)}';
}

/// Version label such as `0.2.0 (build 2000)`, isolated for Arabic.
String formatUpdateVersion(AppLocalizations l, String version, int build) =>
    l.updateVersionBuild(isolateLtr(version), isolateLtr('$build'));
