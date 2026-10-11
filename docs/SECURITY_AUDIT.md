# Khazna security audit

Date: 2026-10-05 · Scope: the whole repository at the time of the audit
(Dart app, Android/iOS/Windows native code, Supabase SQL + edge function).
Status: **findings only, nothing fixed** (awaiting owner approval).

## How it was tested

| Area | Method | Result |
|---|---|---|
| Crypto | Manual review + KATs (libsodium vectors, PHC Argon2id, golden vault from an independent Python implementation) + per-bit tamper tests | No crypto break found |
| RLS | `supabase/tests/run_rls_tests.sh`: 35 attack queries as Alice against Bob on real PostgreSQL 16 with a Supabase role/grant shim | 33 pass, **2 fail (M-2)** |
| Network | `test/audit/network_inspection_test.dart`: the real Supabase client against a recording backend, full sign-up → sync → second-device sign-in, every request scanned for 25 secret encodings | Pass. Exposed **H-1** |
| Attacks | `test/audit/attack_test.dart`: brute force, throttle, KDF abuse, zxcvbn DoS, CSV fuzz (2,000 inputs), malformed backups, forged tombstones, replay, mass deletion, 600-item pull | 8 pass, **7 fail (findings)** |
| Sync | `test/sync/sync_test.dart`: tamper, swap, stale revision, garbage payloads, header swap | Pass. Replay weakness recorded (**M-1**) |
| Leaks | grep of Dart/Kotlin/Swift/C++ for logging, temp files, toString, analytics SDKs; review of backup and clipboard paths | See M-7, M-10, L-2, L-3, L-10 |
| Dependencies | `osv-scanner` 2.3.3 (offline OSV DB) on 188 pub packages, plus manual review of native libraries | 0 known CVEs (see note) |

Run the finding tests: `flutter test test/audit` (they are expected to fail
until fixed). Normal suite: `flutter test --exclude-tags finding` (all green).

## Summary

| ID | Severity | Title |
|---|---|---|
| H-1 | High | Sync pulls newest-first; changes beyond 500 are silently lost |
| H-2 | High | Deletions (tombstones) are unauthenticated; the mass-delete guard can be bypassed |
| H-3 | High | Supabase auth not hardened: email reset lets an outsider take over the sync account |
| M-1 | Medium | Replayed old ciphertext is accepted (rollback) |
| M-2 | Medium | API roles can `setval` the shared sequence and `TRUNCATE` items (RLS bypass, latent) |
| M-3 | Medium | No upper bound on KDF parameters: server or file can hang or OOM-kill the app |
| M-4 | Medium | zxcvbn hangs on ≥256-char input (UI freeze, DoS via import) |
| M-5 | Medium | Master-password policy (zxcvbn ≥ 3) too weak for an offline Argon2 attack |
| M-6 | Medium | Plaintext temp copies of imported CSVs and screenshots persist |
| M-7 | Medium | Vault key never rotates |
| M-8 | Medium | iOS AutoFill snapshot made without biometric opt-in, never removed |
| M-9 | Medium | iOS iCloud backup / Windows Roaming AppData carry the vault off-device |
| M-10 | Medium | Android autofill trusts browser package names without signature check |
| M-11 | Medium | Background auto-lock breaks OCR/import/export, which pushes users to disable it |
| M-12 | Medium | Recovery edge function does not revoke sessions; unpinned dependency |
| M-13 | Medium | Secrets held in unwipeable Dart Strings (DB key, KEK, entries) |
| M-14 | Medium | Export password has no strength requirement |
| L-1…L-13 | Low | See below |
| I-1…I-6 | Info | Functional gaps found during audit |

No **Critical** findings. The zero-knowledge property held under every test:
the server never received the master password, any key, or any plaintext.

---

## High

### H-1 Sync pulls newest-first; changes beyond 500 are silently lost
- **File:** `lib/services/sync/supabase_remote_store.dart` (`pullSince`: `.order('seq')`)
- **Scenario:** in `postgrest-dart`, `order()` defaults to `ascending: false`.
  The captured request is `…&seq=gt.0&order=seq.desc.nullslast&limit=500`. A
  device that is more than 500 changes behind receives the newest 500 and moves
  its cursor past all older ones. Those changes are never pulled. Signing in on
  a new device with 600 entries yields **500**, and nothing reports an error.
  This also happens after an offline period or a bulk import.
- **Evidence:** `attack_test.dart` "H-1" → `pulled 500 of 600`;
  `build/audit_network_calls.txt`.
- **Fix:** `.order('seq', ascending: true)`. Add a contract test that runs
  against the SQL (or against the recorded query string) so a fake server
  cannot hide this again.

### H-2 Deletions are unauthenticated; the mass-delete guard can be bypassed
- **Files:** `lib/services/sync/sync_service.dart` (`applyRemote`,
  `_guardMassDeletion`), `supabase/migrations/…sql` (`tombstone_shape`)
- **Scenario:** a tombstone is `deleted=true, payload=null`, with no AEAD tag.
  Anyone who can write the user's rows can delete any entry on every device:
  the server operator, someone holding a stolen refresh token, or an
  attacker who took over the account via H-3. The guard only triggers
  when a single pull deletes ≥ 5 entries and > 50 %. Deleting 4 entries per
  sync wipes the whole vault in a few rounds.
- **Evidence:** "H-2" (forged deletion applied); "H-2b" (12 → 0 entries in
  3 rounds).
- **Fix:** make deletions authenticated. Seal a tombstone payload
  `{id, deleted:true, deletedAt, version}` with the entry key and require it
  in `applyRemote`. Keep a local trash (soft delete) for 30 days. Make the
  guard cumulative over a time window, and show a confirmation UI.

### H-3 Supabase auth not hardened
- **Files:** missing `supabase/config.toml`; `docs/SECURITY.md` requires it but
  nothing enforces it.
- **Scenario:** Supabase's built-in "forgot password" and email change are on
  by default. Someone with access to the user's email resets the Supabase
  password and logs in. They cannot decrypt anything, but through H-2 they can
  delete the vault on every device and replace the header (a DoS for new
  devices).
- **Fix:** commit a `config.toml` that disables password recovery, email
  change and anonymous sign-ins, sets a minimum password length of 40
  (auth secrets are 43 characters), enables email confirmation, and enables
  CAPTCHA and rate limits. Route all recovery through the `recover` function.
  With H-2 fixed, this attack drops to a DoS.

## Medium

### M-1 Replayed old ciphertext is accepted
- **File:** `lib/services/sync/sync_service.dart` (`applyRemote`)
- **Scenario:** the server re-serves an old (valid) ciphertext under a higher
  revision. A device with no local edits accepts it, so a changed password
  is rolled back to the old one, possibly a known or leaked one.
- **Evidence:** "M-1" (`v1` restored over `v2`); `sync_test.dart` replay test.
- **Fix:** add a monotonically increasing `version` inside the ciphertext.
  Reject a remote copy whose version is ≤ the local version, and remember the
  highest version seen per id (including for deleted ids).

### M-2 API roles can `setval` the shared sequence and `TRUNCATE` items
- **File:** `supabase/migrations/20261005000000_vaultsnap.sql`
- **Scenario:** Supabase's default grants give `anon` and `authenticated`
  `UPDATE` on `vault_items_seq` and `TRUNCATE` on `vault_items`. Neither is
  subject to RLS. Verified as `authenticated`:
  `setval('vault_items_seq', 1)` makes Bob's next change get a sequence number
  below his devices' cursors, so it is never pulled. Setting the sequence to
  its maximum makes every user's `push_item` fail. `TRUNCATE` would wipe all
  tenants. Neither is reachable through PostgREST today, because pg_catalog
  functions and TRUNCATE are not exposed. Any future SQL surface would make
  both exploitable.
- **Evidence:** `run_rls_tests.sh` S1/S2 FAIL; grant query output in the audit
  log.
- **Fix:** `revoke all on sequence vault_items_seq from anon, authenticated;`,
  then `grant usage` only (enough for `nextval`).
  `revoke truncate, references, trigger on vault_items from anon, authenticated;`.
  Better still, assign `seq` inside a `security definer` function.

### M-3 No upper bound on KDF parameters
- **Files:** `lib/core/crypto/kdf_params.dart`; used by `prelogin`, the header
  and `import_export.dart`
- **Scenario:** only a floor is enforced. A malicious server (via prelogin) or
  a crafted backup file can set `ops=2^30` (hours of CPU) or `mem=4 TiB`
  (immediate OOM-kill on a phone), so the app becomes unusable.
- **Evidence:** "M-3".
- **Fix:** enforce a ceiling (e.g. `ops ≤ 10`, `mem ≤ 1 GiB`), and check
  available memory before deriving.

### M-4 zxcvbn hangs on long input
- **File:** `lib/services/password_generator.dart` (`StrengthMeter`), called on
  every keystroke and over all entries on the dashboard
- **Scenario:** `zxcvbn` 1.0.0 (2021) did not finish on a 256-character
  password within 90 s. It runs synchronously on the UI thread. One long
  password, pasted or imported via CSV, freezes the editor; the dashboard
  freezes whenever it is opened.
- **Evidence:** "M-4" (killed after 10 s); manual probe (> 90 s).
- **Fix:** evaluate only the first 100 characters (as zxcvbn-ts does) and run
  in an isolate with a timeout. Consider a maintained port.

### M-5 Master-password policy too weak for an offline attack
- **Files:** `lib/ui/setup_screen.dart`, `lib/ui/settings_screen.dart`,
  `lib/ui/recovery_reset_screen.dart`
- **Scenario:** score 3 means an estimated 10^8–10^10 guesses
  (`Summer2024!` = 2.8 × 10^7). Argon2id measured **~90 ms per guess**
  (≈ 11 guesses/s per CPU core). A GPU rig at roughly 10^3–10^4 guesses/s
  exhausts 10^8 in hours. The offline oracle is available to anyone who
  gets the auth secret (the server sees it at every login) or the header
  (server, iCloud backup, see M-9).
- **Fix:** require score 4 and ≥ 14 characters, or a generated passphrase of
  5+ words. Consider raising `mem` to 256 MiB on desktop, with parameters
  stored per header.

### M-6 Plaintext temp copies persist
- **Files:** `lib/ui/settings_screen.dart` (`_import`),
  `lib/ui/ocr/ocr_import_screen.dart`, `MainActivity.kt`
- **Scenario:** `file_picker` copies the picked file to
  `cache/file_picker/<ts>/`. A Chrome or Bitwarden CSV, containing every
  password in plain text, stays there indefinitely because
  `FilePicker.clearTemporaryFiles()` is never called. OCR copies
  (`cache/ocr-*.img`) are left behind if the process dies mid-OCR, and
  nothing cleans them up at startup.
- **Fix:** call `clearTemporaryFiles()` in a `finally` block, read the
  content URI as a stream instead of copying, and delete `ocr-*` and
  `file_picker/` at startup.

### M-7 Vault key never rotates
- **File:** `lib/core/crypto/key_hierarchy.dart` (`changePassword`), recovery
  reset
- **Scenario:** a password change re-wraps the same vault key. Anyone who ever
  obtained it can decrypt all future server ciphertexts: an old header plus the
  old password, the biometric wrap and KEK, or the iOS snapshot key.
- **Fix:** add a "rotate vault key" operation that re-encrypts every entry and
  re-wraps for password, recovery and biometrics. Run it automatically after a
  recovery reset and offer it after a password change.

### M-8 iOS AutoFill snapshot without opt-in
- **Files:** `lib/main.dart`, `lib/services/ios_autofill_snapshot.dart`
- **Scenario:** on iOS, every unlock or edit writes a copy of all passwords,
  encrypted under a key that Face ID alone releases. This happens even if
  the user never enabled biometrics. Wiping the vault or disabling
  biometrics does not remove it. All usernames and hosts also go to the
  OS credential identity store.
- **Fix:** create the snapshot only when AutoFill and biometrics are enabled.
  Call `clear()` from `wipeLocalVault`, from biometric disable, and on recovery
  reset.

### M-9 Vault material leaves the device through OS backup / roaming
- **Files:** `lib/main.dart` (directory choice)
- **Scenario:** on iOS, Application Support is included in iCloud backups
  (DB, header and biometric wrap). On Windows, `getApplicationSupportDirectory`
  is **Roaming** AppData, which syncs to domain servers. For local-only users
  this hands the M-5 offline-attack material to third parties.
- **Fix:** set `NSURLIsExcludedFromBackupKey` on the vault directory, and use
  `getApplicationCacheDirectory`-style LocalAppData on Windows.

### M-10 Android autofill trusts browser package names
- **File:** `android/.../HisnAutofillService.kt` (`TRUSTED_BROWSERS`)
- **Scenario:** `webDomain` is trusted if the requesting package name is on the
  list. If Brave isn't installed, a sideloaded app named `com.brave.browser`
  can claim `webDomain = bank.com` and be offered the bank entry.
- **Fix:** verify signing-certificate SHA-256 digests via
  `PackageManager.GET_SIGNING_CERTIFICATES` against pinned values (as
  Bitwarden and KeePassDX do).

### M-11 Background auto-lock breaks system pickers
- **File:** `lib/app.dart` (`didChangeAppLifecycleState`)
- **Scenario:** opening the image, file or save picker sends the app to
  `paused`, which locks the vault (the default). On return, the OCR, import or
  export flow fails (`StateError: Vault is locked`). Users will switch off
  lock-on-background.
- **Fix:** set a short (≤ 2 min) "expected background" grace period while a
  picker started by the app is open, and finish the operation before locking.

### M-12 Recovery function: sessions survive, dependency unpinned
- **File:** `supabase/functions/recover/index.ts`
- **Scenario:** `admin.auth.admin.signOut(userId, …)` expects a **JWT**, not a
  user id. The error is swallowed, so a thief's refresh token keeps working
  after the victim's recovery reset. The import `jsr:@supabase/supabase-js@2`
  is unpinned. A user-not-found response returns faster than a hash
  comparison (minor timing oracle).
- **Fix:** revoke sessions by deleting the user's `auth.sessions` and refresh
  tokens via the service role (or ban and unban). Pin an exact version and a
  lockfile. Make the response time uniform.

### M-13 Secrets in unwipeable Dart Strings
- **Files:** `lib/data/db/database.dart` (DB key as hex String captured by
  the isolate closure), `biometric_unlock.dart` (KEK base64), `vault_crypto.dart`
  (`serverAuthSecret`), all decrypted `VaultEntry` fields, the master password
  in `TextEditingController`
- **Scenario:** lock frees and zeroes all `SecureKey`s (verified), but these
  copies stay in the heap until the GC reuses that memory. A memory dump
  after lock (forensics, malware, or a crash dump) can recover them.
- **Fix:** keep the DB key as bytes (use `sqlite3_key` via FFI with a
  sodium-allocated buffer). Decrypt the password and notes on demand
  instead of caching the whole vault. Document the remaining limits of Dart.

### M-14 Export password has no policy
- **File:** `lib/ui/settings_screen.dart` (`_export`)
- **Scenario:** a backup protected with export password `1` is broken
  instantly if the file is emailed or uploaded to cloud storage.
- **Fix:** apply the master-password policy, or default to a generated 6-word
  passphrase.

## Low

| ID | File | Issue → fix |
|---|---|---|
| L-1 | `unlock_throttle.dart` | Throttle state is a plain file. Deleting it resets the back-off ("L-1" test) → store it in Keystore/Keychain/DPAPI and treat a missing file as maximum delay |
| L-2 | `ui/widgets/secret_text.dart` | `SelectableText` lets users copy passwords with the system menu, bypassing sensitive flags and auto-clear → disable selection for secrets |
| L-3 | `clipboard_service.dart` | If the app is killed before 30 s, the clipboard is never cleared (Android/Windows) → clear on next launch; Android: schedule a clear in a native job |
| L-4 | `ios/Runner/AppDelegate.swift` | `isCaptured` is only checked on change, not at launch; the app-switcher cover depends on a Flutter frame → check at launch; add a native overlay in `sceneWillResignActive` |
| L-5 | `sync_service.dart` | `MassDeletionException` has no UI. Sync silently stays in error; the debounced call is `unawaited` → surface it with a confirmation dialog |
| L-6 | `vault_session.dart` | Undecryptable (tampered) entries are skipped silently → show an integrity warning |
| L-7 | migration `prelogin` | Unauthenticated, no rate limit, scans `auth.users`; returns the real salt and KDF params for any registered email → rate-limit at the edge; index on email |
| L-8 | `sync_service.onPasswordReset` | Changing the password while signed out leaves the old auth secret valid on the server; other devices keep the old header → retry on next sign-in; push a "password changed" marker |
| L-9 | entry edit / notes fields | Keyboard learning is not disabled for username/notes → `enableIMEPersonalizedLearning: false` |
| L-10 | `settings.dart`, `database.g.dart` | Sync email is stored in plaintext JSON; `KvStoreData.toString()` would print the refresh token if ever logged |
| L-11 | `ocr_import_screen.dart` | "Delete source image" silently does nothing for shared images and on iOS → explain to the user, or use PHPicker with the asset id |
| L-12 | ML Kit | The model is bundled and images stay on device, but ML Kit sends usage metrics to Google → disclose in the privacy policy |
| L-13 | `sync_service.dart` | LWW uses the client clock inside the ciphertext. A device with a future clock always wins (losers do go to history) |

## Info: functional gaps found while auditing

- **I-1** On Windows, `biometric_storage` returns `errorHwUnavailable`, so
  Windows Hello unlock is unavailable (the requirement isn't met).
- **I-2** The `recover` edge function has no client UI. Server-side recovery
  for new devices is unreachable.
- **I-3** iOS share-to-app needs a Share Extension, and the AutoFill extension
  needs Xcode target setup (see `ios/AutoFillExtension/README.md`).
- **I-4** Android autofill for native apps requires `androidapp://` URLs, and
  no UI creates them.
- **I-5** With Supabase email confirmation on, `enableSync` crashes
  (`currentUser!` is null before confirmation).
- **I-6** Kotlin, Swift and C++ code was reviewed but not compiled here (no
  SDKs available).

## Verified as working

- **Zero-knowledge:** in the full recorded flow, the server received only:
  email, the auth secret (a BLAKE2b subkey, 43 characters), salt and KDF
  params, wrapped keys, `sha256(recovery auth)`, ciphertexts and ids.
  None of 25 secret encodings appeared in any request: the master password,
  vault/entry/DB keys (hex, b64, b64url), the recovery key, entry plaintext,
  or the TOTP secret.
- **HIBP:** only the 5-character SHA-1 prefix is sent, with `Add-Padding`.
- **AEAD:** every single-bit flip is detected. Cross-entry swaps and
  cross-purpose unwraps are rejected. Nonces are unique across 200 seals.
- **RLS:** read, update, insert-with-forged-owner, owner change, revision
  forging, header takeover, recovery-hash read, private schema access and
  anon access were all blocked (33/35 checks).
- **Imports:** 2,000 fuzzed CSVs, a 100k-column and a 50k-row CSV, truncated,
  bit-flipped, deeply nested (100k) and wrong-format backups all failed
  safely. Bidi and control characters are stripped and `javascript:` URLs
  dropped.
- **Logs:** no secrets are logged (3 type-only debug prints, silenced in
  release). There are no analytics or crash SDKs and no native logging.
- **Android:** `allowBackup=false` plus exclusion rules; `FLAG_SECURE` on both
  activities.
- **Dependencies:** OSV found 0 known vulnerabilities in 188 pub packages.
  *Caveat:* OSV holds only 13 Pub advisories in total, so this is weak
  assurance. The 3 advisories touching packages we use (`http`, `archive`,
  `shared_preferences_android`) do not affect the resolved versions. Native:
  libsodium 1.0.22, SQLCipher 4.19.0 with OpenSSL 4.0.3 (29 Sep 2026), ML Kit
  text-recognition 16.0.1 (bundled model). Stale: `zxcvbn` 1.0.0 (2021,
  see M-4), `biometric_storage` 5.0.1 (2024), `hotkey_manager` 0.2.3 (2024).
