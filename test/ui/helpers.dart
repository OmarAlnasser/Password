import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vaultsnap/core/crypto/crypto.dart';
import 'package:vaultsnap/services/breach_checker.dart';
import 'package:vaultsnap/services/clipboard_service.dart';
import 'package:vaultsnap/services/favicon_service.dart';
import 'package:vaultsnap/services/import_export.dart';
import 'package:vaultsnap/services/password_generator.dart';
import 'package:vaultsnap/services/platform_bridge.dart';
import 'package:vaultsnap/services/settings.dart';
import 'package:vaultsnap/services/unlock_throttle.dart';
import 'package:vaultsnap/services/vault_session.dart';
import 'package:vaultsnap/ui/app_scope.dart';

/// Passes the setup screen's strength check. Synthetic.
const testMasterPassword = 'violet-harbor-quantum-71-lantern';

/// The native runner's channel (see `PlatformBridge`).
const platformChannel = MethodChannel('app.vaultsnap/platform');

/// The app's services over [dir], like `bootstrap` but without network:
/// website icons are only read from the database, never fetched.
Future<AppServices> buildTestServices(Directory dir) async {
  final sodium = await loadSodium();
  final crypto = VaultCrypto(sodium);
  final session = VaultSession(
    crypto: crypto,
    directory: dir,
    throttle: UnlockThrottle(File('${dir.path}/t.json')),
  );
  return AppServices(
    session: session,
    settings: AppSettings(File('${dir.path}/settings.json')),
    clipboard: ClipboardService(
      const PlatformBridge(),
      clearAfter: () => const Duration(seconds: 30),
    ),
    generator: PasswordGenerator(sodium, List.generate(7776, (i) => 'w$i')),
    strength: StrengthMeter(),
    importExport: ImportExport(crypto),
    bridge: const PlatformBridge(),
    breaches: BreachChecker(),
    favicons: FaviconService(
      MockClient((_) async => http.Response('', 404)),
      () => session.db,
      lookup: (_) async => const [],
      enabled: () => false,
    ),
  );
}

/// Answers [channel] with [handler] until the test ends.
void mockChannel(
  WidgetTester tester,
  MethodChannel channel,
  Future<Object?> Function(MethodCall call) handler,
) {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, handler);
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}

/// Lets real async work (Argon2id isolate, drift isolate, file I/O) run in
/// short slices and pumps a frame after each one, until [finder] matches or
/// about 30 s of real time have passed (the caller's expect then fails).
/// Frames keep coming while the work is in flight, as they do on a device.
Future<void> pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 600 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}
