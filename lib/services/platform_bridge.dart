import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What [PlatformBridge.readClipboard] found: an image (preferred) or text.
class ClipboardContent {
  const ClipboardContent({this.imagePath, this.text});

  /// Plaintext copy of the clipboard image in the app's private temp/cache
  /// dir. The caller owns it and must delete it as soon as OCR is done.
  final String? imagePath;

  /// Clipboard text, when there is no image.
  final String? text;

  bool get isEmpty => imagePath == null && text == null;
}

/// Single method channel to the native runners (Android MainActivity,
/// iOS AppDelegate, Windows flutter_window.cpp). All methods degrade
/// gracefully if the native side is missing (tests, unsupported OS).
class PlatformBridge {
  const PlatformBridge();

  static const MethodChannel _ch = MethodChannel('app.vaultsnap/platform');

  /// Native -> Dart events (iOS screen recording / mirroring state).
  static void listen({required void Function(bool captured) onCapture}) {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'captureChanged') {
        onCapture((call.arguments as Map)['captured'] == true);
      }
    });
  }

  /// Copies [text] marking it sensitive / excluded from clipboard history
  /// where the OS supports it:
  /// * Android 13+: ClipDescription.EXTRA_IS_SENSITIVE (hidden in preview).
  /// * iOS: UIPasteboard localOnly (no Universal Clipboard) + expiration.
  /// * Windows: ExcludeClipboardContentFromMonitorProcessing,
  ///   CanIncludeInClipboardHistory=0, CanUploadToCloudClipboard=0.
  Future<void> copySensitive(String text, Duration expiresIn) async {
    try {
      final handled = await _ch.invokeMethod<bool>('copySensitive', {
        'text': text,
        'expiresInMs': expiresIn.inMilliseconds,
      });
      if (handled ?? false) return;
    } on MissingPluginException {
      // fall through
    } on PlatformException {
      // fall through
    }
    await Clipboard.setData(ClipboardData(text: text));
  }

  /// Clears the clipboard only if it still contains [text] (so we don't
  /// wipe something the user copied afterwards). Native implementations
  /// compare without exposing clipboard contents to Dart where possible.
  Future<void> clearClipboardIfMatches(String text) async {
    try {
      final handled = await _ch.invokeMethod<bool>('clearClipboardIfMatches', {
        'text': text,
      });
      if (handled ?? false) return;
    } on MissingPluginException {
      // fall through
    } on PlatformException {
      // fall through
    }
    final current = await Clipboard.getData(Clipboard.kTextPlain);
    if (current?.text == text) {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  }

  /// Reads what the user copied, for the "Paste" button: a screenshot is
  /// copied to a temp file ([ClipboardContent.imagePath], delete it after
  /// OCR), otherwise the text. Call it only from a user action: Android 10+
  /// returns nothing unless we have focus, and iOS may ask to allow pasting.
  /// Without the native side only text can be read.
  Future<ClipboardContent> readClipboard() async {
    try {
      final m = await _ch.invokeMapMethod<String, Object?>('readClipboard');
      if (m != null) {
        return ClipboardContent(
          imagePath: _nonEmpty(m['imagePath'] as String?),
          text: _nonEmpty(m['text'] as String?),
        );
      }
    } on MissingPluginException {
      // fall through
    } on PlatformException {
      // fall through
    }
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      return ClipboardContent(text: _nonEmpty(data?.text));
    } on PlatformException {
      return const ClipboardContent();
    }
  }

  /// Clears the clipboard unconditionally, e.g. after a login read from a
  /// pasted screenshot was saved (the image still shows the password).
  Future<void> clearClipboard() async {
    try {
      final handled = await _ch.invokeMethod<bool>('clearClipboard');
      if (handled ?? false) return;
    } on MissingPluginException {
      // fall through
    } on PlatformException {
      // fall through
    }
    await Clipboard.setData(const ClipboardData(text: ''));
  }

  static String? _nonEmpty(String? s) => (s == null || s.isEmpty) ? null : s;

  /// FLAG_SECURE / WDA_EXCLUDEFROMCAPTURE. Enabled natively at startup; this
  /// lets the app re-assert it (e.g. after a window is recreated).
  Future<void> setSecureScreen(bool enabled) async {
    try {
      await _ch.invokeMethod<void>('setSecureScreen', {'enabled': enabled});
    } on MissingPluginException {
      // ignore
    }
  }

  /// Asks the OS to delete a user image (MediaStore delete request on
  /// Android 11+, which shows a system confirmation). Returns true if the
  /// image was deleted.
  Future<bool> deleteSourceImage(String uriOrPath) async {
    try {
      final ok = await _ch.invokeMethod<bool>('deleteImage', {
        'uri': uriOrPath,
      });
      if (ok != null) return ok;
    } on MissingPluginException {
      // fall through
    } on PlatformException {
      return false;
    }
    if (!uriOrPath.contains('://')) {
      final f = File(uriOrPath);
      if (f.existsSync()) {
        f.deleteSync();
        return true;
      }
    }
    return false;
  }

  /// Windows only: run Windows.Media.Ocr on an image file. Returns lines.
  Future<List<String>> windowsOcr(String path) async {
    final lines = await _ch.invokeListMethod<String>('ocr', {'path': path});
    return lines ?? const [];
  }

  bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
}
