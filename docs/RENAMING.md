# Renaming the app

The app is currently called "VaultSnap" while the owner decides on the final name.
`tool/rename_app.py` changes the name everywhere in one go, and can also change the
technical identifiers (Dart package, Android application id, iOS bundle id, ...).
It uses only the Python 3.9+ standard library.

```sh
git status                                   # the tool wants a clean tree: commit first
python3 tool/rename_app.py --name "Hisn" --dry-run          # list every file it would touch
python3 tool/rename_app.py --name "Hisn"                    # display name only
python3 tool/rename_app.py --name "Hisn" --ids              # display name + technical ids
flutter pub get && flutter analyze && flutter test --exclude-tags finding
git diff                                     # review; build on CI before shipping
```

Arabic name for the Arabic UI, and an ASCII slug (required when `--name` is not ASCII):

```sh
python3 tool/rename_app.py --name "Hisn" --name-ar "حصن" --slug hisn --ids
```

## Which kind of rename do I want?

| | `--name` only | `--name ... --ids` |
|---|---|---|
| App name in the UI, launcher, window title, notifications | yes | yes |
| Existing installs keep working as the *same* app, same data | Android/iOS: yes. Windows: **no**, see "Windows" below | **no**, it becomes a different app on every platform |
| Needs new store/Apple-developer entries | no | iOS: yes (App ID, App Group, Keychain group) |

While nobody but the owner has installed the app, `--ids` is the right choice: the
earlier it is done the cheaper it is. Once real users exist, use `--name` only.

## What `--name` changes

| Where | What |
|---|---|
| `lib/brand.dart` | `const String appName = '...';` (and `appNameAr` if the file declares it). If the file does not exist yet the tool says so and skips it; run the same command again later, it is idempotent |
| `lib/l10n/app_*.arb` | `appTitle` (`--name-ar` for `app_ar.arb`) and every other string that contains the old name; then `flutter gen-l10n` regenerates `lib/l10n/*.dart` (if flutter is not found the generated files are patched textually instead) |
| `android/app/src/main/AndroidManifest.xml` | `android:label` of the application and the autofill service (also `res/values*/strings.xml` `app_name` if a label ever points there) |
| `ios/Runner/Info.plist` | `CFBundleDisplayName`, `CFBundleName` |
| `windows/runner/main.cpp` | window title (non-ASCII names are written as `\uXXXX` so the file's code page does not matter) |
| `windows/runner/Runner.rc` | `ProductName`, `FileDescription`, `InternalName` (= slug). Non-ASCII names fall back to the ASCII slug in the version-info block |
| Kotlin / Swift / Dart strings | "Unlock <name>" prompts, clipboard label, Windows Hello prompts, import error message, `User-Agent` header (always the ASCII name: HTTP header values must be Latin-1) |
| `lib/ui/settings_screen.dart` | suggested backup file name `<slug>-backup.vsnap` (the `.vsnap` extension is a format tag and stays) |
| `.github/workflows/*.yml` | artifact names (`<Name>-android-apk`, ... spaces become `-`, non-ASCII falls back to the slug) |
| `README.md`, `docs/*.md`, code comments, test names/expectations | the old name in prose, e.g. the `not even the <name> developer` text that `test/ui/unlock_reset_test.dart` looks for |
| `--description "..."` | optionally `description:` in `pubspec.yaml` |

Only the whole word is replaced (`VaultSnap` becomes `Hisn`, but `VaultSnapApp` is left
alone unless `--ids` is given).

## What `--ids` adds

| Where | What |
|---|---|
| Dart package | `name:` in `pubspec.yaml` and every `package:<old>/` import in `lib/`, `test/` and other Dart files |
| Class names | the `<Old>` prefix of `<Old>App`, `<Old>AutofillService`, `Register<Old>Channel`, `k<Old>RunOnPlatformThread` ... in Dart, Kotlin, Swift, C++ and the manifest together; files that carry it are renamed too (`VaultSnapAutofillService.kt` becomes `HisnAutofillService.kt`) |
| Android | `applicationId` and `namespace` in `android/app/build.gradle.kts`, the `package` lines, the Kotlin source directory (`kotlin/app/vaultsnap/vaultsnap` moves to `kotlin/<new id as path>`), `taskAffinity`, the intent-extra keys |
| iOS | `PRODUCT_BUNDLE_IDENTIFIER` (also `.RunnerTests`) in `project.pbxproj`, app group `group.<id>`, keychain group `<org>.shared` in both entitlements, both `Info.plist` files and `AppDelegate.swift`, the extension notes in `ios/AutoFillExtension/README.md` |
| Windows | `project(...)` and `BINARY_NAME` in `windows/CMakeLists.txt` (so the executable is `<slug>.exe`), `CompanyName`, `OriginalFilename`, `LegalCopyright` in `Runner.rc`, the `%TEMP%\<slug>-clip-*` file prefix (C++ and `docs/SECURITY.md` together) |
| `--channels` (optional) | the MethodChannel names `<org>/platform` and `<org>/autofill`, on the Dart, Kotlin, Swift and C++ side at once. Off by default: they are invisible to users and the three native sides are compiled only on CI, so there is no reason to touch them |

The application id defaults to `app.<slug>.<slug>` (underscores dropped, iOS rejects
them). `--app-id com.example.hisn` overrides it. `<org>` is the id without its last
segment (`app.hisn`).

## What is never renamed, on purpose

These strings contain the old slug but are part of a persisted or wire format.
Changing them would make existing vaults, backups or biometric wraps unreadable. The
tool masks them while renaming and lists them afterwards as "kept on purpose".

| String | Where | Why it stays |
|---|---|---|
| `vaultsnap/v<N>/<context>` | `lib/core/crypto/vault_crypto.dart`, `docs/SECURITY.md`, `tool/gen_crypto_vectors.py`, iOS `CredentialProviderViewController.swift` (`.../autofill-snapshot`) | associated data of **every** ciphertext and of the iOS autofill snapshot; a different value fails authentication on all existing data |
| `VSnapKEK`, `VSnapAUT`, `VSnapENT`, `VSnapDB_`, `VSnapRCV`, `VSnapEXP` | `lib/core/crypto/`, `lib/services/import_export.dart` | BLAKE2b key-derivation contexts; same reason (and they do not contain the word VaultSnap) |
| `"format": "vaultsnap-export"` | `lib/services/import_export.dart` | tag inside backup files; old backups would no longer import |
| `.vsnap` | file extension of backups | same |
| `vaultsnap_bio_kek` | `lib/services/biometric_unlock.dart` | secure-storage key of the biometric wrap; renaming silently drops it and forces re-enrolment |
| `VSKeychainGroup` | Info.plists, `AppDelegate.swift` | internal Info.plist key (its *value* is renamed) |
| `app.vaultsnap/platform`, `app.vaultsnap/autofill` | Dart, Kotlin, Swift, C++, tests | MethodChannel names, unless `--channels` |
| `supabase/` | migration `20261005000000_vaultsnap.sql`, `supabase/tests/run_rls_tests.sh` | migration history is keyed on the file name; never edited |
| `Follow @vaultsnap` | `test/services/ocr_parser_test.dart` | arbitrary sample text |

Git-ignored IDE files (`.idea/`, `vaultsnap.iml`, `android/vaultsnap_android.iml`) are
not touched; delete them and let the IDE recreate them.

## Safety

* **Idempotent.** The tool finds the current names itself (`lib/brand.dart`, `appTitle`
  in the `.arb` files, `pubspec.yaml`, `build.gradle.kts`, `lib/app.dart`) and only
  rewrites what differs. Running the same command twice prints "Nothing to do". You can
  rename again later (`Hisn` to `Foo`): the slug-based format strings above stay, as
  they must.
* **Refuses a dirty tree** (any uncommitted change in a git checkout) so that the rename
  is one reviewable diff, and refuses an **unknown state** (no `appTitle`, `namespace`
  and `applicationId` that differ, Kotlin sources not in the folder the id says, no
  `<Prefix>App` class, two different Latin names in `brand.dart` and the `.arb` files).
  `--force` overrides both. `--dry-run` never refuses, it only warns.
* A copy without `.git` (for example the scratch copy used for testing) is allowed with a
  warning: there is nothing to check and nothing to undo with.
* All edits are computed in memory first and then written; if a write fails the files
  already written (and moved) are restored.
* Names may contain letters of any script, digits, space, `-`, `_` and `.` (max. 30
  characters). Quotes, `$`, `&`, `<`, `>`, backslash and braces are rejected, because they
  would need different escaping in Dart, Kotlin, XML, JSON/ICU and C++.
* Exit codes: 0 done/nothing to do, 1 bad arguments, 2 refused, 3 `--strict` and an
  unexpected leftover, 4 `flutter gen-l10n` failed (the rename itself is complete).

Other options: `--diff` (print unified diffs), `--strict`, `--root DIR`,
`--flutter PATH`, `--skip-gen-l10n`, `--no-format` (by default `dart format` runs on the
Dart files that were edited, because a new name changes line lengths).

## Caveats: what happens to existing data

* **Android, `--ids`:** a new `applicationId` is a different app. It installs next to the
  old one with an empty vault; the old app and its data stay until uninstalled, there is
  no upgrade path. Export a `.vsnap` backup first (it imports fine, the format does not
  change) or sign in again if sync is on. Biometric unlock has to be enabled again.
* **iOS, `--ids`:** create the new App ID, App Group `group.<id>`, Keychain sharing group
  `<org>.shared` and the extension's App ID (`<id>.autofill`) in the Apple developer
  portal and regenerate provisioning. The data container is new, so the same advice as
  for Android applies. The extension target itself is still added by hand in Xcode, see
  `ios/AutoFillExtension/README.md` (its ids are updated by the tool).
* **Windows (even without `--ids`):** `path_provider` stores the vault in
  `%APPDATA%\<CompanyName>\<ProductName>\vault`, taken from `Runner.rc`. A plain
  `--name` changes `ProductName`, `--ids` also changes `CompanyName`, so a build made after
  the rename will not find a vault created before it (it offers to create a new one; the
  old folder is not deleted). Either move the folder, for example
  `%APPDATA%\app.vaultsnap\vaultsnap` to `%APPDATA%\app.hisn\Hisn`, or pass
  `--keep-data-dir` to leave `CompanyName` and `ProductName` as they are (the visible
  file description and window title still change).
* The old CI artifact names stop being produced; anything that downloads them by name
  must be updated. Repository name, store listings, domains and the Supabase project name
  are outside the repository and are not touched. The generated icons contain no text
  (`tool/gen_icons.py`), so they do not depend on the name.
* Arabic and other non-ASCII names: `--slug` is required. The Windows version-info block
  (it declares code page 1252) falls back to the slug, the window title in `main.cpp` is
  written with `\u` escapes, CI artifacts and the `User-Agent` header use the ASCII
  name/slug. The old Latin name inside Arabic sentences becomes `--name-ar`.

## How it was tested

Done on scratch copies of the repository (never on the working tree), repeated
whenever the tool changed:

1. `git archive HEAD`, and a copy of the working tree (including other people's
   uncommitted theme work) without `build/`, `.dart_tool/` and `.git`.
2. `python3 tool/rename_app.py --name Hisn --ids`, then in the copy
   `flutter pub get`, `flutter gen-l10n`, `flutter analyze` (no issues) and
   `flutter test --exclude-tags finding` (all 280 tests pass on both copies; no test
   file needed a manual change, the tool rewrites the imports and the one asserted UI
   text itself).
3. A second chained rename on the result (`--name "Foo Bar" --app-id com.omar.foobar
   --ids --channels --keep-data-dir`), an Arabic-only name with `--slug`, a display-only
   run, a run where `lib/brand.dart` appears after the first run, refusal on a dirty git
   tree and on a broken `.arb`, `--force`, and a simulated disk-full failure in the middle
   of writing (all files and directories restored byte for byte).
4. `grep -rIni vaultsnap` on the renamed copy: only the "kept on purpose" strings above,
   `supabase/`, and the MethodChannel names (when `--channels` is not used).

The native files (Kotlin, Swift, C++, `.rc`, `.pbxproj`) cannot be compiled locally;
they are compiled by GitHub Actions. The edits there are plain string and identifier
replacements, but push the renamed branch and wait for the Android, Windows and iOS jobs
before relying on it.
