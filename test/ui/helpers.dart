import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

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

/// What ML Kit's method channel returns for [lines] (one block).
Map<String, Object?> mlKitResult(List<String> lines) {
  Map<String, Object?> node(String text) => {
    'text': text,
    'rect': <String, Object?>{},
    'recognizedLanguages': <Object?>[],
    'points': <Object?>[],
  };
  return {
    'text': lines.join('\n'),
    'blocks': [
      {
        ...node(lines.join('\n')),
        'lines': [
          for (final l in lines) {...node(l), 'elements': <Object?>[]},
        ],
      },
    ],
  };
}

/// Plays the OCR engine: ML Kit's method channel, which is the engine on the
/// test host (it is not Windows). For each image the scanner hands over,
/// [read] says what the engine reads; [call] counts the images from 0 and
/// [path] is the file (the original first, then the scanner's enlarged
/// copies). [read] may throw, like an engine that fails.
///
/// The returned list fills with every path the engine was asked to read.
List<String> mockOcr(
  WidgetTester tester,
  FutureOr<List<String>> Function(int call, String path) read,
) {
  final seen = <String>[];
  mockChannel(tester, const MethodChannel('google_mlkit_text_recognizer'), (
    call,
  ) async {
    if (call.method != 'vision#startTextRecognizer') return null;
    final args = call.arguments as Map<Object?, Object?>;
    final path =
        (args['imageData'] as Map<Object?, Object?>)['path']! as String;
    final n = seen.length;
    seen.add(path);
    return mlKitResult(await read(n, path));
  });
  return seen;
}

/// A 175 x 62 PNG like a tiny crop of a dark-mode screenshot: two lines of
/// light grey "text" (blocks) on a near-black background. Real image work:
/// call it inside `tester.runAsync`.
Future<Uint8List> darkCropPng() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 175, 62),
    ui.Paint()..color = const ui.Color.fromARGB(255, 18, 18, 19),
  );
  final ink = ui.Paint()
    ..color = const ui.Color.fromARGB(255, 200, 200, 200)
    ..isAntiAlias = false;
  void line(double top, double height, double x1) {
    for (var x = 6.0; x < x1; x += 5) {
      canvas.drawRect(ui.Rect.fromLTWH(x, top, 3, height), ink);
    }
  }

  line(0, 14, 150);
  line(26, 15, 100);
  final picture = recorder.endRecording();
  final image = await picture.toImage(175, 62);
  final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  image.dispose();
  picture.dispose();
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
