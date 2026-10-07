import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sodium/sodium_sumo.dart';
import 'package:vaultsnap/core/crypto/crypto.dart';
import 'package:vaultsnap/services/settings.dart';
import 'package:vaultsnap/services/update/app_version.dart';
import 'package:vaultsnap/services/update/secure_downloader.dart';
import 'package:vaultsnap/services/update/update_config.dart';
import 'package:vaultsnap/services/update/update_manifest.dart';
import 'package:vaultsnap/services/update/update_service.dart';
import 'package:vaultsnap/services/update/update_verifier.dart';
import 'package:vaultsnap/services/update/update_workspace.dart';

const String repo = UpdateConfig.defaultRepo;

SodiumSumo? _sodium;

/// libsodium, loaded once per test isolate.
Future<SodiumSumo> loadTestSodium() async => _sodium ??= await loadSodium();

/// A throwaway Ed25519 key that stands in for the release key.
class TestSigner {
  TestSigner._(this.sodium, this._pair);

  static Future<TestSigner> create() async {
    final s = await loadTestSodium();
    return TestSigner._(s, s.crypto.sign.keyPair());
  }

  final SodiumSumo sodium;
  final KeyPair _pair;

  Uint8List get publicKey => _pair.publicKey;
  String get publicKeyBase64 => base64.encode(publicKey);

  Uint8List sign(List<int> message) => sodium.crypto.sign.detached(
    message: Uint8List.fromList(message),
    secretKey: _pair.secretKey,
  );

  /// What `update.json.sig` holds.
  Uint8List signatureFile(List<int> message) =>
      Uint8List.fromList(ascii.encode(base64.encode(sign(message))));

  void dispose() => _pair.dispose();
}

String sha256Hex(List<int> bytes) => crypto.sha256.convert(bytes).toString();

Uri assetUrl(String name, {String tag = 'v0.2.0'}) =>
    Uri.https('github.com', '/$repo/releases/download/$tag/$name');

/// A package whose bytes are deterministic and whose size is [size].
Uint8List payload(int size, {int seed = 7}) =>
    Uint8List.fromList([for (var i = 0; i < size; i++) (i * 31 + seed) & 0xff]);

/// The JSON of a schema-1 manifest. Pass [override] to change any field.
Map<String, Object?> manifestJson({
  String version = '0.2.0',
  int? build,
  Uint8List? apk,
  Uint8List? zip,
  Map<String, Object?>? override,
  bool android = true,
  bool windows = true,
}) {
  final v = AppVersion.tryParse(version)!;
  final a = apk ?? payload(3000, seed: 1);
  final z = zip ?? payload(5000, seed: 2);
  final json = <String, Object?>{
    'schema': 1,
    'version': version,
    'build': build ?? v.build,
    'publishedAt': '2026-10-07T12:00:00Z',
    'notes': {'en': 'Fixes.', 'ar': 'إصلاحات.'},
    'assets': {
      if (android)
        'android': {
          'name': 'app-release.apk',
          'url': assetUrl('app-release.apk', tag: 'v$version').toString(),
          'size': a.length,
          'sha256': sha256Hex(a),
        },
      if (windows)
        'windows': {
          'name': 'app-windows.zip',
          'url': assetUrl('app-windows.zip', tag: 'v$version').toString(),
          'size': z.length,
          'sha256': sha256Hex(z),
        },
    },
  };
  if (override != null) json.addAll(override);
  return json;
}

Uint8List jsonBytes(Object? json) =>
    Uint8List.fromList(utf8.encode(jsonEncode(json)));

http.StreamedResponse respond(
  List<int> body,
  int status, {
  Map<String, String> headers = const {},
  bool declareLength = true,
}) => http.StreamedResponse(
  Stream.value(body),
  status,
  contentLength: declareLength ? body.length : null,
  headers: headers,
);

/// A response whose body arrives in [chunks], one per pull, and that counts how
/// many chunks the reader actually asked for. A reader that stops early (size
/// cap, cancel) leaves [pulled] below `chunks.length`.
class CountingBody {
  CountingBody(this.chunks);

  final List<List<int>> chunks;
  int pulled = 0;

  Stream<List<int>> _generate() async* {
    for (final chunk in chunks) {
      pulled++;
      yield chunk;
      await Future<void>.delayed(Duration.zero);
    }
  }

  http.StreamedResponse response({int status = 200, int? declared}) =>
      http.StreamedResponse(_generate(), status, contentLength: declared);
}

/// A response that sends [first] and then nothing, ever.
class StallingBody {
  StallingBody(this.first);

  final List<int> first;

  /// The reader has started listening.
  bool listened = false;

  /// The reader has stopped listening (closed the connection).
  bool cancelled = false;

  http.StreamedResponse response({int? declared}) {
    final c = StreamController<List<int>>(
      onListen: () => listened = true,
      onCancel: () => cancelled = true,
    );
    c.add(first);
    return http.StreamedResponse(c.stream, 200, contentLength: declared);
  }
}

typedef Handler = FutureOr<http.StreamedResponse> Function(http.BaseRequest r);

/// A fake network. Unknown URLs answer 404. Every request is recorded.
class FakeNet {
  final Map<String, Handler> routes = {};
  final List<http.BaseRequest> requests = [];

  late final http.Client client = MockClient.streaming((req, _) async {
    requests.add(req);
    final route = routes[_key(req.url)];
    if (route == null) return respond(utf8.encode('not found'), 404);
    return await route(req);
  });

  static String _key(Uri u) => u.toString();

  List<String> get urls => [for (final r in requests) r.url.toString()];

  void on(Uri url, Handler h) => routes[_key(url)] = h;

  void serve(Uri url, List<int> body, {bool declareLength = true}) =>
      on(url, (_) => respond(body, 200, declareLength: declareLength));

  void redirect(Uri from, String to, [int code = 302]) =>
      on(from, (_) => respond(const [], code, headers: {'location': to}));
}

/// One simulated GitHub release plus everything a test needs around it.
class UpdateEnv {
  UpdateEnv._(this.signer, this.config, this.dir, this.version, this.platform);

  static Future<UpdateEnv> create({
    AppVersion? version,
    UpdatePlatform? platform = UpdatePlatform.android,
    TestSigner? signer,
    UpdateConfig Function(String publicKeyBase64)? configBuilder,
  }) async {
    final s = signer ?? await TestSigner.create();
    final dir = await Directory.systemTemp.createTemp('update-test-');
    final cfg = configBuilder != null
        ? configBuilder(s.publicKeyBase64)
        : UpdateConfig(
            publicKeyBase64: s.publicKeyBase64,
            requestTimeout: const Duration(seconds: 5),
            stallTimeout: const Duration(seconds: 5),
          );
    return UpdateEnv._(
      s,
      cfg,
      dir,
      version ?? AppVersion.tryParse('0.1.0')!,
      platform,
    );
  }

  final TestSigner signer;
  final UpdateConfig config;
  final Directory dir;
  final AppVersion version;
  final UpdatePlatform? platform;
  final FakeNet net = FakeNet();

  Directory get workRoot => Directory(p.join(dir.path, 'updates'));

  late final UpdateWorkspace workspace = UpdateWorkspace(workRoot);

  late final SecureDownloader downloader = SecureDownloader(net.client, config);

  late final UpdateService service = UpdateService(
    config: config,
    downloader: downloader,
    verifier: SodiumManifestVerifier(signer.sodium, config.publicKey),
    workspace: workspace,
    version: version,
    platform: platform,
  );

  AppSettings newSettings() => AppSettings(File(p.join(dir.path, 's.json')));

  /// Publishes [manifest] (default: a valid 0.2.0 one) and its signature the
  /// way GitHub serves "latest": through redirects into the tag's download URL
  /// and on to the CDN.
  void publish({
    Map<String, Object?>? manifest,
    Uint8List? manifestBytes,
    Uint8List? signatureBytes,
    TestSigner? signedBy,
    Uint8List? apk,
    Uint8List? zip,
  }) {
    final mBytes = manifestBytes ?? jsonBytes(manifest ?? manifestJson());
    final sig = signatureBytes ?? (signedBy ?? signer).signatureFile(mBytes);
    final tag = 'v0.2.0';
    for (final (name, body) in [
      (UpdateConfig.manifestFileName, mBytes),
      (UpdateConfig.signatureFileName, sig),
    ]) {
      net.redirect(
        Uri.https('github.com', '/$repo/releases/latest/download/$name'),
        'https://github.com/$repo/releases/download/$tag/$name',
      );
      net.redirect(
        assetUrl(name, tag: tag),
        'https://release-assets.githubusercontent.com/github-production-release-asset/1/$name?sp=r&sig=abc',
      );
      net.serve(
        Uri.parse(
          'https://release-assets.githubusercontent.com/github-production-release-asset/1/$name?sp=r&sig=abc',
        ),
        body,
      );
    }
    serveAsset('app-release.apk', apk ?? payload(3000, seed: 1));
    serveAsset('app-windows.zip', zip ?? payload(5000, seed: 2));
  }

  /// Serves a package from its tag URL through one CDN redirect.
  void serveAsset(String name, List<int> bytes, {String tag = 'v0.2.0'}) {
    final cdn = 'https://objects.githubusercontent.com/$tag/$name?sig=1';
    net.redirect(assetUrl(name, tag: tag), cdn);
    net.serve(Uri.parse(cdn), bytes);
  }

  Future<void> dispose() async {
    signer.dispose();
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Files left anywhere under the work root.
  List<FileSystemEntity> leftovers() =>
      workRoot.existsSync() ? workRoot.listSync(recursive: true) : const [];
}

/// Waits (polling) until [condition] holds, so tests do not depend on how
/// slow the machine is.
Future<void> waitFor(bool Function() condition) async {
  final end = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(end)) throw StateError('condition not reached');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
