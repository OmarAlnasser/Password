import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import '../services/biometric_unlock.dart';
import '../services/breach_checker.dart';
import '../services/clipboard_service.dart';
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
