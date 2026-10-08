import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Size limits for [ImagePreprocessor]. The defaults suit every OCR engine
/// the app uses: Windows.Media.Ocr refuses bitmaps over
/// `OcrEngine::MaxImageDimension` (about 2600 px) and ML Kit gets slow and
/// memory hungry on very large ones.
class PreprocessLimits {
  const PreprocessLimits({
    this.maxEngineSide = 2600,
    this.maxOutputPixels = 16 * 1000 * 1000,
    this.maxDecodePixels = 24 * 1000 * 1000,
    this.maxInputBytes = 64 * 1024 * 1024,
    this.probeSide = 1400,
    this.tileSide = 2400,
    this.maxTiles = 12,
    this.pad = 16,
  });

  /// The longest side of any file handed to an engine.
  final int maxEngineSide;

  /// The most pixels (width x height) of any file handed to an engine.
  final int maxOutputPixels;

  /// The most pixels the full-size copy of the image may have in memory. A
  /// bigger image is decoded straight to a smaller size, never at full size.
  final int maxDecodePixels;

  /// Files bigger than this are not preprocessed at all.
  final int maxInputBytes;

  /// The image is measured on a copy whose longest side is at most this.
  final int probeSide;

  /// The longest side of a tile cut out of an image that is too big for the
  /// engines.
  final int tileSide;

  /// The most tiles one variant may have; beyond it the image is shrunk
  /// instead.
  final int maxTiles;

  /// The border of the image's background colour put round every output, in
  /// output pixels. Text that touches the edge of a crop is not read well
  /// without it.
  final int pad;
}

/// What the preprocessor learnt about an image from a reduced copy of it.
class ImageStats {
  const ImageStats({
    required this.width,
    required this.height,
    required this.sampleWidth,
    required this.sampleHeight,
    required this.bgLuma,
    required this.bgRed,
    required this.bgGreen,
    required this.bgBlue,
    required this.dark,
    required this.contrastLow,
    required this.contrastHigh,
    required this.contrastUseful,
    required this.textHeight,
  });

  /// The image's own size.
  final int width;
  final int height;

  /// The size of the copy that was measured.
  final int sampleWidth;
  final int sampleHeight;

  /// The background: the median of the 1 px border, 0..255 (luma) and per
  /// channel.
  final int bgLuma;
  final int bgRed;
  final int bgGreen;
  final int bgBlue;

  /// Light text on a dark background (the background luma is under 128).
  final bool dark;

  /// The levels a linear contrast stretch maps to black and to white: the
  /// background and the 0.5% extreme of the ink side. Only meaningful when
  /// [contrastUseful].
  final int contrastLow;
  final int contrastHigh;

  /// Whether the stretch range is wide enough (24 levels) to be worth it;
  /// below it a stretch would only amplify noise.
  final bool contrastUseful;

  /// The median height of a line of text, in the image's own pixels, or null
  /// when no text-like rows were found.
  final double? textHeight;

  int get longSide => math.max(width, height);
  int get shortSide => math.min(width, height);

  /// Measures [rgba] (straight, not premultiplied, 4 bytes a pixel) which is
  /// a [sampleWidth] x [sampleHeight] copy of a [width] x [height] image.
  /// Pure, so it can be tested without any decoding.
  static ImageStats analyze(
    Uint8List rgba,
    int sampleWidth,
    int sampleHeight, {
    required int width,
    required int height,
  }) {
    final sw = sampleWidth;
    final sh = sampleHeight;
    final n = sw * sh;
    if (sw <= 0 || sh <= 0 || rgba.length < n * 4) {
      throw ArgumentError('Bad sample');
    }
    final gray = Uint8List(n);
    final hist = Int32List(256);
    // Transparent pixels are read as if drawn on white.
    int over(int c, int a) => a == 255 ? c : (c * a + 255 * (255 - a)) ~/ 255;
    int lumaAt(int p) {
      final a = rgba[p + 3];
      return (over(rgba[p], a) * 299 +
              over(rgba[p + 1], a) * 587 +
              over(rgba[p + 2], a) * 114 +
              500) ~/
          1000;
    }

    for (var i = 0, p = 0; i < n; i++, p += 4) {
      final l = lumaAt(p);
      gray[i] = l;
      hist[l]++;
    }

    final borderL = Int32List(256);
    final borderR = Int32List(256);
    final borderG = Int32List(256);
    final borderB = Int32List(256);
    var borderCount = 0;
    void border(int x, int y) {
      final i = y * sw + x;
      final p = i * 4;
      final a = rgba[p + 3];
      borderL[gray[i]]++;
      borderR[over(rgba[p], a)]++;
      borderG[over(rgba[p + 1], a)]++;
      borderB[over(rgba[p + 2], a)]++;
      borderCount++;
    }

    for (var x = 0; x < sw; x++) {
      border(x, 0);
      if (sh > 1) border(x, sh - 1);
    }
    for (var y = 1; y < sh - 1; y++) {
      border(0, y);
      if (sw > 1) border(sw - 1, y);
    }
    final bg = _median(borderL, borderCount);
    final bgR = _median(borderR, borderCount);
    final bgG = _median(borderG, borderCount);
    final bgB = _median(borderB, borderCount);
    final dark = bg < 128;

    final hi = _percentile(hist, n, 0.995);
    final lo = _percentile(hist, n, 0.005);
    final dyn = math.max(hi - bg, bg - lo);
    final low = dark ? bg : math.min(lo, bg);
    final high = dark ? math.max(hi, bg) : bg;

    double? textHeight;
    if (dyn >= 24) {
      final thr = (0.35 * dyn).round();
      final minInk = math.max(1, sw ~/ 100);
      final runs = <int>[];
      var run = 0;
      for (var y = 0; y < sh; y++) {
        var ink = 0;
        final row = y * sw;
        for (var x = 0; x < sw; x++) {
          final d = gray[row + x] - bg;
          if (d > thr || -d > thr) ink++;
        }
        if (ink >= minInk) {
          run++;
        } else {
          if (run >= 3) runs.add(run);
          run = 0;
        }
      }
      if (run >= 3) runs.add(run);
      if (runs.isNotEmpty) {
        runs.sort();
        final mid = runs.length ~/ 2;
        final median = runs.length.isOdd
            ? runs[mid].toDouble()
            : (runs[mid - 1] + runs[mid]) / 2;
        textHeight = median * height / sh;
      }
    }

    return ImageStats(
      width: width,
      height: height,
      sampleWidth: sw,
      sampleHeight: sh,
      bgLuma: bg,
      bgRed: bgR,
      bgGreen: bgG,
      bgBlue: bgB,
      dark: dark,
      contrastLow: low,
      contrastHigh: high,
      contrastUseful: high - low >= 24,
      textHeight: textHeight,
    );
  }

  static int _median(Int32List hist, int count) {
    if (count <= 0) return 255;
    final half = (count + 1) ~/ 2;
    var acc = 0;
    for (var i = 0; i < 256; i++) {
      acc += hist[i];
      if (acc >= half) return i;
    }
    return 255;
  }

  /// The lowest level at or below which [fraction] of the pixels lie.
  static int _percentile(Int32List hist, int count, double fraction) {
    final target = fraction * count;
    var acc = 0;
    for (var i = 0; i < 256; i++) {
      acc += hist[i];
      if (acc >= target) return i;
    }
    return 255;
  }
}

/// One way of re-rendering an image for OCR.
class VariantSpec {
  const VariantSpec({
    required this.name,
    this.scale = 1,
    this.pad = 0,
    this.gray = false,
    this.invert = false,
    this.contrast = false,
    this.tiled = false,
    this.tileSide = 0,
    this.overlap = 0,
  });

  /// Short and fixed ("inverted", "upscaled"...): safe to show in diagnostics.
  final String name;

  /// How much bigger (or, below 1, smaller) the output is than the image.
  final double scale;

  /// The border round the output, in output pixels.
  final int pad;

  /// Greyscale (luma). Implied by [invert] and [contrast].
  final bool gray;

  /// Dark text on a light background, from the reverse.
  final bool invert;

  /// A linear stretch of the levels between the background and the far end
  /// of the ink. Never a threshold: binarising lost most text in the lab.
  final bool contrast;

  /// Cut the image into [tileSide] pieces that overlap by [overlap] pixels
  /// and write one file for each.
  final bool tiled;
  final int tileSide;
  final int overlap;

  bool get hasColorChange => gray || invert || contrast;

  /// Two specs with the same key produce the same pixels.
  String get key =>
      '${scale.toStringAsFixed(3)}|$pad|${gray || invert || contrast}|$invert|'
      '$contrast|$tiled|$tileSide|$overlap';
}

/// A private scratch directory for the files one scan writes. Everything in
/// it is a plaintext copy of the user's image: delete it as soon as possible.
class ImageWorkspace {
  ImageWorkspace._(this.dir);

  /// The directory all scans' workspaces live in, below the temp root.
  static const String rootName = 'hisn-ocr';

  /// A workspace this old was left by a crash.
  static const Duration staleAfter = Duration(minutes: 15);

  final Directory dir;
  bool _disposed = false;
  int _counter = 0;

  bool get isDisposed => _disposed;

  /// Creates a workspace below [root] (the system temp directory by
  /// default); [Directory.createTemp] makes it readable by this user only on
  /// every platform that has such a concept. Workspaces left behind by an
  /// earlier crash are removed first.
  static Future<ImageWorkspace> create([Directory? root]) async {
    final parent = Directory(
      '${(root ?? Directory.systemTemp).path}${Platform.pathSeparator}'
      '$rootName',
    );
    await parent.create(recursive: true);
    await _sweep(parent, staleAfter);
    return ImageWorkspace._(await parent.createTemp('s-'));
  }

  /// Removes the workspaces older than [olderThan] below [root] (the system
  /// temp directory by default): the plaintext copies an app that was killed
  /// or crashed in the middle of a scan left behind. Call it once when the app
  /// starts, so they do not wait for the next scan. Never throws.
  static Future<void> sweepStale({
    Directory? root,
    Duration olderThan = staleAfter,
  }) => _sweep(
    Directory(
      '${(root ?? Directory.systemTemp).path}${Platform.pathSeparator}'
      '$rootName',
    ),
    olderThan,
  );

  static Future<void> _sweep(Directory parent, Duration olderThan) async {
    try {
      final cutoff = DateTime.now().subtract(olderThan);
      await for (final e in parent.list(followLinks: false)) {
        if (e is! Directory) continue;
        try {
          if ((await e.stat()).modified.isBefore(cutoff)) {
            await e.delete(recursive: true);
          }
        } on FileSystemException {
          // In use or already gone.
        }
      }
    } on FileSystemException {
      // Best effort.
    }
  }

  /// A new, unused file path in the workspace.
  File newFile(String stem, [String extension = 'png']) {
    if (_disposed) throw StateError('Workspace is disposed');
    return File(
      '${dir.path}${Platform.pathSeparator}${_counter++}-$stem.$extension',
    );
  }

  /// Deletes the directory and everything in it. Returns whether it is gone
  /// (false if a file is still open, as on Windows while an engine reads it).
  Future<bool> dispose() async {
    _disposed = true;
    try {
      await dir.delete(recursive: true);
      return true;
    } on PathNotFoundException {
      return true;
    } on FileSystemException {
      return false;
    }
  }
}

/// The files of one rendered variant.
class PreparedVariant {
  PreparedVariant(this.name, this.files);

  final String name;
  final List<File> files;

  List<String> get paths => [for (final f in files) f.path];

  /// Deletes the files. Returns whether all of them are gone.
  Future<bool> delete() async {
    var gone = true;
    for (final f in files) {
      try {
        await f.delete();
      } on PathNotFoundException {
        // Already gone.
      } on FileSystemException {
        gone = false;
      }
    }
    return gone;
  }
}

/// An image opened for preprocessing: its measurements, and the pixels decoded
/// on demand at a size that is always bounded.
class ImageSource {
  ImageSource._(
    this._buffer,
    this._descriptor,
    this.stats,
    this.sampleWidth,
    this.sampleHeight,
    this.baseWidth,
    this.baseHeight,
    this._thumb,
  );

  final ui.ImmutableBuffer _buffer;
  final ui.ImageDescriptor _descriptor;
  final ImageStats stats;

  /// The size of the reduced copy the measurements came from. Never more than
  /// [PreprocessLimits.probeSide] on the long side, however big the image.
  final int sampleWidth;
  final int sampleHeight;

  /// The size [base] has: the image's own, or less when it has more than
  /// [PreprocessLimits.maxDecodePixels].
  final int baseWidth;
  final int baseHeight;

  ui.Image? _thumb;
  ui.Image? _base;
  Future<ui.Image>? _baseLoading;
  bool _disposed = false;

  /// The pixels of the image at [baseWidth] x [baseHeight], decoded once.
  /// When the image is bigger than the limit it is decoded straight to the
  /// smaller size.
  Future<ui.Image> base() {
    if (_disposed) throw StateError('Image source is disposed');
    final ready = _base;
    if (ready != null) return Future.value(ready);
    return _baseLoading ??= _loadBase();
  }

  Future<ui.Image> _loadBase() async {
    final thumb = _thumb;
    if (thumb != null &&
        thumb.width == baseWidth &&
        thumb.height == baseHeight) {
      _thumb = null;
      return _base = thumb;
    }
    final same = baseWidth == stats.width && baseHeight == stats.height;
    final image = await ImagePreprocessor._decode(
      _descriptor,
      same ? null : baseWidth,
      same ? null : baseHeight,
    );
    if (_disposed) {
      image.dispose();
      throw StateError('Image source is disposed');
    }
    return _base = image;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _thumb?.dispose();
    _base?.dispose();
    _thumb = _base = null;
    _descriptor.dispose();
    _buffer.dispose();
  }
}

/// Re-renders an image the ways the OCR engines read small and light-on-dark
/// text better: scaled up (bicubic, never nearest), greyscale, inverted,
/// contrast stretched and with a border. All drawing uses dart:ui; nothing
/// leaves the device.
///
/// The measurements and the recipes follow the lab: tiny crops want 2x to 4x
/// (about 42 px a line of text), dark ones are inverted, a border is
/// mandatory for crops cut through a line of text, and images too big for the
/// engines are tiled at their own resolution instead of being shrunk.
class ImagePreprocessor {
  ImagePreprocessor({this.limits = const PreprocessLimits(), this.tempRoot});

  final PreprocessLimits limits;

  /// Where scratch directories go; the system temp directory when null (the
  /// app's private cache on Android and iOS).
  final Directory? tempRoot;

  /// A fresh scratch directory for one scan.
  Future<ImageWorkspace> createWorkspace() => ImageWorkspace.create(tempRoot);

  /// The size of the image in [path], read from its header without decoding
  /// it, or null if it cannot be read.
  Future<({int width, int height})?> peek(String path) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      final bytes = await _read(path);
      if (bytes == null) return null;
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      return (width: descriptor.width, height: descriptor.height);
    } on Object {
      return null;
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  Future<Uint8List?> _read(String path) async {
    final file = File(path);
    final length = await file.length();
    if (length <= 0 || length > limits.maxInputBytes) return null;
    return file.readAsBytes();
  }

  /// Opens [path] and measures it on a reduced copy (never more than
  /// [PreprocessLimits.probeSide] on the long side, so a 4K screenshot is not
  /// decoded at full size to look at it). Null if the file is too big or not
  /// an image the platform can decode. Call [ImageSource.dispose] when done.
  Future<ImageSource?> open(String path) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Image? thumb;
    try {
      final bytes = await _read(path);
      if (bytes == null) return null;
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final w = descriptor.width;
      final h = descriptor.height;
      if (w <= 0 || h <= 0) return null;
      final long = math.max(w, h);
      int? tw;
      int? th;
      if (long > limits.probeSide) {
        final f = limits.probeSide / long;
        tw = math.max(1, (w * f).round());
        th = math.max(1, (h * f).round());
      }
      thumb = await _decode(descriptor, tw, th);
      final data = await thumb.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (data == null) return null;
      final stats = ImageStats.analyze(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        thumb.width,
        thumb.height,
        width: w,
        height: h,
      );
      final (bw, bh) = _baseSize(w, h);
      final source = ImageSource._(
        buffer,
        descriptor,
        stats,
        thumb.width,
        thumb.height,
        bw,
        bh,
        thumb,
      );
      // The source owns them now.
      buffer = null;
      descriptor = null;
      thumb = null;
      return source;
    } on Object {
      return null;
    } finally {
      thumb?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  static Future<ui.Image> _decode(
    ui.ImageDescriptor descriptor,
    int? targetWidth,
    int? targetHeight,
  ) async {
    final codec = await descriptor.instantiateCodec(
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  (int, int) _baseSize(int w, int h) {
    final pixels = w * h;
    if (pixels <= limits.maxDecodePixels) return (w, h);
    final f = math.sqrt(limits.maxDecodePixels / pixels);
    return (math.max(1, (w * f).floor()), math.max(1, (h * f).floor()));
  }

  // ------------------------------------------------------------ planning

  /// The variants worth trying for an image with these [stats], best first.
  /// At most three, and none that would exceed the engine limits.
  List<VariantSpec> plan(ImageStats stats) {
    final (bw, bh) = _baseSize(stats.width, stats.height);
    final pad = limits.pad;
    final dark = stats.dark;
    final specs = <VariantSpec>[];
    void add(VariantSpec v) {
      if (specs.every((o) => o.key != v.key)) specs.add(v);
    }

    if (math.max(bw, bh) > limits.maxEngineSide) {
      // Too big for the engines: cut it into tiles at its own resolution
      // (shrinking it loses the text: 5120 px wide images read 0% shrunk
      // against 100% tiled in the lab).
      final tile = limits.tileSide;
      final overlap = math.max(300, (tile * 0.15).round());
      final count =
          _starts(bw, tile, overlap).length * _starts(bh, tile, overlap).length;
      if (count <= limits.maxTiles) {
        add(
          VariantSpec(
            name: 'tiles-enhanced',
            pad: pad,
            gray: true,
            invert: dark,
            contrast: true,
            tiled: true,
            tileSide: tile,
            overlap: overlap,
          ),
        );
        add(
          VariantSpec(
            name: 'tiles',
            pad: pad,
            tiled: true,
            tileSide: tile,
            overlap: overlap,
          ),
        );
      } else {
        final shrink = tile / math.max(bw, bh);
        add(
          VariantSpec(
            name: 'shrunk-enhanced',
            scale: shrink,
            pad: pad,
            gray: true,
            invert: dark,
            contrast: true,
          ),
        );
        add(VariantSpec(name: 'shrunk', scale: shrink, pad: pad));
      }
      return specs;
    }

    final k = scaleFor(stats);
    final alt = _altScale(k, stats, bw, bh);
    VariantSpec enhanced(String name, int scale, {required bool invert}) =>
        VariantSpec(
          name: name,
          scale: scale.toDouble(),
          pad: pad,
          gray: true,
          invert: invert,
          contrast: true,
        );
    final plain = VariantSpec(
      name: k > 1 ? 'upscaled' : 'padded',
      scale: k.toDouble(),
      pad: pad,
    );
    if (dark) {
      add(enhanced('inverted', k, invert: true));
      add(plain);
      add(
        alt == null
            ? enhanced('contrast', k, invert: false)
            : enhanced('inverted-alt', alt, invert: true),
      );
    } else {
      add(plain);
      add(enhanced('contrast', k, invert: false));
      if (alt != null) add(enhanced('contrast-alt', alt, invert: false));
    }
    return specs;
  }

  /// How many times bigger the text should be: about 42 px a line, from 1x
  /// (no change) to 4x, 6x for really small text, and never more than the
  /// engine limits allow. 1 when it cannot be measured and the image is not a
  /// small crop.
  int scaleFor(ImageStats stats) {
    final (bw, bh) = _baseSize(stats.width, stats.height);
    // The text height is in the image's own pixels; the base may be smaller.
    var h = stats.textHeight;
    if (h != null) h = h * bw / stats.width;
    h ??= math.min(bw, bh) < 200 ? 12.0 : null;
    if (h == null || h >= 30) return 1;
    final maxK = h < 8 ? 6 : 4;
    return _fit(math.max(1, math.min(maxK, (42 / h).round())), bw, bh);
  }

  int? _altScale(int k, ImageStats stats, int bw, int bh) {
    if (k < 2) return null;
    final maxK = ((stats.textHeight ?? 12) * bw / stats.width) < 8 ? 6 : 4;
    if (k + 1 <= maxK && _fit(k + 1, bw, bh) == k + 1) return k + 1;
    return k - 1 >= 2 ? k - 1 : null;
  }

  int _fit(int k, int bw, int bh) {
    var scale = k;
    while (scale > 1) {
      final w = bw * scale + 2 * limits.pad;
      final h = bh * scale + 2 * limits.pad;
      if (math.max(w, h) <= limits.maxEngineSide &&
          w * h <= limits.maxOutputPixels) {
        break;
      }
      scale--;
    }
    return scale;
  }

  /// Where tiles of [tile] pixels that overlap by [overlap] start to cover
  /// [total] pixels.
  static List<int> _starts(int total, int tile, int overlap) {
    if (total <= tile) return const [0];
    final step = math.max(1, tile - overlap);
    final out = <int>[];
    var x = 0;
    while (true) {
      if (x + tile >= total) {
        out.add(total - tile);
        return out;
      }
      out.add(x);
      x += step;
    }
  }

  // ----------------------------------------------------------- rendering

  /// Renders [spec] into files in [work]: one file, or one for each tile.
  /// Already written files are deleted if rendering fails halfway.
  Future<PreparedVariant> render(
    ImageSource source,
    VariantSpec spec,
    ImageWorkspace work,
  ) async {
    final base = await source.base();
    final bw = base.width;
    final bh = base.height;
    final rects = <ui.Rect>[];
    if (spec.tiled) {
      final tw = math.min(spec.tileSide, bw);
      final th = math.min(spec.tileSide, bh);
      for (final y in _starts(bh, th, spec.overlap)) {
        for (final x in _starts(bw, tw, spec.overlap)) {
          rects.add(
            ui.Rect.fromLTWH(
              x.toDouble(),
              y.toDouble(),
              tw.toDouble(),
              th.toDouble(),
            ),
          );
        }
      }
    } else {
      rects.add(ui.Rect.fromLTWH(0, 0, bw.toDouble(), bh.toDouble()));
    }
    final (filter, fill) = _look(source.stats, spec);
    final files = <File>[];
    try {
      for (var i = 0; i < rects.length; i++) {
        final bytes = await _renderOne(base, rects[i], spec, filter, fill);
        final file = work.newFile(spec.name);
        files.add(file);
        await file.writeAsBytes(bytes, flush: false);
      }
    } on Object {
      await PreparedVariant(spec.name, files).delete();
      rethrow;
    }
    return PreparedVariant(spec.name, files);
  }

  Future<Uint8List> _renderOne(
    ui.Image base,
    ui.Rect src,
    VariantSpec spec,
    ui.ColorFilter? filter,
    ui.Color fill,
  ) async {
    final pad = spec.pad;
    final dw = math.max(1, (src.width * spec.scale).round());
    final dh = math.max(1, (src.height * spec.scale).round());
    final outW = dw + 2 * pad;
    final outH = dh + 2 * pad;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
    );
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
      ui.Paint()
        ..color = fill
        ..isAntiAlias = false,
    );
    final paint = ui.Paint()
      ..filterQuality = ui.FilterQuality.high
      ..isAntiAlias = false;
    if (filter != null) paint.colorFilter = filter;
    canvas.drawImageRect(
      base,
      src,
      ui.Rect.fromLTWH(
        pad.toDouble(),
        pad.toDouble(),
        dw.toDouble(),
        dh.toDouble(),
      ),
      paint,
    );
    final picture = recorder.endRecording();
    ui.Image? out;
    try {
      out = await picture.toImage(outW, outH);
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('PNG encoding failed');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      out?.dispose();
      picture.dispose();
    }
  }

  /// The colour filter of [spec] (null when it keeps the colours) and the
  /// colour of the border and of whatever is transparent.
  (ui.ColorFilter?, ui.Color) _look(ImageStats s, VariantSpec spec) {
    if (!spec.hasColorChange) {
      return (null, ui.Color.fromARGB(255, s.bgRed, s.bgGreen, s.bgBlue));
    }
    var lo = 0;
    var hi = 255;
    if (spec.contrast && s.contrastUseful) {
      lo = s.contrastLow;
      hi = s.contrastHigh;
    }
    // Levels are 0..255, so a gain of 255 / (hi - lo) stretches [lo, hi] to
    // the full range; inverting is 255 - v. ColorFilter.matrix takes the
    // offset column in the same 0..255 units.
    final gain = 255.0 / (hi - lo);
    final sign = spec.invert ? -1.0 : 1.0;
    final offset = spec.invert ? 255 + gain * lo : -gain * lo;
    final r = sign * gain * 0.299;
    final g = sign * gain * 0.587;
    final b = sign * gain * 0.114;
    final filter = ui.ColorFilter.matrix(<double>[
      r, g, b, 0, offset, //
      r, g, b, 0, offset, //
      r, g, b, 0, offset, //
      0, 0, 0, 1, 0,
    ]);
    final level = (sign * gain * s.bgLuma + offset).round();
    final v = math.max(0, math.min(255, level));
    return (filter, ui.Color.fromARGB(255, v, v, v));
  }
}
