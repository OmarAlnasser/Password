import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../platform_bridge.dart';

/// On-device OCR. Never uploads anything:
/// * Android/iOS: Google ML Kit text recognition, using the bundled
///   (not downloaded-on-demand) Latin model, which runs fully offline.
/// * Windows: Windows.Media.Ocr through the native runner.
///
/// An engine reads one image file per call and returns its lines. It throws
/// when it cannot read the image: the Windows engine throws an
/// [OcrNativeException] with the native code, ML Kit a [PlatformException].
/// `OcrScanner` calls it several times on differently prepared copies of one
/// image.
abstract class OcrEngine {
  /// Reads [imagePath]. With [preprocess] false the file is a copy the
  /// scanner already enlarged, inverted or tiled: an engine that prepares
  /// images on its own (Windows) must read it once, as it is.
  Future<List<String>> recognize(String imagePath, {bool preprocess = true});

  static OcrEngine forPlatform(PlatformBridge bridge) =>
      Platform.isWindows ? WindowsOcrEngine(bridge) : MlKitOcrEngine();
}

class MlKitOcrEngine implements OcrEngine {
  @override
  Future<List<String>> recognize(
    String imagePath, {
    bool preprocess = true,
  }) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(imagePath),
      );
      return [
        for (final block in result.blocks)
          for (final line in block.lines) line.text,
      ];
    } finally {
      await recognizer.close();
    }
  }
}

class WindowsOcrEngine implements OcrEngine {
  WindowsOcrEngine(this._bridge);
  final PlatformBridge _bridge;

  @override
  Future<List<String>> recognize(String imagePath, {bool preprocess = true}) =>
      _bridge.windowsOcr(imagePath, preprocess: preprocess);
}
