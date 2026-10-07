import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'autofill_app.dart';
import 'core/crypto/crypto.dart';
import 'services/biometric_unlock.dart';
import 'services/breach_checker.dart';
import 'services/clipboard_service.dart';
import 'services/favicon_service.dart';
import 'services/import_export.dart';
import 'services/ios_autofill_snapshot.dart';
import 'services/ocr/image_preprocessor.dart';
import 'services/password_generator.dart';
import 'services/platform_bridge.dart';
import 'services/settings.dart';
import 'services/sync/supabase_remote_store.dart';
import 'services/sync/sync_service.dart';
import 'services/unlock_throttle.dart';
import 'services/update/update_providers.dart';
import 'services/vault_session.dart';
import 'ui/app_scope.dart';

/// Supabase project, injected at build time:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
/// The anon key is public by design; RLS protects the data.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  final services = await bootstrap();
  // Plaintext copies of a screenshot that a crash or a kill left in the temp
  // directory in the middle of a scan (the native side sweeps the clipboard
  // copies the same way). 10 minutes: another window may be scanning.
  unawaited(ImageWorkspace.sweepStale(olderThan: const Duration(minutes: 10)));
  IosAutofillSnapshot(services.session);
  unawaited(services.session.init());
  runApp(VaultSnapApp(services: services));
}

/// Entry point used by Android's AutofillAuthActivity.
@pragma('vm:entry-point')
Future<void> autofillMain() async {
  final services = await bootstrap(forAutofill: true);
  await services.session.init();
  runApp(AutofillApp(services: services));
}

Future<AppServices> bootstrap({bool forAutofill = false}) async {
  WidgetsFlutterBinding.ensureInitialized();

  // No secrets in logs: silence debugPrint in release builds entirely, and
  // never forward Flutter errors to any remote crash reporter (there is none).
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }
  FlutterError.onError = (details) {
    // Print only the exception type; messages may contain user data.
    if (!kReleaseMode) {
      debugPrint('FlutterError: ${details.exception.runtimeType}');
    }
  };

  if (!kIsWeb && Platform.isWindows && !forAutofill) {
    await windowManager.ensureInitialized();
  }

  final sodium = await loadSodium();
  final crypto = VaultCrypto(sodium);
  final supportDir = await getApplicationSupportDirectory();
  final dir = Directory(p.join(supportDir.path, 'vault'));
  await dir.create(recursive: true);

  final settings = AppSettings(File(p.join(dir.path, 'settings.json')));
  await settings.load();

  final bridge = const PlatformBridge();
  await bridge.setSecureScreen(true);

  final biometrics = BiometricUnlock(dir);
  final session = VaultSession(
    crypto: crypto,
    directory: dir,
    throttle: UnlockThrottle(File(p.join(dir.path, 'throttle.json'))),
    biometrics: biometrics,
  );

  // Self-update (Android and Windows release builds). Null in development
  // builds, on other platforms and in the autofill entry point. The installer
  // calls `prepareExit` right before the process exits or the system
  // installer opens, so the keys are wiped first. Nothing here starts a
  // check: `UpdateGate` (lib/ui/update) does that, throttled, after start-up.
  final updates = createUpdateController(
    sodium: sodium,
    supportDir: supportDir,
    settings: settings,
    prepareExit: session.lock,
    forAutofill: forAutofill,
  );

  SyncService? sync;
  if (!forAutofill && _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(
      url: _supabaseUrl,
      publishableKey: _supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        localStorage: InMemoryOnlyStorage(),
        persistSession: false,
        detectSessionInUri: false,
      ),
    );
    sync = SyncService(session, SupabaseRemoteStore(Supabase.instance.client));
  }

  final words = (await rootBundle.loadString('assets/eff_large_wordlist.txt'))
      .split('\n')
      .map((w) => w.trim())
      .where((w) => w.isNotEmpty)
      .toList();

  return AppServices(
    session: session,
    settings: settings,
    clipboard: ClipboardService(
      bridge,
      clearAfter: () => Duration(seconds: settings.clipboardClearSeconds),
    ),
    generator: PasswordGenerator(sodium, words),
    strength: StrengthMeter(),
    importExport: ImportExport(crypto),
    bridge: bridge,
    breaches: BreachChecker(),
    biometrics: biometrics,
    sync: sync,
    // Only the main app shows icons. They come straight from each site and
    // are stored in the encrypted database.
    favicons: forAutofill
        ? null
        : FaviconService(
            http.Client(),
            () => session.db,
            enabled: () => settings.fetchIcons,
          ),
    updates: updates,
  );
}
