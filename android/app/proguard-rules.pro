# App-specific R8 rules. The Flutter Gradle plugin adds this file to the release
# build type automatically when it exists (alongside proguard-android-optimize.txt
# and Flutter's own rules), so no build.gradle.kts change is needed.

# google_mlkit_text_recognition declares the Chinese, Devanagari, Japanese and
# Korean recognizers as compileOnly but still references their option builders
# in TextRecognizer.initialize, and ships no consumer rules. R8 (AGP 8+) treats
# those missing classes as errors and fails :app:minifyReleaseWithR8.
# Khazna only uses TextRecognitionScript.latin (lib/services/ocr/ocr_engine.dart),
# so those code paths never run and the classes can stay absent.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
