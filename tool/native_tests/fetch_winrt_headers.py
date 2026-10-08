#!/usr/bin/env python3
"""Downloads the C++/WinRT projection headers (winrt/Windows.*.h) so that
run_tests.py can compile the OCR code of windows/runner/platform_channel.cpp
with mingw-w64 against the real API instead of a stub.

The headers are part of the Microsoft.Windows.SDK.CPP NuGet package (about
160 MB; only text headers are extracted, nothing is executed). Output goes
to <dest>/winrt/... with lowercase file names and include paths, so that it
works on a case-sensitive file system.

Usage: python3 tool/native_tests/fetch_winrt_headers.py DEST_DIR
Then:  HISN_WINRT_HEADERS=DEST_DIR python3 tool/native_tests/run_tests.py
"""
import io
import json
import os
import re
import sys
import urllib.request
import zipfile

PACKAGE = 'microsoft.windows.sdk.cpp'
INDEX = 'https://api.nuget.org/v3-flatcontainer/%s/index.json' % PACKAGE
INCLUDE = re.compile(r'(#\s*include\s*[<"])(winrt/[^>"]+)([>"])')


def get(url):
    with urllib.request.urlopen(url, timeout=300) as r:
        return r.read()


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    dest = os.path.abspath(sys.argv[1])
    versions = [v for v in json.loads(get(INDEX))['versions']
                if re.fullmatch(r'10\.0\.\d+\.\d+', v)]
    version = sorted(versions, key=lambda v: [int(x) for x in v.split('.')])[-1]
    print('using %s %s' % (PACKAGE, version))
    url = 'https://api.nuget.org/v3-flatcontainer/%s/%s/%s.%s.nupkg' % (
        PACKAGE, version, PACKAGE, version)
    package = zipfile.ZipFile(io.BytesIO(get(url)))
    marker = '/cppwinrt/winrt/'
    count = 0
    for name in package.namelist():
        if marker not in name or name.endswith('/'):
            continue
        rel = 'winrt/' + name.split(marker, 1)[1]
        target = os.path.join(dest, rel)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        text = package.read(name).decode('utf-8', errors='replace')
        text = INCLUDE.sub(
            lambda m: m.group(1) + m.group(2).lower() + m.group(3), text)
        with open(target, 'w', encoding='utf-8') as f:
            f.write(text)
        count += 1
    print('extracted %d headers to %s' % (count, dest))


if __name__ == '__main__':
    main()
