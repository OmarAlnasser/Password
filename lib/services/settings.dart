import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

/// Non-secret user preferences, stored as JSON in the app support directory.
class AppSettings extends ChangeNotifier {
  AppSettings(this._file);

  final File _file;

  /// Dark is the app's identity, so a new install starts there. A saved
  /// choice (including "system") always wins.
  ThemeMode themeMode = ThemeMode.dark;
  Locale? locale; // null = follow system
  int autoLockSeconds = 120;
  bool lockOnBackground = true;
  int clipboardClearSeconds = 30;
  bool biometricsEnabled = false;
  bool hibpEnabled = true;

  /// Download each login's website icon directly from that site.
  bool fetchIcons = true;
  String? syncEmail;

  /// Look for a new version on GitHub, at most once a day. Development builds
  /// (no `APP_VERSION`) never check, whatever this says.
  bool checkUpdates = true;

  /// When the last automatic or manual update check finished, in
  /// milliseconds since the epoch (0 = never).
  int lastUpdateCheck = 0;

  /// The highest build number of any validly signed update manifest this
  /// install has seen. A signed manifest older than this (but newer than the
  /// installed build) is a replay of an old release and is refused.
  int highestSeenBuild = 0;

  /// The build the user chose "Skip this version" for (0 = none). Automatic
  /// checks stay quiet about exactly this build; a newer one is offered again.
  int skippedBuild = 0;

  Future<void> load() async {
    try {
      final j = jsonDecode(await _file.readAsString()) as Map<String, Object?>;
      themeMode = ThemeMode.values.byName(
        (j['theme'] as String?) ?? ThemeMode.dark.name,
      );
      final lang = j['lang'] as String?;
      locale = lang == null ? null : Locale(lang);
      autoLockSeconds = (j['autoLock'] as int?) ?? autoLockSeconds;
      lockOnBackground = (j['lockBg'] as bool?) ?? lockOnBackground;
      clipboardClearSeconds = (j['clip'] as int?) ?? clipboardClearSeconds;
      biometricsEnabled = (j['bio'] as bool?) ?? false;
      hibpEnabled = (j['hibp'] as bool?) ?? true;
      fetchIcons = (j['icons'] as bool?) ?? true;
      syncEmail = j['syncEmail'] as String?;
      checkUpdates = (j['updates'] as bool?) ?? true;
      lastUpdateCheck = _count(j['updChecked']);
      highestSeenBuild = _count(j['updHighest']);
      skippedBuild = _count(j['updSkipped']);
    } on Object {
      // Defaults.
    }
  }

  Future<void> update(void Function(AppSettings s) change) async {
    change(this);
    // Clamp to sane, safe ranges regardless of what the UI sent.
    autoLockSeconds = autoLockSeconds.clamp(30, 3600);
    clipboardClearSeconds = clipboardClearSeconds.clamp(10, 120);
    lastUpdateCheck = lastUpdateCheck < 0 ? 0 : lastUpdateCheck;
    highestSeenBuild = highestSeenBuild < 0 ? 0 : highestSeenBuild;
    skippedBuild = skippedBuild < 0 ? 0 : skippedBuild;
    notifyListeners();
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
      jsonEncode({
        'theme': themeMode.name,
        'lang': locale?.languageCode,
        'autoLock': autoLockSeconds,
        'lockBg': lockOnBackground,
        'clip': clipboardClearSeconds,
        'bio': biometricsEnabled,
        'hibp': hibpEnabled,
        'icons': fetchIcons,
        'syncEmail': syncEmail,
        'updates': checkUpdates,
        'updChecked': lastUpdateCheck,
        'updHighest': highestSeenBuild,
        'updSkipped': skippedBuild,
      }),
      flush: true,
    );
  }

  /// A non-negative whole number from the file, else 0.
  static int _count(Object? v) => v is int && v > 0 ? v : 0;
}
