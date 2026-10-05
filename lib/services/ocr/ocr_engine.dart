import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../platform_bridge.dart';

/// On-device OCR. Never uploads anything:
/// * Android/iOS: Google ML Kit text recognition, using the bundled
///   (not downloaded-on-demand) Latin model, which runs fully offline.
/// * Windows: Windows.Media.Ocr through the native runner.
abstract class OcrEngine {
  Future<List<String>> recognize(String imagePath);

  static OcrEngine forPlatform(PlatformBridge bridge) =>
      Platform.isWindows ? WindowsOcrEngine(bridge) : MlKitOcrEngine();
}

class MlKitOcrEngine implements OcrEngine {
  @override
  Future<List<String>> recognize(String imagePath) async {
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
  Future<List<String>> recognize(String imagePath) =>
      _bridge.windowsOcr(imagePath);
}
