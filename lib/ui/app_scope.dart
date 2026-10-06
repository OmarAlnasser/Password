import 'dart:async';

import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import '../services/biometric_unlock.dart';
import '../services/breach_checker.dart';
import '../services/clipboard_service.dart';
import '../services/favicon_service.dart';
import '../services/import_export.dart';
import '../services/password_generator.dart';
import '../services/platform_bridge.dart';
import '../services/settings.dart';
import '../services/sync/sync_service.dart';
import '../services/vault_session.dart';

/// Everything the UI needs, created once in `main`.
class AppServices {
  AppServices({
    required this.session,
    required this.settings,
    required this.clipboard,
    required this.generator,
    required this.strength,
    required this.importExport,
    required this.bridge,
    required this.breaches,
    this.biometrics,
    this.sync,
    this.favicons,
  });

  final VaultSession session;
  final AppSettings settings;
  final ClipboardService clipboard;
  final PasswordGenerator generator;
  final StrengthMeter strength;
  final ImportExport importExport;
  final PlatformBridge bridge;
  final BreachChecker breaches;
  final BiometricUnlock? biometrics;
  final SyncService? sync;

  /// Website icons for the entry list; null where none are shown (autofill).
  final FaviconService? favicons;

  /// Loads the website icon of every entry in the background. Called after
  /// unlock, save and import; hosts that are already known are skipped. With
  /// "Fetch website icons" off, [FaviconService] only reads the icons already
  /// stored in the database.
  void prefetchIcons() {
    final icons = favicons;
    if (icons == null || !session.isUnlocked) return;
    unawaited(icons.prefetch([for (final e in session.entries) e.url]));
  }
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}

extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
  AppServices get services => AppScope.of(this);
}
