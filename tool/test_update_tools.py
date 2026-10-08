#!/usr/bin/env python3
"""Tests for the release tooling: make_update_manifest.py, verify_update_manifest.py
and the release workflow.

    python3 tool/test_update_tools.py                    # all tests
    python3 tool/test_update_tools.py -v                 # names
    python3 tool/test_update_tools.py --write-fixtures   # rewrite the Dart fixtures

Standard library only. Two optional packages make the suite stronger:

* `cryptography` (OpenSSL): an independent Ed25519 implementation, to prove
  that the pure-Python signer produces exactly what other software verifies
  (the app verifies with libsodium).
* `PyYAML`: for the static checks of .github/workflows/release.yml.

Without them those tests are skipped. With REQUIRE_OPTIONAL_TESTS=1 (the
release workflow sets it) a missing package is a failure instead.

Every key used here is a THROWAWAY derived from a public string. None of them
is the release key, and the real private keys are never read.
"""
from __future__ import annotations

import base64
import contextlib
import copy
import hashlib
import importlib.util
import io
import json
import os
import re
import shutil
import ssl
import subprocess
import sys
import tempfile
import unittest
import urllib.error
import urllib.request
import zipfile
from pathlib import Path
from typing import Any, Dict, List, Optional
from unittest import mock

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
MAKE = HERE / 'make_update_manifest.py'
VERIFY = HERE / 'verify_update_manifest.py'
THIS_FILE = Path(__file__).resolve()
FIXTURE_DIR = ROOT / 'test' / 'services' / 'update' / 'fixtures' / 'release_tool'
PINNED_KEY_FILE = ROOT / 'release' / 'update_public_key.txt'
WORKFLOW = ROOT / '.github' / 'workflows' / 'release.yml'
DART_DIR = ROOT / 'lib' / 'services' / 'update'

REQUIRE_OPTIONAL = os.environ.get('REQUIRE_OPTIONAL_TESTS') == '1'


def _load(name: str, path: Path) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


verify = _load('verify_update_manifest', VERIFY)
mum = verify.shared                      # the signing tool, as the verifier loads it
ToolError = mum.ToolError

try:
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric.ed25519 import (
        Ed25519PrivateKey, Ed25519PublicKey)
    from cryptography.exceptions import InvalidSignature
    HAVE_CRYPTOGRAPHY = True
except ImportError:  # pragma: no cover - depends on the machine
    HAVE_CRYPTOGRAPHY = False

try:
    import yaml  # type: ignore[import-untyped]
    HAVE_YAML = True
except ImportError:  # pragma: no cover
    HAVE_YAML = False

# A public string, hashed. Never a real key (see the module docstring).
THROWAWAY_SEED = hashlib.sha256(
    b'update-tools-test-fixture: throwaway key, never a release key').digest()
THROWAWAY_SEED_B64 = base64.b64encode(THROWAWAY_SEED).decode()
OTHER_SEED = hashlib.sha256(b'update-tools-test: a second throwaway key').digest()
REPO = 'OmarAlnasser/Password'
PUBLISHED_AT = '2026-10-07T12:00:00Z'

NOTES_EN = 'Fixes and improvements.\n\n- Faster start-up\n- Smaller download\n'
NOTES_AR = 'إصلاحات وتحسينات.\n\n- بدء تشغيل أسرع\n- حجم تنزيل أصغر\n'


def public_of(seed: bytes) -> bytes:
    return mum.ed25519_public_key(seed)


def expand(label: str, size: int) -> bytes:
    """Deterministic filler bytes."""
    out = b''
    counter = 0
    while len(out) < size:
        out += hashlib.sha256(f'{label}/{counter}'.encode()).digest()
        counter += 1
    return out[:size]


def write_zip(path: Path, files: Dict[str, bytes]) -> None:
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_STORED) as archive:
        for name, data in files.items():
            info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_STORED
            info.create_system = 3
            info.external_attr = 0o644 << 16
            archive.writestr(info, data)


def write_fake_apk(path: Path) -> None:
    write_zip(path, {
        'AndroidManifest.xml': b'fixture manifest, not a real APK\n',
        'classes.dex': b'dex\n035\0' + expand('classes.dex', 700),
        'META-INF/CERT.RSA': expand('cert', 120),
    })


def write_fake_windows_zip(path: Path) -> None:
    write_zip(path, {
        'app.exe': b'MZ' + expand('app.exe', 500),
        'flutter_windows.dll': b'MZ' + expand('flutter_windows.dll', 900),
        'data/app.so': expand('app.so', 400),
    })


def run_python(script: Path, args: List[str], *, key: Optional[str] = None,
               cwd: Optional[Path] = None) -> subprocess.CompletedProcess:
    env = {k: v for k, v in os.environ.items()
           if k not in ('UPDATE_SIGNING_KEY', 'PYTHONPATH')}
    if key is not None:
        env['UPDATE_SIGNING_KEY'] = key
    return subprocess.run(
        [sys.executable, '-I', str(script), *args], env=env, cwd=cwd,
        capture_output=True, text=True, timeout=180, check=False)


def good_manifest() -> Dict[str, Any]:
    def asset(name: str, size: int) -> Dict[str, Any]:
        return {
            'name': name,
            'url': mum.asset_url(REPO, 'v0.2.0', name),
            'size': size,
            'sha256': hashlib.sha256(name.encode()).hexdigest(),
        }
    return mum.build_manifest(
        version='0.2.0', build=2000, published_at=PUBLISHED_AT,
        notes={'en': 'Fixes.', 'ar': 'إصلاحات.'},
        assets={'android': asset('android.apk', 1234),
                'windows': asset('windows-x64.zip', 5678)})


def optional_missing(what: str) -> None:
    if REQUIRE_OPTIONAL:
        raise AssertionError(f'{what} is required (REQUIRE_OPTIONAL_TESTS=1)')


# --------------------------------------------------------------------------
# Ed25519
# --------------------------------------------------------------------------

class Ed25519Tests(unittest.TestCase):
    # RFC 8032, section 7.1, tests 1 and 2.
    VECTORS = [
        ('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60',
         'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a',
         '',
         'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155'
         '5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b'),
        ('4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb',
         '3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c',
         '72',
         '92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da'
         '085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00'),
    ]

    def test_rfc8032_vectors(self) -> None:
        for seed_hex, public_hex, message_hex, signature_hex in self.VECTORS:
            seed = bytes.fromhex(seed_hex)
            message = bytes.fromhex(message_hex)
            self.assertEqual(mum.ed25519_public_key(seed).hex(), public_hex)
            signature = mum.ed25519_sign(seed, message)
            self.assertEqual(signature.hex(), signature_hex)
            self.assertTrue(mum.ed25519_verify(
                bytes.fromhex(public_hex), message, signature))

    def test_matches_cryptography(self) -> None:
        if not HAVE_CRYPTOGRAPHY:
            optional_missing('the cryptography package')
            self.skipTest('cryptography is not installed')
        for i in range(24):
            seed = hashlib.sha256(f'cross-check seed {i}'.encode()).digest()
            message = expand(f'cross-check message {i}', i * 37)
            reference = Ed25519PrivateKey.from_private_bytes(seed)
            reference_public = reference.public_key().public_bytes(
                serialization.Encoding.Raw, serialization.PublicFormat.Raw)
            self.assertEqual(mum.ed25519_public_key(seed), reference_public)
            signature = mum.ed25519_sign(seed, message)
            # Ed25519 is deterministic: the signatures are byte-identical.
            self.assertEqual(signature, reference.sign(message))
            Ed25519PublicKey.from_public_bytes(reference_public).verify(
                signature, message)
            self.assertTrue(mum.ed25519_verify(reference_public, message, signature))

    def test_verify_agrees_with_cryptography_on_corrupt_input(self) -> None:
        if not HAVE_CRYPTOGRAPHY:
            optional_missing('the cryptography package')
            self.skipTest('cryptography is not installed')
        seed = THROWAWAY_SEED
        public = public_of(seed)
        message = b'agree on rejections'
        signature = mum.ed25519_sign(seed, message)
        reference = Ed25519PublicKey.from_public_bytes(public)
        for index in range(0, 64, 3):
            corrupt = bytearray(signature)
            corrupt[index] ^= 0x04
            with self.assertRaises(InvalidSignature):
                reference.verify(bytes(corrupt), message)
            self.assertFalse(mum.ed25519_verify(public, message, bytes(corrupt)))

    def test_rejects_changed_message_signature_and_key(self) -> None:
        public = public_of(THROWAWAY_SEED)
        message = b'the exact bytes'
        signature = mum.ed25519_sign(THROWAWAY_SEED, message)
        self.assertTrue(mum.ed25519_verify(public, message, signature))
        self.assertFalse(mum.ed25519_verify(public, message + b'\n', signature))
        self.assertFalse(mum.ed25519_verify(public, message[:-1], signature))
        self.assertFalse(mum.ed25519_verify(public_of(OTHER_SEED), message, signature))
        for index in range(64):
            corrupt = bytearray(signature)
            corrupt[index] ^= 0x01
            self.assertFalse(mum.ed25519_verify(public, message, bytes(corrupt)),
                             f'signature byte {index}')
        for index in range(32):
            corrupt = bytearray(public)
            corrupt[index] ^= 0x01
            self.assertFalse(mum.ed25519_verify(bytes(corrupt), message, signature),
                             f'key byte {index}')

    def test_rejects_wrong_lengths(self) -> None:
        public = public_of(THROWAWAY_SEED)
        signature = mum.ed25519_sign(THROWAWAY_SEED, b'm')
        self.assertFalse(mum.ed25519_verify(public[:31], b'm', signature))
        self.assertFalse(mum.ed25519_verify(public + b'\0', b'm', signature))
        self.assertFalse(mum.ed25519_verify(public, b'm', signature[:63]))
        self.assertFalse(mum.ed25519_verify(public, b'm', signature + b'\0'))
        with self.assertRaises(ToolError):
            mum.ed25519_sign(THROWAWAY_SEED[:31], b'm')
        with self.assertRaises(ToolError):
            mum.ed25519_public_key(THROWAWAY_SEED + b'\0')

    def test_rejects_malleable_signature(self) -> None:
        """S + L is the same point equation, but a canonical signature has S < L."""
        public = public_of(THROWAWAY_SEED)
        signature = mum.ed25519_sign(THROWAWAY_SEED, b'malleable')
        s = int.from_bytes(signature[32:], 'little')
        forged = signature[:32] + int.to_bytes(s + mum._Q, 32, 'little')
        self.assertFalse(mum.ed25519_verify(public, b'malleable', forged))
        if HAVE_CRYPTOGRAPHY:
            with self.assertRaises(InvalidSignature):
                Ed25519PublicKey.from_public_bytes(public).verify(
                    forged, b'malleable')

    def test_rejects_small_order_and_non_canonical_points(self) -> None:
        identity = b'\x01' + b'\x00' * 31
        # With a small-order key and R the verification equation holds
        # trivially (S = 0); libsodium refuses, and so must this.
        self.assertFalse(mum.ed25519_verify(identity, b'x', identity + b'\x00' * 32))
        public = public_of(THROWAWAY_SEED)
        signature = mum.ed25519_sign(THROWAWAY_SEED, b'x')
        self.assertFalse(mum.ed25519_verify(identity, b'x', signature))
        self.assertFalse(mum.ed25519_verify(public, b'x', identity + signature[32:]))
        # y = p is not a canonical encoding.
        not_canonical = int.to_bytes(mum._P, 32, 'little')
        self.assertFalse(mum.ed25519_verify(not_canonical, b'x', signature))
        self.assertFalse(mum.ed25519_verify(public, b'x', not_canonical + signature[32:]))


# --------------------------------------------------------------------------
# The manifest format
# --------------------------------------------------------------------------

GOLDEN_MANIFEST = '''{
  "schema": 1,
  "version": "0.2.0",
  "build": 2000,
  "publishedAt": "2026-10-07T12:00:00Z",
  "notes": {
    "en": "Fixes.",
    "ar": "إصلاحات."
  },
  "assets": {
    "android": {
      "name": "android.apk",
      "url": "https://github.com/OmarAlnasser/Password/releases/download/v0.2.0/android.apk",
      "size": 1234,
      "sha256": "SHA_ANDROID"
    },
    "windows": {
      "name": "windows-x64.zip",
      "url": "https://github.com/OmarAlnasser/Password/releases/download/v0.2.0/windows-x64.zip",
      "size": 5678,
      "sha256": "SHA_WINDOWS"
    }
  }
}
'''


class CanonicalBytesTests(unittest.TestCase):
    def test_golden_bytes(self) -> None:
        expected = (GOLDEN_MANIFEST
                    .replace('SHA_ANDROID', hashlib.sha256(b'android.apk').hexdigest())
                    .replace('SHA_WINDOWS', hashlib.sha256(b'windows-x64.zip').hexdigest()))
        self.assertEqual(mum.canonical_bytes(good_manifest()), expected.encode('utf-8'))

    def test_format_properties(self) -> None:
        raw = mum.canonical_bytes(good_manifest())
        self.assertTrue(raw.endswith(b'}\n'))
        self.assertFalse(raw.endswith(b'\n\n'))
        self.assertFalse(raw.startswith(b'\xef\xbb\xbf'), 'no BOM')
        self.assertNotIn(b'\r', raw)
        self.assertNotIn(b'\\u', raw, 'Arabic is written as UTF-8, not escaped')
        self.assertIn('إصلاحات'.encode('utf-8'), raw)
        raw.decode('utf-8')

    def test_key_order_is_fixed(self) -> None:
        data = json.loads(mum.canonical_bytes(good_manifest()))
        self.assertEqual(list(data), ['schema', 'version', 'build', 'publishedAt',
                                      'notes', 'assets'])
        self.assertEqual(list(data['assets']), ['android', 'windows'])
        for asset in data['assets'].values():
            self.assertEqual(list(asset), ['name', 'url', 'size', 'sha256'])

    def test_round_trip_is_stable(self) -> None:
        raw = mum.canonical_bytes(good_manifest())
        again = mum.canonical_bytes(mum.parse_manifest_bytes(raw))
        self.assertEqual(raw, again)

    def test_extra_keys_in_inputs_are_not_copied(self) -> None:
        assets = good_manifest()['assets']
        assets['android']['evil'] = 'x'
        manifest = mum.build_manifest(version='0.2.0', build=2000,
                                      published_at=PUBLISHED_AT, notes={'en': 'x'},
                                      assets=assets)
        self.assertNotIn('evil', manifest['assets']['android'])


class NotesTests(unittest.TestCase):
    def test_cleaning(self) -> None:
        raw = '\ufeffLine one  \r\nLine two\r\rLine\x00 three\x07\u200b\t\n\n\n'
        self.assertEqual(mum.clean_notes(raw), 'Line one\nLine two\n\nLine three\u200b')

    def test_tab_and_arabic_survive(self) -> None:
        self.assertEqual(mum.clean_notes('a\tb\nإصلاحات'), 'a\tb\nإصلاحات')

    def test_length_cap_counts_utf16_units(self) -> None:
        long_text = ('\U0001F600' * 3000)       # 2 UTF-16 units each
        cleaned = mum.clean_notes(long_text)
        self.assertLessEqual(mum.utf16_len(cleaned), mum.MAX_NOTES_UNITS)
        self.assertTrue(cleaned.endswith('…'))
        arabic = 'كلمة ' * 2000
        cleaned = mum.clean_notes(arabic)
        self.assertLessEqual(mum.utf16_len(cleaned), mum.MAX_NOTES_UNITS)
        self.assertEqual(mum.clean_notes('short'), 'short')

    def test_cut_prefers_a_line_break(self) -> None:
        lines = '\n'.join(f'- change number {i}' for i in range(1000))
        cleaned = mum.clean_notes(lines)
        self.assertLessEqual(mum.utf16_len(cleaned), mum.MAX_NOTES_UNITS)
        body = cleaned[:-2]
        self.assertTrue(body.split('\n')[-1].startswith('- change number '))
        self.assertRegex(body.split('\n')[-1], r'^- change number [0-9]+$')


class VersionTests(unittest.TestCase):
    def test_valid(self) -> None:
        for text, expected in [('0.2.0', (0, 2, 0)), ('1.10.3', (1, 10, 3)),
                               ('0.0.1', (0, 0, 1)),
                               ('2000.999.999', (2000, 999, 999))]:
            self.assertEqual(mum.parse_version(text), expected)

    def test_invalid(self) -> None:
        for text in ['', '0.0.0', '1', '1.2', '1.2.3.4', 'v1.2.3', '1.2.3-rc1',
                     '01.2.3', '1.02.3', '1.2.03', ' 1.2.3', '1.2.3 ', '1.2.3\n',
                     '2001.0.0', '1.1000.0', '1.0.1000', '-1.0.0', '1.2.x',
                     '١.٢.٣', '1_0.2.3', '0' * 33]:
            with self.assertRaises(ToolError, msg=repr(text)):
                mum.parse_version(text)

    def test_build_number(self) -> None:
        self.assertEqual(mum.build_of(0, 2, 0), 2000)
        self.assertEqual(mum.build_of(1, 10, 3), 1010003)
        self.assertEqual(mum.build_of(2000, 999, 999), 2000999999)
        self.assertLess(mum.build_of(2000, 999, 999), 2 ** 31 - 1,
                        'fits Android versionCode')
        self.assertLess(mum.build_of(1, 9, 9), mum.build_of(1, 10, 0))

    def test_repo(self) -> None:
        self.assertEqual(mum.parse_repo('OmarAlnasser/Password'), 'OmarAlnasser/Password')
        for text in ['', 'a', 'a/b/c', '../x', 'a/..', '.a/b', 'a /b', 'a/b\n',
                     '/a/b', 'a/b?x=1', 'a b/c']:
            with self.assertRaises(ToolError, msg=repr(text)):
                mum.parse_repo(text)


def mutated(*path_and_value: Any) -> Dict[str, Any]:
    *path, value = path_and_value
    data = good_manifest()
    node = data
    for key in path[:-1]:
        node = node[key]
    if value is _DELETE:
        del node[path[-1]]
    else:
        node[path[-1]] = value
    return data


_DELETE = object()


class ManifestValidationTests(unittest.TestCase):
    def test_good_manifest(self) -> None:
        mum.validate_manifest(good_manifest())
        mum.check_release_layout(good_manifest(), repo=REPO, tag='v0.2.0',
                                 version='0.2.0')

    def assert_bad(self, data: Any, why: str) -> None:
        with self.assertRaises(ToolError, msg=why):
            mum.validate_manifest(data)

    def test_root_and_schema(self) -> None:
        self.assert_bad([], 'root is a list')
        self.assert_bad('x', 'root is a string')
        self.assert_bad(mutated('schema', 2), 'schema 2')
        self.assert_bad(mutated('schema', '1'), 'schema string')
        self.assert_bad(mutated('schema', True), 'schema bool')
        self.assert_bad(mutated('schema', _DELETE), 'no schema')

    def test_version_and_build(self) -> None:
        for bad in ['0.2', 'v0.2.0', '0.2.0\n', ' 0.2.0', '0.2.0-beta', 7, None]:
            self.assert_bad(mutated('version', bad), f'version {bad!r}')
        for bad in [2001, 1999, 0, -1, 2000.0, '2000', True, None]:
            self.assert_bad(mutated('build', bad), f'build {bad!r}')

    def test_published_at(self) -> None:
        for bad in ['2026-10-07 12:00:00Z', '2026-10-07T12:00:00+00:00',
                    '2026-10-07T12:00:00', '2026-13-07T12:00:00Z',
                    '2026-10-07T25:00:00Z', '2026-10-07T12:00:00Z\n', '', 5, None,
                    '2026-10-07T12:00:00.1234567Z']:
            self.assert_bad(mutated('publishedAt', bad), f'publishedAt {bad!r}')
        for good in ['2026-10-07T12:00:00Z', '2026-10-07T12:00:00.123Z']:
            mum.validate_manifest(mutated('publishedAt', good))

    def test_notes(self) -> None:
        self.assert_bad(mutated('notes', []), 'notes list')
        self.assert_bad(mutated('notes', {'EN': 'x'}), 'upper-case language')
        self.assert_bad(mutated('notes', {'english': 'x'}), 'long language')
        self.assert_bad(mutated('notes', {'en': 5}), 'non-string note')
        self.assert_bad(mutated('notes', {'en': 'x' * 4001}), 'too long')
        self.assert_bad(mutated('notes', {'en': 'a\x00b'}), 'NUL')
        self.assert_bad(mutated('notes', {'en': 'a\x1bb'}), 'ESC')
        self.assert_bad(mutated('notes', {f'a{chr(97 + i)}': 'x' for i in range(9)}),
                        'nine languages')
        self.assert_bad(mutated('notes', {'en': '\U0001F600' * 2001}),
                        'surrogate pairs count as two units')
        mum.validate_manifest(mutated('notes', {'en': 'x' * 4000}))
        mum.validate_manifest(mutated('notes', {}))
        mum.validate_manifest(mutated('notes', {'en-GB': 'x', 'ar': 'a\tb\nc'}))

    def test_assets_map(self) -> None:
        self.assert_bad(mutated('assets', {}), 'no assets')
        self.assert_bad(mutated('assets', []), 'assets list')
        self.assert_bad(mutated('assets', {'Android': {}}), 'bad platform key')
        self.assert_bad(mutated('assets', {'android': 'x'}), 'asset not an object')
        data = good_manifest()
        for i in range(9):
            data['assets'][f'p{i}'] = copy.deepcopy(data['assets']['android'])
        self.assert_bad(data, 'more than eight assets')

    def test_asset_name(self) -> None:
        for bad in ['', 'a b.apk', '../android.apk', '.hidden.apk', 'x..apk',
                    'android.apk\n', 'a/b.apk', 'android.zip', 'a' * 101 + '.apk',
                    'ä.apk', 5, None]:
            self.assert_bad(mutated('assets', 'android', 'name', bad), f'name {bad!r}')
        self.assert_bad(mutated('assets', 'windows', 'name', 'windows-x64.apk'),
                        'windows needs .zip')

    def test_asset_url(self) -> None:
        good = mum.asset_url(REPO, 'v0.2.0', 'android.apk')
        for bad in [
            good.replace('https://', 'http://'),
            good.replace('github.com', 'evil.example'),
            good.replace('github.com', 'github.com.evil.example'),
            'https://evil.example/' + good.split('https://github.com/')[1],
            'https://github.com@evil.example/x/y/releases/download/v/android.apk',
            'https://user@github.com/' + good.split('https://github.com/')[1],
            good.replace('github.com', 'github.com:8443'),
            good + '?token=1',
            good + '#frag',
            good + '\n',
            good.replace('/releases/download/', '/archive/'),
            good.replace('android.apk', 'other.apk'),
            good.replace('/OmarAlnasser/Password/', '//'),
            good.replace('releases', 'rel\\eases'),
            good.replace('android', 'andr\u00f6id'),
            '', 5, None, good + 'x' * 600,
            'https://raw.githubusercontent.com/OmarAlnasser/Password/main/android.apk',
        ]:
            self.assert_bad(mutated('assets', 'android', 'url', bad), f'url {bad!r}')
        mum.validate_manifest(mutated(
            'assets', 'android', 'url', good.replace('github.com', 'github.com:443')))

    def test_asset_size_and_hash(self) -> None:
        for bad in [0, -1, mum.MAX_ASSET_BYTES + 1, 1.0, 12.5, '1234', True, None]:
            self.assert_bad(mutated('assets', 'android', 'size', bad), f'size {bad!r}')
        mum.validate_manifest(mutated('assets', 'android', 'size', mum.MAX_ASSET_BYTES))
        for bad in ['', 'a' * 63, 'a' * 65, 'g' * 64, ('a' * 64) + '\n', 5, None]:
            self.assert_bad(mutated('assets', 'android', 'sha256', bad),
                            f'sha256 {bad!r}')
        mum.validate_manifest(mutated('assets', 'android', 'sha256', 'A' * 64))

    def test_other_platforms_are_valid_for_the_app_but_not_for_a_release(self) -> None:
        data = good_manifest()
        extra = copy.deepcopy(data['assets']['android'])
        extra['name'] = 'macos.dmg'
        extra['url'] = mum.asset_url(REPO, 'v0.2.0', 'macos.dmg')
        data['assets']['macos'] = extra
        mum.validate_manifest(data)
        with self.assertRaises(ToolError):
            mum.check_release_layout(data, repo=REPO, tag='v0.2.0', version='0.2.0')

    def test_release_layout(self) -> None:
        def layout(data: Dict[str, Any], tag: str = 'v0.2.0',
                   repo: str = REPO) -> None:
            mum.check_release_layout(data, repo=repo, tag=tag, version='0.2.0')
        with self.assertRaises(ToolError):
            layout(good_manifest(), tag='v0.2.1')
        with self.assertRaises(ToolError):
            layout(good_manifest(), repo='someone/else')
        data = good_manifest()
        data['assets']['android']['name'] = 'app-release.apk'
        data['assets']['android']['url'] = mum.asset_url(REPO, 'v0.2.0', 'app-release.apk')
        mum.validate_manifest(data)          # fine for the app ...
        with self.assertRaises(ToolError):
            layout(data)                     # ... but not the generic names
        data = good_manifest()
        del data['assets']['windows']
        with self.assertRaises(ToolError):
            layout(data)

    def test_duplicate_keys_and_non_json_numbers(self) -> None:
        for raw in [
            b'{"schema": 1, "schema": 1}',
            b'{"schema": NaN}',
            b'{"schema": Infinity}',
            b'not json',
            b'',
            b'\xff\xfe',
            b'[]',
        ]:
            with self.assertRaises(ToolError, msg=raw):
                mum.parse_manifest_bytes(raw)
        with self.assertRaises(ToolError):
            mum.parse_manifest_bytes(b' ' * (mum.MAX_MANIFEST_BYTES + 1))
        raw = mum.canonical_bytes(good_manifest())
        duplicated = raw.replace(b'"build": 2000,', b'"build": 2000, "build": 2000,')
        with self.assertRaises(ToolError):
            mum.parse_manifest_bytes(duplicated)

    def test_lone_surrogate_in_notes_is_an_error_not_a_crash(self) -> None:
        raw = mum.canonical_bytes(good_manifest()).replace(
            'إصلاحات.'.encode('utf-8'), b'\\ud800')
        mum.parse_manifest_bytes(raw)         # parses; length counting must not crash


class SignatureFileTests(unittest.TestCase):
    def setUp(self) -> None:
        self.signature = mum.ed25519_sign(THROWAWAY_SEED, b'm')
        self.text = base64.b64encode(self.signature)

    def test_accepts_with_and_without_newline(self) -> None:
        for suffix in [b'', b'\n', b'\r\n', b' \n']:
            self.assertEqual(mum.decode_signature_text(self.text + suffix),
                             self.signature)
        self.assertEqual(mum.encode_signature_file(self.signature), self.text + b'\n')

    def test_rejects_everything_else(self) -> None:
        url_safe = self.text.replace(b'+', b'-').replace(b'/', b'_')
        for raw in [
            b'', self.text[:-4], self.text + b'AAAA', self.text[:-1],
            self.text.rstrip(b'='), b'\n' + self.text[:40] + b'\n' + self.text[40:],
            self.text[:40] + b' ' + self.text[40:], 'é'.encode() + self.text[2:],
            b'\x00' + self.text, self.text + b'\x00', b'x' * 5000,
            base64.b64encode(self.signature[:63]), base64.b64encode(self.signature + b'x'),
        ] + ([url_safe] if url_safe != self.text else []):
            with self.assertRaises(ToolError, msg=raw[:30]):
                mum.decode_signature_text(raw)


# --------------------------------------------------------------------------
# The command line tools
# --------------------------------------------------------------------------

class ToolCase(unittest.TestCase):
    """A temporary directory with a fake APK, a fake Windows zip and notes."""

    def setUp(self) -> None:
        self.work = Path(tempfile.mkdtemp(prefix='update-tools-'))
        self.addCleanup(shutil.rmtree, self.work, True)
        self.apk = self.work / 'android.apk'
        self.win = self.work / 'windows-x64.zip'
        self.notes = self.work / 'notes.md'
        self.pub_file = self.work / 'public_key.txt'
        self.out = self.work / 'out'
        write_fake_apk(self.apk)
        write_fake_windows_zip(self.win)
        self.notes.write_text(NOTES_EN, encoding='utf-8')
        self.pub_file.write_text(
            base64.b64encode(public_of(THROWAWAY_SEED)).decode() + '\n')

    # -- helpers ----------------------------------------------------------

    def make_args(self, **over: Any) -> List[str]:
        opts: Dict[str, Any] = {
            'version': '0.2.0', 'build': '2000', 'tag': 'v0.2.0', 'repo': REPO,
            'apk': self.apk, 'windows-zip': self.win, 'notes-file': self.notes,
            'out-dir': self.out, 'published-at': PUBLISHED_AT,
            'expect-public-key': self.pub_file,
        }
        opts.update({k.replace('_', '-'): v for k, v in over.items()})
        args: List[str] = []
        for key, value in opts.items():
            if value is None:
                continue
            if value is True:
                args.append(f'--{key}')
            else:
                args += [f'--{key}', str(value)]
        return args

    def make(self, *, key: Optional[str] = THROWAWAY_SEED_B64,
             **over: Any) -> subprocess.CompletedProcess:
        proc = run_python(MAKE, self.make_args(**over), key=key, cwd=self.work)
        self.assert_no_secret(proc)
        return proc

    def assert_no_secret(self, proc: subprocess.CompletedProcess) -> None:
        seed_texts = [THROWAWAY_SEED_B64, THROWAWAY_SEED.hex(), THROWAWAY_SEED_B64[:-1]]
        for text in (proc.stdout, proc.stderr):
            for secret in seed_texts:
                self.assertNotIn(secret, text, 'the signing key leaked into output')
        for path in self.work.rglob('*'):
            if path.is_file():
                data = path.read_bytes()
                for secret in (THROWAWAY_SEED, THROWAWAY_SEED_B64.encode(),
                               THROWAWAY_SEED.hex().encode()):
                    self.assertNotIn(secret, data, f'the key was written to {path.name}')

    def out_files(self) -> List[str]:
        return sorted(p.name for p in self.out.iterdir()) if self.out.exists() else []

    def make_ok(self, **over: Any) -> subprocess.CompletedProcess:
        proc = self.make(**over)
        self.assertEqual(proc.returncode, 0, proc.stderr + proc.stdout)
        return proc

    def verify_cli(self, *extra: str, public: Optional[Path] = None,
                   manifest: Optional[Path] = None,
                   signature: Optional[Path] = None) -> subprocess.CompletedProcess:
        args = ['--manifest', str(manifest or self.out / 'update.json'),
                '--signature', str(signature or self.out / 'update.json.sig'),
                '--public-key', str(public or self.pub_file), *extra]
        return run_python(VERIFY, args, cwd=self.work)


class MakeToolTests(ToolCase):
    def test_signs_and_everything_checks_out(self) -> None:
        proc = self.make_ok()
        self.assertEqual(self.out_files(), ['update.json', 'update.json.sig'])
        raw = (self.out / 'update.json').read_bytes()
        sig_file = (self.out / 'update.json.sig').read_bytes()
        self.assertEqual(len(sig_file), 89)
        self.assertTrue(sig_file.endswith(b'\n'))

        manifest = json.loads(raw)
        self.assertEqual(manifest['schema'], 1)
        self.assertEqual(manifest['version'], '0.2.0')
        self.assertEqual(manifest['build'], 2000)
        self.assertEqual(manifest['publishedAt'], PUBLISHED_AT)
        self.assertEqual(manifest['notes'], {'en': mum.clean_notes(NOTES_EN)})
        for key, path, name in [('android', self.apk, 'android.apk'),
                                ('windows', self.win, 'windows-x64.zip')]:
            asset = manifest['assets'][key]
            data = path.read_bytes()
            self.assertEqual(asset['name'], name)
            self.assertEqual(asset['size'], len(data))
            self.assertEqual(asset['sha256'], hashlib.sha256(data).hexdigest())
            self.assertEqual(
                asset['url'],
                f'https://github.com/{REPO}/releases/download/v0.2.0/{name}')
        self.assertEqual(raw, mum.canonical_bytes(manifest), 'canonical bytes')
        self.assertIn('matches the pinned key', proc.stdout)

        # Verified by the verify tool (a separate process) ...
        checked = self.verify_cli('--apk', str(self.apk), '--windows-zip',
                                  str(self.win), '--version', '0.2.0', '--build',
                                  '2000', '--tag', 'v0.2.0', '--repo', REPO,
                                  '--release-layout')
        self.assertEqual(checked.returncode, 0, checked.stderr)
        self.assertIn('VERIFIED', checked.stdout)
        # ... and by an independent implementation.
        if HAVE_CRYPTOGRAPHY:
            Ed25519PublicKey.from_public_bytes(public_of(THROWAWAY_SEED)).verify(
                base64.b64decode(sig_file), raw)
        else:
            optional_missing('the cryptography package')

    def test_output_is_reproducible(self) -> None:
        self.make_ok()
        first = {n: (self.out / n).read_bytes() for n in self.out_files()}
        second_dir = self.work / 'out2'
        self.make_ok(out_dir=second_dir)
        for name, data in first.items():
            self.assertEqual((second_dir / name).read_bytes(), data, name)

    def test_android_is_always_listed_before_windows(self) -> None:
        self.make_ok()
        manifest = json.loads((self.out / 'update.json').read_bytes())
        self.assertEqual(list(manifest['assets']), ['android', 'windows'])

    def test_arabic_notes(self) -> None:
        ar = self.work / 'notes-ar.md'
        ar.write_text(NOTES_AR, encoding='utf-8')
        self.make_ok(notes_ar_file=ar)
        raw = (self.out / 'update.json').read_bytes()
        manifest = json.loads(raw)
        self.assertEqual(list(manifest['notes']), ['en', 'ar'])
        self.assertEqual(manifest['notes']['ar'], mum.clean_notes(NOTES_AR))
        self.assertIn('إصلاحات'.encode('utf-8'), raw)

    def test_notes_are_cleaned(self) -> None:
        self.notes.write_bytes(b'\xef\xbb\xbfLine one  \r\nLine\x00 two\r\n\r\n')
        self.make_ok()
        manifest = json.loads((self.out / 'update.json').read_bytes())
        self.assertEqual(manifest['notes']['en'], 'Line one\nLine two')

    def test_published_at_defaults_to_now_in_utc(self) -> None:
        self.make_ok(published_at=None)
        manifest = json.loads((self.out / 'update.json').read_bytes())
        self.assertRegex(manifest['publishedAt'],
                         r'^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$')

    def test_without_a_pinned_key_it_says_so(self) -> None:
        proc = self.make_ok(expect_public_key=None)
        self.assertIn('not compared to a pinned key', proc.stdout)

    # -- the signing key ----------------------------------------------------

    def test_wrong_secret_fails_the_build(self) -> None:
        """The workflow passes the real pinned key; a wrong secret must stop it."""
        proc = self.make(expect_public_key=PINNED_KEY_FILE)
        self.assertEqual(proc.returncode, 1)
        self.assertIn('does not match the pinned public key', proc.stderr)
        self.assertEqual(self.out_files(), [], 'nothing may be written')
        proc = self.make(key=base64.b64encode(OTHER_SEED).decode())
        self.assertEqual(proc.returncode, 1)
        self.assertEqual(self.out_files(), [])

    def test_the_real_pinned_key_is_not_a_test_key(self) -> None:
        pinned = mum.read_public_key_file(PINNED_KEY_FILE)
        self.assertNotEqual(pinned, public_of(THROWAWAY_SEED))
        self.assertNotEqual(pinned, public_of(OTHER_SEED))

    def test_missing_secret(self) -> None:
        proc = self.make(key=None)
        self.assertEqual(proc.returncode, 1)
        self.assertIn('UPDATE_SIGNING_KEY is not set', proc.stderr)
        self.assertEqual(self.out_files(), [])
        proc = self.make(key='   ')
        self.assertEqual(proc.returncode, 1)

    def test_malformed_secret_is_never_echoed(self) -> None:
        marker = 'SECRETMARKER' + 'x' * 8
        for value in [
            'not base64 !!!',
            marker,
            base64.b64encode(THROWAWAY_SEED[:31]).decode(),
            base64.b64encode(THROWAWAY_SEED + b'x').decode(),
            THROWAWAY_SEED_B64.rstrip('='),            # no padding
            THROWAWAY_SEED_B64.replace('+', '-').replace('/', '_'),
            THROWAWAY_SEED.hex(),
            THROWAWAY_SEED_B64 + THROWAWAY_SEED_B64,
        ]:
            proc = run_python(MAKE, self.make_args(), key=value, cwd=self.work)
            self.assertEqual(proc.returncode, 1, value[:12])
            self.assertNotIn(value, proc.stdout + proc.stderr)
            self.assertNotIn(marker, proc.stdout + proc.stderr)
            self.assertEqual(self.out_files(), [])

    def test_secret_with_surrounding_whitespace_is_accepted(self) -> None:
        self.make_ok(key=f'  {THROWAWAY_SEED_B64}\n')

    def test_check_key_mode(self) -> None:
        good = self.make(key=THROWAWAY_SEED_B64, check_key=True,
                         **{k: None for k in ('version', 'build', 'tag', 'repo', 'apk',
                                              'windows_zip', 'notes_file', 'out_dir',
                                              'published_at')})
        self.assertEqual(good.returncode, 0, good.stderr)
        self.assertIn(base64.b64encode(public_of(THROWAWAY_SEED)).decode(), good.stdout)
        self.assertIn('matches the pinned public key', good.stdout)
        bad = self.make(key=THROWAWAY_SEED_B64, check_key=True,
                        expect_public_key=PINNED_KEY_FILE,
                        **{k: None for k in ('version', 'build', 'tag', 'repo', 'apk',
                                             'windows_zip', 'notes_file', 'out_dir',
                                             'published_at')})
        self.assertEqual(bad.returncode, 1)
        self.assertIn('does NOT match', bad.stderr)

    def test_generate_key(self) -> None:
        proc = run_python(MAKE, ['--generate-key'], cwd=self.work)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        seed_text = re.search(r'base64 seed\): (\S+)', proc.stdout)
        public_text = re.search(r'update_public_key\.txt\): (\S+)', proc.stdout)
        self.assertIsNotNone(seed_text)
        self.assertIsNotNone(public_text)
        seed = mum.decode_base64_strict(seed_text.group(1), 32, 'seed')
        self.assertEqual(base64.b64encode(public_of(seed)).decode(),
                         public_text.group(1))
        other = run_python(MAKE, ['--generate-key'], cwd=self.work)
        self.assertNotEqual(other.stdout, proc.stdout, 'keys are random')

    # -- ephemeral (dry run) key ---------------------------------------------

    def test_ephemeral_key(self) -> None:
        public_out = self.work / 'dry-run-public-key.txt'
        proc = self.make(key=None, expect_public_key=None, ephemeral_key=True,
                         public_key_out=public_out)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn('EPHEMERAL', proc.stdout)
        checked = self.verify_cli(public=public_out, manifest=None)
        self.assertEqual(checked.returncode, 0, checked.stderr)
        # No installed app trusts it: not the pinned key, not the test key.
        self.assertEqual(self.verify_cli(public=PINNED_KEY_FILE).returncode, 1)
        self.assertEqual(self.verify_cli(public=self.pub_file).returncode, 1)
        # A second dry run uses a different key.
        again = self.work / 'again'
        self.make(key=None, expect_public_key=None, ephemeral_key=True,
                  out_dir=again, public_key_out=self.work / 'k2.txt')
        self.assertNotEqual(public_out.read_text(), (self.work / 'k2.txt').read_text())

    def test_ephemeral_key_refuses_the_real_secret(self) -> None:
        proc = self.make(key=THROWAWAY_SEED_B64, expect_public_key=None,
                         ephemeral_key=True)
        self.assertEqual(proc.returncode, 1)
        self.assertIn('must not have the real signing key', proc.stderr)
        self.assertEqual(self.out_files(), [])

    def test_ephemeral_key_cannot_be_pinned(self) -> None:
        proc = self.make(key=None, ephemeral_key=True)       # keeps expect-public-key
        self.assertEqual(proc.returncode, 1)
        self.assertEqual(self.out_files(), [])

    def test_public_key_out_needs_ephemeral(self) -> None:
        proc = self.make(public_key_out=self.work / 'k.txt')
        self.assertEqual(proc.returncode, 1)
        self.assertFalse((self.work / 'k.txt').exists())

    # -- argument checks: every failure leaves the output directory empty --------

    def assert_refused(self, why: str, **over: Any) -> str:
        proc = self.make(**over)
        self.assertEqual(proc.returncode, 1, f'{why}: {proc.stdout}{proc.stderr}')
        self.assertTrue(proc.stderr.startswith('error: '), why + ': ' + proc.stderr)
        self.assertEqual(self.out_files(), [], f'{why}: files were written')
        return proc.stderr

    def test_argument_validation(self) -> None:
        self.assert_refused('bad version', version='0.2')
        self.assert_refused('version with v', version='v0.2.0')
        self.assert_refused('build mismatch', build='2001')
        self.assert_refused('tag mismatch', tag='v0.2.1')
        self.assert_refused('tag without v', tag='0.2.0')
        self.assert_refused('bad repo', repo='a/b/c')
        self.assert_refused('bad time', published_at='2026-10-07 12:00:00')
        self.assert_refused('impossible time', published_at='2026-02-31T12:00:00Z')
        self.assert_refused('non-UTC time', published_at='2026-10-07T12:00:00+02:00')

    def test_missing_arguments_are_a_usage_error(self) -> None:
        proc = run_python(MAKE, ['--version', '0.2.0'], key=THROWAWAY_SEED_B64,
                          cwd=self.work)
        self.assertEqual(proc.returncode, 2)
        self.assertIn('missing', proc.stderr)

    def test_package_validation(self) -> None:
        self.assert_refused('missing apk', apk=self.work / 'nope.apk')
        notzip = self.work / 'bad.apk'
        notzip.write_bytes(b'this is not a zip')
        self.assert_refused('apk is not a zip', apk=notzip)
        write_zip(self.work / 'nomanifest.apk', {'classes.dex': b'x'})
        self.assert_refused('apk without manifest', apk=self.work / 'nomanifest.apk')
        zipped = self.work / 'apk-named-zip.zip'
        shutil.copy(self.apk, zipped)
        self.assert_refused('wrong extension', apk=zipped)
        nested = self.work / 'nested.zip'
        write_zip(nested, {'app/app.exe': b'MZ', 'app/flutter_windows.dll': b'MZ'})
        self.assert_refused('files in a folder, not at the root', windows_zip=nested)
        nodll = self.work / 'nodll.zip'
        write_zip(nodll, {'app.exe': b'MZ'})
        self.assert_refused('no flutter_windows.dll', windows_zip=nodll)
        noexe = self.work / 'noexe.zip'
        write_zip(noexe, {'flutter_windows.dll': b'MZ', 'x.txt': b'x'})
        self.assert_refused('no exe', windows_zip=noexe)
        for evil in ['../evil.txt', '/abs.txt', 'C:/evil.txt', 'a\\b.txt', 'a/../b.txt']:
            bad = self.work / 'unsafe.zip'
            write_zip(bad, {'app.exe': b'MZ', 'flutter_windows.dll': b'MZ', evil: b'x'})
            self.assert_refused(f'unsafe entry {evil}', windows_zip=bad)
        (self.work / 'dir.apk').mkdir()
        self.assert_refused('apk is a directory', apk=self.work / 'dir.apk')

    def test_notes_validation(self) -> None:
        self.notes.write_bytes(b'')
        self.assert_refused('empty notes')
        self.notes.write_bytes(b' \n\r\n\t\n')
        self.assert_refused('blank notes')
        self.notes.write_bytes(b'\xff\xfe\x00')
        self.assert_refused('notes not UTF-8')
        self.notes.write_bytes(b'ok')
        empty_ar = self.work / 'empty-ar.md'
        empty_ar.write_bytes(b'')
        self.assert_refused('empty Arabic notes', notes_ar_file=empty_ar)
        self.assert_refused('missing notes file', notes_file=self.work / 'missing.md')

    def test_size_cap(self) -> None:
        with mock.patch.object(mum, 'MAX_ASSET_BYTES', 100):
            with self.assertRaises(ToolError):
                mum.sha256_and_size(self.apk)
        self.assertEqual(mum.sha256_and_size(self.apk)[1], self.apk.stat().st_size)

    def test_a_failed_run_does_not_touch_an_existing_release_directory(self) -> None:
        self.make_ok()
        before = {n: (self.out / n).read_bytes() for n in self.out_files()}
        self.assert_refused_keeps(before, tag='v0.2.1')
        self.assert_refused_keeps(before, key=base64.b64encode(OTHER_SEED).decode())

    def assert_refused_keeps(self, before: Dict[str, bytes], **over: Any) -> None:
        proc = self.make(**over)
        self.assertEqual(proc.returncode, 1)
        after = {n: (self.out / n).read_bytes() for n in self.out_files()}
        self.assertEqual(after, before)

    # -- tampering ------------------------------------------------------------

    def test_any_change_to_the_signed_bytes_is_detected(self) -> None:
        self.make_ok()
        raw = (self.out / 'update.json').read_bytes()
        sig = (self.out / 'update.json.sig').read_bytes()
        public = public_of(THROWAWAY_SEED)
        verify.verify_signed_manifest(raw, sig, public)
        for index in range(0, len(raw), 3):
            tampered = bytearray(raw)
            tampered[index] ^= 0x01
            with self.assertRaises(ToolError, msg=f'byte {index}') as caught:
                verify.verify_signed_manifest(bytes(tampered), sig, public)
            self.assertIn('SIGNATURE INVALID', str(caught.exception))
        for extra in [raw + b'\n', raw + b' ', b'\n' + raw, raw[:-1]]:
            with self.assertRaises(ToolError):
                verify.verify_signed_manifest(extra, sig, public)

    def test_semantically_equal_json_has_a_different_signature(self) -> None:
        self.make_ok()
        raw = (self.out / 'update.json').read_bytes()
        sig = (self.out / 'update.json.sig').read_bytes()
        compact = json.dumps(json.loads(raw), separators=(',', ':'),
                             ensure_ascii=False).encode('utf-8')
        self.assertNotEqual(compact, raw)
        with self.assertRaises(ToolError):
            verify.verify_signed_manifest(compact, sig, public_of(THROWAWAY_SEED))

    def test_a_changed_package_is_detected(self) -> None:
        self.make_ok()
        data = bytearray(self.apk.read_bytes())
        data[-1] ^= 0x01                          # same size, one bit
        self.apk.write_bytes(bytes(data))
        proc = self.verify_cli('--apk', str(self.apk))
        self.assertEqual(proc.returncode, 1)
        self.assertIn('SHA-256 differs', proc.stderr)
        self.apk.write_bytes(bytes(data) + b'x')
        proc = self.verify_cli('--apk', str(self.apk))
        self.assertEqual(proc.returncode, 1)
        self.assertIn('size', proc.stderr)

    def test_verify_cli_expectations(self) -> None:
        self.make_ok()
        ok = ['--release-layout', '--tag', 'v0.2.0', '--repo', REPO]
        self.assertEqual(self.verify_cli(*ok, '--version', '0.2.0',
                                         '--build', '2000').returncode, 0)
        for extra, why in [
            (['--version', '0.2.1'], 'version'),
            (['--build', '2001'], 'build'),
            (['--release-layout', '--tag', 'v0.2.1', '--repo', REPO], 'tag'),
            (['--release-layout', '--tag', 'v0.2.0', '--repo', 'someone/else'], 'repo'),
            (['--release-layout'], 'layout needs tag and repo'),
        ]:
            proc = self.verify_cli(*extra)
            self.assertEqual(proc.returncode, 1, why)
            self.assertIn('FAILED', proc.stderr)

    def test_verify_cli_usage_and_wrong_files(self) -> None:
        self.make_ok()
        self.assertEqual(self.verify_cli(public=PINNED_KEY_FILE).returncode, 1)
        self.assertEqual(run_python(VERIFY, ['--public-key', str(self.pub_file)],
                                    cwd=self.work).returncode, 1)
        self.assertEqual(run_python(VERIFY, ['--bogus'], cwd=self.work).returncode, 2)
        garbage = self.work / 'garbage.sig'
        garbage.write_text('AAAA')
        self.assertEqual(self.verify_cli(signature=garbage).returncode, 1)
        swapped = self.work / 'other.sig'
        other = mum.ed25519_sign(OTHER_SEED, (self.out / 'update.json').read_bytes())
        swapped.write_bytes(mum.encode_signature_file(other))
        self.assertEqual(self.verify_cli(signature=swapped).returncode, 1)
        self.assertEqual(
            self.verify_cli('--download-assets').returncode, 1,
            '--download-assets is for --remote')


class VerifyOrderTests(unittest.TestCase):
    """The signature is checked before anything in the manifest is looked at."""

    def setUp(self) -> None:
        self.public = public_of(THROWAWAY_SEED)

    def sig_for(self, message: bytes, seed: bytes = THROWAWAY_SEED) -> bytes:
        return mum.encode_signature_file(mum.ed25519_sign(seed, message))

    def test_garbage_with_a_bad_signature_is_a_signature_error(self) -> None:
        for body in [b'not json', b'{"schema": 1', b'\xff\xfe', b'{}', b'[]']:
            with self.assertRaises(ToolError) as caught:
                verify.verify_signed_manifest(
                    body, self.sig_for(b'something else'), self.public)
            self.assertIn('SIGNATURE INVALID', str(caught.exception), body)

    def test_a_valid_signature_over_garbage_is_a_manifest_error(self) -> None:
        for body in [b'not json', b'{}', b'[]', b'{"schema": 2}']:
            with self.assertRaises(ToolError) as caught:
                verify.verify_signed_manifest(body, self.sig_for(body), self.public)
            self.assertNotIn('SIGNATURE', str(caught.exception))

    def test_a_signature_by_another_key_is_rejected(self) -> None:
        body = mum.canonical_bytes(good_manifest())
        with self.assertRaises(ToolError) as caught:
            verify.verify_signed_manifest(body, self.sig_for(body, OTHER_SEED),
                                          self.public)
        self.assertIn('SIGNATURE INVALID', str(caught.exception))

    def test_size_limits_come_first(self) -> None:
        with self.assertRaises(ToolError):
            verify.verify_signed_manifest(b'', self.sig_for(b''), self.public)
        big = b'x' * (mum.MAX_MANIFEST_BYTES + 1)
        with self.assertRaises(ToolError) as caught:
            verify.verify_signed_manifest(big, self.sig_for(big), self.public)
        self.assertIn('64 KiB', str(caught.exception))
        with self.assertRaises(ToolError):
            verify.verify_signed_manifest(
                mum.canonical_bytes(good_manifest()), b'A' * 2000, self.public)

    def test_verify_checks_the_signature_before_parsing(self) -> None:
        body = b'not json'
        with mock.patch.object(mum, 'parse_manifest_bytes') as parse:
            with self.assertRaises(ToolError):
                verify.verify_signed_manifest(
                    body, self.sig_for(b'other'), self.public)
            parse.assert_not_called()


# --------------------------------------------------------------------------
# Remote mode (no real network)
# --------------------------------------------------------------------------

class FakeResponse:
    def __init__(self, body: bytes, status: int = 200,
                 headers: Optional[Dict[str, str]] = None) -> None:
        self._stream = io.BytesIO(body)
        self.status = status
        self.headers = headers or {}
        self.reads = 0

    def read(self, size: int = -1) -> bytes:
        self.reads += 1
        return self._stream.read(size)

    def __enter__(self) -> 'FakeResponse':
        return self

    def __exit__(self, *_exc: Any) -> bool:
        return False


class FakeOpener:
    def __init__(self, responder: Any) -> None:
        self.responder = responder
        self.requests: List[str] = []

    def open(self, request: urllib.request.Request, timeout: Any = None) -> Any:
        self.requests.append(request.full_url)
        return self.responder(request.full_url)


class UrlPolicyTests(unittest.TestCase):
    def test_allowed_hosts_match_the_app(self) -> None:
        self.assertEqual(verify.ALLOWED_HOSTS, frozenset({
            'github.com', 'objects.githubusercontent.com',
            'release-assets.githubusercontent.com'}))
        config = DART_DIR / 'update_config.dart'
        if not config.exists():
            self.skipTest('update_config.dart not present')
        text = config.read_text(encoding='utf-8')
        block = re.search(r'defaultAllowedHosts\s*=\s*\{(.*?)\}', text, re.S)
        if block is None:
            self.skipTest('allow-list not found in update_config.dart')
        dart_hosts = set(re.findall(r"'([^']+)'", block.group(1)))
        self.assertEqual(dart_hosts, set(verify.ALLOWED_HOSTS),
                         'tool/verify_update_manifest.py and UpdateConfig disagree')

    def test_accepts(self) -> None:
        for url in ['https://github.com/OmarAlnasser/Password/releases/latest/download/update.json',
                    'https://objects.githubusercontent.com/x?y=1',
                    'https://release-assets.githubusercontent.com/x',
                    'https://GITHUB.COM/x', 'https://github.com:443/x']:
            verify.check_url(url)

    def test_rejects(self) -> None:
        for url in [
            'http://github.com/x', 'https://evil.example/github.com',
            'https://github.com.evil.example/x', 'https://evilgithub.com/x',
            'https://sub.github.com/x', 'https://raw.githubusercontent.com/x',
            'https://gist.githubusercontent.com/x',
            'https://avatars.githubusercontent.com/x',
            'https://githubusercontent.com/x',
            'https://user@github.com/x', 'https://user:pw@github.com/x',
            'https://github.com:8443/x', 'https://github.com:80/x',
            'ftp://github.com/x', 'file:///etc/passwd', '//github.com/x',
            'github.com/x', '', 'https:///x', 'https://127.0.0.1/x',
            'https://[::1]/x', 'https://github.com@evil.example/x',
            'https://github.com\\@evil.example/x',
            'https://github.com/' + 'a' * 5000,
        ]:
            with self.assertRaises(ToolError, msg=url[:60]):
                verify.check_url(url)

    def test_redirects_are_checked_on_every_hop(self) -> None:
        handler = verify._CheckedRedirects()
        self.assertEqual(handler.max_redirections, 5)
        request = urllib.request.Request('https://github.com/a')
        for target in ['http://github.com/b', 'https://evil.example/b',
                       'http://objects.githubusercontent.com/b',
                       'https://raw.githubusercontent.com/b', 'file:///etc/passwd']:
            with self.assertRaises(ToolError, msg=target):
                handler.redirect_request(request, None, 302, 'Found', {}, target)
        followed = handler.redirect_request(
            request, None, 302, 'Found', {},
            'https://release-assets.githubusercontent.com/b')
        self.assertEqual(followed.full_url,
                         'https://release-assets.githubusercontent.com/b')


class FetchTests(unittest.TestCase):
    URL = 'https://github.com/OmarAlnasser/Password/releases/download/v0.2.0/update.json'

    def fetch(self, response: Any, *, limit: int = 100,
              call: Any = None) -> Any:
        opener = FakeOpener(lambda _url: response if not isinstance(response, Exception)
                            else (_ for _ in ()).throw(response))
        with mock.patch.object(verify.urllib.request, 'build_opener',
                               lambda *_h: opener):
            return (call or verify.fetch)(self.URL, limit, 'update.json')

    def test_reads_a_body_within_the_limit(self) -> None:
        self.assertEqual(self.fetch(FakeResponse(b'x' * 100), limit=100), b'x' * 100)

    def test_stops_streaming_at_the_limit_without_a_length_header(self) -> None:
        response = FakeResponse(b'x' * 10_000_000)
        with self.assertRaises(ToolError) as caught:
            self.fetch(response, limit=100)
        self.assertIn('larger than 100', str(caught.exception))
        self.assertLessEqual(response.reads, 3, 'must not read on and on')

    def test_a_lying_length_header_does_not_help(self) -> None:
        response = FakeResponse(b'x' * 1000, headers={'Content-Length': '5'})
        with self.assertRaises(ToolError):
            self.fetch(response, limit=100)

    def test_a_large_length_header_is_refused_before_reading(self) -> None:
        response = FakeResponse(b'x' * 10, headers={'Content-Length': '999999'})
        with self.assertRaises(ToolError):
            self.fetch(response, limit=100)
        self.assertEqual(response.reads, 0)

    def test_errors_do_not_contain_the_url(self) -> None:
        cases = [
            urllib.error.HTTPError(self.URL, 404, 'Not Found', {}, None),   # type: ignore[arg-type]
            urllib.error.URLError(ssl.SSLError('certificate verify failed')),
            OSError('boom'),
            FakeResponse(b'', status=204),
        ]
        for case in cases:
            with self.assertRaises(ToolError) as caught:
                self.fetch(case)
            self.assertNotIn('github.com', str(caught.exception))
            self.assertNotIn('certificate verify failed', str(caught.exception))

    def test_the_first_url_is_checked_too(self) -> None:
        with self.assertRaises(ToolError):
            verify.fetch('http://github.com/x', 10, 'x')
        with self.assertRaises(ToolError):
            verify.fetch('https://evil.example/x', 10, 'x')
        with self.assertRaises(ToolError):
            verify.fetch_digest('https://evil.example/x', 10, 'x')

    def test_digest_is_streamed_and_capped(self) -> None:
        body = expand('big', 300_000)
        digest, size = self.fetch(FakeResponse(body), limit=1_000_000,
                                  call=verify.fetch_digest)
        self.assertEqual((digest, size), (hashlib.sha256(body).hexdigest(), len(body)))
        with self.assertRaises(ToolError):
            self.fetch(FakeResponse(body), limit=299_999, call=verify.fetch_digest)

    def test_retries(self) -> None:
        calls = []

        def flaky() -> str:
            calls.append(1)
            if len(calls) < 3:
                raise ToolError('not yet')
            return 'done'

        with mock.patch.object(verify.time, 'sleep') as sleep, \
                contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(verify.with_retries(flaky, 5, 10, 'x'), 'done')
            self.assertEqual(sleep.call_count, 2)
        calls.clear()
        with mock.patch.object(verify.time, 'sleep'), \
                contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(ToolError):
                verify.with_retries(flaky, 2, 1, 'x')
        self.assertEqual(len(calls), 2)


class RemoteFlowTests(ToolCase):
    """verify_update_manifest.py --remote against an in-memory "GitHub"."""

    def setUp(self) -> None:
        super().setUp()
        self.make_ok()
        self.base = f'https://github.com/{REPO}/releases/download/v0.2.0/'
        self.latest = f'https://github.com/{REPO}/releases/latest/download/'
        manifest = (self.out / 'update.json').read_bytes()
        signature = (self.out / 'update.json.sig').read_bytes()
        self.store: Dict[str, bytes] = {
            self.base + 'update.json': manifest,
            self.base + 'update.json.sig': signature,
            self.base + 'android.apk': self.apk.read_bytes(),
            self.base + 'windows-x64.zip': self.win.read_bytes(),
            self.latest + 'update.json': manifest,
            self.latest + 'update.json.sig': signature,
        }

    def fake_fetch(self, url: str, limit: int, what: str) -> bytes:
        if url not in self.store:
            raise ToolError(f'{what}: HTTP 404')
        if len(self.store[url]) > limit:
            raise ToolError(f'{what}: larger than {limit} bytes')
        return self.store[url]

    def fake_digest(self, url: str, limit: int, what: str) -> Any:
        if url not in self.store:
            raise ToolError(f'{what}: HTTP 404')
        body = self.store[url]
        return hashlib.sha256(body).hexdigest(), len(body)

    def run_remote(self, *extra: str) -> Any:
        argv = ['--remote', '--repo', REPO, '--tag', 'v0.2.0',
                '--public-key', str(self.pub_file), '--release-layout',
                '--version', '0.2.0', '--build', '2000', *extra]
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(verify, 'fetch', self.fake_fetch), \
                mock.patch.object(verify, 'fetch_digest', self.fake_digest), \
                mock.patch.object(verify.time, 'sleep'), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = verify.main(argv)
        return code, out.getvalue(), err.getvalue()

    def test_published_release_verifies(self) -> None:
        code, out, err = self.run_remote('--download-assets', '--check-latest')
        self.assertEqual(code, 0, err)
        self.assertIn('VERIFIED', out)
        self.assertIn('installed apps will see this release', out)

    def test_published_package_that_differs_is_caught(self) -> None:
        data = bytearray(self.store[self.base + 'android.apk'])
        data[10] ^= 1
        self.store[self.base + 'android.apk'] = bytes(data)
        code, _out, err = self.run_remote('--download-assets')
        self.assertEqual(code, 1)
        self.assertIn('does not match the signed manifest', err)

    def test_missing_package(self) -> None:
        del self.store[self.base + 'windows-x64.zip']
        code, _out, err = self.run_remote('--download-assets')
        self.assertEqual(code, 1)
        self.assertIn('404', err)

    def test_latest_pointing_at_another_release_is_caught(self) -> None:
        self.store[self.latest + 'update.json'] = b'{"older": true}\n'
        code, _out, err = self.run_remote('--check-latest')
        self.assertEqual(code, 1)
        self.assertIn('does not serve this release', err)

    def test_forged_manifest_on_the_release_is_caught(self) -> None:
        manifest = self.store[self.base + 'update.json']
        self.store[self.base + 'update.json'] = manifest.replace(b'0.2.0', b'9.9.9', 1)
        code, _out, err = self.run_remote()
        self.assertEqual(code, 1)
        self.assertIn('SIGNATURE INVALID', err)

    def test_oversized_manifest_is_refused(self) -> None:
        self.store[self.base + 'update.json'] = b'x' * (mum.MAX_MANIFEST_BYTES + 1)
        code, _out, err = self.run_remote()
        self.assertEqual(code, 1)
        self.assertIn('larger than', err)

    def test_remote_needs_repo_and_tag(self) -> None:
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            code = verify.main(['--remote', '--public-key', str(self.pub_file)])
        self.assertEqual(code, 1)


# --------------------------------------------------------------------------
# The fixtures for the Dart tests
# --------------------------------------------------------------------------

FIXTURE_README = '''Fixtures for the Dart update tests, produced by tool/make_update_manifest.py.

* update.json         the signed manifest, exactly as the release tool writes it
* update.json.sig     base64 of the 64-byte Ed25519 signature, plus a newline
* public_key.txt      base64 of the raw 32-byte public key that verifies it
* android.apk         a tiny stand-in package (a zip with AndroidManifest.xml);
                      the manifest lists its real size and SHA-256
* windows-x64.zip     a tiny stand-in package (app.exe and flutter_windows.dll at
                      the zip root); the manifest lists its real size and SHA-256

The key is a THROWAWAY test key: its seed is SHA-256 of the public string
"update-tools-test-fixture: throwaway key, never a release key". It is not the
release key (release/update_public_key.txt), and nothing real may ever be
signed with it. The manifest and its URLs are those of version 0.2.0, build
2000, tag v0.2.0, with the generic asset names android.apk and windows-x64.zip.

tool/test_update_tools.py checks that these files are consistent (the signature
verifies, the hashes match, re-running the tool on the stored packages gives the
same bytes). To rewrite them, run

    python3 tool/test_update_tools.py --write-fixtures
'''


def fixture_make_args(directory: Path, out: Path, public_file: Path) -> List[str]:
    notes_en = directory / 'notes-en.md'
    return [
        '--version', '0.2.0', '--build', '2000', '--tag', 'v0.2.0', '--repo', REPO,
        '--apk', str(directory / 'android.apk'),
        '--windows-zip', str(directory / 'windows-x64.zip'),
        '--notes-file', str(notes_en),
        '--notes-ar-file', str(directory / 'notes-ar.md'),
        '--out-dir', str(out), '--published-at', PUBLISHED_AT,
        '--expect-public-key', str(public_file),
    ]


def write_fixtures() -> None:
    FIXTURE_DIR.mkdir(parents=True, exist_ok=True)
    write_fake_apk(FIXTURE_DIR / 'android.apk')
    write_fake_windows_zip(FIXTURE_DIR / 'windows-x64.zip')
    public_text = base64.b64encode(public_of(THROWAWAY_SEED)).decode() + '\n'
    (FIXTURE_DIR / 'public_key.txt').write_text(public_text, encoding='ascii')
    (FIXTURE_DIR / 'README.txt').write_text(FIXTURE_README, encoding='utf-8')
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        (work / 'notes-en.md').write_text(NOTES_EN, encoding='utf-8')
        (work / 'notes-ar.md').write_text(NOTES_AR, encoding='utf-8')
        for name in ('android.apk', 'windows-x64.zip'):
            shutil.copy(FIXTURE_DIR / name, work / name)
        proc = run_python(MAKE, fixture_make_args(
            work, work / 'out', FIXTURE_DIR / 'public_key.txt'),
            key=THROWAWAY_SEED_B64, cwd=work)
        if proc.returncode != 0:
            raise SystemExit(proc.stderr)
        for name in ('update.json', 'update.json.sig'):
            shutil.copy(work / 'out' / name, FIXTURE_DIR / name)
    print(f'fixtures written to {FIXTURE_DIR.relative_to(ROOT)}')


class FixtureTests(unittest.TestCase):
    def setUp(self) -> None:
        if not FIXTURE_DIR.is_dir():
            self.fail(f'{FIXTURE_DIR} is missing: run '
                      'python3 tool/test_update_tools.py --write-fixtures')
        self.manifest = (FIXTURE_DIR / 'update.json').read_bytes()
        self.signature = (FIXTURE_DIR / 'update.json.sig').read_bytes()
        self.public_text = (FIXTURE_DIR / 'public_key.txt').read_text(encoding='ascii')
        self.public = mum.decode_base64_strict(self.public_text, 32, 'fixture key')

    def test_key_is_the_throwaway_and_not_the_release_key(self) -> None:
        self.assertEqual(self.public, public_of(THROWAWAY_SEED))
        self.assertNotEqual(self.public, mum.read_public_key_file(PINNED_KEY_FILE))
        self.assertNotIn(THROWAWAY_SEED_B64, (FIXTURE_DIR / 'README.txt').read_text('utf-8'))

    def test_signature_verifies_and_manifest_is_valid(self) -> None:
        manifest = verify.verify_signed_manifest(self.manifest, self.signature,
                                                 self.public)
        self.assertEqual(manifest['version'], '0.2.0')
        mum.check_release_layout(manifest, repo=REPO, tag='v0.2.0', version='0.2.0')
        self.assertEqual(manifest['notes']['ar'], mum.clean_notes(NOTES_AR))
        self.assertEqual(manifest['publishedAt'], PUBLISHED_AT)
        if HAVE_CRYPTOGRAPHY:
            Ed25519PublicKey.from_public_bytes(self.public).verify(
                base64.b64decode(self.signature), self.manifest)

    def test_signature_is_not_valid_for_the_real_key(self) -> None:
        with self.assertRaises(ToolError):
            verify.verify_signed_manifest(
                self.manifest, self.signature,
                mum.read_public_key_file(PINNED_KEY_FILE))

    def test_packages_match_the_manifest(self) -> None:
        manifest = json.loads(self.manifest)
        for key, name in [('android', 'android.apk'), ('windows', 'windows-x64.zip')]:
            path = FIXTURE_DIR / name
            verify.check_file_against_asset(path, manifest['assets'][key], name)
            mum.inspect_package(key, path)
            self.assertLess(path.stat().st_size, 4096, 'fixtures stay tiny')

    def test_the_tool_reproduces_the_stored_files(self) -> None:
        """Same inputs, same bytes (the zips are taken as stored, so this does
        not depend on the zip library of the machine)."""
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            (work / 'notes-en.md').write_text(NOTES_EN, encoding='utf-8')
            (work / 'notes-ar.md').write_text(NOTES_AR, encoding='utf-8')
            for name in ('android.apk', 'windows-x64.zip'):
                shutil.copy(FIXTURE_DIR / name, work / name)
            proc = run_python(MAKE, fixture_make_args(
                work, work / 'out', FIXTURE_DIR / 'public_key.txt'),
                key=THROWAWAY_SEED_B64, cwd=work)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertEqual((work / 'out' / 'update.json').read_bytes(), self.manifest)
            self.assertEqual((work / 'out' / 'update.json.sig').read_bytes(),
                             self.signature)

    def test_verify_cli_accepts_the_fixture_directory(self) -> None:
        proc = run_python(VERIFY, [
            '--manifest', str(FIXTURE_DIR / 'update.json'),
            '--signature', str(FIXTURE_DIR / 'update.json.sig'),
            '--public-key', str(FIXTURE_DIR / 'public_key.txt'),
            '--apk', str(FIXTURE_DIR / 'android.apk'),
            '--windows-zip', str(FIXTURE_DIR / 'windows-x64.zip'),
            '--version', '0.2.0', '--build', '2000', '--tag', 'v0.2.0',
            '--repo', REPO, '--release-layout'])
        self.assertEqual(proc.returncode, 0, proc.stderr)


# --------------------------------------------------------------------------
# The Dart side and the pinned key
# --------------------------------------------------------------------------

class DartMirrorTests(unittest.TestCase):
    """The Python tools mirror lib/services/update; keep them from drifting."""

    def dart(self, name: str) -> str:
        path = DART_DIR / name
        if not path.exists():
            self.skipTest(f'{name} not present')
        return path.read_text(encoding='utf-8')

    def test_pinned_key_is_embedded_in_dart(self) -> None:
        pinned = PINNED_KEY_FILE.read_text(encoding='ascii').strip()
        self.assertEqual(len(base64.b64decode(pinned, validate=True)), 32)
        self.assertEqual(pinned, base64.b64encode(
            mum.read_public_key_file(PINNED_KEY_FILE)).decode())
        self.assertIn(f"'{pinned}'", self.dart('update_public_key.dart'))

    def test_default_repo(self) -> None:
        match = re.search(r"defaultRepo\s*=\s*'([^']+)'", self.dart('update_config.dart'))
        self.assertIsNotNone(match)
        self.assertEqual(match.group(1).lower(), mum.DEFAULT_REPO.lower())

    def test_limits(self) -> None:
        manifest = self.dart('update_manifest.dart')
        config = self.dart('update_config.dart')
        for name, value in [('maxNotesLanguages', mum.MAX_NOTES_LANGUAGES),
                            ('maxNotesLength', mum.MAX_NOTES_UNITS),
                            ('maxAssets', mum.MAX_ASSETS),
                            ('maxNameLength', mum.MAX_NAME_LENGTH),
                            ('maxUrlLength', mum.MAX_URL_LENGTH),
                            ('maxVersionLength', mum.MAX_VERSION_LENGTH)]:
            found = re.search(rf'static const int {name}\s*=\s*(\d+);', manifest)
            if found is None:
                continue
            self.assertEqual(int(found.group(1)), value, name)
        for name, value in [('maxManifestBytes', mum.MAX_MANIFEST_BYTES),
                            ('maxSignatureBytes', mum.MAX_SIGNATURE_BYTES),
                            ('maxAssetBytes', mum.MAX_ASSET_BYTES)]:
            found = re.search(rf'this\.{name}\s*=\s*([0-9 *]+),', config)
            if found is None:
                continue
            product = 1
            for factor in found.group(1).split('*'):
                product *= int(factor)
            self.assertEqual(product, value, name)
        self.assertEqual(verify.MAX_REDIRECTS, 5)

    def test_version_limits(self) -> None:
        text = self.dart('app_version.dart')
        for name, value in [('maxMajor', mum._MAX_MAJOR),
                            ('maxMinorOrPatch', mum._MAX_MINOR_OR_PATCH)]:
            found = re.search(rf'static const int {name}\s*=\s*(\d+);', text)
            if found is not None:
                self.assertEqual(int(found.group(1)), value, name)
        self.assertIn('major * 1000000 + minor * 1000 + patch', text)

    def test_asset_names_and_extensions(self) -> None:
        text = self.dart('update_manifest.dart')
        self.assertIn("android('android', '.apk')", text)
        self.assertIn("windows('windows', '.zip')", text)
        self.assertEqual([(k, n, e) for k, n, e in mum.PLATFORMS],
                         [('android', 'android.apk', '.apk'),
                          ('windows', 'windows-x64.zip', '.zip')])


# --------------------------------------------------------------------------
# The release workflow
# --------------------------------------------------------------------------

def workflow_text() -> str:
    return WORKFLOW.read_text(encoding='utf-8')


@unittest.skipUnless(WORKFLOW.exists(), 'release.yml not present')
class WorkflowTextTests(unittest.TestCase):
    def test_no_expression_inside_a_run_script(self) -> None:
        """Event data and secrets reach scripts only through env: (no script
        injection). A tiny extractor, so that PyYAML is not needed."""
        lines = workflow_text().split('\n')
        index = 0
        scripts = 0
        while index < len(lines):
            match = re.match(r'^(\s*)(?:- )?run:\s*(.*)$', lines[index])
            if not match:
                index += 1
                continue
            scripts += 1
            indent = len(match.group(1)) + (2 if lines[index].lstrip().startswith('- ') else 0)
            body = [match.group(2)]
            index += 1
            if match.group(2).strip() in ('|', '|-', '>', '>-'):
                body = []
                while index < len(lines) and (
                        not lines[index].strip() or
                        len(lines[index]) - len(lines[index].lstrip()) > indent):
                    body.append(lines[index])
                    index += 1
            self.assertNotIn('${{', '\n'.join(body),
                             'an expression inside a run script:\n' + '\n'.join(body)[:200])
        self.assertGreater(scripts, 10)

    def test_no_dangerous_triggers_or_contexts(self) -> None:
        text = workflow_text()
        for forbidden in ['pull_request_target', 'github.event.pull_request',
                          'github.head_ref', 'workflow_run', 'issue_comment',
                          'github.event.head_commit', 'github.event.comment',
                          'continue-on-error', 'secrets: inherit', 'ACTIONS_STEP_DEBUG',
                          'set -x', 'echo "$UPDATE', 'echo $UPDATE', 'ACTIONS_ALLOW_UNSECURE']:
            self.assertNotIn(forbidden, text)
        self.assertNotRegex(text, r'(?m)^\s*(pull_request|issues|issue_comment):')
        self.assertNotIn('http://', text.replace('http://github.com/x', ''),
                         'only https URLs')

    def test_asset_and_tool_names(self) -> None:
        text = workflow_text()
        self.assertIn(mum.ANDROID_ASSET, text)
        self.assertIn(mum.WINDOWS_ASSET, text)
        for tool in ('tool/make_update_manifest.py', 'tool/verify_update_manifest.py',
                     'tool/test_update_tools.py', 'release/update_public_key.txt',
                     'release/android_cert_sha256.txt'):
            self.assertIn(tool, text)
            self.assertTrue((ROOT / tool).exists(), tool)

    def test_flutter_version_matches_the_other_workflow(self) -> None:
        other = (ROOT / '.github' / 'workflows' / 'build.yml').read_text('utf-8')
        want = re.search(r'FLUTTER_VERSION:\s*"([^"]+)"', other)
        have = re.search(r'FLUTTER_VERSION:\s*"([^"]+)"', workflow_text())
        self.assertIsNotNone(want)
        self.assertIsNotNone(have)
        self.assertEqual(have.group(1), want.group(1))

    def test_every_flutter_build_passes_version_and_build(self) -> None:
        text = workflow_text()
        builds = re.findall(r'flutter build (\w+)(.*?)(?:\n\n|\n\s*- |\Z)', text, re.S)
        self.assertEqual(sorted(b[0] for b in builds), ['apk', 'windows'])
        for kind, rest in builds:
            for flag in ('--release', '--build-name', '--build-number',
                         '--dart-define=APP_VERSION=', '--dart-define=APP_BUILD='):
                self.assertIn(flag, rest, f'flutter build {kind}')

    def test_the_cert_check_fails_closed(self) -> None:
        text = workflow_text()
        self.assertIn('release/android_cert_sha256.txt', text)
        self.assertIn('apksigner', text)
        self.assertIn('exactly one certificate', text)
        self.assertIn('NOT signed with the release certificate', text)
        self.assertIn('if: always()', text)
        self.assertIn('release.jks', text)


@unittest.skipUnless(WORKFLOW.exists(), 'release.yml not present')
class WorkflowStructureTests(unittest.TestCase):
    def setUp(self) -> None:
        if not HAVE_YAML:
            optional_missing('PyYAML')
            self.skipTest('PyYAML is not installed')
        self.doc = yaml.safe_load(workflow_text())
        # PyYAML reads the key `on` as the boolean True.
        self.on = self.doc.get('on', self.doc.get(True))
        self.jobs = self.doc['jobs']

    def steps(self, job: str) -> List[Dict[str, Any]]:
        return self.jobs[job]['steps']

    def test_triggers(self) -> None:
        self.assertEqual(self.on['push'], {'tags': ['v*']})
        inputs = self.on['workflow_dispatch']['inputs']
        self.assertEqual(inputs['tag']['type'], 'string')
        self.assertTrue(inputs['tag']['required'])
        self.assertEqual(inputs['dry_run']['type'], 'boolean')
        self.assertIs(inputs['dry_run']['default'], True)
        self.assertEqual(set(self.on), {'push', 'workflow_dispatch'})

    def test_permissions_are_minimal(self) -> None:
        self.assertEqual(self.doc['permissions'], {'contents': 'read'})
        writers = [name for name, job in self.jobs.items()
                   if 'write' in (job.get('permissions') or {}).values()]
        self.assertEqual(writers, ['publish'])
        self.assertEqual(self.jobs['publish']['permissions'], {'contents': 'write'})
        for name, job in self.jobs.items():
            if name != 'publish':
                self.assertIn(job.get('permissions', {'contents': 'read'}),
                              [{'contents': 'read'}], name)

    def test_job_graph(self) -> None:
        self.assertEqual(set(self.jobs),
                         {'check', 'android', 'windows', 'sign', 'publish', 'verify'})
        self.assertEqual(self.jobs['android']['needs'], 'check')
        self.assertEqual(self.jobs['windows']['needs'], 'check')
        self.assertEqual(set(self.jobs['sign']['needs']), {'check', 'android', 'windows'})
        self.assertEqual(set(self.jobs['publish']['needs']),
                         {'check', 'android', 'windows', 'sign'})
        self.assertIn("dry_run == 'false'", self.jobs['publish']['if'])
        self.assertEqual(set(self.jobs['verify']['needs']), {'check', 'publish'})
        self.assertIn("dry_run == 'false'", self.jobs['verify']['if'])
        self.assertEqual(self.jobs['verify']['permissions'], {'contents': 'read'})
        for name in ('check', 'android', 'windows', 'sign'):
            self.assertNotIn('if', self.jobs[name], name)
            self.assertNotIn('environment', self.jobs[name])
        self.assertNotIn('environment', self.jobs['publish'])
        self.assertNotIn('environment', self.jobs['verify'])
        self.assertEqual(self.jobs['windows']['runs-on'], 'windows-latest')

    def test_actions_use_major_version_tags_from_an_allow_list(self) -> None:
        allowed = {'actions/checkout@v4', 'actions/setup-java@v4',
                   'subosito/flutter-action@v2', 'actions/upload-artifact@v4',
                   'actions/download-artifact@v4'}
        seen = set()
        for name, job in self.jobs.items():
            for step in job['steps']:
                if 'uses' in step:
                    seen.add(step['uses'])
                    self.assertIn(step['uses'], allowed, name)
        self.assertEqual(seen, allowed)
        self.assertIn('commit SHA', workflow_text(), 'the pinning note is there')

    def test_checkout_does_not_keep_credentials(self) -> None:
        for name, job in self.jobs.items():
            for step in job['steps']:
                if step.get('uses', '').startswith('actions/checkout'):
                    self.assertIs(step['with']['persist-credentials'], False, name)

    def test_secrets_are_scoped(self) -> None:
        where: Dict[str, List[str]] = {}
        for name, job in self.jobs.items():
            for step in job['steps']:
                for key, value in (step.get('env') or {}).items():
                    for secret in re.findall(r'secrets\.([A-Z0-9_]+)', str(value)):
                        where.setdefault(secret, []).append(f'{name}:{key}')
                for section in ('run', 'with', 'if'):
                    self.assertNotIn('secrets.', str(step.get(section, '')),
                                     f'{name}: secrets only in env')
            self.assertNotIn('secrets.', str(job.get('env', '')))
        self.assertNotIn('secrets.', str(self.doc.get('env', '')))
        self.assertEqual(set(where), {'ANDROID_KEYSTORE_BASE64',
                                      'ANDROID_KEYSTORE_PASSWORD',
                                      'UPDATE_SIGNING_KEY', 'GITHUB_TOKEN'})
        self.assertEqual({w.split(':')[0] for w in where['UPDATE_SIGNING_KEY']},
                         {'check', 'sign'})
        self.assertEqual({w.split(':')[0] for w in where['ANDROID_KEYSTORE_BASE64']},
                         {'android'})
        self.assertEqual({w.split(':')[0] for w in where['ANDROID_KEYSTORE_PASSWORD']},
                         {'android'})
        self.assertEqual({w.split(':')[0] for w in where['GITHUB_TOKEN']}, {'publish'})

    def test_signing_key_only_reaches_our_own_scripts(self) -> None:
        for name in ('check', 'sign'):
            for step in self.steps(name):
                if 'UPDATE_SIGNING_KEY' in (step.get('env') or {}):
                    self.assertIn('tool/make_update_manifest.py', step['run'], name)
                    self.assertNotIn('uses', step)
        # The real key is only handed over for a real release.
        sign_env = next(s['env'] for s in self.steps('sign')
                        if 'UPDATE_SIGNING_KEY' in (s.get('env') or {}))
        self.assertIn("dry_run == 'false'", sign_env['UPDATE_SIGNING_KEY'])
        check_step = next(s for s in self.steps('check')
                          if 'UPDATE_SIGNING_KEY' in (s.get('env') or {}))
        self.assertIn("dry_run == 'false'", check_step['if'])

    def test_dry_run_signs_with_a_throwaway_key_and_publishes_nothing(self) -> None:
        sign = next(s for s in self.steps('sign')
                    if 'make_update_manifest' in s.get('run', ''))
        self.assertIn('--ephemeral-key', sign['run'])
        self.assertIn('unset UPDATE_SIGNING_KEY', sign['run'])
        self.assertIn('--expect-public-key release/update_public_key.txt', sign['run'])
        for name in ('check', 'android', 'windows', 'sign'):
            for step in self.steps(name):
                self.assertNotIn('gh release', step.get('run', ''), name)
        publish_text = ' '.join(s.get('run', '') for s in self.steps('publish'))
        self.assertIn('gh release create', publish_text)
        self.assertIn('--draft', publish_text)
        self.assertIn('--verify-tag', publish_text)
        self.assertIn('--draft=false', publish_text)

    def test_publish_uploads_exactly_the_four_files(self) -> None:
        create = next(s for s in self.steps('publish')
                      if 'gh release create' in s.get('run', ''))['run']
        for name in ('android.apk', 'windows-x64.zip', 'update.json', 'update.json.sig'):
            self.assertIn(name, create)
        self.assertIn('--title "$TAG"', create)
        before = [s for s in self.steps('publish')
                  if 'verify_update_manifest.py' in s.get('run', '')]
        self.assertEqual(len(before), 1, 'the local files are checked before publishing')
        self.assertIn('--release-layout', before[0]['run'])
        self.assertIn('release/update_public_key.txt', before[0]['run'])
        # After publishing, a separate read-only job plays the installed app.
        after = [s for s in self.steps('verify')
                 if 'verify_update_manifest.py' in s.get('run', '')]
        self.assertEqual(len(after), 1)
        self.assertNotIn('GH_TOKEN', after[0].get('env', {}))
        self.assertIn('release/update_public_key.txt', after[0]['run'])
        for flag in ('--remote', '--download-assets', '--check-latest',
                     '--release-layout'):
            self.assertIn(flag, after[0]['run'])

    def test_bash_scripts_stop_on_errors(self) -> None:
        for name, job in self.jobs.items():
            for step in job['steps']:
                run = step.get('run')
                if run is None or step.get('shell') == 'pwsh':
                    continue
                if '\n' in run.strip():
                    self.assertIn('set -euo pipefail', run, f"{name}: {step.get('name')}")

    def test_the_windows_zip_has_the_files_at_its_root(self) -> None:
        zip_step = next(s for s in self.steps('windows') if 'CreateFromDirectory' in s.get('run', ''))
        self.assertEqual(zip_step['shell'], 'pwsh')
        self.assertIn('$false)', zip_step['run'], 'includeBaseDirectory = false')
        self.assertIn('flutter_windows.dll', zip_step['run'])

    def test_keystore_is_removed_even_after_a_failure(self) -> None:
        steps = self.steps('android')
        cleanup = [s for s in steps if s.get('if') == 'always()']
        self.assertEqual(len(cleanup), 1)
        self.assertIn('release.jks', cleanup[0]['run'])
        self.assertGreater(steps.index(cleanup[0]),
                           max(i for i, s in enumerate(steps)
                               if 'flutter build apk' in s.get('run', '')))
        decode = next(s for s in steps if 'base64 --decode' in s.get('run', ''))
        self.assertIn('chmod 600', decode['run'])
        self.assertIn('umask 077', decode['run'])


# --------------------------------------------------------------------------
# Nothing here may carry the app name (it is renamed by tool/rename_app.py)
# --------------------------------------------------------------------------

class NoAppNameTests(unittest.TestCase):
    def names(self) -> List[str]:
        brand = ROOT / 'lib' / 'brand.dart'
        if not brand.exists():
            self.skipTest('lib/brand.dart not present')
        text = brand.read_text(encoding='utf-8')
        found = re.findall(r"const String appName(?:Ar)?\s*=\s*'([^']+)'", text)
        return sorted({n.lower() for n in found if len(n) >= 3})

    def test_release_files_do_not_hard_code_the_app_name(self) -> None:
        names = self.names()
        self.assertTrue(names)
        files = [WORKFLOW, MAKE, VERIFY, THIS_FILE, ROOT / 'docs' / 'RELEASING.md']
        files += [p for p in FIXTURE_DIR.rglob('*') if p.is_file()]
        checked = 0
        for path in files:
            if not path.exists():
                continue
            data = path.read_bytes().lower()
            checked += 1
            for name in names:
                self.assertNotIn(name.encode('utf-8'), data, path.name)
        self.assertGreater(checked, 5)


if __name__ == '__main__':
    if '--write-fixtures' in sys.argv:
        write_fixtures()
        sys.exit(0)
    unittest.main()
