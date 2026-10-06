import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../platform_bridge.dart';
import 'image_preprocessor.dart';
import 'ocr_engine.dart';
import 'ocr_parser.dart';

/// Why a scan found nothing because OCR itself failed, so the UI can say
/// what is wrong instead of "nothing found".
enum ScanError {
  /// No OCR language pack is installed (Windows): the user has to add one in
  /// Windows Settings.
  noLanguage,

  /// The engine refused the image for its size.
  imageTooLarge,

  /// The engine cannot read this image format or file.
  unsupportedImage,

  /// The file could not be opened.
  fileUnreadable,

  /// The scan ran out of time before any pass finished.
  timeout,

  /// Any other engine failure.
  failed,
}

/// Why a scan stopped.
enum ScanStop {
  /// A pass found an address and a password, and (for tiny crops, which
  /// engines misread) a second pass agreed.
  satisfied,

  /// All the planned passes ran, or there was nothing more to try.
  exhausted,

  /// The time budget ran out.
  timeout,

  /// The caller cancelled.
  cancelled,
}

/// What one pass read, for diagnostics.
class ScanPass {
  const ScanPass({
    required this.name,
    required this.lines,
    required this.quality,
    this.error,
  });

  /// The variant: "original", "inverted", "upscaled", "tiles"...
  final String name;

  /// What the engine read; empty if the pass failed.
  final List<String> lines;

  /// [OcrResult.quality] of this pass alone.
  final double quality;

  /// Set when the pass failed.
  final ScanError? error;

  bool get failed => error != null;
}

/// Lets the caller stop a scan that is running: the pass in flight is
/// abandoned at once and no further pass starts.
class ScanCancelToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  void _listen(void Function() l) => _listeners.add(l);
  void _unlisten(void Function() l) => _listeners.remove(l);
}

/// The outcome of [OcrScanner.scan].
class ScanResult {
  const ScanResult({
    required this.best,
    required this.chips,
    required this.rawPasses,
    required this.passes,
    required this.passesRun,
    required this.stop,
    this.error,
  });

  /// The credentials read: for each field the value most passes agreed on,
  /// taken from the best-scoring pass. Its chips are [chips].
  final OcrResult best;

  /// Every distinct line and token any pass read, best pass first, for the
  /// tap-to-assign chips. Never more than
  /// [OcrCredentialParser.maxChips].
  final List<String> chips;

  /// The lines each pass read (empty for a pass that failed), in the order
  /// the passes ran. [rawPasses].length == [passesRun].
  final List<List<String>> rawPasses;

  /// The same passes with their names, scores and errors.
  final List<ScanPass> passes;

  /// How many passes ran an engine (a failed one counts).
  final int passesRun;

  final ScanStop stop;

  /// Set only when every pass that ran failed. Null when the engine worked,
  /// even if it read nothing.
  final ScanError? error;

  /// Whether the engine read any text at all.
  bool get readAnything => rawPasses.any((p) => p.isNotEmpty);
}

/// Reads credentials out of an image with several passes of the same OCR
/// engine over differently prepared copies of it: the image as it is first,
/// then (only if that was not enough) enlarged, inverted when it is light on
/// dark, contrast stretched and padded. Tiny, dark crops of a screenshot are
/// what engines read worst, and one pass cannot be trusted on them, so the
/// scanner keeps every pass, takes the best and lets the passes vote.
///
/// Everything stays on the device. Every copy is a plaintext file in a private
/// temp directory that is deleted as soon as its pass is over, also when a
/// pass fails, times out or is cancelled. Nothing is ever logged.
class OcrScanner {
  OcrScanner(
    this.engine, {
    ImagePreprocessor? pre,
    OcrCredentialParser? parser,
    this.maxPasses = 4,
    this.timeout = const Duration(seconds: 20),
    this.goodQuality = 0.85,
    this.cropSide = 400,
  }) : pre = pre ?? ImagePreprocessor(),
       parser = parser ?? OcrCredentialParser();

  /// The scanner for this platform's OCR engine.
  factory OcrScanner.forPlatform(PlatformBridge bridge) =>
      OcrScanner(OcrEngine.forPlatform(bridge));

  final OcrEngine engine;
  final ImagePreprocessor pre;
  final OcrCredentialParser parser;

  /// The most engine passes of one scan, the original included.
  final int maxPasses;

  /// The time one scan may take in all, preparing the copies included. The
  /// pass that is running when it expires is abandoned.
  final Duration timeout;

  /// The [OcrResult.quality] from which a pass with an address and a
  /// password counts as complete.
  final double goodQuality;

  /// Images with a shorter side than this are crops. When the text of a crop
  /// is small (it would be enlarged 2x or more), one complete-looking reading
  /// is not trusted until a second pass agrees: engines misread such text
  /// by a character or two and still return something plausible.
  final int cropSide;

  Future<ScanResult> scan(String imagePath, {ScanCancelToken? cancel}) async {
    final clock = Stopwatch()..start();
    final runs = <_Pass>[];
    final abandoned = <Future<void>>[];
    ImageSource? source;
    ImageWorkspace? work;
    var plan = const <VariantSpec>[];
    var opened = false;
    var cursor = 0;
    var stop = ScanStop.exhausted;
    bool? tiny;

    // The image is opened (reduced copy only) the first time something needs
    // to know about it: the variants, or whether it is a tiny crop.
    Future<void> open() async {
      if (opened) return;
      opened = true;
      try {
        source = await pre.open(imagePath);
        final s = source;
        if (s != null) plan = pre.plan(s.stats);
      } on Object {
        plan = const [];
      }
    }

    bool interrupted() {
      if (cancel?.isCancelled ?? false) {
        stop = ScanStop.cancelled;
        return true;
      }
      if (clock.elapsed >= timeout) {
        stop = ScanStop.timeout;
        return true;
      }
      return false;
    }

    try {
      while (runs.length < maxPasses) {
        if (interrupted()) break;

        String name;
        List<String> paths;
        PreparedVariant? variant;
        if (runs.isEmpty) {
          name = 'original';
          paths = [imagePath];
        } else {
          await open();
          // The next variant that can be rendered.
          final s = source;
          while (variant == null && s != null && cursor < plan.length) {
            if (interrupted()) break;
            try {
              work ??= await pre.createWorkspace();
              variant = await pre.render(s, plan[cursor++], work);
            } on Object {
              variant = null;
            }
          }
          if (variant == null) break;
          name = variant.name;
          paths = variant.paths;
        }

        // The original file may be prepared again by the engine; the copies
        // already are.
        final pass = await _runPass(
          name,
          paths,
          clock,
          cancel,
          abandoned,
          prepared: variant != null,
        );
        // The copy is no longer needed (or, abandoned, deleted as soon as the
        // engine lets go of it).
        if (variant != null) await _discard(variant, abandoned);
        if (!pass.started) {
          // Interrupted before any engine ran: not a pass.
          stop = pass.interrupt ?? ScanStop.exhausted;
          break;
        }
        runs.add(pass);

        if (pass.interrupt != null) {
          stop = pass.interrupt!;
          break;
        }
        // No language pack: every other pass would fail the same way.
        if (pass.error == ScanError.noLanguage) break;

        if (_isComplete(pass.result)) {
          if (_agree(runs)) {
            stop = ScanStop.satisfied;
            break;
          }
          if (tiny == null) {
            // A crop whose text is small enough to want enlarging is the
            // kind engines misread while still looking plausible: one
            // reading is not enough.
            var shortSide = source?.stats.shortSide;
            if (shortSide == null && !opened) {
              final size = await pre.peek(imagePath);
              if (size != null) shortSide = math.min(size.width, size.height);
            }
            var small = false;
            if (shortSide != null && shortSide < cropSide) {
              await open();
              final s = source;
              small = s != null && pre.scaleFor(s.stats) >= 2;
            }
            tiny = small;
          }
          if (!tiny) {
            stop = ScanStop.satisfied;
            break;
          }
        }
      }
    } finally {
      source?.dispose();
      final w = work;
      if (w != null) {
        final gone = await w.dispose();
        if (!gone && abandoned.isNotEmpty) {
          // An engine still holds a file (Windows): remove the directory when
          // it lets go.
          unawaited(Future.wait(abandoned).then((_) => w.dispose()));
        }
      }
    }
    return _finish(runs, stop);
  }

  /// Deletes the files of [variant]; if an abandoned engine call still holds
  /// one (Windows will not delete an open file), deletes them when it lets go.
  Future<void> _discard(
    PreparedVariant variant,
    List<Future<void>> abandoned,
  ) async {
    if (await variant.delete()) return;
    final pending = Future.wait(abandoned).then((_) => variant.delete());
    abandoned.add(pending.then((_) {}));
  }

  /// Runs the engine on every file of one variant (one, or the tiles of a
  /// big image) and joins what it read.
  Future<_Pass> _runPass(
    String name,
    List<String> paths,
    Stopwatch clock,
    ScanCancelToken? cancel,
    List<Future<void>> abandoned, {
    required bool prepared,
  }) async {
    final lines = <String>[];
    final seen = <String>{};
    ScanError? error;
    ScanStop? interrupt;
    var started = false;
    var succeeded = false;
    for (final path in paths) {
      final budget = timeout - clock.elapsed;
      if (cancel?.isCancelled ?? false) {
        interrupt = ScanStop.cancelled;
        break;
      }
      if (budget <= Duration.zero) {
        interrupt = ScanStop.timeout;
        break;
      }
      started = true;
      final outcome = await _callEngine(
        path,
        budget,
        cancel,
        abandoned,
        prepared: prepared,
      );
      if (outcome is _Interrupted) {
        interrupt = outcome.reason;
        break;
      }
      if (outcome is _Failed) {
        error ??= _classify(outcome.error);
        // The language pack is missing: no other file will do better.
        if (error == ScanError.noLanguage) break;
        continue;
      }
      succeeded = true;
      for (final line in (outcome as _Done).lines) {
        // Tiles overlap, so the same line can be read twice.
        if (paths.length > 1 && !seen.add(line)) continue;
        lines.add(line);
      }
    }
    if (succeeded) error = null;
    if (!succeeded && interrupt == ScanStop.timeout) error = ScanError.timeout;
    OcrResult? result;
    if (succeeded) {
      try {
        result = parser.parse(lines);
      } on Object {
        result = null;
      }
    }
    return _Pass(name, lines, result, error, interrupt, started);
  }

  Future<_Outcome> _callEngine(
    String path,
    Duration budget,
    ScanCancelToken? cancel,
    List<Future<void>> abandoned, {
    required bool prepared,
  }) async {
    final call = Future<List<String>>.sync(
      () => engine.recognize(path, preprocess: !prepared),
    );
    final interrupted = Completer<_Interrupted>();
    final timer = Timer(budget, () {
      if (!interrupted.isCompleted) {
        interrupted.complete(const _Interrupted(ScanStop.timeout));
      }
    });
    void onCancel() {
      if (!interrupted.isCompleted) {
        interrupted.complete(const _Interrupted(ScanStop.cancelled));
      }
    }

    cancel?._listen(onCancel);
    try {
      final settled = call.then<_Outcome>(
        _Done.new,
        onError: (Object e) => _Failed(e),
      );
      final outcome = await Future.any<_Outcome>([settled, interrupted.future]);
      if (outcome is _Interrupted) {
        // The engine cannot be stopped; it may still hold the file.
        abandoned.add(settled.then((_) {}));
      }
      return outcome;
    } finally {
      timer.cancel();
      cancel?._unlisten(onCancel);
    }
  }

  static ScanError _classify(Object error) {
    if (error is TimeoutException) return ScanError.timeout;
    final code = switch (error) {
      OcrNativeException(:final code) => code,
      PlatformException(:final code) => code,
      _ => null,
    };
    return switch (code) {
      'ocr_no_language' => ScanError.noLanguage,
      'ocr_image_too_large' => ScanError.imageTooLarge,
      'ocr_unsupported_image' => ScanError.unsupportedImage,
      'ocr_file_unreadable' => ScanError.fileUnreadable,
      _ => ScanError.failed,
    };
  }

  /// An address and a password that read like a login.
  bool _isComplete(OcrResult? r) =>
      r != null &&
      r.email != null &&
      r.password != null &&
      r.quality >= goodQuality;

  /// Two passes read the same address and the same password.
  bool _agree(List<_Pass> runs) {
    final seen = <String>{};
    for (final run in runs) {
      final r = run.result;
      if (!_isComplete(r)) continue;
      if (!seen.add('${r!.email}\u0000${r.password}')) return true;
    }
    return false;
  }

  // ------------------------------------------------------------- combine

  ScanResult _finish(List<_Pass> runs, ScanStop stop) {
    final okRuns = [
      for (final r in runs)
        if (r.result != null) r,
    ];
    ScanError? error;
    if (okRuns.isEmpty && runs.isNotEmpty && stop != ScanStop.cancelled) {
      final errors = [for (final r in runs) ?r.error];
      error = errors.contains(ScanError.noLanguage)
          ? ScanError.noLanguage
          : (errors.firstOrNull ??
                (stop == ScanStop.timeout ? ScanError.timeout : null));
    }
    if (okRuns.isEmpty && runs.isEmpty && stop == ScanStop.timeout) {
      error = ScanError.timeout;
    }
    final best = _combine(okRuns);
    return ScanResult(
      best: best,
      chips: best.chips,
      rawPasses: [for (final r in runs) List.unmodifiable(r.lines)],
      passes: [
        for (final r in runs)
          ScanPass(
            name: r.name,
            lines: List.unmodifiable(r.lines),
            quality: r.result?.quality ?? 0,
            error: r.error,
          ),
      ],
      passesRun: runs.length,
      stop: stop,
      error: error,
    );
  }

  /// One result from the passes that read something: the best-scoring pass,
  /// with each field the value most passes read (ties go to the better pass),
  /// every chip and every candidate any pass had.
  OcrResult _combine(List<_Pass> runs) {
    if (runs.isEmpty) return parser.parse(const []);
    // Best first; the earlier pass wins a tie.
    final ranked = [...runs];
    ranked.sort((a, b) {
      final c = b.result!.quality.compareTo(a.result!.quality);
      return c != 0 ? c : runs.indexOf(a).compareTo(runs.indexOf(b));
    });
    final results = [for (final r in ranked) r.result!];

    final email = _vote([for (final r in results) r.email]);
    final password = _vote([for (final r in results) r.password]);
    // The best pass that read both winning values, else the best pass.
    final winner =
        results
            .where(
              (r) =>
                  (email == null || r.email == email) &&
                  (password == null || r.password == password),
            )
            .firstOrNull ??
        results.first;

    final chips = <String>{};
    for (final r in results) {
      for (final c in r.chips) {
        if (chips.length >= OcrCredentialParser.maxChips) break;
        chips.add(c);
      }
    }

    String? firstOf(String? Function(OcrResult) pick) {
      final own = pick(winner);
      if (own != null) return own;
      for (final r in results) {
        final v = pick(r);
        if (v != null) return v;
      }
      return null;
    }

    final derivedUsername =
        winner.username == null || winner.username == winner.email;
    return OcrResult(
      chips: chips.toList(),
      email: email ?? winner.email,
      username: derivedUsername ? (email ?? winner.username) : winner.username,
      password: password ?? winner.password,
      url: firstOf((r) => r.url),
      title: firstOf((r) => r.title),
      emailCandidates: _candidates(email ?? winner.email, [
        for (final r in results) r.emailCandidates,
      ]),
      passwordCandidates: _candidates(password ?? winner.password, [
        for (final r in results) r.passwordCandidates,
      ]),
    );
  }

  /// The value read by most passes; passes are best first, which breaks ties.
  static String? _vote(List<String?> values) {
    final counts = <String, int>{};
    for (final v in values) {
      if (v != null) counts[v] = (counts[v] ?? 0) + 1;
    }
    String? top;
    var most = 0;
    for (final v in values) {
      if (v == null) continue;
      if (counts[v]! > most) {
        top = v;
        most = counts[v]!;
      }
    }
    return top;
  }

  /// [chosen] first, then the candidates of every pass, those most passes
  /// offered first.
  static List<String> _candidates(String? chosen, List<List<String>> lists) {
    final score = <String, int>{};
    final order = <String>[];
    for (final list in lists) {
      for (final c in list) {
        if (!score.containsKey(c)) order.add(c);
        score[c] = (score[c] ?? 0) + 1;
      }
    }
    if (chosen == null && order.isEmpty) return const [];
    final rest = [
      for (final c in order)
        if (c != chosen) c,
    ];
    // Stable: most offered first, then the order they were first seen in.
    final index = {for (var i = 0; i < rest.length; i++) rest[i]: i};
    rest.sort((a, b) {
      final c = score[b]!.compareTo(score[a]!);
      return c != 0 ? c : index[a]!.compareTo(index[b]!);
    });
    return [?chosen, ...rest].take(OcrCredentialParser.maxCandidates).toList();
  }
}

/// One engine pass inside [OcrScanner.scan].
class _Pass {
  _Pass(
    this.name,
    this.lines,
    this.result,
    this.error,
    this.interrupt,
    this.started,
  );

  final String name;
  final List<String> lines;

  /// Null when the pass failed or was interrupted before it read anything.
  final OcrResult? result;
  final ScanError? error;
  final ScanStop? interrupt;

  /// Whether the engine was called at all.
  final bool started;
}

sealed class _Outcome {
  const _Outcome();
}

class _Done extends _Outcome {
  const _Done(this.lines);
  final List<String> lines;
}

class _Failed extends _Outcome {
  const _Failed(this.error);
  final Object error;
}

class _Interrupted extends _Outcome {
  const _Interrupted(this.reason);
  final ScanStop reason;
}
