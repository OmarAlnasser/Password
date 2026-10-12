# Khazna

Zero-knowledge, offline-first password manager (Flutter: Android, iOS, Windows;
Supabase used only for auth + encrypted blobs).

See [docs/SECURITY.md](docs/SECURITY.md) for the design, rationale and known weaknesses.

## Status

- [x] Phase 1 – crypto layer + known-answer tests (`lib/core/crypto/`)
- [x] Phase 2 – local vault (drift + SQLCipher) + UI
- [x] Phase 3 – OCR import
- [x] Phase 4 – sync (`supabase/`)
- [x] Phase 5 – autofill + biometrics
- [x] Phase 6 – security dashboard
- [x] Security audit – [docs/SECURITY_AUDIT.md](docs/SECURITY_AUDIT.md) (findings open)
- [x] Browser extension for Chrome, Edge and Brave on Windows – [docs/BROWSER_EXTENSION.md](docs/BROWSER_EXTENSION.md)

## Installing on Windows

1. Download `windows-x64-setup.exe` from the latest
   [release](https://github.com/OmarAlnasser/Password/releases/latest).
2. Run it. It installs for your Windows user only, into
   `%LOCALAPPDATA%\Programs\Khazna`, and does not ask for admin rights. The
   files are not code-signed, so SmartScreen may say "Windows protected your
   PC": choose *More info → Run anyway*.
3. Start Khazna from the Start menu or the desktop shortcut.

Updates install themselves: when a new version is out, the app offers it,
checks the download against the signed update manifest, closes, runs the new
setup without a window and opens again. To remove the app use Settings → Apps →
Installed apps; your vault is kept (it lives in your app data folder, not in
the install folder).

`windows-x64.zip` is still published with every release: the same app as a
plain folder, for portable use without installing. A portable copy updates
by running the setup too, so after its first update it lives in the installed
folder; delete the old one.

## Running the tests

```sh
flutter pub get
flutter test --exclude-tags finding     # full suite (green)
flutter test test/audit                 # audit: failing tests = open findings
PGHOST=/path PGPORT=5432 supabase/tests/run_rls_tests.sh   # RLS attack suite
```

The first run compiles libsodium from source through `package:sodium`'s build
hook (needs a C toolchain: gcc/clang on Linux & macOS, MSVC on Windows).

Regenerating the golden vectors (only if the format intentionally changes,
which also requires a format version bump):

```sh
pip install argon2-cffi cryptography
python3 tool/gen_crypto_vectors.py > test/core/crypto/golden_vectors.dart
```
