#!/usr/bin/env python3
"""Add the browser extension to a Windows build of the app.

    python3 tool/bundle_browser.py build/windows/x64/runner/Release --version 0.1.2

Puts two things next to the app's exe:

* khazna_bridge.exe, the browser helper (Chrome's native messaging host),
  compiled from browser/bridge with `dart compile exe`. `--helper <file>`
  copies an already built one instead.
* extension/, the unpacked Chrome extension (browser/extension without its
  tests), with the manifest's version set to --version.

It refuses a manifest whose public key does not give the extension id the
app expects (browser/bridge/lib/bridge_protocol.dart): the app's native
messaging manifest only lets that id start the helper.

Standard library only; `dart` must be on PATH unless --helper is given.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / 'browser' / 'bridge'
EXTENSION = ROOT / 'browser' / 'extension'
PROTOCOL = BRIDGE / 'lib' / 'bridge_protocol.dart'
HELPER_NAME = 'khazna_bridge.exe'
VERSION = re.compile(r'^\d{1,4}\.\d{1,3}\.\d{1,3}$')


def extension_id(key_b64: str) -> str:
    """Chrome's id for a manifest "key": SHA-256 of the DER public key, first
    16 bytes, each hex digit 0-f written as a-p."""
    digest = hashlib.sha256(base64.b64decode(key_b64)).hexdigest()[:32]
    return ''.join(chr(ord('a') + int(c, 16)) for c in digest)


def expected_id() -> str:
    m = re.search(r"const extensionId = '([a-p]{32})';", PROTOCOL.read_text('utf-8'))
    if not m:
        raise SystemExit(f'extensionId not found in {PROTOCOL}')
    return m.group(1)


def copy_extension(dest: Path, version: str | None) -> None:
    manifest = json.loads((EXTENSION / 'manifest.json').read_text('utf-8'))
    got = extension_id(manifest['key'])
    want = expected_id()
    if got != want:
        raise SystemExit(f'extension key gives id {got}, the app expects {want}')
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(EXTENSION, dest, ignore=shutil.ignore_patterns('test', '.*'))
    if version is not None:
        manifest['version'] = version
        (dest / 'manifest.json').write_text(
            json.dumps(manifest, indent=2, ensure_ascii=False) + '\n', 'utf-8')


def build_helper(dest: Path, prebuilt: Path | None) -> None:
    if prebuilt is not None:
        shutil.copyfile(prebuilt, dest)
        return
    dart = shutil.which('dart')
    if dart is None:
        raise SystemExit('dart not found on PATH (or pass --helper)')
    subprocess.run([dart, 'pub', 'get'], cwd=BRIDGE, check=True)
    subprocess.run(
        [dart, 'compile', 'exe', 'bin/khazna_bridge.dart', '-o', str(dest)],
        cwd=BRIDGE, check=True)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('release_dir', type=Path,
                    help='the folder with the app exe (build/windows/x64/runner/Release)')
    ap.add_argument('--version', help='x.y.z for the extension manifest')
    ap.add_argument('--helper', type=Path, help='a built khazna_bridge.exe to copy')
    args = ap.parse_args(argv)

    if args.version is not None and not VERSION.match(args.version):
        raise SystemExit(f'not a version: {args.version}')
    if not args.release_dir.is_dir():
        raise SystemExit(f'not a folder: {args.release_dir}')
    copy_extension(args.release_dir / 'extension', args.version)
    build_helper(args.release_dir / HELPER_NAME, args.helper)
    print(f'Added {HELPER_NAME} and extension/ to {args.release_dir}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
