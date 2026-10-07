#!/usr/bin/env python3
"""Build and sign the update manifest (update.json + update.json.sig).

Used by .github/workflows/release.yml. Python 3.9+, standard library only (no
pip install in the job that holds the signing key).

    python3 tool/make_update_manifest.py \\
        --version 0.2.0 --build 2000 --tag v0.2.0 \\
        --repo OmarAlnasser/Password \\
        --apk dist/android.apk --windows-zip dist/windows-x64.zip \\
        --notes-file notes.md --out-dir out \\
        --published-at 2026-10-07T12:00:00Z \\
        --expect-public-key release/update_public_key.txt

What it does, in this order, and stops at the first problem:

  1. Checks the arguments (strict version, build = major*1000000 + minor*1000 +
     patch, tag = "v" + version, repository name).
  2. Hashes both packages (SHA-256, size) and sanity-checks them (zip magic,
     size cap, the Windows zip has the exe and flutter_windows.dll at its root).
  3. Writes the manifest in a canonical form: fixed key order, 2-space indent,
     UTF-8 without BOM, one trailing newline. Same inputs give the same bytes.
  4. Signs the EXACT bytes with Ed25519. The key is the base64 of the raw
     32-byte seed in the environment variable UPDATE_SIGNING_KEY. It is never
     printed, never written to disk and never part of an error message.
  5. Verifies the signature again with the public key derived from the seed and,
     with --expect-public-key, compares that public key to the pinned one, so
     a wrong secret fails the build instead of producing a manifest that no
     installed app accepts.
  6. Only now writes update.json and update.json.sig (base64 of the 64-byte
     signature plus a newline) to --out-dir. A failed run leaves no new files.

--ephemeral-key signs with a random throwaway key instead (release dry runs).
The public key is printed (and written with --public-key-out) so that the
result can be checked; no installed app trusts it.

Asset names are generic on purpose (android.apk, windows-x64.zip): the app name
is not part of any file name, so renaming the app never touches the pipeline.

This file also holds the pieces the verify tool shares: the Ed25519
implementation (RFC 8032, pure Python) and the manifest schema checks that
mirror lib/services/update/update_manifest.dart. Python's `cryptography`
package is used only by the unit tests, as an independent cross-check.
"""
from __future__ import annotations

import argparse
import base64
import binascii
import datetime
import hashlib
import json
import os
import re
import secrets
import sys
import zipfile
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

# --------------------------------------------------------------------------
# Constants. The limits mirror lib/services/update/update_config.dart and
# update_manifest.dart; a manifest this tool refuses is one the app would
# refuse, and the other way round.
# --------------------------------------------------------------------------

SCHEMA = 1
MAX_MANIFEST_BYTES = 64 * 1024
MAX_SIGNATURE_BYTES = 1024
MAX_ASSET_BYTES = 400 * 1024 * 1024
MAX_NOTES_UNITS = 4000          # UTF-16 code units, like Dart's String.length
MAX_NOTES_LANGUAGES = 8
MAX_ASSETS = 8
MAX_NAME_LENGTH = 100
MAX_URL_LENGTH = 512
MAX_VERSION_LENGTH = 32

ANDROID_ASSET = 'android.apk'
WINDOWS_ASSET = 'windows-x64.zip'
# (manifest key, generic file name, required extension)
PLATFORMS: Tuple[Tuple[str, str, str], ...] = (
    ('android', ANDROID_ASSET, '.apk'),
    ('windows', WINDOWS_ASSET, '.zip'),
)
EXTENSION_OF = {key: ext for key, _name, ext in PLATFORMS}

SIGNING_KEY_ENV = 'UPDATE_SIGNING_KEY'
DEFAULT_REPO = 'OmarAlnasser/Password'

_VERSION_RE = re.compile(
    r'^(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\Z')
_MAX_MAJOR = 2000
_MAX_MINOR_OR_PATCH = 999
_REPO_RE = re.compile(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\Z')
_LANG_RE = re.compile(r'^[a-z]{2,3}(-[A-Za-z0-9]{2,8})?\Z')
_PLATFORM_RE = re.compile(r'^[a-z][a-z0-9_]{0,15}\Z')
_FILE_NAME_RE = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._-]*\Z')
_SHA256_RE = re.compile(r'^[0-9a-fA-F]{64}\Z')
_TIMESTAMP_RE = re.compile(
    r'^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,6})?Z\Z')
_STRICT_TIMESTAMP_RE = re.compile(
    r'^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\Z')
# Everything below U+0020 except tab, line feed and carriage return, and DEL.
_BAD_CONTROL_RE = re.compile('[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]')
_BASE64_RE = re.compile(r'^[A-Za-z0-9+/]*={0,2}\Z')


class ToolError(Exception):
    """A problem to report to the person running the tool. The message never
    contains key material."""


# --------------------------------------------------------------------------
# Ed25519 (RFC 8032, section 6 reference algorithm, pure Python).
#
# Used for signing in CI so that the job that holds the signing key installs
# nothing from the network. It is checked against the RFC 8032 test vectors and
# against the `cryptography` package in tool/test_update_tools.py, and the app
# (libsodium) verifies what it signs in test/services/update. It is not
# constant-time; it runs once on a build machine nobody can time.
# --------------------------------------------------------------------------

_P = 2 ** 255 - 19
_Q = 2 ** 252 + 27742317777372353535851937790883648493
_D = (-121665 * pow(121666, _P - 2, _P)) % _P
_SQRT_M1 = pow(2, (_P - 1) // 4, _P)
_IDENTITY = (0, 1, 1, 0)


def _inv(x: int) -> int:
    return pow(x, _P - 2, _P)


def _recover_x(y: int, sign: int) -> Optional[int]:
    if y >= _P:
        return None
    x2 = (y * y - 1) * _inv(_D * y * y + 1) % _P
    if x2 == 0:
        return None if sign else 0
    x = pow(x2, (_P + 3) // 8, _P)
    if (x * x - x2) % _P != 0:
        x = x * _SQRT_M1 % _P
    if (x * x - x2) % _P != 0:
        return None
    if (x & 1) != sign:
        x = _P - x
    return x


_GY = 4 * _inv(5) % _P
_GX = _recover_x(_GY, 0)
assert _GX is not None
_BASE = (_GX, _GY, 1, _GX * _GY % _P)


def _add(p: Tuple[int, int, int, int],
         q: Tuple[int, int, int, int]) -> Tuple[int, int, int, int]:
    a = (p[1] - p[0]) * (q[1] - q[0]) % _P
    b = (p[1] + p[0]) * (q[1] + q[0]) % _P
    c = 2 * p[3] * q[3] * _D % _P
    d = 2 * p[2] * q[2] % _P
    e, f, g, h = b - a, d - c, d + c, b + a
    return (e * f % _P, g * h % _P, f * g % _P, e * h % _P)


def _mul(s: int, p: Tuple[int, int, int, int]) -> Tuple[int, int, int, int]:
    q = _IDENTITY
    while s > 0:
        if s & 1:
            q = _add(q, p)
        p = _add(p, p)
        s >>= 1
    return q


def _same(p: Tuple[int, int, int, int], q: Tuple[int, int, int, int]) -> bool:
    return ((p[0] * q[2] - q[0] * p[2]) % _P == 0 and
            (p[1] * q[2] - q[1] * p[2]) % _P == 0)


def _compress(p: Tuple[int, int, int, int]) -> bytes:
    zinv = _inv(p[2])
    x = p[0] * zinv % _P
    y = p[1] * zinv % _P
    return int.to_bytes(y | ((x & 1) << 255), 32, 'little')


def _decompress(s: bytes) -> Optional[Tuple[int, int, int, int]]:
    if len(s) != 32:
        return None
    y = int.from_bytes(s, 'little')
    sign = y >> 255
    y &= (1 << 255) - 1
    x = _recover_x(y, sign)
    if x is None:
        return None
    return (x, y, 1, x * y % _P)


def _secret_expand(seed: bytes) -> Tuple[int, bytes]:
    if len(seed) != 32:
        raise ToolError('an Ed25519 seed is 32 bytes')
    h = hashlib.sha512(seed).digest()
    a = int.from_bytes(h[:32], 'little')
    a &= (1 << 254) - 8
    a |= 1 << 254
    return a, h[32:]


def _sha512_modq(data: bytes) -> int:
    return int.from_bytes(hashlib.sha512(data).digest(), 'little') % _Q


def ed25519_public_key(seed: bytes) -> bytes:
    """The 32-byte public key for a 32-byte seed."""
    a, _prefix = _secret_expand(seed)
    return _compress(_mul(a, _BASE))


def ed25519_sign(seed: bytes, message: bytes) -> bytes:
    """The 64-byte detached signature of [message]."""
    a, prefix = _secret_expand(seed)
    public = _compress(_mul(a, _BASE))
    r = _sha512_modq(prefix + message)
    r_enc = _compress(_mul(r, _BASE))
    h = _sha512_modq(r_enc + public + message)
    s = (r + h * a) % _Q
    return r_enc + int.to_bytes(s, 32, 'little')


def ed25519_verify(public: bytes, message: bytes, signature: bytes) -> bool:
    """True only for a canonical, valid signature. Rejects malleable and
    small-order inputs, like libsodium."""
    if len(public) != 32 or len(signature) != 64:
        return False
    a_point = _decompress(public)
    r_point = _decompress(signature[:32])
    if a_point is None or r_point is None:
        return False
    if _same(_mul(8, a_point), _IDENTITY) or _same(_mul(8, r_point), _IDENTITY):
        return False
    s = int.from_bytes(signature[32:], 'little')
    if s >= _Q:
        return False
    h = _sha512_modq(signature[:32] + public + message)
    return _same(_mul(s, _BASE), _add(r_point, _mul(h, a_point)))


# --------------------------------------------------------------------------
# Small helpers
# --------------------------------------------------------------------------

def decode_base64_strict(text: str, expected_len: int, what: str) -> bytes:
    """Canonical padded base64 of exactly [expected_len] bytes. The message
    never contains the text itself."""
    text = text.strip()
    expected_chars = (expected_len + 2) // 3 * 4
    if len(text) != expected_chars or not _BASE64_RE.match(text):
        raise ToolError(f'{what} is not canonical base64 of {expected_len} bytes')
    try:
        raw = base64.b64decode(text, validate=True)
    except (binascii.Error, ValueError):
        raise ToolError(
            f'{what} is not canonical base64 of {expected_len} bytes') from None
    if len(raw) != expected_len or base64.b64encode(raw).decode() != text:
        raise ToolError(f'{what} is not canonical base64 of {expected_len} bytes')
    return raw


def read_public_key_file(path: Path) -> bytes:
    try:
        text = path.read_text(encoding='ascii')
    except (OSError, UnicodeDecodeError):
        raise ToolError(f'cannot read the public key file {path.name}') from None
    return decode_base64_strict(text, 32, f'public key {path.name}')


def read_limited(path: Path, limit: int, what: str) -> bytes:
    """The whole file, refusing anything larger than [limit] bytes."""
    try:
        with open(path, 'rb') as handle:
            data = handle.read(limit + 1)
    except OSError:
        raise ToolError(f'cannot read {what}') from None
    if len(data) > limit:
        raise ToolError(f'{what} is larger than {limit} bytes')
    return data


def parse_version(text: str) -> Tuple[int, int, int]:
    """Strict major.minor.patch with the app's limits (AppVersion.tryParse)."""
    m = _VERSION_RE.match(text) if len(text) <= MAX_VERSION_LENGTH else None
    if m is None:
        raise ToolError('version must be major.minor.patch without leading zeros')
    major, minor, patch = (int(g) for g in m.groups())
    if (major > _MAX_MAJOR or minor > _MAX_MINOR_OR_PATCH or
            patch > _MAX_MINOR_OR_PATCH or build_of(major, minor, patch) <= 0):
        raise ToolError(
            'version out of range (major <= 2000, minor and patch <= 999, not 0.0.0)')
    return major, minor, patch


def build_of(major: int, minor: int, patch: int) -> int:
    return major * 1000000 + minor * 1000 + patch


def parse_repo(text: str) -> str:
    if (_REPO_RE.match(text) is None or
            any(part.startswith('.') for part in text.split('/'))):
        raise ToolError('repo must look like owner/name')
    return text


def asset_url(repo: str, tag: str, name: str) -> str:
    return f'https://github.com/{repo}/releases/download/{tag}/{name}'


def utf16_len(text: str) -> int:
    return len(text.encode('utf-16-le', 'surrogatepass')) // 2


def clean_notes(text: str) -> str:
    """Release notes as the app can show them: LF line breaks, no control
    characters, no trailing blanks, at most MAX_NOTES_UNITS UTF-16 units."""
    text = text.lstrip('\ufeff')
    text = text.replace('\r\n', '\n').replace('\r', '\n')
    text = _BAD_CONTROL_RE.sub('', text)
    text = '\n'.join(line.rstrip() for line in text.split('\n')).strip('\n')
    if utf16_len(text) <= MAX_NOTES_UNITS:
        return text
    suffix = '\n…'
    budget = MAX_NOTES_UNITS - utf16_len(suffix)
    out: List[str] = []
    used = 0
    for ch in text:
        units = 2 if ord(ch) > 0xFFFF else 1
        if used + units > budget:
            break
        out.append(ch)
        used += units
    cut = ''.join(out)
    last_break = cut.rfind('\n')
    if last_break > len(cut) // 2:
        cut = cut[:last_break]
    return cut.rstrip() + suffix


def read_notes_file(path: Path, what: str) -> str:
    raw = read_limited(path, 1024 * 1024, what)
    try:
        text = raw.decode('utf-8')
    except UnicodeDecodeError:
        raise ToolError(f'{what} is not valid UTF-8') from None
    return clean_notes(text)


def sha256_and_size(path: Path) -> Tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    try:
        with open(path, 'rb') as handle:
            while True:
                chunk = handle.read(1024 * 1024)
                if not chunk:
                    break
                size += len(chunk)
                if size > MAX_ASSET_BYTES:
                    raise ToolError(
                        f'{path.name} is larger than the {MAX_ASSET_BYTES} byte '
                        'cap the app enforces')
                digest.update(chunk)
    except OSError:
        raise ToolError(f'cannot read {path.name}') from None
    return digest.hexdigest(), size


def inspect_package(platform: str, path: Path) -> None:
    """Cheap sanity checks that catch a wrong or broken file before it is
    signed: it is a zip, and it looks like what the platform expects."""
    try:
        with open(path, 'rb') as handle:
            magic = handle.read(4)
    except OSError:
        raise ToolError(f'cannot read {path.name}') from None
    if magic != b'PK\x03\x04':
        raise ToolError(f'{path.name} is not a zip archive')
    try:
        with zipfile.ZipFile(path) as archive:
            names = archive.namelist()
    except (zipfile.BadZipFile, OSError):
        raise ToolError(f'{path.name} is not a readable zip archive') from None
    if platform == 'android':
        if 'AndroidManifest.xml' not in names:
            raise ToolError(f'{path.name} has no AndroidManifest.xml (not an APK)')
        return
    if platform == 'windows':
        for name in names:
            if ('\\' in name or name.startswith('/') or
                    '..' in name.split('/') or re.match(r'^[A-Za-z]:', name)):
                raise ToolError(f'{path.name} has an unsafe entry name')
        roots = [n for n in names if '/' not in n]
        if 'flutter_windows.dll' not in roots:
            raise ToolError(f'{path.name} has no flutter_windows.dll at its root')
        if not any(n.lower().endswith('.exe') for n in roots):
            raise ToolError(f'{path.name} has no .exe at its root')


# --------------------------------------------------------------------------
# The manifest
# --------------------------------------------------------------------------

def build_manifest(*, version: str, build: int, published_at: str,
                   notes: Dict[str, str],
                   assets: Dict[str, Dict[str, Any]]) -> Dict[str, Any]:
    """The manifest as a dict with the canonical key order (Python dicts keep
    insertion order, and canonical_bytes() does not sort)."""
    return {
        'schema': SCHEMA,
        'version': version,
        'build': build,
        'publishedAt': published_at,
        'notes': dict(notes),
        'assets': {
            key: {
                'name': asset['name'],
                'url': asset['url'],
                'size': asset['size'],
                'sha256': asset['sha256'],
            }
            for key, asset in assets.items()
        },
    }


def canonical_bytes(manifest: Dict[str, Any]) -> bytes:
    """The exact bytes that are signed and published."""
    text = json.dumps(manifest, indent=2, ensure_ascii=False,
                      separators=(',', ': '), allow_nan=False)
    return (text + '\n').encode('utf-8')


def _reject_duplicates(pairs: List[Tuple[str, Any]]) -> Dict[str, Any]:
    seen: Dict[str, Any] = {}
    for key, value in pairs:
        if key in seen:
            raise ToolError('manifest invalid: duplicate key')
        seen[key] = value
    return seen


def _reject_constant(_name: str) -> Any:
    raise ToolError('manifest invalid: not a JSON number')


def parse_manifest_bytes(raw: bytes) -> Dict[str, Any]:
    """Parse signature-verified bytes into a dict (strict JSON)."""
    if not raw or len(raw) > MAX_MANIFEST_BYTES:
        raise ToolError('manifest invalid: size')
    try:
        data = json.loads(raw.decode('utf-8'), object_pairs_hook=_reject_duplicates,
                          parse_constant=_reject_constant)
    except (UnicodeDecodeError, ValueError):
        raise ToolError('manifest invalid: not UTF-8 JSON') from None
    return validate_manifest(data)


def _bad(field: str) -> 'ToolError':
    return ToolError(f'manifest invalid: {field}')


def validate_manifest(data: Any) -> Dict[str, Any]:
    """Mirror of UpdateManifest.parse in lib/services/update/update_manifest.dart:
    the same fields, types and limits. Raises ToolError, returns [data]."""
    if not isinstance(data, dict):
        raise _bad('root')
    schema = data.get('schema')
    if type(schema) is not int:
        raise _bad('schema')
    if schema != SCHEMA:
        raise ToolError('manifest invalid: unsupported schema')
    version = data.get('version')
    build = data.get('build')
    if not isinstance(version, str) or type(build) is not int:
        raise _bad('version/build')
    try:
        parsed = parse_version(version)
    except ToolError:
        raise _bad('version') from None
    if build != build_of(*parsed):
        raise _bad('build does not match version')
    published = data.get('publishedAt')
    if (not isinstance(published, str) or len(published) > 40 or
            _TIMESTAMP_RE.match(published) is None):
        raise _bad('publishedAt')
    try:
        datetime.datetime.strptime(published[:19], '%Y-%m-%dT%H:%M:%S')
    except ValueError:
        raise _bad('publishedAt') from None

    notes = data.get('notes')
    if not isinstance(notes, dict) or len(notes) > MAX_NOTES_LANGUAGES:
        raise _bad('notes')
    for lang, text in notes.items():
        if (_LANG_RE.match(lang) is None or not isinstance(text, str) or
                utf16_len(text) > MAX_NOTES_UNITS or
                _BAD_CONTROL_RE.search(text) is not None):
            raise _bad('notes')

    assets = data.get('assets')
    if not isinstance(assets, dict) or not assets or len(assets) > MAX_ASSETS:
        raise _bad('assets')
    for key, asset in assets.items():
        if _PLATFORM_RE.match(key) is None or not isinstance(asset, dict):
            raise _bad('assets')
        _validate_asset(key, asset)
    return data


def _validate_asset(platform: str, asset: Dict[str, Any]) -> None:
    name = asset.get('name')
    url = asset.get('url')
    size = asset.get('size')
    digest = asset.get('sha256')
    where = f'assets.{platform}'
    if (not isinstance(name, str) or not name or len(name) > MAX_NAME_LENGTH or
            _FILE_NAME_RE.match(name) is None or '..' in name):
        raise _bad(f'{where}.name')
    if not isinstance(url, str) or not url or len(url) > MAX_URL_LENGTH:
        raise _bad(f'{where}.url')
    if type(size) is not int or size <= 0 or size > MAX_ASSET_BYTES:
        raise _bad(f'{where}.size')
    if not isinstance(digest, str) or _SHA256_RE.match(digest) is None:
        raise _bad(f'{where}.sha256')
    extension = EXTENSION_OF.get(platform)
    if extension is not None and not name.endswith(extension):
        raise _bad(f'{where}.name')
    # The app's first request goes to this URL, so it must be the tag-pinned
    # download URL on github.com; other hosts are reached only by redirect.
    if ('?' in url or '#' in url or '\\' in url or
            any(ord(ch) <= 0x20 or ord(ch) >= 0x7F for ch in url)):
        raise _bad(f'{where}.url')
    m = re.match(r'^https://github\.com(?::443)?(/[^?#]*)\Z', url)
    if m is None:
        raise _bad(f'{where}.url')
    path = m.group(1)
    if not re.match(r'^/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/releases/download/', path):
        raise _bad(f'{where}.url')
    if path.rsplit('/', 1)[1] != name:
        raise _bad(f'{where}.url')


def check_release_layout(data: Dict[str, Any], *, repo: str, tag: str,
                         version: str) -> None:
    """What the release workflow publishes, beyond what the app accepts:
    exactly the two generic assets, at the canonical URLs of this tag."""
    if tag != f'v{version}':
        raise ToolError('tag does not match the manifest version')
    assets = data['assets']
    if set(assets) != {key for key, _n, _e in PLATFORMS}:
        raise ToolError('manifest must hold exactly the android and windows assets')
    for key, name, _ext in PLATFORMS:
        asset = assets[key]
        if asset['name'] != name:
            raise ToolError(f'assets.{key}.name must be {name}')
        if asset['url'] != asset_url(repo, tag, name):
            raise ToolError(f'assets.{key}.url is not the canonical URL of this tag')


def decode_signature_text(raw: bytes) -> bytes:
    """A signature file: base64 of the 64 raw bytes, optional trailing
    whitespace (what the app's decodeSignatureFile accepts)."""
    if len(raw) > MAX_SIGNATURE_BYTES:
        raise ToolError('signature file is too large')
    try:
        text = raw.decode('ascii')
    except UnicodeDecodeError:
        raise ToolError('signature file is not ASCII') from None
    return decode_base64_strict(text, 64, 'signature')


def encode_signature_file(signature: bytes) -> bytes:
    return base64.b64encode(signature) + b'\n'


# --------------------------------------------------------------------------
# Signing
# --------------------------------------------------------------------------

def seed_from_environment() -> bytes:
    """The signing seed from UPDATE_SIGNING_KEY. Removes the variable from this
    process's environment; never echoes the value."""
    value = os.environ.pop(SIGNING_KEY_ENV, None)
    if value is None or not value.strip():
        raise ToolError(f'{SIGNING_KEY_ENV} is not set')
    return decode_base64_strict(
        value, 32, f'{SIGNING_KEY_ENV} (the base64 of a raw 32-byte Ed25519 seed)')


def sign_and_check(manifest_bytes: bytes, seed: bytes,
                   expected_public: Optional[bytes]) -> Tuple[bytes, bytes]:
    """Returns (signature, public key). Raises unless the signature verifies
    under the derived public key and, if given, the pinned one."""
    public = ed25519_public_key(seed)
    if expected_public is not None and public != expected_public:
        raise ToolError(
            'the signing key does not match the pinned public key '
            f'(derived {base64.b64encode(public).decode()}, pinned '
            f'{base64.b64encode(expected_public).decode()}): wrong '
            f'{SIGNING_KEY_ENV} secret?')
    signature = ed25519_sign(seed, manifest_bytes)
    if not ed25519_verify(public, manifest_bytes, signature):
        raise ToolError('the new signature does not verify (internal error)')
    if expected_public is not None and not ed25519_verify(
            expected_public, manifest_bytes, signature):
        raise ToolError('the new signature does not verify under the pinned key')
    return signature, public


def write_atomically(path: Path, data: bytes) -> None:
    tmp = path.with_name(path.name + '.tmp')
    try:
        with open(tmp, 'wb') as handle:
            handle.write(data)
        os.replace(tmp, path)
    except OSError:
        try:
            tmp.unlink()
        except OSError:
            pass
        raise ToolError(f'cannot write {path.name}') from None


# --------------------------------------------------------------------------
# Command line
# --------------------------------------------------------------------------

def make_release(args: argparse.Namespace) -> int:
    version = args.version
    parsed = parse_version(version)
    if args.build != build_of(*parsed):
        raise ToolError(
            f'--build must be major*1000000 + minor*1000 + patch '
            f'({build_of(*parsed)} for {version})')
    if args.tag != f'v{version}':
        raise ToolError('--tag must be v<version>')
    repo = parse_repo(args.repo)
    published_at = args.published_at
    if published_at is None:
        published_at = datetime.datetime.now(datetime.timezone.utc).strftime(
            '%Y-%m-%dT%H:%M:%SZ')
    if _STRICT_TIMESTAMP_RE.match(published_at) is None:
        raise ToolError('--published-at must look like 2026-10-07T12:00:00Z (UTC)')
    try:
        datetime.datetime.strptime(published_at, '%Y-%m-%dT%H:%M:%SZ')
    except ValueError:
        raise ToolError('--published-at is not a valid date') from None

    # Decide how to sign before touching any file, so that a missing or
    # mistaken key fails fast.
    if args.ephemeral_key:
        if SIGNING_KEY_ENV in os.environ:
            raise ToolError(
                f'--ephemeral-key was given but {SIGNING_KEY_ENV} is set: a dry '
                'run must not have the real signing key in its environment')
        if args.expect_public_key:
            raise ToolError('--ephemeral-key cannot be combined with '
                            '--expect-public-key (a throwaway key never matches)')
        seed = secrets.token_bytes(32)
    else:
        if args.public_key_out:
            raise ToolError('--public-key-out is only for --ephemeral-key runs')
        seed = seed_from_environment()
    expected_public = (read_public_key_file(Path(args.expect_public_key))
                       if args.expect_public_key else None)

    notes: Dict[str, str] = {}
    notes['en'] = read_notes_file(Path(args.notes_file), '--notes-file')
    if not notes['en']:
        raise ToolError('--notes-file is empty (release notes are required)')
    if args.notes_ar_file:
        notes['ar'] = read_notes_file(Path(args.notes_ar_file), '--notes-ar-file')
        if not notes['ar']:
            raise ToolError('--notes-ar-file is empty')

    assets: Dict[str, Dict[str, Any]] = {}
    sources = {'android': args.apk, 'windows': args.windows_zip}
    for key, name, extension in PLATFORMS:
        path = Path(sources[key])
        if path.suffix != extension:
            raise ToolError(f'the {key} package must be a {extension} file')
        if not path.is_file():
            raise ToolError(f'the {key} package does not exist')
        inspect_package(key, path)
        digest, size = sha256_and_size(path)
        if size <= 0:
            raise ToolError(f'the {key} package is empty')
        assets[key] = {'name': name, 'url': asset_url(repo, args.tag, name),
                       'size': size, 'sha256': digest}

    manifest = build_manifest(version=version, build=args.build,
                              published_at=published_at, notes=notes,
                              assets=assets)
    manifest_bytes = canonical_bytes(manifest)
    # Parse what we are about to sign exactly as the app would.
    parsed_back = parse_manifest_bytes(manifest_bytes)
    check_release_layout(parsed_back, repo=repo, tag=args.tag, version=version)

    signature, public = sign_and_check(manifest_bytes, seed, expected_public)
    del seed

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    write_atomically(out_dir / 'update.json', manifest_bytes)
    write_atomically(out_dir / 'update.json.sig', encode_signature_file(signature))
    public_b64 = base64.b64encode(public).decode()
    if args.ephemeral_key and args.public_key_out:
        write_atomically(Path(args.public_key_out), (public_b64 + '\n').encode())

    print(f'update.json      {len(manifest_bytes)} bytes, version {version}, '
          f'build {args.build}')
    for key, _name, _ext in PLATFORMS:
        a = assets[key]
        print(f'{key:<16} {a["name"]} {a["size"]} bytes sha256 {a["sha256"]}')
    print(f'update.json.sig  signed with public key {public_b64}'
          + (' (EPHEMERAL, dry run)' if args.ephemeral_key else
             ' (matches the pinned key)' if expected_public else
             ' (not compared to a pinned key)'))
    return 0


def check_key(args: argparse.Namespace) -> int:
    seed = seed_from_environment()
    public = ed25519_public_key(seed)
    del seed
    public_b64 = base64.b64encode(public).decode()
    print(f'public key derived from {SIGNING_KEY_ENV}: {public_b64}')
    if args.expect_public_key:
        expected = read_public_key_file(Path(args.expect_public_key))
        if expected != public:
            raise ToolError('does NOT match the pinned public key')
        print('matches the pinned public key')
    return 0


def generate_key(_args: argparse.Namespace) -> int:
    seed = secrets.token_bytes(32)
    public = ed25519_public_key(seed)
    print('NEW signing key. Store the seed in a password manager and in the '
          f'GitHub secret {SIGNING_KEY_ENV}; never commit or share it.')
    print(f'  {SIGNING_KEY_ENV} (secret, base64 seed): '
          f'{base64.b64encode(seed).decode()}')
    print(f'  public key (release/update_public_key.txt): '
          f'{base64.b64encode(public).decode()}')
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description='Build and sign update.json for a release.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='The signing key comes from the environment variable '
               f'{SIGNING_KEY_ENV} (base64 of the raw 32-byte Ed25519 seed).')
    p.add_argument('--version', help='X.Y.Z')
    p.add_argument('--build', type=int,
                   help='major*1000000 + minor*1000 + patch')
    p.add_argument('--tag', help='vX.Y.Z')
    p.add_argument('--repo', default=DEFAULT_REPO, help='owner/name')
    p.add_argument('--apk', help='the signed release APK')
    p.add_argument('--windows-zip', help='the Windows zip (files at its root)')
    p.add_argument('--notes-file', help='release notes (UTF-8), English')
    p.add_argument('--notes-ar-file', help='optional Arabic release notes')
    p.add_argument('--out-dir', help='where update.json and update.json.sig go')
    p.add_argument('--published-at', help='UTC time, 2026-10-07T12:00:00Z '
                                          '(default: now)')
    p.add_argument('--expect-public-key', metavar='FILE',
                   help='pinned public key file; the signing key must match')
    p.add_argument('--ephemeral-key', action='store_true',
                   help='sign with a random throwaway key (dry runs)')
    p.add_argument('--public-key-out', metavar='FILE',
                   help='with --ephemeral-key: write the throwaway public key')
    p.add_argument('--check-key', action='store_true',
                   help=f'only derive the public key of {SIGNING_KEY_ENV}')
    p.add_argument('--generate-key', action='store_true',
                   help='print a NEW random signing key (run locally, never in CI)')
    return p


_REQUIRED_FOR_RELEASE = ('version', 'build', 'tag', 'apk', 'windows_zip',
                         'notes_file', 'out_dir')


def main(argv: Optional[List[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if args.generate_key:
            return generate_key(args)
        if args.check_key:
            return check_key(args)
        missing = [name for name in _REQUIRED_FOR_RELEASE
                   if getattr(args, name) is None]
        if missing:
            parser.error('missing --' + ', --'.join(
                name.replace('_', '-') for name in missing))
        return make_release(args)
    except ToolError as error:
        print(f'error: {error}', file=sys.stderr)
        return 1
    except Exception as error:  # noqa: BLE001 - never leak locals or secrets
        print(f'error: unexpected failure ({type(error).__name__})',
              file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
