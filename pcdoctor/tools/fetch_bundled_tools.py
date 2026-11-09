"""CI only: downloads the pinned bundled tools for one architecture into <out>/tools, verifying SHA-256.

Usage: python -I tools/fetch_bundled_tools.py <X64|Arm64> <out-dir>
"""
import hashlib, io, json, os, shutil, sys, urllib.request, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "third_party")


def main(arch: str, out: str) -> None:
    manifest = json.load(open(os.path.join(ROOT, "bundled-tools.json"), encoding="utf-8"))
    dest = os.path.join(out, "tools")
    os.makedirs(dest, exist_ok=True)
    cache = {}
    for tool in manifest["tools"]:
        if tool["arch"] != arch:
            continue
        url = tool["url"]
        if url not in cache:
            with urllib.request.urlopen(url, timeout=120) as r:
                cache[url] = r.read()
        data = cache[url]
        if tool["zipEntry"]:
            data = zipfile.ZipFile(io.BytesIO(data)).read(tool["zipEntry"])
        digest = hashlib.sha256(data).hexdigest()
        if digest != tool["sha256"]:
            sys.exit(f"{tool['name']} ({arch}): hash {digest} != pinned {tool['sha256']}")
        with open(os.path.join(dest, tool["name"]), "wb") as f:
            f.write(data)
        shutil.copy(os.path.join(ROOT, "licenses", tool["license"]), dest)
        print(f"{tool['name']} {arch} ok")
    shutil.copy(os.path.join(ROOT, "bundled-tools.json"), dest)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
