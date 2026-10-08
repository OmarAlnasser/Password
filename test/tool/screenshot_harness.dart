/// Render-and-look harness: draws widgets and whole screens to PNG files with
/// the real bundled fonts, the real theme and the real localisations, so a
/// visual change can be looked at instead of guessed.
///
/// The files are for review only. They go to `$SHOTS_DIR` (default:
/// `<system temp>/app_screenshots`), never into the repository, and are never
/// committed. A screenshot test shows fake data only.
///
/// ## Quick start
///
/// ```dart
/// @Tags(['screenshots'])          // skipped unless asked for (dart_test.yaml)
/// library;
///
/// import '../tool/screenshot_harness.dart';
///
/// void main() {
///   testWidgets('lock screen', (tester) async {
///     await pumpScreenshots(tester, const UnlockScreen(), 'unlock',
///         wrap: (app) => AppScope(services: services, child: app));
///   });
/// }
/// ```
///
/// Run it (the skipped tag needs `--run-skipped`):
///
/// ```sh
/// export PATH=/opt/flutter/bin:$PATH
/// SHOTS_DIR=/some/dir flutter test --run-skipped -t screenshots test/ui/my_shots_test.dart
/// ```
///
/// then open the PNGs. Run with `--exclude-tags screenshots` (or just without
/// `--run-skipped`) and these tests do nothing.
///
/// ## API
///
/// * [pumpScreenshot] renders ONE variant (locale, brightness, size, text
///   scale) and returns the PNG file.
/// * [pumpScreenshots] renders the matrix: [phone] and [desktop] sizes x dark
///   and light x English and Arabic, named `<name>-<size>-<theme>-<lang>.png`
///   (for example `unlock-phone-dark-ar.png`). Pass fewer `sizes`, `themes`
///   or `locales` for a smaller matrix.
/// * [loadBundledFonts] registers every font declared in `pubspec.yaml`
///   (Outfit, IBM Plex Sans Arabic, JetBrains Mono, the Material icons).
///   Both functions above call it; call it yourself in tests that measure
///   text without a screenshot.
/// * [ShotSize] (`phone` 390x844, `desktop` 1280x800, `narrow` 360x640,
///   or your own) and [shotsDir].
///
/// ## What it does for you
///
/// * Builds a `MaterialApp` configured like the real one: `AppTheme` for the
///   locale, `themeMode` from the brightness, the app's localisation
///   delegates and `AppShell` (app-wide background with the ambient glow,
///   locale-aware text theme). Arabic is real RTL.
/// * The widget you pass becomes `home`. Pass a whole screen (a `Scaffold`),
///   not a bare component: wrap components in a `Scaffold` yourself.
/// * Screens that read `context.services` need an `AppScope` **above**
///   `MaterialApp`: pass `wrap: (app) => AppScope(services: s, child: app)`.
///   `buildTestServices` in `test/ui/helpers.dart` builds services over a
///   temp directory.
/// * Pumps real async work (asset images) and a second of animation time
///   before the capture; `afterPump` runs after that, then it pumps again
///   (open a dialog, type into a field, tap a tab).
/// * Turns `debugDisableShadows` off while capturing (otherwise soft shadows
///   and glows render as hard blocks) and restores it.
/// * `textScale: 2` checks large system text. A `RenderFlex overflowed`
///   error fails the test, which is the point.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/l10n/app_localizations.dart';
import 'package:hisn/ui/theme/app_theme.dart';
import 'package:hisn/ui/widgets/app_shell.dart';

/// A logical window size (device pixel ratio 1).
class ShotSize {
  const ShotSize(this.label, this.size);

  /// Used in the file name.
  final String label;
  final Size size;

  /// A phone, 390 x 844.
  static const phone = ShotSize('phone', Size(390, 844));

  /// The smallest phone worth supporting, 360 x 640.
  static const narrow = ShotSize('narrow', Size(360, 640));

  /// A desktop window, 1280 x 800.
  static const desktop = ShotSize('desktop', Size(1280, 800));

  /// Any size, for example a tall phone to see a whole scrolling page.
  static ShotSize custom(String label, double w, double h) =>
      ShotSize(label, Size(w, h));
}

/// Where PNGs are written: `$SHOTS_DIR`, else `<system temp>/app_screenshots`.
Directory shotsDir() {
  final env = Platform.environment['SHOTS_DIR'];
  final dir = Directory(
    env != null && env.isNotEmpty
        ? env
        : '${Directory.systemTemp.path}/app_screenshots',
  );
  dir.createSync(recursive: true);
  return dir;
}

Future<void>? _fontsLoaded;

/// Registers every font family declared in `pubspec.yaml` (read from the
/// asset bundle's `FontManifest.json`) and, if the manifest did not bring it,
/// the Material icon font from the Flutter SDK. `flutter_test` does not load
/// declared fonts by itself: without this every glyph is a solid box.
///
/// Call it inside `tester.runAsync` (the screenshot functions do).
Future<void> loadBundledFonts() => _fontsLoaded ??= _loadFonts();

Future<void> _loadFonts() async {
  final loaded = <String>{};
  try {
    final manifest = jsonDecode(
      await rootBundle.loadString('FontManifest.json'),
    ) as List<Object?>;
    for (final entry in manifest.cast<Map<String, Object?>>()) {
      final family = entry['family']! as String;
      final loader = FontLoader(family);
      for (final f
          in (entry['fonts']! as List<Object?>).cast<Map<String, Object?>>()) {
        loader.addFont(rootBundle.load(f['asset']! as String));
      }
      try {
        await loader.load();
        loaded.add(family);
      } on Object {
        // One broken family must not hide the others.
      }
    }
  } on Object {
    // No manifest in this environment: fall through to the SDK icon font.
  }
  if (!loaded.contains('MaterialIcons')) {
    // .../bin/cache/artifacts/engine/<platform>/flutter_tester
    final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
    final icons = File(
      '${artifacts.path}/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
      await loader.load();
    }
  }
}

/// Renders [widget] once and writes `<shotsDir>/<name>.png`.
///
/// * [locale] `Locale('ar')` gives Arabic and real RTL.
/// * [brightness] picks the dark or light theme.
/// * [size] is the window in logical pixels; [pixelRatio] scales the PNG
///   (2 is crisp enough to read 12 px text).
/// * [textScale] sets the system text scale (try 2.0).
/// * [wrap] goes above `MaterialApp` (an `AppScope`, a `Provider`).
/// * [afterPump] runs after the first settle, then the frame is pumped again.
/// * [shell] false skips `AppShell` (to see a widget on a bare theme).
Future<File> pumpScreenshot(
  WidgetTester tester,
  Widget widget,
  String name, {
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.dark,
  Size size = const Size(390, 844),
  double pixelRatio = 2,
  double textScale = 1,
  Widget Function(Widget app)? wrap,
  Future<void> Function(WidgetTester tester)? afterPump,
  bool shell = true,
}) async {
  await tester.runAsync(loadBundledFonts);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final boundary = GlobalKey();
  Widget app = MaterialApp(
    key: UniqueKey(),
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(locale),
    darkTheme: AppTheme.dark(locale),
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) {
      var body = child!;
      if (shell) body = AppShell(child: body);
      body = MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: body,
      );
      return RepaintBoundary(key: boundary, child: body);
    },
    home: widget,
  );
  if (wrap != null) app = wrap(app);

  final shadows = debugDisableShadows;
  debugDisableShadows = false;
  try {
    await tester.pumpWidget(app);
    await _settle(tester);
    if (afterPump != null) {
      await afterPump(tester);
      await _settle(tester);
    }
    final file = File('${shotsDir().path}/$name.png');
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: pixelRatio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    });
    return file;
  } finally {
    debugDisableShadows = shadows;
  }
}

/// Lets asset images load (real async) and runs entrance animations to their
/// end, without waiting for animations that never end.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 80)),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 1));
}

/// Renders [widget] for every combination of [sizes], [themes] and [locales]
/// and returns the files, named `<name>-<size>-<theme>-<lang>.png`.
Future<List<File>> pumpScreenshots(
  WidgetTester tester,
  Widget widget,
  String name, {
  List<ShotSize> sizes = const [ShotSize.phone, ShotSize.desktop],
  List<Brightness> themes = const [Brightness.dark, Brightness.light],
  List<Locale> locales = const [Locale('en'), Locale('ar')],
  double pixelRatio = 2,
  double textScale = 1,
  Widget Function(Widget app)? wrap,
  Future<void> Function(WidgetTester tester)? afterPump,
  bool shell = true,
}) async {
  final files = <File>[];
  for (final s in sizes) {
    for (final b in themes) {
      for (final l in locales) {
        files.add(
          await pumpScreenshot(
            tester,
            widget,
            '$name-${s.label}-${b.name}-${l.languageCode}',
            locale: l,
            brightness: b,
            size: s.size,
            pixelRatio: pixelRatio,
            textScale: textScale,
            wrap: wrap,
            afterPump: afterPump,
            shell: shell,
          ),
        );
      }
    }
  }
  return files;
}
