import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultsnap/services/update/app_version.dart';
import 'package:vaultsnap/services/update/update_config.dart';
import 'package:vaultsnap/services/update/update_failure.dart';
import 'package:vaultsnap/services/update/update_manifest.dart';
import 'package:vaultsnap/services/update/update_public_key.dart';
import 'package:vaultsnap/services/update/update_service.dart';
import 'package:vaultsnap/services/update/update_verifier.dart';

import 'update_test_kit.dart';

/// A manifest and signature produced by Python (`cryptography`, Ed25519) with
/// a throwaway key; see fixtures/README.txt. Proves Dart accepts exactly what
/// the release tooling signs.
void main() {
  final dir = 'test/services/update/fixtures';
  final manifest = File('$dir/update.json').readAsBytesSync();
  final sigFile = File('$dir/update.json.sig').readAsBytesSync();
  final fixtureKey = File('$dir/fixture_public_key.txt')
      .readAsStringSync()
      .trim();

  test('the fixture key is a throwaway, never the real release key', () {
    expect(fixtureKey, isNot(updatePublicKeyBase64));
    expect(base64.decode(fixtureKey), hasLength(32));
  });

  test('Dart verifies the Python signature over the exact bytes', () async {
    final sodium = await loadTestSodium();
    final verifier = SodiumManifestVerifier(sodium, base64.decode(fixtureKey));
    final signature = decodeSignatureFile(sigFile);
    expect(verifier.verify(manifest, signature), isTrue);
  });

  test('the real release key rejects it', () async {
    final sodium = await loadTestSodium();
    final real = SodiumManifestVerifier(sodium, UpdateConfig().publicKey);
    expect(real.verify(manifest, decodeSignatureFile(sigFile)), isFalse);
  });

  test('any change to the signed bytes is rejected', () async {
    final sodium = await loadTestSodium();
    final verifier = SodiumManifestVerifier(sodium, base64.decode(fixtureKey));
    final signature = decodeSignatureFile(sigFile);
    for (var i = 0; i < manifest.length; i += 5) {
      final t = Uint8List.fromList(manifest)..[i] ^= 0x01;
      expect(verifier.verify(t, signature), isFalse, reason: 'byte $i');
    }
    // Re-encoding the JSON (same data, different bytes) breaks the signature
    // too: the signature is over bytes, not over data.
    final reencoded = utf8.encode(
      jsonEncode(jsonDecode(utf8.decode(manifest))),
    );
    expect(verifier.verify(Uint8List.fromList(reencoded), signature), isFalse);
  });

  test('the Python manifest parses and has the expected content', () {
    final m = UpdateManifest.parse(
      manifest,
      UpdateConfig(publicKeyBase64: fixtureKey),
    );
    expect(m.version.version, '0.2.0');
    expect(m.build, 2000);
    expect(m.notes['ar'], 'إصلاحات وتحسينات.');
    final apk = m.assetFor(UpdatePlatform.android)!;
    expect(apk.size, 3000);
    expect(apk.sha256, sha256Hex(payload(3000, seed: 1)));
    final zip = m.assetFor(UpdatePlatform.windows)!;
    expect(zip.size, 5000);
    expect(zip.sha256, sha256Hex(payload(5000, seed: 2)));
  });

  test('end to end: check, download and verify what Python signed', () async {
    final env = await UpdateEnv.create(
      version: AppVersion.tryParse('0.1.0'),
      configBuilder: (_) => UpdateConfig(publicKeyBase64: fixtureKey),
    );
    addTearDown(env.dispose);
    // Serve the fixture files exactly as they are on disk.
    env.publish(manifestBytes: manifest, signatureBytes: sigFile);

    final result = await env.service.check();
    expect(result, isA<UpdateAvailable>(), reason: '$result');
    final offer = result as UpdateAvailable;
    final dl = await env.service.download(offer);
    await env.service.verify(dl);
    final staged = await env.service.stageForInstall(dl);
    expect(await staged.file.readAsBytes(), payload(3000, seed: 1));
  });

  test('the same fixture is refused under the real key (check)', () async {
    final env = await UpdateEnv.create(
      version: AppVersion.tryParse('0.1.0'),
      configBuilder: (_) => UpdateConfig(),
    );
    addTearDown(env.dispose);
    env.publish(manifestBytes: manifest, signatureBytes: sigFile);
    final result = await env.service.check();
    expect(result, isA<UpdateFailed>());
    expect((result as UpdateFailed).reason, UpdateFailure.signatureInvalid);
  });
}
