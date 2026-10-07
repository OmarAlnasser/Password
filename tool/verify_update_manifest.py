#!/usr/bin/env python3
"""Verify an update manifest, its signature and (optionally) the packages.

Used by .github/workflows/release.yml before a release is created and again
after it is published. Python 3.9+, standard library only.

Local files:

    python3 tool/verify_update_manifest.py \\
        --manifest update.json --signature update.json.sig \\
        --public-key release/update_public_key.txt \\
        --apk dist/android.apk --windows-zip dist/windows-x64.zip \\
        --version 0.2.0 --build 2000 --tag v0.2.0 --repo OmarAlnasser/Password

What the published release looks like to the world (no credentials, the same
URLs and redirects the app follows):

    python3 tool/verify_update_manifest.py --remote --repo OmarAlnasser/Password \\
        --tag v0.2.0 --public-key release/update_public_key.txt \\
        --download-assets --check-latest

Order of checks, each one stops the run:

  1. Size limits (manifest 64 KiB, signature 1 KiB) before anything is parsed.
  2. The signature, over the exact manifest bytes, with the pinned public key.
     Nothing in the manifest is looked at before this passes.
  3. The manifest schema, with the same rules as the app
     (lib/services/update/update_manifest.dart).
  4. With --version/--build/--tag/--repo: the manifest says what the workflow
     built, and the assets are exactly the two generic packages at the
     canonical URLs of this tag.
  5. With --apk/--windows-zip: size and SHA-256 of the local files. With
     --download-assets (remote mode): the same for the files as downloaded from
     the published release.
  6. With --check-latest (remote mode): releases/latest/download/update.json is
     byte-identical, i.e. an installed app that polls "latest" sees this
     release.

Remote mode is HTTPS only, follows at most 5 redirects, checks the host of
every hop against the same allow-list as the app, and caps what it reads.
Exit status: 0 verified, 1 verification failed, 2 bad usage.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple


def _load_shared() -> Any:
    """The signing tool next to this file: Ed25519, schema checks, constants.
    Loaded by path so that it works from any directory and under `python -I`."""
    path = Path(__file__).resolve().with_name('make_update_manifest.py')
    spec = importlib.util.spec_from_file_location('make_update_manifest', path)
    if spec is None or spec.loader is None:
        raise SystemExit('error: cannot load make_update_manifest.py')
    module = importlib.util.module_from_spec(spec)
    sys.modules['make_update_manifest'] = module
    spec.loader.exec_module(module)
    return module


shared = _load_shared()
ToolError = shared.ToolError

# Same list as UpdateConfig.defaultAllowedHosts. Exact names, no wildcard.
ALLOWED_HOSTS = frozenset({
    'github.com',
    'objects.githubusercontent.com',
    'release-assets.githubusercontent.com',
})
MAX_REDIRECTS = 5
REQUEST_TIMEOUT = 30
USER_AGENT = 'update-manifest-verifier'


# --------------------------------------------------------------------------
# Verification (pure, no network)
# --------------------------------------------------------------------------

def verify_signed_manifest(manifest_bytes: bytes, signature_bytes: bytes,
                           public_key: bytes) -> Dict[str, Any]:
    """Signature first, schema second. Returns the validated manifest."""
    if not manifest_bytes or len(manifest_bytes) > shared.MAX_MANIFEST_BYTES:
        raise ToolError('manifest is empty or larger than 64 KiB')
    signature = shared.decode_signature_text(signature_bytes)
    if not shared.ed25519_verify(public_key, manifest_bytes, signature):
        raise ToolError('SIGNATURE INVALID: the manifest was not signed with '
                        'the pinned key (or was changed after signing)')
    return shared.parse_manifest_bytes(manifest_bytes)


def check_expectations(manifest: Dict[str, Any], *, version: Optional[str],
                       build: Optional[int], tag: Optional[str],
                       repo: Optional[str], release_layout: bool) -> None:
    if version is not None and manifest['version'] != version:
        raise ToolError('manifest version is not the version that was built')
    if build is not None and manifest['build'] != build:
        raise ToolError('manifest build is not the build that was built')
    if release_layout:
        if tag is None or repo is None:
            raise ToolError('--tag and --repo are needed to check the layout')
        shared.check_release_layout(manifest, repo=shared.parse_repo(repo),
                                    tag=tag, version=manifest['version'])


def check_file_against_asset(path: Path, asset: Dict[str, Any], what: str) -> None:
    digest, size = shared.sha256_and_size(path)
    if size != asset['size']:
        raise ToolError(f'{what}: size {size} differs from the manifest '
                        f'({asset["size"]})')
    if digest != asset['sha256'].lower():
        raise ToolError(f'{what}: SHA-256 differs from the manifest')


# --------------------------------------------------------------------------
# Network (remote mode only)
# --------------------------------------------------------------------------

class _CheckedRedirects(urllib.request.HTTPRedirectHandler):
    """Every hop: https, allow-listed host, no credentials, default port."""

    max_redirections = MAX_REDIRECTS

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # type: ignore[no-untyped-def]
        check_url(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def check_url(url: str) -> None:
    parts = urllib.parse.urlsplit(url)
    host = parts.hostname or ''
    if (parts.scheme != 'https' or parts.username is not None or
            parts.password is not None or parts.port not in (None, 443) or
            host not in ALLOWED_HOSTS or len(url) > 4096):
        raise ToolError('a request or redirect left the allowed HTTPS hosts')


def fetch(url: str, limit: int, what: str) -> bytes:
    """GET [url] without credentials. Reads at most [limit] bytes and fails if
    there is more."""
    check_url(url)
    opener = urllib.request.build_opener(_CheckedRedirects())
    request = urllib.request.Request(url, headers={'User-Agent': USER_AGENT,
                                                    'Accept': '*/*'})
    try:
        with opener.open(request, timeout=REQUEST_TIMEOUT) as response:
            if response.status != 200:
                raise ToolError(f'{what}: HTTP {response.status}')
            length = response.headers.get('Content-Length')
            if length is not None and length.isdigit() and int(length) > limit:
                raise ToolError(f'{what}: larger than {limit} bytes')
            chunks: List[bytes] = []
            total = 0
            while True:
                chunk = response.read(64 * 1024)
                if not chunk:
                    break
                total += len(chunk)
                if total > limit:
                    raise ToolError(f'{what}: larger than {limit} bytes')
                chunks.append(chunk)
            return b''.join(chunks)
    except urllib.error.HTTPError as error:
        raise ToolError(f'{what}: HTTP {error.code}') from None
    except (urllib.error.URLError, OSError, ValueError) as error:
        reason = getattr(error, 'reason', None)
        raise ToolError(f'{what}: network error '
                        f'({type(reason or error).__name__})') from None


def fetch_digest(url: str, limit: int, what: str) -> Tuple[str, int]:
    """SHA-256 and size of [url], streamed (the packages are large)."""
    check_url(url)
    opener = urllib.request.build_opener(_CheckedRedirects())
    request = urllib.request.Request(url, headers={'User-Agent': USER_AGENT,
                                                    'Accept': '*/*'})
    digest = hashlib.sha256()
    total = 0
    try:
        with opener.open(request, timeout=REQUEST_TIMEOUT) as response:
            if response.status != 200:
                raise ToolError(f'{what}: HTTP {response.status}')
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                total += len(chunk)
                if total > limit:
                    raise ToolError(f'{what}: larger than {limit} bytes')
                digest.update(chunk)
    except urllib.error.HTTPError as error:
        raise ToolError(f'{what}: HTTP {error.code}') from None
    except (urllib.error.URLError, OSError, ValueError) as error:
        reason = getattr(error, 'reason', None)
        raise ToolError(f'{what}: network error '
                        f'({type(reason or error).__name__})') from None
    return digest.hexdigest(), total


def with_retries(action: Callable[[], Any], attempts: int, delay: float,
                 what: str) -> Any:
    """Release files can take a short while to appear on GitHub's CDN."""
    last: Optional[ToolError] = None
    for attempt in range(max(1, attempts)):
        try:
            return action()
        except ToolError as error:
            last = error
            if attempt + 1 < attempts:
                print(f'  {what}: {error}; retrying in {delay:g}s '
                      f'({attempt + 1}/{attempts})', file=sys.stderr)
                time.sleep(delay)
    assert last is not None
    raise last


# --------------------------------------------------------------------------
# Command line
# --------------------------------------------------------------------------

def run(args: argparse.Namespace) -> int:
    if args.public_key is None:
        raise ToolError('--public-key is required')
    public_key = shared.read_public_key_file(Path(args.public_key))

    if args.remote:
        if not args.repo or not args.tag:
            raise ToolError('--remote needs --repo and --tag')
        repo = shared.parse_repo(args.repo)
        base = f'https://github.com/{repo}/releases/download/{args.tag}/'
        manifest_bytes = with_retries(
            lambda: fetch(base + 'update.json', shared.MAX_MANIFEST_BYTES,
                          'update.json'),
            args.retries, args.retry_delay, 'update.json')
        signature_bytes = with_retries(
            lambda: fetch(base + 'update.json.sig', shared.MAX_SIGNATURE_BYTES,
                          'update.json.sig'),
            args.retries, args.retry_delay, 'update.json.sig')
    else:
        if not args.manifest or not args.signature:
            raise ToolError('--manifest and --signature are required '
                            '(or use --remote)')
        if args.download_assets or args.check_latest:
            raise ToolError('--download-assets and --check-latest need --remote')
        manifest_bytes = shared.read_limited(
            Path(args.manifest), shared.MAX_MANIFEST_BYTES, 'the manifest')
        signature_bytes = shared.read_limited(
            Path(args.signature), shared.MAX_SIGNATURE_BYTES, 'the signature')

    manifest = verify_signed_manifest(manifest_bytes, signature_bytes, public_key)
    print(f'signature ok, manifest ok: version {manifest["version"]}, '
          f'build {manifest["build"]}')

    check_expectations(manifest, version=args.version, build=args.build,
                       tag=args.tag, repo=args.repo,
                       release_layout=args.release_layout)

    for key, option in (('android', args.apk), ('windows', args.windows_zip)):
        if option is None:
            continue
        asset = manifest['assets'].get(key)
        if asset is None:
            raise ToolError(f'the manifest has no {key} asset')
        path = Path(option)
        if path.suffix != shared.EXTENSION_OF[key]:
            raise ToolError(f'the {key} package must be a '
                            f'{shared.EXTENSION_OF[key]} file')
        check_file_against_asset(path, asset, f'local {key} package')
        shared.inspect_package(key, path)
        print(f'local {key} package matches the manifest ({asset["size"]} bytes)')

    if args.remote and args.download_assets:
        for key, asset in manifest['assets'].items():
            digest, size = with_retries(
                lambda a=asset: fetch_digest(
                    a['url'], shared.MAX_ASSET_BYTES, 'published ' + a['name']),
                args.retries, args.retry_delay, asset['name'])
            if size != asset['size'] or digest != asset['sha256'].lower():
                raise ToolError(f'published {asset["name"]} does not match the '
                                'signed manifest (size or SHA-256)')
            print(f'published {key} package matches the manifest '
                  f'({asset["size"]} bytes, downloaded without credentials)')

    if args.remote and args.check_latest:
        repo = shared.parse_repo(args.repo)
        latest = f'https://github.com/{repo}/releases/latest/download/'
        with_retries(
            lambda: _same_bytes(
                fetch(latest + 'update.json', shared.MAX_MANIFEST_BYTES,
                      'latest update.json'), manifest_bytes),
            args.retries, args.retry_delay, 'latest update.json')
        with_retries(
            lambda: _same_bytes(
                fetch(latest + 'update.json.sig', shared.MAX_SIGNATURE_BYTES,
                      'latest update.json.sig'), signature_bytes),
            args.retries, args.retry_delay, 'latest update.json.sig')
        print('releases/latest serves this manifest and signature: installed '
              'apps will see this release')
    print('VERIFIED')
    return 0


def _same_bytes(got: bytes, want: bytes) -> bytes:
    if got != want:
        raise ToolError('releases/latest does not serve this release yet')
    return got


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description='Verify update.json, its signature and the packages.',
        formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--manifest', help='local update.json')
    p.add_argument('--signature', help='local update.json.sig')
    p.add_argument('--public-key', metavar='FILE', help='pinned public key file')
    p.add_argument('--apk', help='local android package to check')
    p.add_argument('--windows-zip', help='local windows package to check')
    p.add_argument('--version', help='expected version, X.Y.Z')
    p.add_argument('--build', type=int, help='expected build number')
    p.add_argument('--tag', help='expected tag, vX.Y.Z')
    p.add_argument('--repo', help='owner/name')
    p.add_argument('--release-layout', action='store_true',
                   help='require exactly the generic android.apk and '
                        'windows-x64.zip at the canonical URLs of --tag')
    p.add_argument('--remote', action='store_true',
                   help='fetch update.json and its signature from the GitHub '
                        'release of --repo/--tag instead of local files')
    p.add_argument('--download-assets', action='store_true',
                   help='with --remote: download every package and compare')
    p.add_argument('--check-latest', action='store_true',
                   help='with --remote: releases/latest must serve the same bytes')
    p.add_argument('--retries', type=int, default=1,
                   help='with --remote: attempts per download (default 1)')
    p.add_argument('--retry-delay', type=float, default=10.0,
                   help='seconds between attempts (default 10)')
    return p


def main(argv: Optional[List[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return run(args)
    except ToolError as error:
        print(f'FAILED: {error}', file=sys.stderr)
        return 1
    except Exception as error:  # noqa: BLE001
        print(f'FAILED: unexpected failure ({type(error).__name__})',
              file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
