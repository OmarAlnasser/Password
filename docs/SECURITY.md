# VaultSnap security design

Status: Phase 1 (crypto layer) is implemented in `lib/core/crypto/`.
Later phases must keep to the rules in this document.

## Key hierarchy

```
master password ─NFKC─► Argon2id(16 B salt, t=3, m=64 MiB, p=1) ─► master key (never stored)
    master key ─BLAKE2b ctx "VSnapKEK"─► password KEK ── wraps ──┐
    master key ─BLAKE2b ctx "VSnapAUT"─► server auth secret      │
                                                                 ▼
  recovery key (256-bit random) ─"VSnapRCV"#1─► recovery KEK ─► vault key (random 256-bit)
                                ─"VSnapRCV"#2─► recovery auth secret      │
                                                    ┌─────────────────────┤
                                     "VSnapENT" ◄───┘          "VSnapDB_" ▼
                                     entry key                  SQLCipher key
```

Ciphertext envelope (every blob): `0x01 ‖ nonce(24) ‖ XChaCha20-Poly1305(ct ‖ tag16)`,
with associated data `"vaultsnap/v1/<context>"`, where context is `entry/<uuid>`,
`wrap/masterPassword`, `wrap/recoveryKey`, `wrap/biometric` or `wrap/export`.

## Decisions and reasons

| Decision | Reason |
|---|---|
| Argon2id, 64 MiB, t=3, parameters stored with the salt | Memory-hard, which makes GPU/ASIC guessing expensive. Storing the parameters lets us raise them later without a migration. |
| Client refuses KDF parameters below 64 MiB / t=3 | On a new device the salt and parameters come from the server. A hostile server could otherwise send weak parameters so that the auth secret it receives is cheap to brute-force. |
| NFKC-normalise the password before hashing | Different Arabic keyboards and IMEs, or full-width digits, can encode the same visible password as different code points. Without normalisation the user would be locked out on another device. |
| Split the master key with BLAKE2b `crypto_kdf` into a KEK and an auth key | The server only ever sees the auth key, which is a one-way derivation. Knowing it gives nothing toward the KEK. |
| Random vault key wrapped by the KEK, instead of encrypting with the password-derived key | Changing the password or adding the recovery key or biometrics means re-wrapping 32 bytes, not re-encrypting every entry. |
| XChaCha20-Poly1305 with a random 192-bit nonce on every encryption | Random nonces are safe at this size (no counter state to sync between devices). The AEAD detects any modification. |
| Entry id and purpose bound into the associated data | The server cannot swap two entries' ciphertexts, replay an entry under another id, or pass an entry blob off as a wrapped key. |
| Padding plaintext to 128-byte blocks (`sodium_pad`) | Ciphertext size no longer reveals exact password or notes lengths. |
| Keys live only in libsodium `SecureKey`s | `sodium_malloc` memory is mlock'ed and guard-paged, and `sodium_free` zeroes it. `Keyring.lock()` frees every key. |
| Argon2 runs in a background isolate, and the result is passed back as a transferable `SecureKey` | The UI does not freeze, and the key never becomes a Dart `List`. |
| Recovery key = 256 random bits, Crockford Base32 plus a 16-bit checksum | It needs no stretching because it can't be guessed. Crockford drops I/L/O/U, and the parser maps O→0 and I/L→1. The checksum catches typos before a slow unlock attempt. |
| Constant, generic exception messages | Exceptions reach logs and crash reports, so they must never carry secrets. |
| HMAC for TOTP from `package:crypto` | libsodium has no HMAC-SHA1, which most TOTP issuers still use. HMAC-SHA1 is still a secure PRF. |
| `package:sodium` instead of `sodium_libs` | `sodium_libs` 4.x is deprecated and just re-exports `sodium`. `sodium` now compiles the libsodium 1.0.22 source bundled with the package (minisign-signed archive) via a build hook on every platform. We use the "sumo" build because Argon2 `crypto_pwhash` is only exposed there. |

## Known weaknesses and how we handle them

1. **Weak master password plus a hostile server.** Supabase receives the auth
   secret at every login. A server-side attacker can run Argon2id guesses
   against it offline. That costs 64 MiB per guess but is still feasible for
   weak passwords. *Mitigation:* enforce zxcvbn score ≥ 3 at signup
   (phase 2). This weakness is inherent to every password-based
   zero-knowledge design.
2. **Fetching the salt before login exposes data.** To log in on a new
   device the client must fetch the salt and KDF parameters for an email
   before authenticating. That allows email enumeration and lets an attacker
   precompute guesses. *Mitigation (phase 4):* a `prelogin` RPC that returns
   a deterministic fake salt, `HMAC(server_secret, email)`, for unknown
   emails, and is rate-limited.
3. **Dart cannot wipe Strings.** Keys are wiped, but the master password from
   the `TextField` and decrypted fields shown in the UI are immutable Dart
   `String`s that stay in memory until the GC reuses that memory. "Wipe keys
   on lock" therefore holds for keys, not for every plaintext. *Mitigation:*
   decrypt entries only on demand, never cache a decrypted vault, clear
   controllers on lock, and use FLAG_SECURE.
4. **Supabase email password reset would let an attacker delete the vault.**
   Whoever controls the user's email could reset the Supabase password and
   then delete or replace the encrypted rows. They still cannot decrypt
   them. *Mitigation (phase 4):* disable the built-in reset. Recovery goes
   through the recovery auth secret instead. Local data stays authoritative
   until sync detects a mass deletion.
5. **Last-write-wins on client clocks.** A device with a wrong clock can
   overwrite newer edits. *Mitigation (phase 4):* the server assigns
   `updated_at` and a revision counter. Clients send the revision they
   edited, and the losing version always goes to password history, so
   nothing is lost silently.
6. **The server can roll back data or withhold rows.** The AEAD stops
   tampering and swapping, but a server can serve an older valid ciphertext
   or omit an entry. *Mitigation (phase 4):* the revision number goes into the
   associated data, and the client remembers the highest revision it has
   seen per entry. Protecting the vault as a whole against omission would
   need a signed manifest, which is out of scope for now.
7. **Metadata is visible to the server.** It can see the number of entries,
   padded sizes, edit times and deletions (tombstones). Titles, URLs and tags
   are inside the ciphertext.
8. **Biometric unlock trades security for convenience.** The vault key is
   wrapped by a hardware-backed key on Android (StrongBox/TEE, user
   authentication required) and iOS (Secure Enclave, `.biometryCurrentSet`).
   On Windows, **DPAPI only protects against other OS users. Any malware
   running as the same user can unwrap it.** *Mitigation (phase 5):* use
   Windows Hello (`KeyCredentialManager`) to sign a challenge from which the
   wrap key is derived, falling back to "password only" on Windows.
9. **The iOS AutoFill extension has a memory limit of about 120 MB.** Running
   Argon2 with 64 MiB inside the Flutter engine probably won't fit. The
   extension must be native Swift and unlock via the Keychain-shared
   biometric wrap only.
10. **Android autofill can be phished.** A malicious app can claim any web
    domain. *Mitigation (phase 5):* match on package name plus signing
    certificate, and verify web domains through Digital Asset Links.
11. **Screenshots used for OCR import may already be in a cloud backup.** The
    app can delete the local image, but Google Photos or iCloud may already
    have uploaded it. On Android 11+ deleting a media item needs a system
    confirmation. The UI will warn about this.
12. **Clipboard.** Clipboard managers, Gboard, Windows Clipboard History and
    cloud sync can capture copied secrets. *Mitigation (phase 2):* mark the
    clip `IS_SENSITIVE` on Android 13+, use
    `ExcludeClipboardContentFromMonitorProcessing` on Windows, and on iOS set
    `localOnly` and an expiry. Auto-clear only wipes if the clipboard still
    holds our value.
13. **The screen-capture block isn't available on every platform.**
    FLAG_SECURE works on Android. On Windows we use
    `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)`. iOS has no real
    block: we can only blur in the app switcher and hide content while
    `UIScreen.isCaptured` is true.
14. **The unlock rate limit doesn't stop an offline attacker.** Someone who
    copies the app's files can skip the UI delays. Argon2's cost is the real
    barrier. The rate limit counter is still kept in secure storage, so an
    app restart doesn't reset it.
15. **Dependency risk.** `sqlcipher_flutter_libs` is now marked end-of-life on
    pub.dev. Phase 2 will use the replacement recommended by drift (SQLCipher
    via the `sqlite3` package's build hooks) and pin it.
16. **The recovery key is as powerful as the master password.** Anyone who
    has it gets full access. It is shown once, with copy, print and confirm
    steps, and can be rotated (`AccountKeys.rotateRecoveryKey`).
17. **Website icons tell the network which sites are in the vault.**
    "Fetch website icons" is on by default. After every unlock, save and
    import the app requests each entry's site directly (its page, then the
    icon). DNS resolvers, anyone watching the network and each site learn
    that this user has an account there and roughly when the vault is
    unlocked; each site sees the user's IP address. No third-party icon
    service is used, so no single party learns the whole list.
    *Mitigation:* HTTPS only; the page, every redirect and the icon must stay
    on the entry's registrable domain; no cookies, no Referer, a generic
    User-Agent; size limits. Hosts come from imports and are untrusted: IP
    literals, single-label and local names, and names that resolve to
    loopback, private or link-local addresses are skipped. The HTTP client
    resolves the name again when it connects, so DNS rebinding can still
    send a TLS handshake to a local address; certificate checks stop it
    there, leaving a probe of whether port 443 answers. Icons are stored
    only in the SQLCipher database (fetched again after 30 days, failures
    after 7) and in memory while unlocked. Turning the setting off stops all
    requests; icons already stored are still shown.
18. **Screenshots are written to temporary files in plaintext.** OCR needs
    the image as a file, in three places:
    * *The pasted screenshot.* The native side copies it to the app's cache:
      Android `cacheDir/clip-*.img` (and `ocr-*.img` for the OCR import), iOS
      `tmp/clip-*.png` with complete file protection, Windows
      `%TEMP%\vaultsnap-clip-*`. On Windows an image file copied in
      Explorer is copied the same way (local drives only, at most 16 MB, the
      original is only read, and the copy is made after the clipboard is
      closed again so a slow drive cannot hold it up).
    * *The scanner's copies.* A small or dark screenshot is read again
      enlarged, inverted or with more contrast, and a very large one in tiles.
      Those copies are PNG files in `<temp>/vaultsnap-ocr/s-*/` (Android app
      cache, iOS `tmp`, Windows `%TEMP%`), without file protection on iOS.
      Each is deleted when its pass ends and the folder when the scan ends. A
      file an engine still holds (Windows) is deleted when it lets go.
    * *What was read.* The recognised lines are kept in memory, shown (in plain
      text, only when the user opens "What was read") and never logged or
      stored.

    On Windows `%TEMP%` can be read by other programs of the same user.
    Dart deletes the pasted copy as soon as OCR has finished, whether it found
    anything or not, and the scan stops when the screen is left or the vault
    locks. If the app dies in between, the next start deletes pasted copies
    and scanner folders older than 10 minutes (Android, iOS and Windows each
    sweep the pasted copies natively; the scanner folders are swept by Dart at
    start-up, and again by every scan once they are 15 minutes old).
    Recognition and parsing run on the device only. Clipboard text can come
    from any app or website, so parsing reads at most 16 KB and skips runs of
    over 256 characters without whitespace. After a save the app offers to
    clear the clipboard (the default action); that does not remove copies a
    clipboard history (Windows + V, keyboard apps) or a cloud clipboard has
    already kept.
19. **The lock screen can erase the vault without a password.** "Forgot
    password?" offers a reset for users who lost both the master password
    and the recovery key, so anyone holding the locked, running app can
    destroy the local vault (after typing a confirmation word). They learn
    nothing from it. The reset signs out of sync and forgets the sync email,
    so a vault created afterwards cannot sync into the old account, and the
    old account's data on the server is untouched: signing in again with
    the old master password restores it.

## Test vectors

`test/core/crypto/` checks:
* libsodium's published vectors for XChaCha20-Poly1305 and `crypto_kdf`.
* Argon2id outputs from the PHC reference implementation (argon2-cffi) at
  VaultSnap's parameters.
* RFC 4648 Base32, RFC 4226 HOTP and RFC 6238 TOTP for SHA-1, SHA-256 and SHA-512.
* A **golden vault** (header, wrapped keys and an encrypted entry) produced
  by `tool/gen_crypto_vectors.py`. That script is an independent
  implementation: reference Argon2, hashlib BLAKE2b, and pyca
  ChaCha20-Poly1305 plus a hand-written HChaCha20. It shares no code with
  libsodium and pins the stored format.
