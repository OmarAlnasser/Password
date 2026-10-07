import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vaultsnap/services/update/app_version.dart';
import 'package:vaultsnap/services/update/update_config.dart';
import 'package:vaultsnap/services/update/update_manifest.dart';
import 'package:vaultsnap/services/update/update_public_key.dart';
import 'package:vaultsnap/services/update/update_service.dart';
import 'package:vaultsnap/services/update/update_verifier.dart';
import 'package:vaultsnap/services/update/windows_installer.dart';

import 'update_test_kit.dart';

/// The files written by `tool/make_update_manifest.py`, the tool the release
/// workflow runs, read by the app's own code. `update_fixture_test.dart` covers
/// fixtures made by a separate snippet; this one pins the contract between the
/// release tool and the app: if the tool's output and the Dart parser drift
/// apart, every real release would fail with "manifest invalid", and this test
/// fails first. (`tool/test_update_tools.py` checks the files themselves; to
/// rewrite them run `python3 tool/test_update_tools.py --write-fixtures`.)
void main() {
  const dir = 'test/services/update/fixtures/release_tool';
  final manifest = File('$dir/update.json').readAsBytesSync();
  final sigFile = File('$dir/update.json.sig').readAsBytesSync();
  final apk = File('$dir/android.apk').readAsBytesSync();
  final zip = File('$dir/windows-x64.zip').readAsBytesSync();
  final fixtureKey = File('$dir/public_key.txt').readAsStringSync().trim();

  UpdateConfig fixtureConfig([String? _]) =>
      UpdateConfig(publicKeyBase64: fixtureKey);

  test('the fixture key is a throwaway, never the real release key', () {
    expect(fixtureKey, isNot(updatePublicKeyBase64));
    expect(base64.decode(fixtureKey), hasLength(32));
  });

  test(
    'the tool\'s signature verifies with libsodium over its exact bytes',
    () async {
      final sodium = await loadTestSodium();
      final verifier = SodiumManifestVerifier(
        sodium,
        base64.decode(fixtureKey),
      );
      final signature = decodeSignatureFile(sigFile);

      expect(verifier.verify(manifest, signature), isTrue);

      // The real release key must not accept a throwaway-key signature.
      final real = SodiumManifestVerifier(sodium, UpdateConfig().publicKey);
      expect(real.verify(manifest, signature), isFalse);
      // One changed byte, and the signature is gone.
      final tampered = Uint8List.fromList(manifest)
        ..[manifest.length ~/ 2] ^= 1;
      expect(verifier.verify(tampered, signature), isFalse);
    },
  );

  test('the tool\'s manifest parses, and lists what is on disk', () {
    final m = UpdateManifest.parse(manifest, fixtureConfig());

    expect(m.version.version, '0.2.0');
    expect(m.build, 2000);
    expect(m.notes['en'], contains('Fixes and improvements'));
    expect(
      m.notes['ar'],
      'إصلاحات وتحسينات.\n\n- بدء تشغيل أسرع\n- حجم تنزيل أصغر',
    );

    final android = m.assetFor(UpdatePlatform.android)!;
    expect(android.name, 'android.apk');
    expect(android.size, apk.length);
    expect(android.sha256, sha256Hex(apk));
    expect(android.url, assetUrl('android.apk'));

    final windows = m.assetFor(UpdatePlatform.windows)!;
    expect(windows.name, 'windows-x64.zip');
    expect(windows.size, zip.length);
    expect(windows.sha256, sha256Hex(zip));
    expect(windows.url, assetUrl('windows-x64.zip'));
  });

  for (final (platform, name, bytes) in [
    (UpdatePlatform.android, 'android.apk', apk),
    (UpdatePlatform.windows, 'windows-x64.zip', zip),
  ]) {
    test('${platform.name}: check, download, verify and stage the tool\'s '
        'release', () async {
      final env = await UpdateEnv.create(
        version: AppVersion.tryParse('0.1.0'),
        platform: platform,
        configBuilder: fixtureConfig,
      );
      addTearDown(env.dispose);
      // The manifest and signature exactly as the tool wrote them, and the
      // packages under the names the tool uses.
      env.publish(manifestBytes: manifest, signatureBytes: sigFile);
      env.serveAsset('android.apk', apk);
      env.serveAsset('windows-x64.zip', zip);

      final result = await env.service.check();
      expect(result, isA<UpdateAvailable>(), reason: '$result');
      final offer = result as UpdateAvailable;
      expect(offer.asset.name, name);

      final download = await env.service.download(offer);
      await env.service.verify(download);
      final staged = await env.service.stageForInstall(download);

      expect(p.basename(staged.file.path), name);
      expect(await staged.file.readAsBytes(), bytes);
    });
  }

  test('the tool\'s Windows package unpacks with the safe extractor', () async {
    final tmp = await Directory.systemTemp.createTemp('release-tool-zip-');
    addTearDown(() => tmp.delete(recursive: true));
    final file = File(p.join(tmp.path, 'windows-x64.zip'))
      ..writeAsBytesSync(zip);
    final out = Directory(p.join(tmp.path, 'out'))..createSync();

    final result = await const SafeZipExtractor().extract(file, out);

    expect(result.files, 3);
    expect(File(p.join(out.path, 'app.exe')).existsSync(), isTrue);
    expect(File(p.join(out.path, 'flutter_windows.dll')).existsSync(), isTrue);
    expect(File(p.join(out.path, 'data', 'app.so')).existsSync(), isTrue);
  });

  test('the same release is refused under the real key', () async {
    final env = await UpdateEnv.create(
      version: AppVersion.tryParse('0.1.0'),
      configBuilder: (_) => UpdateConfig(),
    );
    addTearDown(env.dispose);
    env.publish(manifestBytes: manifest, signatureBytes: sigFile);

    expect(await env.service.check(), isA<UpdateFailed>());
  });
}
