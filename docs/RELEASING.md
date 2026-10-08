# Releasing

How to publish a version that installed apps (Android and Windows) update to by
themselves. Everything is done by GitHub Actions
(`.github/workflows/release.yml`); you add three secrets once, then cut a
release with one `git tag` and one `git push`.

Read `docs/SECURITY.md` for the threat model. This file is the checklist.

## How it works, in one minute

```
git tag v0.2.0 && git push origin v0.2.0
        │
        ▼  .github/workflows/release.yml
  check     tag is strictly vX.Y.Z; analyze + tests; signing key matches the pinned one
  android   APK signed with the release keystore; fails unless it carries the
            pinned certificate (release/android_cert_sha256.txt) and the right versionCode
  windows   Windows build, zipped with the exe and dlls at the zip root
  sign      update.json (sizes, SHA-256, URLs, notes) signed with Ed25519
  publish   draft release → upload 4 files → publish   (the only job that can write)
  verify    downloads everything from the public URLs like an installed app would
```

The release holds exactly four files, with names that never contain the app
name (so a rename never touches the pipeline):

| File | What it is |
|---|---|
| `android.apk` | the app, signed with the stable release keystore |
| `windows-x64.zip` | the Windows app (files at the zip root) |
| `update.json` | the manifest: version, build number, notes, and for each package its URL, size and SHA-256 |
| `update.json.sig` | base64 Ed25519 signature over the exact bytes of `update.json` |

Installed apps fetch
`https://github.com/OmarAlnasser/Password/releases/latest/download/update.json`
and `update.json.sig`, check the signature against the public key that is
compiled into the app (`release/update_public_key.txt`), compare build numbers,
download the package for their platform, check its size and SHA-256 against the
**signed** manifest, and only then install:

* **Android:** the app hands the APK to the system installer; you tap Install.
  Android itself also refuses the update unless it is signed with the same key as
  the installed app.
* **Windows:** the app unpacks the zip next to itself, locks the vault, exits;
  a small script swaps the files and starts the new version.

Two independent keys protect Android users: the **manifest key** (Ed25519, the
app checks it) and the **Android keystore** (Android itself checks it), so
stealing one of them is not enough to push a malicious update. On Windows the
manifest key is the only check, which makes it the more critical of the two.

Builds from `build.yml` (every push) carry no version number, so they never
show or offer updates. Only release builds do.

## Before the first release

1. **Rename the app first** (`tool/rename_app.py`, see `docs/RENAMING.md`) if you
   are going to. The Windows updater only accepts a zip whose exe has the same
   file name as the running exe, and `--ids` changes the Android application id,
   which Android treats as a different app. A rename after people have installed
   the app means they have to install the new one by hand. Rename before anyone
   installs.
2. **The first release-signed build is installed by hand**, once:
   * Builds before the updater existed cannot update themselves.
   * A phone that has a build from `build.yml` (signed with a debug key) cannot be
     updated to the release-signed APK: Android refuses (different signature).
     Uninstall it first. **Uninstalling deletes the local vault on that phone**:
     export a backup or make sure sync has run first.
   * Windows: unzip `windows-x64.zip` into a folder your user can write to (for
     example under your user profile). Not `C:\Program Files`: the updater needs
     to write there and refuses otherwise.
3. Merge `release.yml` into the default branch. GitHub only shows the "Run
   workflow" button (for dry runs) for workflows that exist on the default branch.
   (At the time of writing the repository's default branch is
   `claude/phase-1-crypto` and there is no `main`. Either use that name wherever
   this file says "the release branch", or rename the branch in **Settings →
   Branches** first. Whatever you choose, tag a commit that is on it.)
4. **The repository must stay public.** Installed apps read
   `releases/latest/download/update.json` without logging in, and GitHub answers
   404 for that address when the repository is private. Every check then fails;
   an automatic check says nothing, "Check now" says it could not reach GitHub.
5. **Expect warnings on the very first install**, because the files are not
   signed by a publisher Windows or Google knows. They mostly go away for later
   updates, because the app installs those itself:
   * Android: the browser or Files app needs "Install unknown apps" switched on
     (Settings → Apps → Special access), and Play Protect may say "App blocked"
     or "Unknown developer": choose *Install anyway* / *More details*. The first
     in-app update asks for the same permission for the app itself.
   * Windows: Microsoft Defender SmartScreen says "Windows protected your PC" for
     the unsigned exe: *More info → Run anyway*. A zip downloaded in a browser is
     marked "from the internet": right-click the zip → Properties → tick
     **Unblock** before unzipping, or Explorer may block every file.

## One-time setup: the three secrets

GitHub → the repository → **Settings → Secrets and variables → Actions → New
repository secret**. Add these exactly (names are case sensitive). Once saved a
secret can never be read back, only replaced, so keep your own copy (see "Keys").

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | the release keystore file (PKCS12, alias `release`), base64 on one line |
| `ANDROID_KEYSTORE_PASSWORD` | its password (the key password is the same, as PKCS12 requires) |
| `UPDATE_SIGNING_KEY` | base64 of the raw 32-byte Ed25519 seed (44 characters ending in `=`) |

The private files were created outside the repository (a git-ignored
`.secrets/` folder on the machine that generated them) and are never committed.
The matching public parts are in the repository: `release/update_public_key.txt`
and `release/android_cert_sha256.txt`.

How to turn the keystore into one line of base64:

```sh
# Linux
base64 -w0 release.jks
# macOS
base64 -i release.jks | tr -d '\n'
```

```powershell
# Windows PowerShell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("release.jks"))
```

**Check the values before you paste them** (the workflow checks again, but this
is faster than a failed run):

```sh
# 1. The keystore: the SHA256 line must equal release/android_cert_sha256.txt
#    (same digits, colons or not). keytool asks for the password.
keytool -list -v -keystore release.jks -alias release | grep 'SHA256:'
cat release/android_cert_sha256.txt

# 2. The manifest key: must print "matches the pinned public key".
#    `read -rs` keeps the value out of your shell history.
read -rs UPDATE_SIGNING_KEY && export UPDATE_SIGNING_KEY
python3 tool/make_update_manifest.py --check-key --expect-public-key release/update_public_key.txt
unset UPDATE_SIGNING_KEY
```

On Windows PowerShell, for step 2: `$env:UPDATE_SIGNING_KEY = Read-Host "seed"`,
then the same `python tool/make_update_manifest.py ...` line, then
`Remove-Item Env:UPDATE_SIGNING_KEY`.

### Recommended repository settings

Anyone who can push a tag `v*` runs the release pipeline with the secrets, so
keep that group tiny.

* Turn on two-factor authentication for your GitHub account (a stolen account is
  the realistic attack on this design).
* **Settings → Rules → Rulesets → New tag ruleset**: target pattern `v*`, restrict
  creation, update and deletion to yourself. This also stops a published tag
  from ever being moved.
* Do not give write access to people you would not trust with the signing key.
* **Settings → Actions → General**: keep "Workflow permissions" on *Read
  repository contents*, and require approval for workflows from outside
  collaborators.

## Cutting a release

### 1. Pick the version

`MAJOR.MINOR.PATCH`, for example `0.2.0`; the tag is `v0.2.0`. The build number
the app compares is `MAJOR*1000000 + MINOR*1000 + PATCH` (so `0.2.0` is 2000 and
`1.10.3` is 1010003). Limits: MAJOR up to 2000, MINOR and PATCH up to 999, no
leading zeros, no `-rc1` suffixes. Every release must be higher than the last
one published; the workflow refuses anything else.

### 2. Release notes (optional)

The notes shown in the app and on the release page are, in this order:

1. `release/notes/0.2.0.md` if it exists (English, plain text, keep it short:
   at most 4,000 characters in total),
2. "Changes since v0.1.0" followed by the commit subjects since the previous
   release tag (at most 100). These are public, so write commit subjects you are
   happy to show.

`release/notes/0.2.0.ar.md` (optional) is the Arabic text shown to users whose
app is in Arabic. Commit the notes before tagging.

### 3. Dry run (recommended before a real release)

GitHub → **Actions → Release → Run workflow**:

* "Use workflow from": the release branch (see "Before the first release"), or
  the branch you want to test
* `tag`: `v0.2.0` (the version you plan to release)
* "Dry run": leave it **checked**

This runs everything: tests, the signed Android build with the certificate
check, the Windows build and zip, and the manifest. The manifest is signed with
a throwaway key that no app trusts, and **nothing is published**. Download the
artifacts from the run page if you want to try the files; they are kept for 3
days.

Note that the dry-run APK is signed with your real release keystore, and the
artifacts of a public repository can be downloaded by any signed-in GitHub user
while they exist. It is the same build you would publish, but it is released
early. The dry run holds no manifest signing key.

### 4. The real release

**Without a git clone (one click):** GitHub → **Actions → Create release tag →
Run workflow**, "Use workflow from" the default branch, `version`: `0.2.0` (no
`v`). It tags the head of the default branch `v0.2.0` and starts the Release
workflow from that tag. It refuses a commit whose "Build & test" run has not
passed, an existing tag, and any branch but the default one. Wait for the green
check on the branch before you run it.

**With git:**

```sh
git checkout <release-branch> && git pull   # the branch you ship from
git tag v0.2.0
git push origin v0.2.0
```

Either way, you tag the commit you want to ship. The run takes about 20 to 30 minutes. Watch
it under **Actions → Release**. When it is green, the **Releases** page shows
`v0.2.0` with the four files, and installed apps find it on their next check.

Installed apps check at most once every 24 hours, and only if "check for
updates" is on in their settings; a user can also check by hand.

### 5. After the run

* Open the release page and make sure the four files are there.
* The `verify` job already did the end-to-end check from the public URLs (signature
  with the pinned key, sizes and SHA-256 of both packages, and that `latest`
  serves this release). You can repeat it from any machine with Python 3:

  ```sh
  python3 tool/verify_update_manifest.py --remote --repo OmarAlnasser/Password \
    --tag v0.2.0 --public-key release/update_public_key.txt \
    --download-assets --check-latest
  ```

* Install it on a real phone and a Windows machine from the previous version
  and watch the update happen. Do this for every release that touches the
  updater. For the very first release there is no previous version: follow
  "Test the update end to end" below, which needs two releases.

## Test the update end to end

The only real proof that updating works is to update a real install. It needs
two releases, A and a higher B (use the numbers you like; the example uses
`v0.2.0` and `v0.2.1`).

1. **Publish A.** Tag `v0.2.0` as in "The real release". Wait for the green run.
2. **Install A by hand.** Download `android.apk` / `windows-x64.zip` from the
   Releases page in a browser and install it (see the warnings under "Before the
   first release"; an Android phone that has a `build.yml` build must uninstall
   it first, which deletes its local vault). On Windows unzip into a folder your
   user can write to. Open the app, create or open a vault, and look at
   **Settings → Updates**: the Version row must say `0.2.0 (build 2000)`. If it
   says "Development build" and the screen says "Updates are off in development
   builds", that build was not made by the release workflow.
3. **Publish B.** Make any visible change (or only bump the version), commit it
   and tag `v0.2.1`. Wait for the green run.
4. **Force the check on A.** The app checks by itself only once every 24 hours,
   so do not wait: in A open **Settings → Updates → Check now**. Expected:
   * "Version 0.2.1 is available" and a **View update** button (the same offer
     appears as a pill at the top of the app). Opening it shows the version,
     size, release date and notes.
   * If it says "Couldn’t reach GitHub", the repository is private or the phone
     is offline. If it says "This update’s signature could not be verified",
     `UPDATE_SIGNING_KEY` and `release/update_public_key.txt` do not match: the
     `check` job should have caught it, so report it.
5. **Update.** Tap **Update now**: a progress bar, then "Checking the download",
   then "Ready to install".
   * **Android:** tap **Install**. The first time, Android opens its "Install
     unknown apps" page for the app: switch it on, go back, tap **Install**
     again. Android's own installer opens; tap **Install** there. The app is
     replaced and closes. If Android says the update was not accepted, the
     installed A is signed with another key than the release keystore (for
     example a debug build): uninstall it and install A from the Releases page.
   * **Windows:** tap **Close and install**. The app locks the vault and closes,
     and a moment later the new version opens by itself. If the
     old version comes back with a message "The last update didn’t finish", the
     install folder is protected or a file was in use: nothing was changed.
6. **Check B.** Open **Settings → Updates**: the Version row says `0.2.1 (build
   2001)` and **Check now** answers "You have the latest version." Your vault is still there
   after unlocking.

Things that are normal: a build from `build.yml` never offers updates (it has no
version); an offer you dismissed with *Later* or *Hide for now* comes back at the
next start of the app; *Skip this version* silences only that version.

## Keys: backup, loss and leaks

### Back up now

| What | Keep it in |
|---|---|
| Release keystore file + password | a password manager **and** an offline copy (USB stick in a drawer) |
| Manifest signing seed (`UPDATE_SIGNING_KEY`) | a password manager **and** an offline copy |

GitHub secrets are write-only. If your copies are gone, the keys are gone.

### Lost keys

* **Keystore lost** (no leak): Android will never accept an update signed with
  another key. Existing installs cannot be updated in place. Users must
  uninstall and install a build signed with a new key, which deletes their local
  vault unless they have a backup or sync. There is no way around this; it is
  why the keystore needs two backups.
* **Manifest seed lost** (no leak): installed apps pin the old public key, so
  they cannot verify any new manifest. They keep working but never update. Users
  must install a new build that pins a new public key by hand. (Android keeps
  the data when the same keystore signs the new APK; on Windows unzip over the
  old folder.)

### Leaked keys

Treat any leaked key as an incident, even though one key alone cannot push an
update to installed apps.

* **What a leaked manifest seed allows:** signing a manifest. To get it to users
  the attacker would also need to put files on your release URLs, which needs
  access to your GitHub account or repository. On Android the update must also be
  signed with the keystore. On Windows the signed manifest is the only check, so
  for Windows the seed is the more critical key.
* **What a leaked keystore allows:** building APKs that Android accepts as
  updates of the app, to be sideloaded or phished. They still cannot come
  through the in-app updater without a signed manifest.

What to do:

1. Rotate your GitHub credentials (password, 2FA, tokens), and check
   your account's security log and the Releases page for anything you did not do.
2. Delete any release you did not create. Deleting a release makes `latest` point
   at the one before it.
3. Generate a replacement: `python3 tool/make_update_manifest.py --generate-key`
   (run on your machine, never in CI; it prints the new seed once).
4. **The app pins a single manifest key and has no key-rotation path.** Replace
   `release/update_public_key.txt` and the constant in
   `lib/services/update/update_public_key.dart` (a test checks they are equal),
   update the `UPDATE_SIGNING_KEY` secret, and give the new build to users by
   hand. Installed copies keep trusting the old key until they get that build.
   If rotation without a manual step is ever needed, the app must first learn
   to accept two keys; that is a code change and a release signed with the old
   key.
5. A leaked keystore: Android can move to a new key without a reinstall using
   APK Signature Scheme v3 key rotation (`apksigner rotate`), which needs the old
   key. Plan it before you need it; it is not automated here.

## Rollback policy

* **Published releases are never edited.** Do not replace files of a published
  release and do not re-use a version number. The manifest, its signature and
  the packages are a set, and apps remember versions they have seen.
* **Apps never go backwards.** Android refuses a lower `versionCode`, and the app
  ignores any manifest older than the newest one it has ever seen (so an old
  signed manifest cannot be replayed to hold users on a vulnerable version). The
  workflow also refuses to publish a build that is not higher than the newest
  published release.
* **A bad release is fixed by a newer one.** Make the fix, then tag the next
  version (`v0.2.1`). Users who took the bad version get the fix at their next
  check.
* **To stop the spread at once**, delete the bad release on GitHub (or edit it
  and tick "pre-release", which removes it from `latest`). New checks then see
  the previous release, which is older than what the early adopters already
  have, so those apps simply do nothing until the fixed version is out. Do this
  and release the fix right away.
* If a run fails **before** the release is published (nothing visible on the
  Releases page), nothing reached users: fix the problem and run the failed
  jobs again, or delete the tag (`git push origin :refs/tags/v0.2.0` and
  `git tag -d v0.2.0`) and tag the right commit. A half-made draft release from
  an earlier try is replaced automatically. Never delete a tag whose release
  was published.

## When a run fails

| Message | Meaning and fix |
|---|---|
| `The tag must be vX.Y.Z` | The tag is not `v` plus three plain numbers. Delete it and tag again. |
| `A real release must run from the tag itself` | A manual run with "Dry run" unchecked must be started with the tag selected as "Use workflow from". |
| `The UPDATE_SIGNING_KEY secret is not set` / `ANDROID_KEYSTORE_*` | Add the secret (see above). |
| `the signing key does not match the pinned public key` | `UPDATE_SIGNING_KEY` holds a different seed than the one behind `release/update_public_key.txt`. The message prints both public keys (public values). Fix the secret. |
| `The APK is NOT signed with the release certificate` | `ANDROID_KEYSTORE_BASE64` is a different keystore than the one in `release/android_cert_sha256.txt`. |
| `The APK versionCode is not the build number` | `android/app/build.gradle.kts` no longer takes its version from Flutter. |
| `Build N is not higher than the newest published release` | Releases only go forward. Use a higher version. |
| `A release for this tag is already published` | Releases are never changed. Use a new version. |
| `lib/services/update/update_config.dart defaultRepo` | The repository the app polls is not the repository running the workflow (a fork). |
| `verify` job fails with 404 or "does not serve this release yet" | GitHub's CDN is slow; the job retries for 5 minutes. Use "Re-run failed jobs" later: re-running only `verify` is safe because it only reads. |
| `unexpected failure` from a Python tool | A bug: run the tool locally with the same arguments and report the output. |

## Files

| File | Role |
|---|---|
| `.github/workflows/release.yml` | the pipeline |
| `tool/make_update_manifest.py` | builds and signs `update.json` (pure Python 3.9+, standard library only, so the job that holds the key installs nothing from the network) |
| `tool/verify_update_manifest.py` | verifies manifest, signature and packages, locally or against a published release |
| `tool/test_update_tools.py` | tests for both tools and static checks of the workflow; run `python3 tool/test_update_tools.py` |
| `release/update_public_key.txt` | the pinned manifest public key (also compiled into the app) |
| `release/android_cert_sha256.txt` | the release certificate fingerprint the APK must carry |
| `release/notes/<version>.md`, `.ar.md` | optional release notes |
| `test/services/update/fixtures/release_tool/` | manifest and signature made by the tool with a throwaway key; `release_tool_fixture_test.dart` feeds them to the app's own parser, so a drift between the tool and the app fails `flutter test` |
| `.gitattributes` | keeps the signed test fixtures byte for byte on every checkout (a signature covers exact bytes; CRLF conversion would break it) |

Third-party actions are referenced by major version tag (`actions/checkout@v4`
and so on), as `build.yml` does, because commit hashes cannot be checked from
here. To pin them, replace each `uses:` reference with the full commit SHA of
that tag and keep the tag in a comment; Dependabot can keep the SHAs current.
