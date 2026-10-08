import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/services/platform_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('app.vaultsnap/platform');
  const bridge = PlatformBridge();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // Synthetic data only.
  const email = 'abcde07@hotmail.com';
  const password = 'xQmR42abCD5k';

  late List<MethodCall> nativeCalls;
  late List<MethodCall> flutterClipboardCalls;
  String? flutterClipboard;

  void mockNative(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call);
      return handler(call);
    });
  }

  setUp(() {
    nativeCalls = [];
    flutterClipboardCalls = [];
    flutterClipboard = null;
    // Flutter's own clipboard (the fallback when the native side is missing).
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      flutterClipboardCalls.add(call);
      switch (call.method) {
        case 'Clipboard.getData':
          return flutterClipboard == null
              ? null
              : <String, Object?>{'text': flutterClipboard};
        case 'Clipboard.setData':
          flutterClipboard = (call.arguments as Map)['text'] as String?;
          return null;
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('readClipboard', () {
    test('returns the temp image path from the native side', () async {
      mockNative((_) => {'imagePath': '/data/cache/clip-0001.img'});
      final c = await bridge.readClipboard();
      expect(nativeCalls.single.method, 'readClipboard');
      expect(c.imagePath, '/data/cache/clip-0001.img');
      expect(c.text, isNull);
      expect(c.isEmpty, isFalse);
      expect(flutterClipboardCalls, isEmpty);
    });

    test('returns text from the native side', () async {
      mockNative((_) => {'text': '$email $password'});
      final c = await bridge.readClipboard();
      expect(c.imagePath, isNull);
      expect(c.text, '$email $password');
    });

    test('an empty native result is authoritative (no fallback)', () async {
      flutterClipboard = email;
      mockNative((_) => <String, Object?>{});
      final c = await bridge.readClipboard();
      expect(c.isEmpty, isTrue);
      expect(flutterClipboardCalls, isEmpty);
    });

    test('empty strings are treated as absent', () async {
      mockNative((_) => {'imagePath': '', 'text': ''});
      expect((await bridge.readClipboard()).isEmpty, isTrue);
    });

    test(
      'falls back to Flutter text when the native side is missing',
      () async {
        flutterClipboard = password;
        final c = await bridge.readClipboard();
        expect(c.imagePath, isNull);
        expect(c.text, password);
        expect(flutterClipboardCalls.single.method, 'Clipboard.getData');
      },
    );

    test('falls back to Flutter text on a native error', () async {
      flutterClipboard = email;
      mockNative((_) => throw PlatformException(code: 'clipboard_busy'));
      final c = await bridge.readClipboard();
      expect(nativeCalls, hasLength(1));
      expect(c.imagePath, isNull);
      expect(c.text, email);
    });

    test('fallback with an empty clipboard is empty', () async {
      expect((await bridge.readClipboard()).isEmpty, isTrue);
      flutterClipboard = '';
      expect((await bridge.readClipboard()).isEmpty, isTrue);
    });
  });

  group('clearClipboard', () {
    test('uses the native side when it handles it', () async {
      flutterClipboard = password;
      mockNative((_) => true);
      await bridge.clearClipboard();
      expect(nativeCalls.single.method, 'clearClipboard');
      expect(flutterClipboardCalls, isEmpty);
    });

    test('falls back to clearing via Flutter when native is missing', () async {
      flutterClipboard = password;
      await bridge.clearClipboard();
      expect(flutterClipboardCalls.single.method, 'Clipboard.setData');
      expect(flutterClipboard, '');
    });

    test('falls back when native reports failure or errors', () async {
      flutterClipboard = password;
      mockNative((_) => false);
      await bridge.clearClipboard();
      expect(flutterClipboard, '');

      flutterClipboard = email;
      mockNative((_) => throw PlatformException(code: 'clipboard_busy'));
      await bridge.clearClipboard();
      expect(flutterClipboard, '');
    });

    test('clears unconditionally, unlike clearClipboardIfMatches', () async {
      flutterClipboard = email;
      await bridge.clearClipboardIfMatches(password);
      expect(flutterClipboard, email);
      await bridge.clearClipboard();
      expect(flutterClipboard, '');
    });
  });
}
