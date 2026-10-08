import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:hisn/services/update/cancel_token.dart';
import 'package:hisn/services/update/secure_downloader.dart';
import 'package:hisn/services/update/update_config.dart';
import 'package:hisn/services/update/update_failure.dart';

import 'update_test_kit.dart';

Matcher failsWith(UpdateFailure reason) =>
    throwsA(isA<UpdateException>().having((e) => e.reason, 'reason', reason));

void main() {
  late Directory tmp;
  late FakeNet net;

  SecureDownloader downloader([UpdateConfig? config]) =>
      SecureDownloader(net.client, config ?? UpdateConfig());

  final start = Uri.https(
    'github.com',
    '/$repo/releases/download/v1.0.0/a.bin',
  );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('dl-test-');
    net = FakeNet();
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  File target() => File(p.join(tmp.path, 'out.bin'));

  group('fetchBytes', () {
    test('returns the body', () async {
      net.serve(start, [1, 2, 3]);
      expect(await downloader().fetchBytes(start, maxBytes: 100), [1, 2, 3]);
    });

    test('follows GitHub-style redirects through the CDN', () async {
      net.redirect(
        start,
        'https://release-assets.githubusercontent.com/x/a?sig=1',
      );
      net.serve(
        Uri.parse('https://release-assets.githubusercontent.com/x/a?sig=1'),
        [9],
      );
      expect(await downloader().fetchBytes(start, maxBytes: 100), [9]);
      expect(net.requests, hasLength(2));
    });

    test('follows relative redirects and every redirect status', () async {
      for (final code in [301, 302, 303, 307, 308]) {
        net = FakeNet();
        net.redirect(start, '/$repo/releases/download/v1.0.0/b.bin', code);
        net.serve(
          Uri.https('github.com', '/$repo/releases/download/v1.0.0/b.bin'),
          [code & 0xff],
        );
        expect(await downloader().fetchBytes(start, maxBytes: 100), [
          code & 0xff,
        ], reason: '$code');
      }
    });

    test(
      'sends no cookies, no referer, no credentials, no compression',
      () async {
        net.redirect(start, 'https://objects.githubusercontent.com/a');
        net.serve(Uri.parse('https://objects.githubusercontent.com/a'), [1]);
        await downloader().fetchBytes(start, maxBytes: 10);
        for (final r in net.requests) {
          final names = r.headers.keys.map((k) => k.toLowerCase()).toSet();
          expect(names, {'user-agent', 'accept', 'accept-encoding'});
          expect(r.headers['Accept-Encoding'], 'identity');
          expect(r.headers['User-Agent'], 'Mozilla/5.0');
          expect(r.followRedirects, isFalse);
          expect(r.method, 'GET');
        }
      },
    );

    test('the start URL is checked before anything is sent', () async {
      for (final (url, why) in [
        ('http://github.com/x', UpdateFailure.insecureUrl),
        ('https://evil.com/x', UpdateFailure.hostNotAllowed),
        ('https://raw.githubusercontent.com/x', UpdateFailure.hostNotAllowed),
        ('https://user@github.com/x', UpdateFailure.hostNotAllowed),
        ('https://github.com:444/x', UpdateFailure.hostNotAllowed),
      ]) {
        await expectLater(
          downloader().fetchBytes(Uri.parse(url), maxBytes: 10),
          failsWith(why),
          reason: url,
        );
      }
      expect(net.requests, isEmpty);
    });

    test(
      'redirect to a host that is not allow-listed is not followed',
      () async {
        net.redirect(start, 'https://evil.example.com/a.bin');
        net.serve(Uri.parse('https://evil.example.com/a.bin'), [1, 2, 3]);
        await expectLater(
          downloader().fetchBytes(start, maxBytes: 100),
          failsWith(UpdateFailure.hostNotAllowed),
        );
        expect(net.urls, [
          start.toString(),
        ], reason: 'evil host never contacted');
      },
    );

    test('redirect to other githubusercontent hosts is not followed', () async {
      for (final host in [
        'raw.githubusercontent.com',
        'gist.githubusercontent.com',
        'user-images.githubusercontent.com',
        'evil.objects.githubusercontent.com',
      ]) {
        net = FakeNet();
        net.redirect(start, 'https://$host/a');
        await expectLater(
          downloader().fetchBytes(start, maxBytes: 100),
          failsWith(UpdateFailure.hostNotAllowed),
          reason: host,
        );
        expect(net.requests, hasLength(1));
      }
    });

    test('redirect to http is refused, never downgraded', () async {
      net.redirect(start, 'http://github.com/$repo/releases/download/v1/a.bin');
      net.serve(
        Uri.parse('http://github.com/$repo/releases/download/v1/a.bin'),
        [1],
      );
      await expectLater(
        downloader().fetchBytes(start, maxBytes: 100),
        failsWith(UpdateFailure.insecureUrl),
      );
      expect(net.requests, hasLength(1));
    });

    test('redirect on a later hop to http is refused too', () async {
      net.redirect(start, 'https://objects.githubusercontent.com/a');
      net.redirect(
        Uri.parse('https://objects.githubusercontent.com/a'),
        'http://objects.githubusercontent.com/b',
      );
      await expectLater(
        downloader().fetchBytes(start, maxBytes: 100),
        failsWith(UpdateFailure.insecureUrl),
      );
    });

    test(
      'redirects to other schemes, credentials and ports are refused',
      () async {
        for (final target in [
          'ftp://github.com/a',
          'file:///etc/passwd',
          'javascript:alert(1)',
          '//evil.com/a',
          'https://github.com@evil.com/a',
          'https://u:p@github.com/a',
          'https://github.com:8080/a',
        ]) {
          net = FakeNet();
          net.redirect(start, target);
          await expectLater(
            downloader().fetchBytes(start, maxBytes: 100),
            throwsA(isA<UpdateException>()),
            reason: target,
          );
          expect(net.requests, hasLength(1), reason: target);
        }
      },
    );

    test('a redirect loop is detected', () async {
      final b = Uri.https('github.com', '/b');
      net.redirect(start, b.toString());
      net.redirect(b, start.toString());
      await expectLater(
        downloader().fetchBytes(start, maxBytes: 100),
        failsWith(UpdateFailure.tooManyRedirects),
      );
      expect(net.requests.length, lessThanOrEqualTo(3));
    });

    test('a self-redirect is a loop', () async {
      net.redirect(start, start.toString());
      await expectLater(
        downloader().fetchBytes(start, maxBytes: 100),
        failsWith(UpdateFailure.tooManyRedirects),
      );
      expect(net.requests, hasLength(1));
    });

    test('at most 5 redirects are followed', () async {
      Uri hop(int i) => Uri.https('github.com', '/hop$i');
      for (var i = 0; i < 20; i++) {
        net.redirect(i == 0 ? start : hop(i), hop(i + 1).toString());
      }
      await expectLater(
        downloader().fetchBytes(start, maxBytes: 100),
        failsWith(UpdateFailure.tooManyRedirects),
      );
      // The first request plus five redirects, and no more.
      expect(net.requests, hasLength(6));
    });

    test('exactly 5 redirects still work', () async {
      Uri hop(int i) => Uri.https('github.com', '/hop$i');
      for (var i = 0; i < 5; i++) {
        net.redirect(i == 0 ? start : hop(i), hop(i + 1).toString());
      }
      net.serve(hop(5), [42]);
      expect(await downloader().fetchBytes(start, maxBytes: 100), [42]);
    });

    test('redirect without or with an empty Location fails', () async {
      net.on(start, (_) => respond(const [], 302));
      await expectLater(
        downloader().fetchBytes(start, maxBytes: 100),
        failsWith(UpdateFailure.badStatus),
      );
      net.on(start, (_) => respond(const [], 302, headers: {'location': '  '}));
      await expectLater(
        downloader().fetchBytes(start, maxBytes: 100),
        failsWith(UpdateFailure.badStatus),
      );
    });

    test('other statuses fail', () async {
      for (final code in [204, 206, 304, 400, 401, 403, 404, 429, 500, 503]) {
        net = FakeNet();
        net.on(start, (_) => respond([1], code));
        await expectLater(
          downloader().fetchBytes(start, maxBytes: 100),
          failsWith(UpdateFailure.badStatus),
          reason: '$code',
        );
      }
    });

    test('a declared length over the cap is refused before reading', () async {
      final body = CountingBody([
        [for (var i = 0; i < 10; i++) 1],
      ]);
      net.on(start, (_) => body.response(declared: 1000));
      await expectLater(
        downloader().fetchBytes(start, maxBytes: 100),
        failsWith(UpdateFailure.tooLarge),
      );
      expect(body.pulled, lessThanOrEqualTo(1), reason: 'body not read');
    });

    test(
      'the cap is enforced while streaming, whatever the headers say',
      () async {
        // No Content-Length at all, and then a body far over the cap.
        final body = CountingBody([
          for (var i = 0; i < 1000; i++) Uint8List(100),
        ]);
        net.on(start, (_) => body.response());
        await expectLater(
          downloader().fetchBytes(start, maxBytes: 450),
          failsWith(UpdateFailure.tooLarge),
        );
        expect(body.pulled, lessThan(10), reason: 'stopped reading early');
      },
    );

    test('a lying Content-Length does not widen the cap', () async {
      final body = CountingBody([
        for (var i = 0; i < 1000; i++) Uint8List(100),
      ]);
      net.on(start, (_) => body.response(declared: 50));
      await expectLater(
        downloader().fetchBytes(start, maxBytes: 450),
        failsWith(UpdateFailure.tooLarge),
      );
      expect(body.pulled, lessThan(10));
    });

    test('a body of exactly the cap is fine', () async {
      net.serve(start, Uint8List(450), declareLength: false);
      expect(
        await downloader().fetchBytes(start, maxBytes: 450),
        hasLength(450),
      );
    });

    test('network errors become a plain failure', () async {
      net.on(start, (_) => throw const SocketException('boom: secret-host'));
      try {
        await downloader().fetchBytes(start, maxBytes: 10);
        fail('should throw');
      } on UpdateException catch (e) {
        expect(e.reason, UpdateFailure.network);
        expect(e.toString(), 'UpdateException(network)');
      }
      net.on(start, (_) => throw http.ClientException('x', start));
      await expectLater(
        downloader().fetchBytes(start, maxBytes: 10),
        failsWith(UpdateFailure.network),
      );
      net.on(start, (_) => throw const HandshakeException('bad cert'));
      await expectLater(
        downloader().fetchBytes(start, maxBytes: 10),
        failsWith(UpdateFailure.network),
      );
    });

    test('an error in the middle of the body is a failure', () async {
      net.on(start, (_) {
        final c = StreamController<List<int>>();
        c.add([1, 2]);
        c.addError(const SocketException('reset'));
        return http.StreamedResponse(c.stream, 200);
      });
      await expectLater(
        downloader().fetchBytes(start, maxBytes: 100),
        failsWith(UpdateFailure.network),
      );
    });

    test('no response in time is a timeout', () async {
      net.on(start, (_) => Completer<http.StreamedResponse>().future);
      final cfg = UpdateConfig(
        requestTimeout: const Duration(milliseconds: 50),
      );
      await expectLater(
        downloader(cfg).fetchBytes(start, maxBytes: 100),
        failsWith(UpdateFailure.timeout),
      );
    });

    test(
      'a body that stalls is a timeout and the connection is closed',
      () async {
        final stalling = StallingBody([1, 2, 3]);
        net.on(start, (_) => stalling.response());
        final cfg = UpdateConfig(
          stallTimeout: const Duration(milliseconds: 100),
        );
        await expectLater(
          downloader(cfg).fetchBytes(start, maxBytes: 100),
          failsWith(UpdateFailure.timeout),
        );
        expect(stalling.cancelled, isTrue);
      },
    );

    test('cancelling stops the request', () async {
      final stalling = StallingBody([1, 2, 3]);
      net.on(start, (_) => stalling.response());
      final cancel = CancelToken();
      final future = downloader().fetchBytes(
        start,
        maxBytes: 100,
        cancel: cancel,
      );
      unawaited(future.catchError((Object _) => Uint8List(0)));
      await waitFor(() => stalling.listened);
      cancel.cancel();
      await expectLater(future, failsWith(UpdateFailure.cancelled));
      expect(stalling.cancelled, isTrue);
    });

    test('an already cancelled token sends nothing', () async {
      net.serve(start, [1]);
      final cancel = CancelToken()..cancel();
      await expectLater(
        downloader().fetchBytes(start, maxBytes: 10, cancel: cancel),
        failsWith(UpdateFailure.cancelled),
      );
      expect(net.requests, isEmpty);
    });
  });

  group('downloadToFile', () {
    final data = payload(10000);

    test('writes the exact bytes and reports progress', () async {
      net.serve(start, data);
      final progress = <int>[];
      final n = await downloader().downloadToFile(
        start,
        target(),
        expectedSize: data.length,
        onProgress: (received, total) {
          expect(total, data.length);
          progress.add(received);
        },
      );
      expect(n, data.length);
      expect(await target().readAsBytes(), data);
      expect(progress, isNotEmpty);
      expect(progress.last, data.length);
      expect(progress, orderedEquals([...progress]..sort()));
    });

    test('several chunks arrive in order', () async {
      final chunks = [
        for (var i = 0; i < 10; i++) data.sublist(i * 1000, (i + 1) * 1000),
      ];
      net.on(start, (_) => CountingBody(chunks).response());
      await downloader().downloadToFile(start, target(), expectedSize: 10000);
      expect(await target().readAsBytes(), data);
    });

    test('truncated: fewer bytes than the signed size', () async {
      net.serve(start, data.sublist(0, 9000));
      await expectLater(
        downloader().downloadToFile(start, target(), expectedSize: 10000),
        failsWith(UpdateFailure.truncated),
      );
      expect(target().existsSync(), isFalse, reason: 'partial file removed');
    });

    test('more bytes than the signed size stops the download', () async {
      final body = CountingBody([for (var i = 0; i < 500; i++) Uint8List(100)]);
      net.on(start, (_) => body.response());
      await expectLater(
        downloader().downloadToFile(start, target(), expectedSize: 1000),
        failsWith(UpdateFailure.tooLarge),
      );
      expect(body.pulled, lessThan(20));
      expect(target().existsSync(), isFalse);
    });

    test('the hard asset cap holds even if the caller asks for more', () async {
      final body = CountingBody([for (var i = 0; i < 500; i++) Uint8List(100)]);
      net.on(start, (_) => body.response());
      final cfg = UpdateConfig(maxAssetBytes: 1000);
      await expectLater(
        downloader(cfg).downloadToFile(start, target(), expectedSize: 50000),
        failsWith(UpdateFailure.tooLarge),
      );
      expect(body.pulled, lessThan(20));
      expect(target().existsSync(), isFalse);
    });

    test('redirect problems leave no file', () async {
      net.redirect(start, 'https://evil.example.com/x');
      await expectLater(
        downloader().downloadToFile(start, target(), expectedSize: 10),
        failsWith(UpdateFailure.hostNotAllowed),
      );
      expect(target().existsSync(), isFalse);
    });

    test('a bad status leaves no file', () async {
      await expectLater(
        downloader().downloadToFile(start, target(), expectedSize: 10),
        failsWith(UpdateFailure.badStatus),
      );
      expect(target().existsSync(), isFalse);
    });

    test('cancelling mid-download deletes the temp file', () async {
      final chunks = Stream<List<int>>.periodic(
        const Duration(milliseconds: 5),
        (_) => Uint8List(100),
      );
      var cancelledSource = false;
      net.on(start, (_) {
        final c = StreamController<List<int>>(
          onCancel: () => cancelledSource = true,
        );
        final sub = chunks.listen(c.add);
        c.onCancel = () {
          cancelledSource = true;
          return sub.cancel();
        };
        return http.StreamedResponse(c.stream, 200);
      });
      final cancel = CancelToken();
      var calls = 0;
      final future = downloader().downloadToFile(
        start,
        target(),
        expectedSize: 1000000,
        cancel: cancel,
        onProgress: (_, _) {
          if (++calls == 3) cancel.cancel();
        },
      );
      await expectLater(future, failsWith(UpdateFailure.cancelled));
      expect(cancelledSource, isTrue);
      expect(target().existsSync(), isFalse);
    });

    test(
      'a progress listener that throws does not break the download',
      () async {
        net.serve(start, data);
        await downloader().downloadToFile(
          start,
          target(),
          expectedSize: data.length,
          onProgress: (_, _) => throw StateError('ui bug'),
        );
        expect(await target().readAsBytes(), data);
      },
    );

    test('an unwritable destination is a storage failure', () async {
      net.serve(start, data);
      final bad = File(p.join(tmp.path, 'missing-dir', 'out.bin'));
      await expectLater(
        downloader().downloadToFile(start, bad, expectedSize: data.length),
        failsWith(UpdateFailure.storage),
      );
    });
  });
}
