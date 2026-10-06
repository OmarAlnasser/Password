import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultsnap/services/ocr/image_preprocessor.dart';
import 'package:vaultsnap/services/ocr/ocr_engine.dart';
import 'package:vaultsnap/services/ocr/ocr_parser.dart';
import 'package:vaultsnap/services/ocr/ocr_scanner.dart';
import 'package:vaultsnap/services/platform_bridge.dart';

// Synthetic data only.
const email = 'abcde07@hotmail.com';
const password = 'xQmR42abCD5k';
const wrongPassword = 'xQmR42abCDSk';

/// A line of "text" for the synthetic images: a run of small boxes.
class _Ink {
  const _Ink(this.top, this.height, this.x0, this.x1);
  final int top;
  final int height;
  final int x0;
  final int x1;
}

/// What the fake engine saw in the file it was given.
class _Seen {
  const _Seen(
    this.path,
    this.width,
    this.height,
    this.mean,
    this.corner, {
    this.darkShare = 0,
    this.lightShare = 0,
  });
  final String path;
  final int width;
  final int height;

  /// Mean luma over the image, 0..255.
  final double mean;

  /// Luma of the pixel at (2, 2): the border, for a padded copy.
  final int corner;

  /// The share of pixels darker than 60, and lighter than 195.
  final double darkShare;
  final double lightShare;

  bool get isBright => mean > 128;
}

Future<_Seen> _inspect(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    final data = (await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    ))!;
    final px = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    int luma(int i) =>
        (px[i] * 299 + px[i + 1] * 587 + px[i + 2] * 114 + 500) ~/ 1000;
    var sum = 0.0;
    var n = 0;
    var dark = 0;
    var light = 0;
    for (var i = 0; i + 3 < px.length; i += 4 * 7) {
      final l = luma(i);
      sum += l;
      if (l < 60) dark++;
      if (l > 195) light++;
      n++;
    }
    final w = image.width;
    final h = image.height;
    final corner = w > 2 && h > 2 ? luma((2 * w + 2) * 4) : 0;
    image.dispose();
    return _Seen(
      path,
      w,
      h,
      n == 0 ? 0 : sum / n,
      corner,
      darkShare: n == 0 ? 0 : dark / n,
      lightShare: n == 0 ? 0 : light / n,
    );
  } on Object {
    return _Seen(path, 0, 0, 0, 0);
  }
}

Future<Uint8List> _pngBytes(
  int w,
  int h, {
  required ui.Color bg,
  required ui.Color fg,
  List<_Ink> lines = const [],
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = bg,
  );
  final paint = ui.Paint()
    ..color = fg
    ..isAntiAlias = false;
  for (final l in lines) {
    for (var x = l.x0; x < l.x1; x += 5) {
      canvas.drawRect(
        ui.Rect.fromLTWH(
          x.toDouble(),
          l.top.toDouble(),
          3,
          l.height.toDouble(),
        ),
        paint,
      );
    }
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  image.dispose();
  picture.dispose();
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

const _darkBg = ui.Color.fromARGB(255, 18, 18, 19);
const _lightText = ui.Color.fromARGB(255, 200, 200, 200);

/// The shape of the owner's sample: a 175 x 62 dark crop, two lines of light
/// grey text about 14 px tall, the first one cut by the top edge.
Future<Uint8List> _tinyDarkCrop() => _pngBytes(
  175,
  62,
  bg: _darkBg,
  fg: _lightText,
  lines: const [_Ink(0, 14, 6, 150), _Ink(26, 15, 6, 100)],
);

/// A 480 x 140 light image with 34 px text: needs no help.
Future<Uint8List> _easyImage() => _pngBytes(
  480,
  140,
  bg: const ui.Color.fromARGB(255, 250, 250, 250),
  fg: const ui.Color.fromARGB(255, 20, 20, 20),
  lines: const [_Ink(20, 34, 10, 400), _Ink(80, 34, 10, 300)],
);

/// Larger than the engines accept: 3200 x 1800 of light-on-dark text.
Future<Uint8List> _bigScreenshot() => _pngBytes(
  3200,
  1800,
  bg: _darkBg,
  fg: _lightText,
  lines: const [_Ink(400, 40, 300, 1500), _Ink(520, 40, 300, 1100)],
);

class _Env {
  _Env()
    : images = Directory.systemTemp.createTempSync('vsnap-scan-images-'),
      scratch = Directory.systemTemp.createTempSync('vsnap-scan-scratch-');

  final Directory images;

  /// Where the scanner writes its copies; must be empty again after a scan.
  final Directory scratch;

  Future<File> write(String name, Uint8List bytes) async {
    final f = File('${images.path}${Platform.pathSeparator}$name');
    await f.writeAsBytes(bytes);
    return f;
  }

  ImagePreprocessor pre({PreprocessLimits? limits}) => ImagePreprocessor(
    tempRoot: scratch,
    limits: limits ?? const PreprocessLimits(),
  );

  OcrScanner scanner(
    OcrEngine engine, {
    ImagePreprocessor? pre,
    int maxPasses = 4,
    Duration timeout = const Duration(seconds: 20),
  }) => OcrScanner(
    engine,
    pre: pre ?? this.pre(),
    maxPasses: maxPasses,
    timeout: timeout,
  );

  /// Files (not directories) left anywhere in the scratch directory.
  List<String> leftovers() => [
    for (final e in scratch.listSync(recursive: true))
      if (e is File) e.path,
  ];

  void dispose() {
    for (final d in [images, scratch]) {
      try {
        d.deleteSync(recursive: true);
      } on Object {
        // best effort
      }
    }
  }
}

typedef _Script = FutureOr<List<String>> Function(_Seen seen, int call);

class _FakeEngine implements OcrEngine {
  _FakeEngine(this.script);
  final _Script script;
  final List<_Seen> calls = [];

  /// The `preprocess` flag of each call.
  final List<bool> preprocessFlags = [];

  @override
  Future<List<String>> recognize(
    String imagePath, {
    bool preprocess = true,
  }) async {
    final seen = await _inspect(imagePath);
    calls.add(seen);
    preprocessFlags.add(preprocess);
    return script(seen, calls.length);
  }
}

/// A scanner test: runs [body] in real async (dart:ui decoding does not work
/// under fake async) and then checks that no scratch file is left.
void _scannerTest(String name, Future<void> Function(_Env env) body) {
  testWidgets(name, (tester) async {
    final env = _Env();
    try {
      await tester.runAsync(() async {
        await body(env);
        expect(env.leftovers(), isEmpty, reason: 'temp copies must be deleted');
      });
    } finally {
      env.dispose();
    }
  });
}

const _login = [email, password];

ImageStats _stats({
  double? textHeight,
  int width = 175,
  int height = 62,
  bool dark = true,
}) => ImageStats(
  width: width,
  height: height,
  sampleWidth: width,
  sampleHeight: height,
  bgLuma: dark ? 18 : 250,
  bgRed: dark ? 18 : 250,
  bgGreen: dark ? 18 : 250,
  bgBlue: dark ? 19 : 250,
  dark: dark,
  contrastLow: dark ? 18 : 20,
  contrastHigh: dark ? 200 : 250,
  contrastUseful: true,
  textHeight: textHeight,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImageStats.analyze', () {
    Uint8List rgba(
      int w,
      int h,
      List<int> bg, {
      List<int> ink = const [200, 200, 200],
      List<(int, int)> bands = const [],
      int alpha = 255,
    }) {
      final out = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        final inBand = bands.any((b) => y >= b.$1 && y < b.$1 + b.$2);
        for (var x = 0; x < w; x++) {
          final c = inBand && x % 5 < 3 && x > 3 && x < w - 4 ? ink : bg;
          final i = (y * w + x) * 4;
          out[i] = c[0];
          out[i + 1] = c[1];
          out[i + 2] = c[2];
          out[i + 3] = alpha;
        }
      }
      return out;
    }

    test('measures a dark crop: dark, background, line height', () {
      final s = ImageStats.analyze(
        rgba(100, 60, [18, 18, 19], bands: [(2, 12), (30, 12)]),
        100,
        60,
        width: 100,
        height: 60,
      );
      expect(s.dark, isTrue);
      expect(s.bgLuma, closeTo(18, 1));
      expect(s.textHeight, 12);
      expect(s.contrastUseful, isTrue);
      expect(s.contrastLow, s.bgLuma);
    });

    test('a light page is not dark and has its own anchors', () {
      final s = ImageStats.analyze(
        rgba(100, 60, [250, 250, 250], ink: [20, 20, 20], bands: [(5, 20)]),
        100,
        60,
        width: 100,
        height: 60,
      );
      expect(s.dark, isFalse);
      expect(s.contrastHigh, s.bgLuma);
      expect(s.textHeight, 20);
    });

    test('a flat image has no text and no useful contrast', () {
      final s = ImageStats.analyze(
        rgba(50, 50, [30, 30, 30]),
        50,
        50,
        width: 50,
        height: 50,
      );
      expect(s.textHeight, isNull);
      expect(s.contrastUseful, isFalse);
    });

    test('heights of a reduced copy are scaled back to the image', () {
      final s = ImageStats.analyze(
        rgba(100, 60, [18, 18, 19], bands: [(2, 12), (30, 12)]),
        100,
        60,
        width: 400,
        height: 240,
      );
      expect(s.textHeight, 48);
    });

    test('transparent pixels are read as white', () {
      final s = ImageStats.analyze(
        rgba(10, 10, [0, 0, 0], alpha: 0),
        10,
        10,
        width: 10,
        height: 10,
      );
      expect(s.bgLuma, 255);
      expect(s.dark, isFalse);
    });

    test('rejects a buffer that is too short', () {
      expect(
        () => ImageStats.analyze(Uint8List(8), 10, 10, width: 10, height: 10),
        throwsArgumentError,
      );
    });
  });

  group('ImagePreprocessor planning', () {
    final pre = ImagePreprocessor();

    test('scale: about 42 px a line, 6x only for micro text', () {
      expect(pre.scaleFor(_stats(textHeight: 14.5)), 3);
      expect(pre.scaleFor(_stats(textHeight: 25)), 2);
      expect(pre.scaleFor(_stats(textHeight: 31)), 1);
      expect(pre.scaleFor(_stats(textHeight: 11)), 4);
      expect(pre.scaleFor(_stats(textHeight: 7)), 6);
      expect(pre.scaleFor(_stats(textHeight: 9)), 4);
    });

    test('scale: unmeasured text is assumed small only in a small crop', () {
      expect(pre.scaleFor(_stats()), 4);
      expect(pre.scaleFor(_stats(width: 900, height: 500)), 1);
    });

    test('scale never makes the output exceed the engine limits', () {
      // 900 x 300 at 4x would be 3600 px wide.
      expect(pre.scaleFor(_stats(textHeight: 11, width: 900, height: 300)), 2);
      // Nothing fits: no scaling at all.
      expect(pre.scaleFor(_stats(textHeight: 11, width: 2500, height: 300)), 1);
    });

    test(
      'a dark tiny crop: inverted first, then plain, then another scale',
      () {
        final plan = pre.plan(_stats(textHeight: 14.5));
        expect(
          [for (final p in plan) p.name],
          ['inverted', 'upscaled', 'inverted-alt'],
        );
        expect([for (final p in plan) p.scale], [3, 3, 4]);
        expect(plan[0].invert, isTrue);
        expect(plan[0].contrast, isTrue);
        expect(plan[1].hasColorChange, isFalse);
        expect([for (final p in plan) p.pad], everyElement(16));
      },
    );

    test('a light crop is never inverted', () {
      final plan = pre.plan(_stats(textHeight: 14.5, dark: false));
      expect(
        [for (final p in plan) p.name],
        ['upscaled', 'contrast', 'contrast-alt'],
      );
      expect([for (final p in plan) p.invert], everyElement(isFalse));
    });

    test('text that needs no scaling still gets a border and contrast', () {
      final plan = pre.plan(
        _stats(textHeight: 34, width: 600, height: 300, dark: false),
      );
      expect([for (final p in plan) p.name], ['padded', 'contrast']);
      expect([for (final p in plan) p.scale], [1, 1]);
    });

    test('an image too big for the engines is tiled, not shrunk', () {
      final plan = pre.plan(_stats(textHeight: 14, width: 3840, height: 2160));
      expect([for (final p in plan) p.name], ['tiles-enhanced', 'tiles']);
      expect(plan.first.tiled, isTrue);
      expect(plan.first.scale, 1);
      expect(plan.first.tileSide, lessThanOrEqualTo(2600));
      expect(plan.first.invert, isTrue);
    });

    test('too many tiles fall back to a shrunk copy', () {
      final few = ImagePreprocessor(
        limits: const PreprocessLimits(maxTiles: 1),
      );
      final plan = few.plan(_stats(width: 3840, height: 2160));
      expect([for (final p in plan) p.name], ['shrunk-enhanced', 'shrunk']);
      expect(plan.first.tiled, isFalse);
      expect(plan.first.scale, 2400 / 3840);
    });

    test('a giant image is planned on the bounded copy', () {
      // 20000 x 12000 is decoded at about 6300 x 3800 and tiled from that.
      final plan = pre.plan(_stats(width: 20000, height: 12000));
      expect(plan.first.name, 'tiles-enhanced');
    });
  });

  group('ImagePreprocessor rendering', () {
    _scannerTest('measures and renders the dark crop the lab recommends', (
      env,
    ) async {
      final file = await env.write('crop.png', await _tinyDarkCrop());
      final pre = env.pre();
      final source = (await pre.open(file.path))!;
      final work = await pre.createWorkspace();
      try {
        final s = source.stats;
        expect(s.dark, isTrue);
        expect(s.bgLuma, closeTo(18, 1));
        expect(s.textHeight, closeTo(14.5, 1.5));
        expect(pre.scaleFor(s), 3);
        final plan = pre.plan(s);
        expect(
          [for (final p in plan) p.name],
          ['inverted', 'upscaled', 'inverted-alt'],
        );

        final inverted = await pre.render(source, plan[0], work);
        final plain = await pre.render(source, plan[1], work);
        final alt = await pre.render(source, plan[2], work);
        final a = await _inspect(inverted.paths.single);
        final b = await _inspect(plain.paths.single);
        final c = await _inspect(alt.paths.single);

        // 3x plus 16 px of border on each side.
        expect((a.width, a.height), (175 * 3 + 32, 62 * 3 + 32));
        expect((b.width, b.height), (a.width, a.height));
        expect((c.width, c.height), (175 * 4 + 32, 62 * 4 + 32));
        // Dark text on a light page, and the border is the page: most pixels
        // white, and the text (about a fifth of the image) now near black,
        // stretched to the full range.
        expect(a.isBright, isTrue);
        expect(a.corner, greaterThan(235));
        expect(a.lightShare, greaterThan(0.6));
        expect(a.darkShare, inInclusiveRange(0.06, 0.4));
        // The plain copy keeps the colours, and its border is the background.
        expect(b.isBright, isFalse);
        expect(b.corner, closeTo(18, 2));
        expect(b.darkShare, greaterThan(0.6));
        expect(b.lightShare, inInclusiveRange(0.06, 0.4));
        expect(c.isBright, isTrue);

        // Every copy is a private file of the workspace.
        for (final v in [inverted, plain, alt]) {
          expect(v.files.single.path, startsWith(work.dir.path));
        }
        expect(await inverted.delete(), isTrue);
        expect(inverted.files.single.existsSync(), isFalse);
      } finally {
        source.dispose();
        await work.dispose();
      }
      expect(work.dir.existsSync(), isFalse);
    });

    _scannerTest('low contrast text is stretched to the full range', (
      env,
    ) async {
      // Grey on slightly lighter grey: 50 levels apart.
      final file = await env.write(
        'grey.png',
        await _pngBytes(
          175,
          62,
          bg: const ui.Color.fromARGB(255, 70, 70, 72),
          fg: const ui.Color.fromARGB(255, 120, 120, 120),
          lines: const [_Ink(4, 14, 6, 150), _Ink(26, 15, 6, 100)],
        ),
      );
      final pre = env.pre();
      final source = (await pre.open(file.path))!;
      final work = await pre.createWorkspace();
      try {
        expect(source.stats.contrastUseful, isTrue);
        expect(source.stats.dark, isTrue);
        final plan = pre.plan(source.stats);
        final v = await pre.render(source, plan.first, work);
        final seen = await _inspect(v.files.single.path);
        // Background to white and text to black, not 185 and 135.
        expect(seen.corner, greaterThan(245));
        expect(seen.lightShare, greaterThan(0.6));
        expect(seen.darkShare, inInclusiveRange(0.06, 0.4));
      } finally {
        source.dispose();
        await work.dispose();
      }
    });

    _scannerTest('an image too big is tiled at its own resolution', (
      env,
    ) async {
      final file = await env.write('big.png', await _bigScreenshot());
      final pre = env.pre();
      final source = (await pre.open(file.path))!;
      final work = await pre.createWorkspace();
      try {
        // Only a reduced copy was measured.
        expect(source.sampleWidth, lessThanOrEqualTo(1400));
        expect(source.stats.width, 3200);
        final plan = pre.plan(source.stats);
        expect(plan.first.name, 'tiles-enhanced');
        final tiles = await pre.render(source, plan.first, work);
        expect(tiles.files.length, 2);
        for (final f in tiles.files) {
          final seen = await _inspect(f.path);
          expect(seen.width, lessThanOrEqualTo(2600));
          expect(seen.height, lessThanOrEqualTo(2600));
          // Native resolution: 2400 px tile plus the border, not a shrunk copy.
          expect(seen.width, 2400 + 32);
          expect(seen.isBright, isTrue);
        }
      } finally {
        source.dispose();
        await work.dispose();
      }
    });

    _scannerTest('decoding is bounded however big the image is', (env) async {
      final file = await env.write('big.png', await _bigScreenshot());
      final pre = env.pre(
        limits: const PreprocessLimits(
          maxDecodePixels: 500 * 1000,
          probeSide: 400,
        ),
      );
      final source = (await pre.open(file.path))!;
      final work = await pre.createWorkspace();
      try {
        expect(source.sampleWidth, lessThanOrEqualTo(400));
        expect(source.sampleHeight, lessThanOrEqualTo(400));
        expect(
          source.baseWidth * source.baseHeight,
          lessThanOrEqualTo(500 * 1000),
        );
        // Still renders (from the bounded copy), within the engine limits.
        final plan = pre.plan(source.stats);
        final v = await pre.render(source, plan.first, work);
        for (final f in v.files) {
          final seen = await _inspect(f.path);
          expect(seen.width, lessThanOrEqualTo(2600));
          expect(seen.width * seen.height, lessThan(16 * 1000 * 1000));
        }
      } finally {
        source.dispose();
        await work.dispose();
      }
    });

    _scannerTest('files that are not images, or too big, are not opened', (
      env,
    ) async {
      final text = File('${env.images.path}/notes.png')
        ..writeAsStringSync('not an image at all');
      expect(await env.pre().open(text.path), isNull);
      expect(await env.pre().peek(text.path), isNull);
      expect(await env.pre().open('${env.images.path}/missing.png'), isNull);
      final file = await env.write('crop.png', await _tinyDarkCrop());
      final capped = env.pre(
        limits: const PreprocessLimits(maxInputBytes: 100),
      );
      expect(await capped.open(file.path), isNull);
      expect(await capped.peek(file.path), isNull);
    });

    _scannerTest('peek reads the size without decoding', (env) async {
      final file = await env.write('crop.png', await _tinyDarkCrop());
      final size = await env.pre().peek(file.path);
      expect(size, (width: 175, height: 62));
    });

    _scannerTest('a workspace is private, numbered and removable', (env) async {
      final work = await env.pre().createWorkspace();
      final a = work.newFile('x');
      final b = work.newFile('x');
      expect(a.path, isNot(b.path));
      expect(a.path, startsWith(env.scratch.path));
      await a.writeAsBytes([1]);
      expect(await work.dispose(), isTrue);
      expect(work.isDisposed, isTrue);
      expect(() => work.newFile('y'), throwsStateError);
      expect(await work.dispose(), isTrue);
    });

    _scannerTest('leftovers of a crashed scan are swept', (env) async {
      // Needs touch(1) to age the directory.
      if (!Platform.isLinux) return;
      final stale = Directory(
        '${env.scratch.path}/${ImageWorkspace.rootName}/s-old',
      )..createSync(recursive: true);
      File('${stale.path}/leftover.png').writeAsBytesSync([1, 2, 3]);
      final r = await Process.run('touch', ['-d', '2 hours ago', stale.path]);
      expect(r.exitCode, 0);
      final work = await env.pre().createWorkspace();
      await work.dispose();
      expect(stale.existsSync(), isFalse);
      // A recent one (another scan in flight) is left alone.
      final fresh = Directory(
        '${env.scratch.path}/${ImageWorkspace.rootName}/s-fresh',
      )..createSync(recursive: true);
      final work2 = await env.pre().createWorkspace();
      await work2.dispose();
      expect(fresh.existsSync(), isTrue);
    });
  });

  group('startup sweep', () {
    _scannerTest('old workspaces are removed without a scan', (env) async {
      // Needs touch(1) to age the directories.
      if (!Platform.isLinux) return;
      Directory aged(String name, String age) {
        final d = Directory(
          '${env.scratch.path}/${ImageWorkspace.rootName}/$name',
        )..createSync(recursive: true);
        File('${d.path}/leftover.png').writeAsBytesSync([1, 2, 3]);
        final r = Process.runSync('touch', ['-d', age, d.path]);
        expect(r.exitCode, 0);
        return d;
      }

      final old = aged('s-old', '2 hours ago');
      final twelve = aged('s-12min', '12 minutes ago');
      final fresh = aged('s-fresh', '1 minute ago');

      await ImageWorkspace.sweepStale(root: env.scratch);
      expect(old.existsSync(), isFalse);
      // The same 15-minute rule as a scan applies by default.
      expect(twelve.existsSync(), isTrue);
      expect(fresh.existsSync(), isTrue);

      await ImageWorkspace.sweepStale(
        root: env.scratch,
        olderThan: const Duration(minutes: 10),
      );
      expect(twelve.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue, reason: 'another window may scan');
      fresh.deleteSync(recursive: true);
    });

    _scannerTest('no scratch directory yet: nothing to sweep', (env) async {
      await ImageWorkspace.sweepStale(root: env.scratch);
      await ImageWorkspace.sweepStale(
        root: Directory('${env.scratch.path}/missing'),
      );
    });
  });

  group('OcrScanner', () {
    _scannerTest('an easy image is read in one pass, with no copies', (
      env,
    ) async {
      final file = await env.write('easy.png', await _easyImage());
      final engine = _FakeEngine((_, _) => _login);
      final r = await env.scanner(engine).scan(file.path);
      expect(engine.calls.length, 1);
      expect(engine.calls.single.path, file.path);
      expect(r.passesRun, 1);
      expect(r.stop, ScanStop.satisfied);
      expect(r.error, isNull);
      expect(r.best.email, email);
      expect(r.best.password, password);
      expect(r.best.quality, greaterThan(0.85));
      expect(r.rawPasses, [_login]);
      expect(r.passes.single.name, 'original');
      // No workspace was even created.
      expect(env.scratch.listSync(), isEmpty);
    });

    _scannerTest('a large image with small text is not a crop', (env) async {
      final file = await env.write(
        'screen.png',
        await _pngBytes(
          900,
          500,
          bg: _darkBg,
          fg: _lightText,
          lines: const [_Ink(100, 14, 20, 300), _Ink(140, 14, 20, 200)],
        ),
      );
      final engine = _FakeEngine((_, _) => _login);
      final r = await env.scanner(engine).scan(file.path);
      // Small text, but the image is no tight crop: no second opinion.
      expect(r.passesRun, 1);
      expect(r.stop, ScanStop.satisfied);
    });

    _scannerTest('a crop is a crop even after the image was opened', (
      env,
    ) async {
      final file = await env.write('crop.png', await _tinyDarkCrop());
      // The first pass reads nothing (so the image is opened to plan the
      // passes); the second reads something complete: still tiny, so the
      // scan goes on until two passes agree.
      final engine = _FakeEngine((_, call) => call == 1 ? const [] : _login);
      final r = await env.scanner(engine).scan(file.path);
      expect(r.passesRun, 3);
      expect(r.stop, ScanStop.satisfied);
    });

    _scannerTest('the original file is never deleted or changed', (env) async {
      final bytes = await _tinyDarkCrop();
      final file = await env.write('crop.png', bytes);
      final engine = _FakeEngine((s, _) => s.isBright ? _login : const []);
      await env.scanner(engine).scan(file.path);
      expect(file.existsSync(), isTrue);
      expect(await file.readAsBytes(), bytes);
    });

    _scannerTest('a dark tiny crop is read by the later passes', (env) async {
      final file = await env.write('crop.png', await _tinyDarkCrop());
      // Only a bright (inverted) and bigger copy is readable.
      final engine = _FakeEngine(
        (s, _) => s.isBright && s.width >= 400 ? _login : const ['abcde0'],
      );
      final r = await env.scanner(engine).scan(file.path);

      expect(engine.calls.first.path, file.path);
      expect(engine.calls.first.width, 175);
      expect(engine.calls.first.isBright, isFalse);
      // The second pass: 3x, inverted, with a border.
      final second = engine.calls[1];
      expect(second.path, isNot(file.path));
      expect(second.path, startsWith(env.scratch.path));
      expect((second.width, second.height), (557, 218));
      expect(second.isBright, isTrue);
      // The third keeps the dark colours: only enlarged.
      expect(engine.calls[2].isBright, isFalse);
      expect(engine.calls[2].width, 557);

      expect(r.best.email, email);
      expect(r.best.password, password);
      expect(r.error, isNull);
      // A tiny crop needs two agreeing readings: the inverted 3x and 4x.
      expect(r.passesRun, 4);
      expect(r.stop, ScanStop.satisfied);
      expect(r.passes[0].quality, lessThan(r.passes[1].quality));
      expect(
        [for (final p in r.passes) p.name],
        ['original', 'inverted', 'upscaled', 'inverted-alt'],
      );
    });

    _scannerTest('only the original is left to the engine to prepare', (
      env,
    ) async {
      final file = await env.write('crop.png', await _tinyDarkCrop());
      final engine = _FakeEngine((s, _) => s.width > 175 ? _login : const []);
      final r = await env.scanner(engine).scan(file.path);
      expect(r.passesRun, greaterThan(1));
      // The copies are already enlarged or inverted: the engine reads each
      // once instead of trying its own variants on top.
      expect(engine.preprocessFlags.first, isTrue);
      expect(engine.preprocessFlags.skip(1), everyElement(isFalse));
    });

    _scannerTest('a tiny crop stops as soon as two passes agree', (env) async {
      final file = await env.write('crop.png', await _tinyDarkCrop());
      final engine = _FakeEngine((s, _) => s.width > 175 ? _login : const []);
      final r = await env.scanner(engine).scan(file.path);
      // Original: nothing. Inverted 3x: complete. Plain 3x: the same.
      expect(r.passesRun, 3);
      expect(r.stop, ScanStop.satisfied);
      expect(r.best.email, email);
      expect(r.best.password, password);
    });

    _scannerTest('a tiny crop is not trusted on one complete-looking reading', (
      env,
    ) async {
      final file = await env.write('crop.png', await _tinyDarkCrop());
      // The original reads the password wrong; every enlarged copy right.
      final engine = _FakeEngine(
        (s, _) => s.width > 175 ? _login : const [email, wrongPassword],
      );
      final r = await env.scanner(engine).scan(file.path);
      expect(r.rawPasses.first, [email, wrongPassword]);
      expect(r.passes.first.quality, greaterThan(0.85));
      expect(r.passesRun, 3);
      expect(r.best.password, password);
      expect(r.best.passwordCandidates.first, password);
      expect(r.best.passwordCandidates, contains(wrongPassword));
      expect(r.best.emailCandidates.first, email);
    });

    _scannerTest('the passes vote when they disagree', (env) async {
      final file = await env.write('crop.png', await _tinyDarkCrop());
      final reads = [
        const [email, wrongPassword],
        const [email, password],
        const [email, wrongPassword],
        const [email, wrongPassword],
      ];
      final engine = _FakeEngine((_, call) => reads[call - 1]);
      final r = await env.scanner(engine).scan(file.path);
      // Passes 1 and 3 agree with each other, so the scan stops after the
      // third and the odd one out (pass 2) loses the vote.
      expect(r.passesRun, 3);
      expect(r.best.password, wrongPassword);
      expect(r.stop, ScanStop.satisfied);
    });

    _scannerTest(
      'fields read in different passes are combined, chips are the union',
      (env) async {
        // No pass is complete on its own, so all three run (the image needs
        // no enlarging: the original, a padded and a contrast copy).
        final file = await env.write('easy.png', await _easyImage());
        final reads = [
          const [email, 'Sign in to continue'],
          const ['Welcome back', password],
          const ['Forgot it?'],
        ];
        final engine = _FakeEngine((_, call) => reads[call - 1]);
        final r = await env.scanner(engine).scan(file.path);
        expect(r.passesRun, 3);
        expect(r.best.email, email);
        expect(r.best.password, password);
        expect(r.chips, containsAll([email, password, 'Sign in to continue']));
        expect(r.chips, containsAll(['Welcome back', 'Forgot it?']));
        expect(r.best.chips, r.chips);
        expect(r.rawPasses, [for (final l in reads) l]);
        expect(r.readAnything, isTrue);
      },
    );

    _scannerTest('every pass empty: nothing found, no error', (env) async {
      final file = await env.write('crop.png', await _tinyDarkCrop());
      final engine = _FakeEngine((_, _) => const []);
      final r = await env.scanner(engine).scan(file.path);
      expect(r.passesRun, 4);
      expect(r.stop, ScanStop.exhausted);
      expect(r.error, isNull);
      expect(r.best.email, isNull);
      expect(r.best.password, isNull);
      expect(r.best.quality, 0);
      expect(r.chips, isEmpty);
      expect(r.rawPasses, everyElement(isEmpty));
      expect(r.rawPasses.length, 4);
      expect(r.readAnything, isFalse);
    });

    _scannerTest('a pass that throws does not stop the others', (env) async {
      final file = await env.write('crop.png', await _tinyDarkCrop());
      final engine = _FakeEngine((s, call) {
        if (call == 1) throw StateError('boom $email');
        return _login;
      });
      final r = await env.scanner(engine).scan(file.path);
      expect(r.passes.first.failed, isTrue);
      expect(r.passes.first.error, ScanError.failed);
      expect(r.passes.first.lines, isEmpty);
      expect(r.best.email, email);
      expect(r.best.password, password);
      // The error is only for when everything failed.
      expect(r.error, isNull);
      expect(r.rawPasses.length, r.passesRun);
    });

    _scannerTest('an engine that throws synchronously is a failed pass', (
      env,
    ) async {
      final file = await env.write('easy.png', await _easyImage());
      final engine = _ThrowingEngine(() => throw const FormatException('x'));
      final r = await env.scanner(engine).scan(file.path);
      expect(r.error, ScanError.failed);
      // Nothing to enlarge: the original, a padded and a contrast copy.
      expect(r.passesRun, 3);
    });

    _scannerTest('no language pack: the reason is surfaced, no more passes', (
      env,
    ) async {
      final file = await env.write('crop.png', await _tinyDarkCrop());
      final engine = _ThrowingEngine(
        () => throw const OcrNativeException('ocr_no_language'),
      );
      final r = await env.scanner(engine).scan(file.path);
      expect(r.error, ScanError.noLanguage);
      expect(r.passesRun, 1);
      expect(r.best.email, isNull);
      expect(r.chips, isEmpty);
      expect(r.passes.single.error, ScanError.noLanguage);
    });

    _scannerTest('other native errors are mapped, all passes still run', (
      env,
    ) async {
      final file = await env.write('crop.png', await _tinyDarkCrop());
      final cases = {
        'ocr_unsupported_image': ScanError.unsupportedImage,
        'ocr_image_too_large': ScanError.imageTooLarge,
        'ocr_file_unreadable': ScanError.fileUnreadable,
        'ocr_failed': ScanError.failed,
        'ocr_bad_arguments': ScanError.failed,
      };
      for (final MapEntry(key: code, value: expected) in cases.entries) {
        final engine = _ThrowingEngine(() => throw OcrNativeException(code));
        final r = await env.scanner(engine).scan(file.path);
        expect(r.error, expected, reason: code);
        expect(r.passesRun, 4, reason: code);
      }
    });

    _scannerTest('a PlatformException is classified like a native one', (
      env,
    ) async {
      final file = await env.write('easy.png', await _easyImage());
      final engine = _ThrowingEngine(
        () => throw PlatformException(code: 'ocr_no_language'),
      );
      expect(
        (await env.scanner(engine).scan(file.path)).error,
        ScanError.noLanguage,
      );
      final other = _ThrowingEngine(
        () => throw PlatformException(code: 'MLKitException'),
      );
      expect(
        (await env.scanner(other).scan(file.path)).error,
        ScanError.failed,
      );
    });

    _scannerTest('a native error from a later pass does not hide a reading', (
      env,
    ) async {
      final file = await env.write('easy.png', await _easyImage());
      final engine = _FakeEngine((_, call) {
        if (call == 1) return const ['Settings'];
        if (call == 2) throw const OcrNativeException('ocr_failed');
        return _login;
      });
      final r = await env.scanner(engine).scan(file.path);
      expect(r.error, isNull);
      expect(r.best.email, email);
      expect(r.passes[1].error, ScanError.failed);
    });

    _scannerTest('timeout: a pass that never returns is abandoned', (
      env,
    ) async {
      final file = await env.write('crop.png', await _tinyDarkCrop());
      final engine = _FakeEngine((_, _) => Completer<List<String>>().future);
      final clock = Stopwatch()..start();
      final r = await env
          .scanner(engine, timeout: const Duration(milliseconds: 400))
          .scan(file.path);
      expect(clock.elapsed, lessThan(const Duration(seconds: 5)));
      expect(
        clock.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 350)),
      );
      expect(r.stop, ScanStop.timeout);
      expect(r.error, ScanError.timeout);
      expect(r.passesRun, 1);
      expect(r.best.email, isNull);
    });

    _scannerTest('timeout in a later pass keeps what the first pass read', (
      env,
    ) async {
      final file = await env.write('crop.png', await _tinyDarkCrop());
      final engine = _FakeEngine(
        (_, call) =>
            call == 1 ? const [email] : Completer<List<String>>().future,
      );
      final r = await env
          .scanner(engine, timeout: const Duration(seconds: 2))
          .scan(file.path);
      expect(r.stop, ScanStop.timeout);
      // The engine did work, so it is not an error.
      expect(r.error, isNull);
      expect(r.passesRun, 2);
      expect(r.best.email, email);
      expect(r.rawPasses, [
        [email],
        <String>[],
      ]);
      // The abandoned copy was still deleted (checked after every test).
    });

    _scannerTest('the pass cap is honoured', (env) async {
      final file = await env.write('crop.png', await _tinyDarkCrop());
      for (final cap in [1, 2, 3]) {
        final engine = _FakeEngine((_, _) => const []);
        final r = await env.scanner(engine, maxPasses: cap).scan(file.path);
        expect(r.passesRun, cap);
        expect(engine.calls.length, cap);
      }
      // A cap above what is planned: the original plus three variants.
      final engine = _FakeEngine((_, _) => const []);
      final r = await env.scanner(engine, maxPasses: 50).scan(file.path);
      expect(r.passesRun, 4);
      expect(r.stop, ScanStop.exhausted);
    });

    _scannerTest('cancelling abandons the pass in flight', (env) async {
      final file = await env.write('crop.png', await _tinyDarkCrop());
      final token = ScanCancelToken();
      final engine = _FakeEngine((_, _) => Completer<List<String>>().future);
      Timer(const Duration(milliseconds: 100), token.cancel);
      final clock = Stopwatch()..start();
      final r = await env.scanner(engine).scan(file.path, cancel: token);
      expect(clock.elapsed, lessThan(const Duration(seconds: 5)));
      expect(r.stop, ScanStop.cancelled);
      expect(r.error, isNull);
      expect(r.passesRun, 1);
    });

    _scannerTest('a scan cancelled before it starts runs nothing', (env) async {
      final file = await env.write('crop.png', await _tinyDarkCrop());
      final token = ScanCancelToken()..cancel();
      final engine = _FakeEngine((_, _) => _login);
      final r = await env.scanner(engine).scan(file.path, cancel: token);
      expect(engine.calls, isEmpty);
      expect(r.passesRun, 0);
      expect(r.stop, ScanStop.cancelled);
      expect(r.best.email, isNull);
    });

    _scannerTest('cancelling between passes stops before the next one', (
      env,
    ) async {
      final file = await env.write('crop.png', await _tinyDarkCrop());
      final token = ScanCancelToken();
      final engine = _FakeEngine((_, call) {
        token.cancel();
        return const <String>[];
      });
      final r = await env.scanner(engine).scan(file.path, cancel: token);
      expect(r.passesRun, 1);
      expect(r.stop, ScanStop.cancelled);
    });

    _scannerTest('a huge image is tiled, every file within the limits', (
      env,
    ) async {
      final file = await env.write('big.png', await _bigScreenshot());
      final engine = _FakeEngine(
        (s, _) => s.path == file.path ? const <String>[] : const ['Overlap'],
      );
      final r = await env.scanner(engine).scan(file.path);
      // The original, then 2 tiles, then 2 more tiles of the plain variant.
      expect(engine.calls.length, 5);
      expect(engine.calls.first.path, file.path);
      for (final seen in engine.calls.skip(1)) {
        expect(seen.width, lessThanOrEqualTo(2600));
        expect(seen.height, lessThanOrEqualTo(2600));
        expect(seen.width, greaterThan(0));
      }
      expect(r.passesRun, 3);
      expect(
        [for (final p in r.passes) p.name],
        ['original', 'tiles-enhanced', 'tiles'],
      );
      // The overlap read the same line twice; a tiled pass keeps one.
      expect(r.rawPasses[1], ['Overlap']);
      expect(r.rawPasses[2], ['Overlap']);
      expect(r.stop, ScanStop.exhausted);
    });

    _scannerTest('a tile that fails does not fail the pass', (env) async {
      final file = await env.write('big.png', await _bigScreenshot());
      var tileCalls = 0;
      final engine = _FakeEngine((s, _) {
        if (s.path == file.path) return const <String>[];
        if (tileCalls++ == 0) throw StateError('first tile');
        return const [email, password];
      });
      final r = await env.scanner(engine).scan(file.path);
      expect(r.passes[1].failed, isFalse);
      expect(r.best.email, email);
      expect(r.best.password, password);
    });

    _scannerTest('an image that cannot be decoded only gets the first pass', (
      env,
    ) async {
      final bad = File('${env.images.path}/bad.png')
        ..writeAsStringSync('not an image');
      final engine = _FakeEngine((_, _) => const <String>[]);
      final r = await env.scanner(engine).scan(bad.path);
      expect(r.passesRun, 1);
      expect(r.stop, ScanStop.exhausted);
      expect(r.error, isNull);
    });

    _scannerTest('a missing file still gets one pass, and can succeed', (
      env,
    ) async {
      final path = '${env.images.path}/missing.png';
      final engine = _FakeEngine((_, _) => _login);
      final r = await env.scanner(engine).scan(path);
      expect(r.passesRun, 1);
      expect(r.best.email, email);
      expect(r.stop, ScanStop.satisfied);
    });

    _scannerTest('a preprocessor that fails leaves nothing behind', (
      env,
    ) async {
      final file = await env.write('crop.png', await _tinyDarkCrop());
      final pre = _FailingPre(env);
      final engine = _FakeEngine((_, _) => const <String>[]);
      final r = await env.scanner(engine, pre: pre).scan(file.path);
      expect(pre.renders, 3);
      // Only the original ran; every variant failed to render.
      expect(r.passesRun, 1);
      expect(r.error, isNull);
    });

    _scannerTest('nothing is printed or logged while scanning', (env) async {
      final file = await env.write('crop.png', await _tinyDarkCrop());
      final printed = <String>[];
      final previous = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        printed.add(message ?? '');
      };
      try {
        final engine = _FakeEngine((s, call) {
          if (call == 2) throw StateError('failed on $email');
          return s.width > 175 ? _login : const [email, password];
        });
        await runZoned(
          () => env.scanner(engine).scan(file.path),
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) => printed.add(line),
          ),
        );
      } finally {
        debugPrint = previous;
      }
      expect(printed, isEmpty);
    });

    _scannerTest('quality of the combined result follows its fields', (
      env,
    ) async {
      final file = await env.write('easy.png', await _easyImage());
      final reads = [
        const [email],
        const [password],
      ];
      final engine = _FakeEngine(
        (_, call) => call <= 2 ? reads[call - 1] : const <String>[],
      );
      final r = await env.scanner(engine).scan(file.path);
      final alone = OcrCredentialParser().parse(const [email]);
      expect(r.best.quality, greaterThan(alone.quality));
      expect(r.best.username, email);
    });
  });

  group('windows engine through the bridge', () {
    const channel = MethodChannel('app.vaultsnap/platform');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<MethodCall> calls;

    void mockOcr(Object? Function(MethodCall call) handler) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return handler(call);
      });
    }

    setUp(() => calls = []);
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test(
      'windowsOcr throws the native code as an OcrNativeException',
      () async {
        mockOcr(
          (_) => throw PlatformException(code: 'ocr_no_language', message: 'x'),
        );
        await expectLater(
          const PlatformBridge().windowsOcr('a.png'),
          throwsA(
            isA<OcrNativeException>()
                .having((e) => e.code, 'code', 'ocr_no_language')
                .having((e) => e.detail, 'detail', 'x'),
          ),
        );
        expect(calls.single.method, 'ocr');
        expect((calls.single.arguments as Map)['path'], 'a.png');
      },
    );

    test('the native side is told not to prepare an image twice', () async {
      mockOcr((_) => [email]);
      await const PlatformBridge().windowsOcr('a.png');
      expect((calls.last.arguments as Map).containsKey('preprocess'), isFalse);
      await const PlatformBridge().windowsOcr('b.png', preprocess: false);
      expect((calls.last.arguments as Map)['preprocess'], false);
      await WindowsOcrEngine(const PlatformBridge())
          .recognize('c.png', preprocess: false);
      expect((calls.last.arguments as Map)['path'], 'c.png');
      expect((calls.last.arguments as Map)['preprocess'], false);
    });

    test('other platform errors pass through unchanged', () async {
      mockOcr((_) => throw PlatformException(code: 'something_else'));
      await expectLater(
        const PlatformBridge().windowsOcr('a.png'),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'something_else',
          ),
        ),
      );
    });

    test('lines come back, and null is an empty list', () async {
      mockOcr((_) => [email, password]);
      expect(await const PlatformBridge().windowsOcr('a.png'), [
        email,
        password,
      ]);
      mockOcr((_) => null);
      expect(await const PlatformBridge().windowsOcr('a.png'), isEmpty);
    });

    _scannerTest('the scanner reports a missing language pack', (env) async {
      mockOcr((_) => throw PlatformException(code: 'ocr_no_language'));
      final file = await env.write('easy.png', await _easyImage());
      final scanner = env.scanner(WindowsOcrEngine(const PlatformBridge()));
      final r = await scanner.scan(file.path);
      expect(r.error, ScanError.noLanguage);
      expect(r.passesRun, 1);
    });

    _scannerTest('the scanner reads through the bridge', (env) async {
      mockOcr((_) => [email, password]);
      final file = await env.write('easy.png', await _easyImage());
      final scanner = env.scanner(WindowsOcrEngine(const PlatformBridge()));
      final r = await scanner.scan(file.path);
      expect(r.best.email, email);
      expect(r.best.password, password);
      expect(calls.length, 1);
    });
  });
}

class _ThrowingEngine implements OcrEngine {
  _ThrowingEngine(this.thrower);
  final Never Function() thrower;

  @override
  Future<List<String>> recognize(String imagePath, {bool preprocess = true}) =>
      thrower();
}

/// A preprocessor whose renders write a file and then fail.
class _FailingPre extends ImagePreprocessor {
  _FailingPre(_Env env) : super(tempRoot: env.scratch);
  int renders = 0;

  @override
  Future<PreparedVariant> render(
    ImageSource source,
    VariantSpec spec,
    ImageWorkspace work,
  ) async {
    renders++;
    await work.newFile('half').writeAsBytes([1, 2, 3]);
    throw StateError('render failed');
  }
}
