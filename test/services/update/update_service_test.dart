import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:hisn/services/update/app_version.dart';
import 'package:hisn/services/update/cancel_token.dart';
import 'package:hisn/services/update/update_config.dart';
import 'package:hisn/services/update/update_failure.dart';
import 'package:hisn/services/update/update_manifest.dart';
import 'package:hisn/services/update/update_service.dart';
import 'package:hisn/services/update/update_verifier.dart';

import 'update_test_kit.dart';

Matcher failsWith(UpdateFailure reason) =>
    throwsA(isA<UpdateException>().having((e) => e.reason, 'reason', reason));

Matcher failed(UpdateFailure reason) =>
    isA<UpdateFailed>().having((f) => f.reason, 'reason', reason);

void main() {
  late UpdateEnv env;

  setUp(() async => env = await UpdateEnv.create());
  tearDown(() async => env.dispose());

  UpdateAvailable available(UpdateCheckResult r) {
    expect(r, isA<UpdateAvailable>(), reason: '$r');
    return r as UpdateAvailable;
  }

  group('check', () {
    test('good path: signed newer manifest is offered', () async {
      env.publish();
      final r = available(await env.service.check());
      expect(r.manifest.version.version, '0.2.0');
      expect(r.latestBuild, 2000);
      expect(r.asset.name, 'app-release.apk');
      expect(r.asset.size, 3000);
      expect(r.asset.sha256, sha256Hex(payload(3000, seed: 1)));
      // Signature and manifest, each through two redirects.
      expect(env.net.urls.first, contains('update.json.sig'));
      expect(
        env.net.urls.where((u) => u.contains('/releases/download/')),
        isNotEmpty,
      );
    });

    test('the Windows build gets the zip', () async {
      final win = await UpdateEnv.create(platform: UpdatePlatform.windows);
      addTearDown(win.dispose);
      win.publish();
      final r = available(await win.service.check());
      expect(r.asset.name, 'app-windows.zip');
      expect(r.asset.size, 5000);
    });

    test('bad signature (random bytes)', () async {
      env.publish(
        signatureBytes: Uint8List.fromList(
          ascii.encode(base64.encode(List.filled(64, 7))),
        ),
      );
      expect(await env.service.check(), failed(UpdateFailure.signatureInvalid));
    });

    test('flipped manifest byte', () async {
      final bytes = jsonBytes(manifestJson());
      final sig = env.signer.signatureFile(bytes);
      // Flip one bit in the version digit: still valid JSON, different text.
      final tampered = Uint8List.fromList(bytes);
      final i = utf8.decode(tampered).indexOf('0.2.0') + 2;
      tampered[i] ^= 0x01;
      expect(() => jsonDecode(utf8.decode(tampered)), returnsNormally);
      env.publish(manifestBytes: tampered, signatureBytes: sig);
      expect(await env.service.check(), failed(UpdateFailure.signatureInvalid));
    });

    test('every single flipped bit of the manifest is caught', () async {
      final bytes = jsonBytes(manifestJson());
      final sig = env.signer.sign(bytes);
      final verifier = SodiumManifestVerifier(
        env.signer.sodium,
        env.config.publicKey,
      );
      expect(verifier.verify(bytes, sig), isTrue);
      for (var i = 0; i < bytes.length; i += 7) {
        final t = Uint8List.fromList(bytes)..[i] ^= 0x10;
        expect(verifier.verify(t, sig), isFalse, reason: 'byte $i');
      }
    });

    test('flipped signature byte', () async {
      final bytes = jsonBytes(manifestJson());
      final sig = env.signer.sign(bytes);
      sig[10] ^= 1;
      env.publish(
        manifestBytes: bytes,
        signatureBytes: Uint8List.fromList(ascii.encode(base64.encode(sig))),
      );
      expect(await env.service.check(), failed(UpdateFailure.signatureInvalid));
    });

    test('a manifest signed by another key is refused', () async {
      final other = await TestSigner.create();
      addTearDown(other.dispose);
      env.publish(signedBy: other);
      expect(await env.service.check(), failed(UpdateFailure.signatureInvalid));
    });

    test('a signature over different bytes is refused', () async {
      final a = jsonBytes(manifestJson(version: '0.2.0'));
      final b = jsonBytes(manifestJson(version: '0.9.0'));
      env.publish(
        manifestBytes: b,
        signatureBytes: env.signer.signatureFile(a),
      );
      expect(await env.service.check(), failed(UpdateFailure.signatureInvalid));
    });

    test('signature file in the wrong format', () async {
      final bytes = jsonBytes(manifestJson());
      final good = env.signer.sign(bytes);
      for (final bad in <Uint8List>[
        Uint8List(0),
        Uint8List.fromList(ascii.encode('not base64!')),
        Uint8List.fromList(ascii.encode(base64.encode(good.sublist(0, 63)))),
        Uint8List.fromList(ascii.encode(base64.encode([...good, 0]))),
        Uint8List.fromList(good), // raw, not base64
        Uint8List.fromList(
          ascii.encode(base64Url.encode(good).replaceAll('=', '')),
        ),
        Uint8List.fromList(ascii.encode(base64.encode(good) * 2)),
        Uint8List.fromList([0xff, 0xfe, 0x41]),
      ]) {
        env.net.routes.clear();
        env.publish(manifestBytes: bytes, signatureBytes: bad);
        expect(
          await env.service.check(),
          failed(UpdateFailure.signatureInvalid),
          reason: '${bad.length} bytes',
        );
      }
    });

    test('a trailing newline in the signature file is fine', () async {
      final bytes = jsonBytes(manifestJson());
      final sig = env.signer.signatureFile(bytes);
      env.publish(
        manifestBytes: bytes,
        signatureBytes: Uint8List.fromList([...sig, 10]),
      );
      available(await env.service.check());
    });

    test('the signature is checked before the manifest is parsed', () async {
      // An unsigned manifest of an unknown schema, and one that is not even
      // JSON: both must be reported as a signature failure, which proves
      // that nothing looked inside them first.
      for (final body in ['{"schema":99}', 'not json at all', '{"schema":1}']) {
        env.net.routes.clear();
        final bytes = Uint8List.fromList(utf8.encode(body));
        env.publish(
          manifestBytes: bytes,
          signatureBytes: Uint8List.fromList(
            ascii.encode(base64.encode(List.filled(64, 1))),
          ),
        );
        expect(
          await env.service.check(),
          failed(UpdateFailure.signatureInvalid),
          reason: body,
        );
      }
    });

    test('unknown schema (validly signed)', () async {
      env.publish(manifest: manifestJson(override: {'schema': 2}));
      expect(
        await env.service.check(),
        failed(UpdateFailure.unsupportedSchema),
      );
    });

    test('malformed JSON (validly signed)', () async {
      final bytes = Uint8List.fromList(utf8.encode('{"schema": 1, "version":'));
      env.publish(manifestBytes: bytes);
      expect(await env.service.check(), failed(UpdateFailure.manifestInvalid));
    });

    test('schema violations (validly signed)', () async {
      for (final m in [
        manifestJson(override: {'build': 5}),
        manifestJson(override: {'assets': <String, Object?>{}}),
        manifestJson(override: {'version': '1.0'}),
      ]) {
        env.net.routes.clear();
        env.publish(manifest: m);
        expect(
          await env.service.check(),
          failed(UpdateFailure.manifestInvalid),
        );
      }
    });

    test('oversized manifest (validly signed) is cut off at 64 KB', () async {
      final big = jsonBytes(manifestJson(override: {'pad': 'x' * 70000}));
      expect(big.length, greaterThan(64 * 1024));
      env.publish(manifestBytes: big);
      expect(await env.service.check(), failed(UpdateFailure.tooLarge));
    });

    test('an endless manifest is not read to the end', () async {
      final body = CountingBody([
        for (var i = 0; i < 10000; i++) Uint8List(1024),
      ]);
      env.publish();
      final url = Uri.https(
        'github.com',
        '/$repo/releases/latest/download/update.json',
      );
      env.net.on(url, (_) => body.response());
      expect(await env.service.check(), failed(UpdateFailure.tooLarge));
      expect(body.pulled, lessThan(100));
    });

    test('an oversized signature file is refused', () async {
      env.publish(signatureBytes: Uint8List(5000));
      expect(await env.service.check(), failed(UpdateFailure.tooLarge));
    });

    test('same build: up to date', () async {
      env.publish(manifest: manifestJson(version: '0.1.0'));
      final r = await env.service.check();
      expect(r, isA<UpdateUpToDate>());
      expect((r as UpdateUpToDate).latestBuild, 1000);
    });

    test(
      'older signed manifest than the installed build: nothing to do',
      () async {
        env.publish(manifest: manifestJson(version: '0.0.9'));
        expect(await env.service.check(), isA<UpdateUpToDate>());
      },
    );

    test('replay of an old signed manifest is refused', () async {
      // The installed app is 0.1.0. It has already seen the signed 0.5.0.
      // An attacker now serves the genuinely signed 0.3.0 manifest again.
      env.publish(manifest: manifestJson(version: '0.3.0'));
      final replay = await env.service.check(highestSeenBuild: 5000);
      expect(replay, failed(UpdateFailure.rollback));
      // The same manifest is fine for an install that has not seen 0.5.0.
      available(await env.service.check(highestSeenBuild: 3000));
      available(await env.service.check(highestSeenBuild: 0));
    });

    test('the newest build seen is still offered again', () async {
      env.publish(manifest: manifestJson(version: '0.5.0'));
      available(await env.service.check(highestSeenBuild: 5000));
    });

    test('no package for this platform', () async {
      env.publish(manifest: manifestJson(android: false));
      expect(await env.service.check(), failed(UpdateFailure.noAsset));
      final win = await UpdateEnv.create(platform: UpdatePlatform.windows);
      addTearDown(win.dispose);
      win.publish(manifest: manifestJson(windows: false));
      expect(await win.service.check(), failed(UpdateFailure.noAsset));
    });

    test('disabled without APP_VERSION: no request at all', () async {
      env.publish();
      final dev = UpdateEnv.create(version: AppVersion.none);
      final e = await dev;
      addTearDown(e.dispose);
      e.publish();
      expect(e.service.enabled, isFalse);
      expect(await e.service.check(), isA<UpdateDisabled>());
      expect(e.net.requests, isEmpty);
      await expectLater(
        e.service.download(
          UpdateAvailable(
            UpdateManifest.parse(jsonBytes(manifestJson()), e.config),
            UpdateManifest.parse(
              jsonBytes(manifestJson()),
              e.config,
            ).assets['android']!,
          ),
        ),
        failsWith(UpdateFailure.disabled),
      );
      expect(e.net.requests, isEmpty);
      expect(e.leftovers(), isEmpty);
    });

    test('disabled on a platform without updates', () async {
      final e = await UpdateEnv.create(platform: null);
      addTearDown(e.dispose);
      e.publish();
      expect(await e.service.check(), isA<UpdateDisabled>());
      expect(e.net.requests, isEmpty);
    });

    test('the manifest cannot send the download to another host', () async {
      env.publish(
        manifest: manifestJson(
          override: {
            'assets': {
              'android': {
                'name': 'app-release.apk',
                'url':
                    'https://evil.example.com/$repo/releases/download/v0.2.0/app-release.apk',
                'size': 3000,
                'sha256': sha256Hex(payload(3000, seed: 1)),
              },
            },
          },
        ),
      );
      expect(await env.service.check(), failed(UpdateFailure.manifestInvalid));
    });

    test('a hostile redirect for the manifest is not followed', () async {
      env.publish();
      env.net.redirect(
        Uri.https('github.com', '/$repo/releases/latest/download/update.json'),
        'https://evil.example.com/update.json',
      );
      expect(await env.service.check(), failed(UpdateFailure.hostNotAllowed));
      expect(env.net.urls.any((u) => u.contains('evil')), isFalse);
    });

    test('network failure', () async {
      // Nothing published: GitHub answers 404 for everything.
      expect(await env.service.check(), failed(UpdateFailure.badStatus));
    });

    test('cancelling a check', () async {
      env.publish();
      final cancel = CancelToken()..cancel();
      expect(
        await env.service.check(cancel: cancel),
        failed(UpdateFailure.cancelled),
      );
    });

    test('check never throws, whatever the verifier does', () async {
      env.publish();
      final boom = _ThrowingVerifier();
      final service = UpdateService(
        config: env.config,
        downloader: env.downloader,
        verifier: boom,
        workspace: env.workspace,
        version: env.version,
        platform: env.platform,
      );
      expect(await service.check(), failed(UpdateFailure.internal));
    });
  });

  group('download, verify, stage', () {
    late UpdateAvailable offer;

    Future<void> prepare({
      Uint8List? served,
      Map<String, Object?>? manifest,
    }) async {
      env.publish(manifest: manifest, apk: served);
      offer = available(await env.service.check());
    }

    test('good path: downloaded, verified, staged', () async {
      await prepare();
      final progress = <int>[];
      final dl = await env.service.download(
        offer,
        onProgress: (r, t) => progress.add(r),
      );
      expect(dl.file.existsSync(), isTrue);
      expect(p.basename(dl.file.path), 'app-release.apk');
      expect(p.isWithin(env.workRoot.path, dl.file.path), isTrue);
      expect(progress.last, 3000);
      await env.service.verify(dl);

      final staged = await env.service.stageForInstall(dl);
      expect(staged.file.path, isNot(dl.file.path));
      expect(p.isWithin(env.workRoot.path, staged.file.path), isTrue);
      expect(await staged.file.readAsBytes(), payload(3000, seed: 1));

      await env.service.discard(dl.directory);
      expect(dl.directory.existsSync(), isFalse);
      expect(staged.file.existsSync(), isTrue);
      await env.service.cleanup();
      expect(env.leftovers(), isEmpty);
    });

    test('wrong sha256 is caught and the files are deleted', () async {
      // Same size, different content.
      final evil = payload(3000, seed: 99);
      await prepare(served: evil);
      // The download itself succeeds (the size matches)...
      final dl = await env.service.download(offer);
      // ...and verification does not.
      await expectLater(
        env.service.verify(dl),
        failsWith(UpdateFailure.hashMismatch),
      );
      expect(dl.directory.existsSync(), isFalse);
      expect(env.leftovers(), isEmpty);
    });

    test('truncated download: nothing left behind', () async {
      await prepare(served: payload(2999, seed: 1));
      await expectLater(
        env.service.download(offer),
        failsWith(UpdateFailure.truncated),
      );
      expect(env.leftovers(), isEmpty);
    });

    test('size cap exceeded while streaming: stops and cleans up', () async {
      await prepare();
      final body = CountingBody([
        for (var i = 0; i < 1000; i++) Uint8List(100),
      ]);
      env.net.on(
        Uri.parse(
          'https://objects.githubusercontent.com/v0.2.0/app-release.apk?sig=1',
        ),
        (_) => body.response(),
      );
      await expectLater(
        env.service.download(offer),
        failsWith(UpdateFailure.tooLarge),
      );
      expect(body.pulled, lessThan(40), reason: 'cap is 3000 bytes of 100 000');
      expect(env.leftovers(), isEmpty);
    });

    test(
      'a package name that is a path is refused before anything happens',
      () async {
        await prepare();
        for (final name in [
          '../evil.apk',
          'a/b.apk',
          r'a\b.apk',
          '.hidden',
          '',
          'c:evil.apk',
        ]) {
          final bad = UpdateAvailable(
            offer.manifest,
            UpdateAsset(
              name: name,
              url: offer.asset.url,
              size: offer.asset.size,
              sha256: offer.asset.sha256,
            ),
          );
          await expectLater(
            env.service.download(bad),
            failsWith(UpdateFailure.manifestInvalid),
            reason: name,
          );
        }
        expect(env.leftovers(), isEmpty);
      },
    );

    test('redirect to a non-allow-listed host while downloading', () async {
      await prepare();
      env.net.redirect(
        offer.asset.url,
        'https://evil.example.com/app-release.apk',
      );
      await expectLater(
        env.service.download(offer),
        failsWith(UpdateFailure.hostNotAllowed),
      );
      expect(env.leftovers(), isEmpty);
    });

    test('redirect to http while downloading', () async {
      await prepare();
      env.net.redirect(
        offer.asset.url,
        'http://objects.githubusercontent.com/app-release.apk',
      );
      await expectLater(
        env.service.download(offer),
        failsWith(UpdateFailure.insecureUrl),
      );
      expect(env.leftovers(), isEmpty);
    });

    test('redirect loop while downloading', () async {
      await prepare();
      env.net.redirect(offer.asset.url, offer.asset.url.toString());
      await expectLater(
        env.service.download(offer),
        failsWith(UpdateFailure.tooManyRedirects),
      );
      expect(env.leftovers(), isEmpty);
    });

    test('cancellation deletes the temp file and its directory', () async {
      await prepare();
      final stalling = StallingBody(Uint8List(100));
      env.net.on(
        Uri.parse(
          'https://objects.githubusercontent.com/v0.2.0/app-release.apk?sig=1',
        ),
        (_) => stalling.response(),
      );
      final cancel = CancelToken();
      final future = env.service.download(
        offer,
        cancel: cancel,
        onProgress: (_, _) => cancel.cancel(),
      );
      await expectLater(future, failsWith(UpdateFailure.cancelled));
      expect(stalling.cancelled, isTrue);
      expect(env.leftovers(), isEmpty);
    });

    test(
      'a file changed after the download is caught before install',
      () async {
        await prepare();
        final dl = await env.service.download(offer);
        await env.service.verify(dl);
        // Something swaps the file between the check and the install.
        final bytes = await dl.file.readAsBytes();
        bytes[5] ^= 0xff;
        await dl.file.writeAsBytes(bytes);
        await expectLater(
          env.service.stageForInstall(dl),
          failsWith(UpdateFailure.hashMismatch),
        );
        // No staging directory is left behind.
        final dirs = env.workRoot.listSync().map((e) => e.path).toList();
        expect(dirs, [dl.directory.path]);
      },
    );

    test('the staged copy is verified too, not just the original', () async {
      await prepare();
      final service = UpdateService(
        config: env.config,
        downloader: env.downloader,
        verifier: SodiumManifestVerifier(
          env.signer.sodium,
          env.config.publicKey,
        ),
        workspace: env.workspace,
        version: env.version,
        platform: env.platform,
        // A copy that comes out different (bad disk, hostile filesystem).
        copyFile: (from, to) async {
          final bytes = await from.readAsBytes();
          bytes[100] ^= 1;
          await File(to).writeAsBytes(bytes);
        },
      );
      final dl = await service.download(offer);
      await service.verify(dl);
      await expectLater(
        service.stageForInstall(dl),
        failsWith(UpdateFailure.hashMismatch),
      );
      final dirs = env.workRoot.listSync().map((e) => e.path).toList();
      expect(dirs, [dl.directory.path], reason: 'staging dir removed');
    });

    test('a failing copy is a storage failure and leaves nothing', () async {
      await prepare();
      final service = UpdateService(
        config: env.config,
        downloader: env.downloader,
        verifier: SodiumManifestVerifier(
          env.signer.sodium,
          env.config.publicKey,
        ),
        workspace: env.workspace,
        version: env.version,
        platform: env.platform,
        copyFile: (from, to) async =>
            throw const FileSystemException('disk full'),
      );
      final dl = await service.download(offer);
      await expectLater(
        service.stageForInstall(dl),
        failsWith(UpdateFailure.storage),
      );
      expect(env.workRoot.listSync(), hasLength(1));
    });

    test('a file truncated or grown after the download is caught', () async {
      await prepare();
      final dl = await env.service.download(offer);
      await dl.file.writeAsBytes([...await dl.file.readAsBytes(), 0]);
      await expectLater(
        env.service.verifyFile(dl.file, dl.asset),
        failsWith(UpdateFailure.hashMismatch),
      );
      await dl.file.writeAsBytes([1, 2, 3]);
      await expectLater(
        env.service.verifyFile(dl.file, dl.asset),
        failsWith(UpdateFailure.hashMismatch),
      );
    });

    test('a symlink in place of the package is refused', () async {
      if (Platform.isWindows) return;
      await prepare();
      final dl = await env.service.download(offer);
      final real = File(p.join(env.dir.path, 'real.apk'))
        ..writeAsBytesSync(payload(3000, seed: 1));
      dl.file.deleteSync();
      Link(dl.file.path).createSync(real.path);
      await expectLater(
        env.service.verifyFile(dl.file, dl.asset),
        failsWith(UpdateFailure.hashMismatch),
      );
    });

    test('a missing file is a failure, not a crash', () async {
      await prepare();
      final dl = await env.service.download(offer);
      dl.file.deleteSync();
      await expectLater(
        env.service.verify(dl),
        throwsA(isA<UpdateException>()),
      );
    });

    test('work directories are private to the owner', () async {
      if (Platform.isWindows) return;
      await prepare();
      final dl = await env.service.download(offer);
      String mode(String path) =>
          (FileStat.statSync(path).mode & 0x1ff).toRadixString(8);
      expect(mode(env.workRoot.path), '700');
      expect(mode(dl.directory.path), '700');
      final staged = await env.service.stageForInstall(dl);
      expect(mode(staged.directory.path), '700');
      expect(staged.directory.path, isNot(dl.directory.path));
    });

    test('directory names are random', () async {
      final a = await env.workspace.create();
      final b = await env.workspace.create();
      expect(p.basename(a.path), matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(p.basename(a.path), isNot(p.basename(b.path)));
    });

    test('the workspace never deletes what it did not create', () async {
      // A misconfigured root (say, the vault folder) must survive cleanup.
      final precious = File(p.join(env.workRoot.path, 'vault.db'))
        ..createSync(recursive: true)
        ..writeAsStringSync('keep');
      final folder = Directory(p.join(env.workRoot.path, 'notes'))
        ..createSync();
      File(p.join(folder.path, 'a.txt')).writeAsStringSync('keep');
      final ours = await env.workspace.create();
      await env.service.cleanup();
      expect(ours.existsSync(), isFalse);
      expect(precious.existsSync(), isTrue);
      expect(File(p.join(folder.path, 'a.txt')).existsSync(), isTrue);
      await env.workspace.delete(folder);
      expect(folder.existsSync(), isTrue);
    });

    test('the workspace deletes only inside its root', () async {
      final outside = Directory(p.join(env.dir.path, 'outside'))..createSync();
      await env.workspace.delete(outside);
      expect(outside.existsSync(), isTrue);
      await env.workspace.delete(
        env.workRoot,
      ); // the root itself is not "inside"
      await env.workspace.create();
      await env.workspace.deleteAll();
      expect(env.leftovers(), isEmpty);
      expect(outside.existsSync(), isTrue);
    });
  });

  group('verifier', () {
    test('wrong-size inputs are "not valid", never an exception', () async {
      final v = SodiumManifestVerifier(env.signer.sodium, env.config.publicKey);
      final msg = Uint8List.fromList([1, 2, 3]);
      expect(v.verify(msg, Uint8List(0)), isFalse);
      expect(v.verify(msg, Uint8List(63)), isFalse);
      expect(v.verify(msg, Uint8List(65)), isFalse);
      expect(v.verify(msg, Uint8List(64)), isFalse);
      final shortKey = SodiumManifestVerifier(env.signer.sodium, Uint8List(10));
      expect(shortKey.verify(msg, env.signer.sign(msg)), isFalse);
    });

    test('decodeSignatureFile accepts only canonical base64 of 64 bytes', () {
      final sig = Uint8List.fromList(List.generate(64, (i) => i));
      expect(
        decodeSignatureFile(
          Uint8List.fromList(ascii.encode(base64.encode(sig))),
        ),
        sig,
      );
      expect(
        decodeSignatureFile(
          Uint8List.fromList(ascii.encode('${base64.encode(sig)}\r\n')),
        ),
        sig,
      );
      for (final bad in ['', '=', 'AAAA', base64.encode(sig.sublist(1))]) {
        expect(
          () => decodeSignatureFile(Uint8List.fromList(ascii.encode(bad))),
          failsWith(UpdateFailure.signatureInvalid),
          reason: bad,
        );
      }
    });
  });

  group('production factory', () {
    test('wires GitHub, the pinned key and a work directory', () async {
      final s = await loadTestSodium();
      final service = UpdateService.create(
        sodium: s,
        workRoot: Directory(p.join(env.dir.path, 'prod')),
        version: AppVersion.tryParse('0.3.0'),
        platform: UpdatePlatform.android,
      );
      expect(service.enabled, isTrue);
      expect(service.config.repo, UpdateConfig.defaultRepo);
      expect(service.version.build, 3000);
    });
  });
}

class _ThrowingVerifier implements ManifestVerifier {
  @override
  bool verify(Uint8List message, Uint8List signature) =>
      throw StateError('bug: secret-detail');
}
