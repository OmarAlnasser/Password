import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

/// Non-secret user preferences, stored as JSON in the app support directory.
class AppSettings extends ChangeNotifier {
  AppSettings(this._file);

  final File _file;

  ThemeMode themeMode = ThemeMode.system;
  Locale? locale; // null = follow system
  int autoLockSeconds = 120;
  bool lockOnBackground = true;
  int clipboardClearSeconds = 30;
  bool biometricsEnabled = false;
  bool hibpEnabled = true;
  String? syncEmail;

  Future<void> load() async {
    try {
      final j = jsonDecode(await _file.readAsString()) as Map<String, Object?>;
      themeMode = ThemeMode.values.byName(
        (j['theme'] as String?) ?? ThemeMode.system.name,
      );
      final lang = j['lang'] as String?;
      locale = lang == null ? null : Locale(lang);
      autoLockSeconds = (j['autoLock'] as int?) ?? autoLockSeconds;
      lockOnBackground = (j['lockBg'] as bool?) ?? lockOnBackground;
      clipboardClearSeconds = (j['clip'] as int?) ?? clipboardClearSeconds;
      biometricsEnabled = (j['bio'] as bool?) ?? false;
      hibpEnabled = (j['hibp'] as bool?) ?? true;
      syncEmail = j['syncEmail'] as String?;
    } on Object {
      // Defaults.
    }
  }

  Future<void> update(void Function(AppSettings s) change) async {
    change(this);
    // Clamp to sane, safe ranges regardless of what the UI sent.
    autoLockSeconds = autoLockSeconds.clamp(30, 3600);
    clipboardClearSeconds = clipboardClearSeconds.clamp(10, 120);
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
        'syncEmail': syncEmail,
      }),
      flush: true,
    );
  }
}
