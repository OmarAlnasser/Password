import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'cancel_token.dart';
import 'update_config.dart';
import 'update_failure.dart';

/// Receives `(bytesSoFar, totalBytes)` while a package downloads.
typedef DownloadProgress = void Function(int received, int total);

/// The only code that talks to the network for updates.
///
/// Rules, all enforced here and not left to the HTTP stack:
/// * HTTPS only, on every request and every redirect target. A redirect to
///   `http://` is refused; it is never "upgraded" or followed.
/// * Only hosts of [UpdateConfig.allowedHosts], no credentials in the URL, no
///   port but 443, again on every hop. Redirects are followed by hand
///   (`followRedirects = false`), at most [UpdateConfig.maxRedirects], and a URL
///   that is visited twice counts as a loop.
/// * Bodies are counted while they stream and the download stops the moment
///   the cap is passed; a declared `Content-Length` is only an early hint.
/// * `Accept-Encoding: identity`: no transparent decompression, so the counted
///   bytes are the bytes that are hashed.
/// * No cookies, no `Referer`, no authorization, a generic `User-Agent`. The
///   request does not say which app or version asks.
/// * Nothing is logged. Failures are [UpdateException]s that carry only an
///   [UpdateFailure].
class SecureDownloader {
  SecureDownloader(this._client, this.config);

  final http.Client _client;
  final UpdateConfig config;

  /// Same generic value the favicon fetcher sends.
  static const String userAgent = 'Mozilla/5.0';

  static const Set<int> _redirectCodes = {301, 302, 303, 307, 308};

  /// Downloads [url] into memory (manifest, signature).
  Future<Uint8List> fetchBytes(
    Uri url, {
    required int maxBytes,
    CancelToken? cancel,
  }) async {
    final out = BytesBuilder(copy: false);
    await _run(url, maxBytes: maxBytes, cancel: cancel, (res) async {
      await _readBody(
        res,
        maxBytes: maxBytes,
        cancel: cancel,
        onChunk: (chunk) async => out.add(chunk),
      );
    });
    return out.takeBytes();
  }

  /// Downloads [url] into [destination] (created, or overwritten) and returns
  /// the number of bytes written, which equals [expectedSize]. The file is
  /// deleted again if anything goes wrong or the caller cancels.
  ///
  /// More than [expectedSize] bytes aborts the download at once
  /// ([UpdateFailure.tooLarge]); fewer is [UpdateFailure.truncated].
  Future<int> downloadToFile(
    Uri url,
    File destination, {
    required int expectedSize,
    DownloadProgress? onProgress,
    CancelToken? cancel,
  }) async {
    final cap = expectedSize < config.maxAssetBytes
        ? expectedSize
        : config.maxAssetBytes;
    RandomAccessFile? raf;
    var written = 0;
    try {
      await _run(url, maxBytes: cap, cancel: cancel, (res) async {
        try {
          raf = await destination.open(mode: FileMode.writeOnly);
        } on Object {
          throw const UpdateException(UpdateFailure.storage);
        }
        final file = raf!;
        written = await _readBody(
          res,
          maxBytes: cap,
          cancel: cancel,
          onChunk: (chunk) => file.writeFrom(chunk),
          onProgress: onProgress == null
              ? null
              : (received) => onProgress(received, expectedSize),
        );
      });
      if (written != expectedSize) {
        throw const UpdateException(UpdateFailure.truncated);
      }
      try {
        await raf?.flush();
      } on Object {
        throw const UpdateException(UpdateFailure.storage);
      }
      return written;
    } on Object {
      await _closeQuietly(raf);
      raf = null;
      await _deleteQuietly(destination);
      rethrow;
    } finally {
      await _closeQuietly(raf);
    }
  }

  // --- Requests -------------------------------------------------------------

  /// Sends the request, follows redirects by hand and gives the 200 response
  /// to [body]. Maps every error to an [UpdateException].
  Future<void> _run(
    Uri start,
    Future<void> Function(http.StreamedResponse res) body, {
    required int maxBytes,
    CancelToken? cancel,
  }) async {
    final abort = Completer<void>();
    unawaited(cancel?.whenCancelled.then((_) => _complete(abort)));
    try {
      if (cancel?.isCancelled ?? false) {
        throw const UpdateException(UpdateFailure.cancelled);
      }
      final res = await _open(start, abort, cancel);
      final declared = res.contentLength;
      if (declared != null && declared > maxBytes) {
        await _discard(res);
        throw const UpdateException(UpdateFailure.tooLarge);
      }
      await body(res);
    } on UpdateException {
      rethrow;
    } on Object catch (e) {
      throw UpdateException(_classify(e, cancel));
    } finally {
      // Closes a connection that is still open (no-op once finished).
      _complete(abort);
    }
  }

  Future<http.StreamedResponse> _open(
    Uri start,
    Completer<void> abort,
    CancelToken? cancel,
  ) async {
    var uri = start;
    final visited = <String>{};
    for (var hop = 0; ; hop++) {
      final rejected = config.rejectUrl(uri);
      if (rejected != null) throw UpdateException(rejected);
      if (!visited.add(uri.toString())) {
        throw const UpdateException(UpdateFailure.tooManyRedirects);
      }
      // Only these headers (plus Host, added by the HTTP stack).
      final req = http.AbortableRequest('GET', uri, abortTrigger: abort.future)
        ..followRedirects = false
        ..headers['User-Agent'] = userAgent
        ..headers['Accept'] = '*/*'
        ..headers['Accept-Encoding'] = 'identity';
      final res = await _until(
        cancel,
        _client
            .send(req)
            .timeout(
              config.requestTimeout,
              onTimeout: () =>
                  throw const UpdateException(UpdateFailure.timeout),
            ),
      );
      if (cancel?.isCancelled ?? false) {
        await _discard(res);
        throw const UpdateException(UpdateFailure.cancelled);
      }
      if (_redirectCodes.contains(res.statusCode)) {
        final location = res.headers['location'];
        await _discard(res);
        if (hop >= config.maxRedirects) {
          throw const UpdateException(UpdateFailure.tooManyRedirects);
        }
        final target = location == null ? null : Uri.tryParse(location.trim());
        if (target == null || location!.trim().isEmpty) {
          throw const UpdateException(UpdateFailure.badStatus);
        }
        uri = uri.resolveUri(target).removeFragment();
        continue;
      }
      if (res.statusCode != 200) {
        await _discard(res);
        throw const UpdateException(UpdateFailure.badStatus);
      }
      return res;
    }
  }

  // --- Bodies ---------------------------------------------------------------

  /// Reads the body chunk by chunk, counting as it goes. Returns the number of
  /// bytes read. Stops the download as soon as [maxBytes] is passed, when no
  /// data arrives for [UpdateConfig.stallTimeout], or when [cancel] fires.
  Future<int> _readBody(
    http.StreamedResponse res, {
    required int maxBytes,
    required Future<void> Function(List<int> chunk) onChunk,
    CancelToken? cancel,
    void Function(int received)? onProgress,
  }) async {
    final done = Completer<int>();
    var received = 0;
    Timer? stall;
    StreamSubscription<List<int>>? sub;
    // The write that is in flight, as a future that never fails. Waited for
    // before returning so the caller never closes a file mid-write.
    Future<void>? pending;

    void finish([UpdateFailure? failure]) {
      if (done.isCompleted) return;
      stall?.cancel();
      if (failure == null) {
        done.complete(received);
      } else {
        done.completeError(UpdateException(failure));
      }
      final s = sub;
      if (s != null) unawaited(s.cancel().catchError((Object _) {}));
    }

    void arm() {
      stall?.cancel();
      stall = Timer(config.stallTimeout, () => finish(UpdateFailure.timeout));
    }

    if (cancel?.isCancelled ?? false) {
      unawaited(_discard(res));
      throw const UpdateException(UpdateFailure.cancelled);
    }
    unawaited(
      cancel?.whenCancelled.then((_) => finish(UpdateFailure.cancelled)),
    );
    arm();
    sub = res.stream.listen(
      (chunk) async {
        if (done.isCompleted) return;
        received += chunk.length;
        if (received > maxBytes) {
          finish(UpdateFailure.tooLarge);
          return;
        }
        // Back-pressure: no new chunk while this one is being written.
        sub!.pause();
        stall?.cancel();
        final write = onChunk(chunk);
        pending = write.then((_) {}, onError: (Object _) {});
        try {
          await write;
        } on Object {
          finish(UpdateFailure.storage);
          return;
        }
        if (done.isCompleted) return;
        try {
          onProgress?.call(received);
        } on Object {
          // A faulty listener must not stall the download.
        }
        arm();
        sub!.resume();
      },
      onError: (Object e, StackTrace _) => finish(_classify(e, cancel)),
      onDone: finish,
      cancelOnError: true,
    );
    try {
      return await done.future;
    } finally {
      stall?.cancel();
      final inFlight = pending;
      if (inFlight != null) await inFlight;
    }
  }

  // --- Helpers --------------------------------------------------------------

  static UpdateFailure _classify(Object e, CancelToken? cancel) {
    if (e is UpdateException) return e.reason;
    if (cancel?.isCancelled ?? false) return UpdateFailure.cancelled;
    if (e is TimeoutException) return UpdateFailure.timeout;
    if (e is http.RequestAbortedException) return UpdateFailure.cancelled;
    if (e is SocketException ||
        e is HandshakeException ||
        e is TlsException ||
        e is HttpException ||
        e is http.ClientException ||
        e is OSError) {
      return UpdateFailure.network;
    }
    return UpdateFailure.internal;
  }

  /// [work], or a cancellation as soon as [cancel] fires, even if the HTTP
  /// client itself ignores the abort request.
  static Future<T> _until<T>(CancelToken? cancel, Future<T> work) {
    if (cancel == null) return work;
    return Future.any([
      work,
      cancel.whenCancelled.then<T>(
        (_) => throw const UpdateException(UpdateFailure.cancelled),
      ),
    ]);
  }

  static void _complete(Completer<void> c) {
    if (!c.isCompleted) c.complete();
  }

  static Future<void> _discard(http.StreamedResponse res) async {
    try {
      await res.stream.listen(null, onError: (Object _) {}).cancel();
    } on Object {
      // Already closed.
    }
  }

  static Future<void> _closeQuietly(RandomAccessFile? raf) async {
    try {
      await raf?.close();
    } on Object {
      // Already closed.
    }
  }

  static Future<void> _deleteQuietly(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } on Object {
      // The workspace is removed as a whole afterwards.
    }
  }
}
