import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'entry_sort.dart';

// The sort preference is part of the settings; the enum lives with the sort
// function, which must not depend on this file.
export 'entry_sort.dart' show EntrySort;

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

  EntrySort _entrySort = EntrySort.recent;
  bool _updating = false;

  /// How the entry list is ordered (default [EntrySort.recent]). Setting it
  /// notifies listeners and saves, whether it is assigned directly or inside
  /// [update]. An unknown value in the file reads as the default.
  EntrySort get entrySort => _entrySort;
  set entrySort(EntrySort value) {
    if (value == _entrySort) return;
    _entrySort = value;
    // Inside update() the notification and the save follow anyway.
    if (_updating) return;
    unawaited(
      update((_) {}).catchError(
        // The preference stays in memory for this run; never throw from a
        // setter into a UI callback.
        (Object e) => debugPrint('Settings not saved (${e.runtimeType})'),
      ),
    );
  }

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
      // First, so that nothing unrelated in the file can keep it from loading.
      _entrySort = _parseEntrySort(j['sort']);
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
    _updating = true;
    try {
      change(this);
    } finally {
      _updating = false;
    }
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
        'sort': _entrySort.name,
        'syncEmail': syncEmail,
        'updates': checkUpdates,
        'updChecked': lastUpdateCheck,
        'updHighest': highestSeenBuild,
        'updSkipped': skippedBuild,
      }),
      flush: true,
    );
  }

  /// A saved [EntrySort] name, else the default for anything else (missing,
  /// an unknown name from a newer version, the wrong type).
  static EntrySort _parseEntrySort(Object? v) => v is String
      ? EntrySort.values.asNameMap()[v] ?? EntrySort.recent
      : EntrySort.recent;

  /// A non-negative whole number from the file, else 0.
  static int _count(Object? v) => v is int && v > 0 ? v : 0;
}
