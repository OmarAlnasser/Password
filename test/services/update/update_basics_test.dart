import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/services/update/app_version.dart';
import 'package:hisn/services/update/update_config.dart';
import 'package:hisn/services/update/update_failure.dart';
import 'package:hisn/services/update/update_manifest.dart';
import 'package:hisn/services/update/update_public_key.dart';

import 'update_test_kit.dart';

void main() {
  group('pinned public key', () {
    test('the Dart constant equals release/update_public_key.txt', () {
      final file = File('release/update_public_key.txt').readAsStringSync();
      expect(updatePublicKeyBase64, file.trim());
    });

    test('is 32 raw bytes and is what the default config uses', () {
      final raw = base64.decode(updatePublicKeyBase64);
      expect(raw, hasLength(32));
      expect(UpdateConfig().publicKey, raw);
    });

    test('a config refuses a key of the wrong size or format', () {
      expect(
        () => UpdateConfig(publicKeyBase64: base64.encode([1, 2, 3])),
        throwsArgumentError,
      );
      expect(
        () => UpdateConfig(publicKeyBase64: '***not base64***'),
        throwsArgumentError,
      );
    });
  });

  group('UpdateConfig', () {
    final config = UpdateConfig();

    test('defaults: repository, URLs, limits', () {
      expect(config.repo, 'OmarAlnasser/Password');
      expect(
        config.manifestUri.toString(),
        'https://github.com/OmarAlnasser/Password/releases/latest/download/update.json',
      );
      expect(
        config.signatureUri.toString(),
        'https://github.com/OmarAlnasser/Password/releases/latest/download/update.json.sig',
      );
      expect(config.maxManifestBytes, 64 * 1024);
      expect(config.maxAssetBytes, 400 * 1024 * 1024);
      expect(config.maxRedirects, 5);
      expect(config.checkInterval, const Duration(hours: 24));
    });

    test('the host allow-list is exact: no wildcard subdomains', () {
      expect(UpdateConfig.defaultAllowedHosts, {
        'github.com',
        'objects.githubusercontent.com',
        'release-assets.githubusercontent.com',
      });
      for (final bad in [
        'https://raw.githubusercontent.com/x',
        'https://gist.githubusercontent.com/x',
        'https://evil.github.com/x',
        'https://github.com.evil.com/x',
        'https://notgithub.com/x',
        'https://github.com./x',
        'https://api.github.com/x',
      ]) {
        expect(
          config.rejectUrl(Uri.parse(bad)),
          UpdateFailure.hostNotAllowed,
          reason: bad,
        );
      }
    });

    test('rejectUrl: https only, no credentials, only port 443', () {
      expect(
        config.rejectUrl(Uri.parse('http://github.com/x')),
        UpdateFailure.insecureUrl,
      );
      expect(
        config.rejectUrl(Uri.parse('ftp://github.com/x')),
        UpdateFailure.hostNotAllowed,
      );
      expect(
        config.rejectUrl(Uri.parse('https://user:pw@github.com/x')),
        UpdateFailure.hostNotAllowed,
      );
      expect(
        config.rejectUrl(Uri.parse('https://github.com@evil.com/x')),
        UpdateFailure.hostNotAllowed,
      );
      expect(
        config.rejectUrl(Uri.parse('https://github.com:8443/x')),
        UpdateFailure.hostNotAllowed,
      );
      expect(config.rejectUrl(Uri.parse('https://github.com:443/x')), isNull);
      expect(config.rejectUrl(Uri.parse('https://GitHub.com/x')), isNull);
      expect(
        config.rejectUrl(
          Uri.parse('https://objects.githubusercontent.com/a?b=c'),
        ),
        isNull,
      );
      expect(config.rejectUrl(Uri.parse('/relative/path')), isNotNull);
    });

    test('a repository name must look like owner/name', () {
      expect(() => UpdateConfig(repo: 'no-slash'), throwsArgumentError);
      expect(() => UpdateConfig(repo: 'a/b/c'), throwsArgumentError);
      expect(() => UpdateConfig(repo: '../x'), throwsArgumentError);
    });
  });

  group('AppVersion', () {
    test('build = major*1000000 + minor*1000 + patch', () {
      expect(AppVersion.tryParse('0.2.0')!.build, 2000);
      expect(AppVersion.tryParse('1.0.0')!.build, 1000000);
      expect(AppVersion.tryParse('1.12.345')!.build, 1012345);
      expect(AppVersion.buildOf(2, 3, 4), 2003004);
    });

    test('only strict major.minor.patch is accepted', () {
      for (final bad in [
        '',
        '1',
        '1.2',
        '1.2.3.4',
        'v1.2.3',
        '1.2.3-beta',
        '1.2.3+4',
        '01.2.3',
        '1.02.3',
        '1.2.03',
        '1.2.1000',
        '1.1000.0',
        '2001.0.0',
        '0.0.0',
        '-1.2.3',
        '1.2.x',
        ' 1.2.3',
        '1.2.3 ',
        '1.2.3\n',
      ]) {
        expect(AppVersion.tryParse(bad), isNull, reason: '"$bad"');
      }
      expect(AppVersion.tryParse('2000.999.999'), isNotNull);
      // The largest build fits Android's signed 32-bit versionCode.
      expect(AppVersion.tryParse('2000.999.999')!.build, lessThan(1 << 31));
    });

    test('a build that does not match the version is refused', () {
      expect(AppVersion.tryParse('0.2.0', build: 2000), isNotNull);
      expect(AppVersion.tryParse('0.2.0', build: 2001), isNull);
      expect(AppVersion.tryParse('0.2.0', build: 0), isNull);
    });

    test('fromDefines: enabled only with a consistent version', () {
      expect(AppVersion.fromDefines('0.2.0', 2000).enabled, isTrue);
      expect(AppVersion.fromDefines('0.2.0', 2000).version, '0.2.0');
      // No explicit build: derived from the version.
      expect(AppVersion.fromDefines('0.2.0', 0).build, 2000);
      // Missing, broken or inconsistent: disabled, never half working.
      expect(AppVersion.fromDefines('', 0).enabled, isFalse);
      expect(AppVersion.fromDefines('', 2000).enabled, isFalse);
      expect(AppVersion.fromDefines('banana', 5).enabled, isFalse);
      expect(AppVersion.fromDefines('0.2.0', 9999).enabled, isFalse);
      expect(AppVersion.none.enabled, isFalse);
      expect(AppVersion.none.build, 0);
    });

    test('this test run is a development build: updater disabled', () {
      const defined = String.fromEnvironment('APP_VERSION');
      expect(AppVersion.current.enabled, defined.isNotEmpty);
    });

    test('comparison is by build number', () {
      final a = AppVersion.tryParse('0.9.9')!;
      final b = AppVersion.tryParse('0.10.0')!;
      expect(b.isNewerThan(a), isTrue);
      expect(a.isNewerThan(b), isFalse);
      expect(a.isNewerThan(a), isFalse);
      expect(a, AppVersion.tryParse('0.9.9'));
    });
  });

  group('UpdateManifest.parse', () {
    final config = UpdateConfig();

    UpdateManifest parse(Object? json) =>
        UpdateManifest.parse(jsonBytes(json), config);

    void rejects(Object? json, {UpdateFailure? why, String? reason}) {
      expect(
        () => parse(json),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.reason,
            'reason',
            why ?? UpdateFailure.manifestInvalid,
          ),
        ),
        reason: reason,
      );
    }

    Map<String, Object?> withAsset(Map<String, Object?> changes) {
      final m = manifestJson();
      final assets = Map<String, Object?>.from(m['assets']! as Map);
      final android = Map<String, Object?>.from(assets['android']! as Map)
        ..addAll(changes);
      assets['android'] = android;
      m['assets'] = assets;
      return m;
    }

    test('a good manifest', () {
      final m = parse(manifestJson());
      expect(m.version.version, '0.2.0');
      expect(m.build, 2000);
      expect(m.publishedAt, DateTime.utc(2026, 10, 7, 12));
      expect(m.notes['en'], 'Fixes.');
      expect(m.notesFor('ar'), 'إصلاحات.');
      expect(m.notesFor('fr'), 'Fixes.'); // falls back to English
      final apk = m.assetFor(UpdatePlatform.android)!;
      expect(apk.name, 'app-release.apk');
      expect(apk.size, 3000);
      expect(apk.sha256, sha256Hex(payload(3000, seed: 1)));
      expect(apk.url.host, 'github.com');
      expect(m.assetFor(UpdatePlatform.windows)!.name, 'app-windows.zip');
      expect(m.assets, isA<Map<String, UpdateAsset>>());
      expect(() => m.assets['x'] = apk, throwsUnsupportedError);
    });

    test('unknown extra keys are ignored (the signature covers them)', () {
      final m = parse(manifestJson(override: {'future': true}));
      expect(m.build, 2000);
    });

    test('uppercase hex is accepted and normalised', () {
      final upper = sha256Hex(payload(3000, seed: 1)).toUpperCase();
      final m = parse(withAsset({'sha256': upper}));
      expect(m.assetFor(UpdatePlatform.android)!.sha256, upper.toLowerCase());
    });

    test('unknown schema', () {
      rejects(
        manifestJson(override: {'schema': 2}),
        why: UpdateFailure.unsupportedSchema,
      );
      rejects(
        manifestJson(override: {'schema': 0}),
        why: UpdateFailure.unsupportedSchema,
      );
      rejects(manifestJson(override: {'schema': '1'}));
      rejects(manifestJson(override: {'schema': 1.0}));
      rejects(manifestJson()..remove('schema'));
    });

    test('top level must be an object', () {
      rejects([1, 2]);
      rejects('manifest');
      rejects(null);
      rejects(7);
    });

    test('version and build', () {
      rejects(manifestJson(override: {'version': 'v0.2.0'}));
      rejects(manifestJson(override: {'version': '0.2'}));
      rejects(manifestJson(override: {'version': '0.2.0-beta'}));
      rejects(manifestJson(override: {'version': 2}));
      rejects(
        manifestJson(override: {'build': 2001}),
      ); // not the build of 0.2.0
      rejects(manifestJson(override: {'build': '2000'}));
      rejects(manifestJson(override: {'build': 2000.0}));
      rejects(manifestJson(override: {'build': -2000}));
      rejects(manifestJson(override: {'version': 'x' * 100}));
      rejects(manifestJson()..remove('version'));
      rejects(manifestJson()..remove('build'));
    });

    test('publishedAt', () {
      rejects(manifestJson(override: {'publishedAt': 'yesterday'}));
      rejects(manifestJson(override: {'publishedAt': '2026-10-07'}));
      rejects(manifestJson(override: {'publishedAt': '2026-10-07T12:00:00'}));
      rejects(manifestJson(override: {'publishedAt': 1790000000}));
      rejects(manifestJson(override: {'publishedAt': 'x' * 100}));
      rejects(manifestJson()..remove('publishedAt'));
      parse(
        manifestJson(override: {'publishedAt': '2026-10-07T12:00:00.123Z'}),
      );
    });

    test('notes', () {
      parse(manifestJson(override: {'notes': <String, Object?>{}}));
      rejects(manifestJson(override: {'notes': 'text'}));
      rejects(
        manifestJson(
          override: {
            'notes': ['x'],
          },
        ),
      );
      rejects(
        manifestJson(
          override: {
            'notes': {'en': 1},
          },
        ),
      );
      rejects(
        manifestJson(
          override: {
            'notes': {'EN': 'upper-case language'},
          },
        ),
      );
      rejects(
        manifestJson(
          override: {
            'notes': {'en': 'x' * (UpdateManifest.maxNotesLength + 1)},
          },
        ),
      );
      rejects(
        manifestJson(
          override: {
            'notes': {'en': 'bell\u0007'},
          },
        ),
      );
      rejects(
        manifestJson(
          override: {
            'notes': {
              for (var i = 0; i < 9; i++)
                'a${String.fromCharCode(97 + i)}': 'x',
            },
          },
        ),
      );
      // Newlines and tabs are fine in notes.
      parse(
        manifestJson(
          override: {
            'notes': {'en': 'a\nb\tc'},
          },
        ),
      );
    });

    test('assets: structure', () {
      rejects(manifestJson(override: {'assets': <String, Object?>{}}));
      rejects(manifestJson(override: {'assets': []}));
      rejects(manifestJson(override: {'assets': 'x'}));
      rejects(manifestJson()..remove('assets'));
      rejects(
        manifestJson(
          override: {
            'assets': {'android': 'not an object'},
          },
        ),
      );
      rejects(
        manifestJson(
          override: {
            'assets': {
              for (var i = 0; i < 9; i++)
                'p${String.fromCharCode(97 + i)}':
                    (manifestJson()['assets']! as Map)['android'],
            },
          },
        ),
      );
      for (final field in ['name', 'url', 'size', 'sha256']) {
        final m = withAsset({});
        ((m['assets']! as Map)['android'] as Map).remove(field);
        rejects(m, reason: 'missing $field');
      }
    });

    test('assets: size', () {
      rejects(withAsset({'size': 0}));
      rejects(withAsset({'size': -1}));
      rejects(withAsset({'size': 1.5}));
      rejects(withAsset({'size': '3000'}));
      rejects(withAsset({'size': 400 * 1024 * 1024 + 1}));
      parse(withAsset({'size': 400 * 1024 * 1024}));
    });

    test('assets: sha256 must be 64 hex characters', () {
      for (final bad in [
        '',
        'abc',
        'g' * 64,
        'a' * 63,
        'a' * 65,
        ' ${'a' * 63}',
        '${'a' * 63}\n',
        'z' * 64,
      ]) {
        rejects(withAsset({'sha256': bad}), reason: bad);
      }
      rejects(withAsset({'sha256': 12345}));
    });

    test('assets: file name', () {
      for (final bad in [
        '',
        '../app.apk',
        'a/b.apk',
        r'a\b.apk',
        '.hidden.apk',
        'a..b.apk',
        'app release.apk',
        'app%2Erelease.apk',
        'app.zip', // wrong extension for android
        'x' * 100 + '.apk',
      ]) {
        rejects(
          withAsset({'name': bad, 'url': assetUrl(bad).toString()}),
          reason: bad,
        );
      }
    });

    test('assets: url must be https, on github.com, in this repository', () {
      final ok = assetUrl('app-release.apk').toString();
      rejects(withAsset({'url': ok.replaceFirst('https', 'http')}));
      rejects(withAsset({'url': ok.replaceFirst('github.com', 'evil.com')}));
      rejects(
        withAsset({
          'url': ok.replaceFirst('github.com', 'github.com.evil.com'),
        }),
      );
      rejects(withAsset({'url': ok.replaceFirst('https://', 'https://u:p@')}));
      rejects(
        withAsset({'url': ok.replaceFirst('github.com', 'github.com:8443')}),
      );
      rejects(withAsset({'url': '$ok?x=1'}));
      rejects(withAsset({'url': '$ok#frag'}));
      rejects(
        withAsset({
          'url':
              'ftp://github.com/$repo/releases/download/v0.2.0/app-release.apk',
        }),
      );
      rejects(withAsset({'url': '/relative/app-release.apk'}));
      rejects(withAsset({'url': ''}));
      rejects(withAsset({'url': 5}));
      // Another repository on github.com.
      rejects(
        withAsset({
          'url': 'https://github.com/someone/else/releases/download/v0.2.0/app-release.apk',
        }),
      );
      // Not the download path of releases.
      rejects(
        withAsset({'url': 'https://github.com/$repo/raw/main/app-release.apk'}),
      );
      // Allow-listed CDN hosts are only reached by redirect, never named here.
      rejects(
        withAsset({
          'url':
              'https://objects.githubusercontent.com/$repo/releases/download/v0.2.0/app-release.apk',
        }),
      );
      // The file name must be the last path segment.
      rejects(withAsset({'url': assetUrl('other.apk').toString()}));
      rejects(withAsset({'url': '${assetUrl('app-release.apk')}/'}));
      rejects(withAsset({'url': 'https://${'a' * 600}.com/x'}));
    });

    test('malformed JSON, empty and oversized input', () {
      for (final bytes in [
        Uint8List(0),
        Uint8List.fromList(utf8.encode('{')),
        Uint8List.fromList(utf8.encode('not json')),
        Uint8List.fromList([0xff, 0xfe, 0x00]),
        Uint8List.fromList([0xef, 0xbb, 0xbf, ...utf8.encode('{}')]),
        Uint8List.fromList(utf8.encode('{"schema":1,}')),
      ]) {
        expect(
          () => UpdateManifest.parse(bytes, config),
          throwsA(isA<UpdateException>()),
        );
      }
      final huge = jsonBytes(
        manifestJson(override: {'pad': 'x' * (config.maxManifestBytes + 1)}),
      );
      expect(huge.length, greaterThan(config.maxManifestBytes));
      expect(
        () => UpdateManifest.parse(huge, config),
        throwsA(isA<UpdateException>()),
      );
    });

    test('the exception text never carries input', () {
      try {
        parse(manifestJson(override: {'version': 'SECRET-VALUE'}));
        fail('should throw');
      } on UpdateException catch (e) {
        expect(e.toString(), 'UpdateException(manifestInvalid)');
      }
    });
  });
}
