# VaultSnap

Zero-knowledge, offline-first password manager (Flutter: Android, iOS, Windows;
Supabase used only for auth + encrypted blobs).

See [docs/SECURITY.md](docs/SECURITY.md) for the design, rationale and known weaknesses.

## Status

- [x] Phase 1 – crypto layer + known-answer tests (`lib/core/crypto/`)
- [ ] Phase 2 – local vault (drift + SQLCipher) + UI
- [ ] Phase 3 – OCR import
- [ ] Phase 4 – sync
- [ ] Phase 5 – autofill + biometrics
- [ ] Phase 6 – security dashboard

## Running the tests

```sh
flutter pub get
flutter test test/core/crypto
```

The first run compiles libsodium from source through `package:sodium`'s build
hook (needs a C toolchain: gcc/clang on Linux & macOS, MSVC on Windows).

Regenerating the golden vectors (only if the format intentionally changes,
which also requires a format version bump):

```sh
pip install argon2-cffi cryptography
python3 tool/gen_crypto_vectors.py > test/core/crypto/golden_vectors.dart
```
