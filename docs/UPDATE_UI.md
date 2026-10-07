# Update UI: how it is wired and how to finish the integration

The self-update flow has three layers. This folder is the top one.

| Layer | Where | What it does |
|---|---|---|
| Core | `lib/services/update/` | Fetches and verifies the signed manifest, downloads, checks size and SHA-256, stages the package, installs (Android system installer, Windows swap script). Knows nothing about widgets. |
| Wiring | `lib/services/update/update_providers.dart`, `lib/ui/app_scope.dart`, `lib/main.dart` | `createUpdateController(...)` builds the `UpdateController` (or returns null), `AppServices.updates` carries it. |
| UI | `lib/ui/update/` | `UpdateGate` (automatic check + banner), `UpdateSheet` (details and buttons), `UpdateSettingsTile`, `AboutVersionTile`. |

## Already done (nothing to do)

* `lib/main.dart` calls `createUpdateController` in `bootstrap` and puts the
  result in `AppServices(updates: ...)`. `prepareExit` is `session.lock`, so
  the keys are wiped before the app exits (Windows) or the system installer
  opens (Android).
* `lib/app.dart` wraps the content that `MaterialApp.builder` gets (the
  `Navigator`) in `UpdateGate`, below `AppShell` and below the black privacy
  cover, so the cover always wins.
* Strings: `lib/l10n/app_en.arb` / `app_ar.arb`, keys starting with `update`
  (appended at the end), generated with `flutter gen-l10n`.

## The settings block (done)

`SettingsScreen` (`lib/ui/settings_screen.dart`) shows `UpdateSettingsTile`
after the sync tile, and `AboutVersionTile` when there is no updater (so the
version, or "Development build", is always visible). It is the only place with
the "Check now" button and the "Check for updates automatically" switch, so it
must stay in the list; `test/ui/update/settings_screen_updates_test.dart`
fails if it falls out.

* With an updater (release build on Android or Windows): switch, installed
  version, last check, result of the last check, "Check now", and "View update"
  while a newer version is on offer. It reads `context.services.updates` and
  `context.services.settings`; pass `controller:` and `settings:` to override.
* Development build (compiled without `APP_VERSION`): one line, "Updates are
  off in development builds", so a tester can tell why there is no "Check now",
  plus the "Development build" version row.
* Platforms without updates (iOS, macOS, Linux, the autofill entry): nothing.

## How it behaves

* **Start-up:** `UpdateGate` waits 3 s, then calls
  `UpdateController.checkAutomatically()`. That sweeps the files of the last
  update, and then checks GitHub at most once every 24 hours, only when the
  "Check for updates automatically" switch is on. The same call is made when
  the vault locks or unlocks and when the app comes back to the foreground; the
  controller's throttle makes extra calls free.
  An offer survives a restart: `settings.highestSeenBuild` remembers the newest
  signed build, so when it is above the installed build and not skipped, the
  first automatic check of each run ignores the 24 h limit once (the user
  tapped Later, went to Android's "install unknown apps" page, or a Windows swap
  was rolled back).
* **Banner:** when a newer signed version exists, a pill appears at the top
  (violet gradient border, mint dot). It pushes the page down (it never covers
  the app bar) and is shown on the unlock screen too: installing needs no
  vault. Its X hides it for this step of this build; "Later" in the sheet does
  the same. "Skip this version" is the persistent no (`settings.skippedBuild`).
  Progress, "Ready to install" and failures of a download show in the same
  banner, so closing the sheet never loses track of a running download.
* **Sheet:** a bottom sheet on phones, a centred dialog from 600 dp. Version,
  size, release date, release notes (current language, else English, else
  whatever the release has; plain text only), then the buttons for the step
  the controller is in. Nothing is downloaded until "Update now" and nothing is
  installed until "Install" / "Close and install": the UI never calls
  `startDownload` or `installUpdate` by itself.
* **Android:** if "install unknown apps" is not allowed yet, the installer
  opens the settings page and the sheet explains what to switch on. After the
  system installer opens, the sheet says so and can open it again. If Android
  refuses the package (typically a debug-signed install meeting the first
  release-signed update) the sheet explains it and points to the release page.
* **Windows:** "Close and install" locks the vault, then the app exits and the
  swap script restarts it. If the install folder cannot be written (for example
  Program Files) the sheet explains it and offers the release page. After a
  restart the gate reports, once, a swap that was rolled back or never started
  (`WindowsUpdateInstaller.readHelperResult`).
* **Errors** are plain sentences chosen from the `UpdateFailure` enum
  (`update_messages.dart`). No URL, path, server text or enum name is ever
  shown. A bad signature reads "Update rejected for your safety".

## Known limits

* **Opening the release page.** The app has no `url_launcher` dependency.
  Windows hands the address to the shell and Android asks the native side
  (`openReleasePage` on the platform channel, `ApkInstaller.openReleasePage`,
  `Intent.ACTION_VIEW`); only an HTTPS `github.com/<repo>/releases...` address
  is ever passed (`isReleasePageUrl`, checked again natively). Other platforms
  offer "Copy link" only.
* **Install failures** reach the UI as `InstallOutcome.failed` only (the
  installers keep the detail in `lastError`), so the failure text lists the
  likely reasons per platform instead of one exact cause.
* The banner sits above the `Navigator`, where there is no `Overlay`, so its
  close button has a semantics label but no tooltip.

## Tests

`test/ui/update/` (widget tests with a scripted service and installer, no
network or disk):

* `update_gate_test.dart`: automatic check and its throttle, banner, sheet
  steps, progress, Skip / Later, errors, Windows notice, Arabic, reduced
  motion, 200 % text.
* `update_settings_tile_test.dart`: the settings block and the About row.
* `update_app_test.dart`: the same inside the real `VaultSnapApp` (navigator
  key, lock before install, privacy cover on top).
* `update_format_test.dart`, `update_providers_test.dart`: formatting, failure
  texts, which builds get an updater, which URLs may be opened.
* `update_screenshots_test.dart` (tag `screenshots`, skipped by default):
  renders PNGs for review:
  `SHOTS_DIR=/some/dir flutter test --run-skipped -t screenshots test/ui/update/update_screenshots_test.dart`

`update_ui_kit.dart` holds the fakes (`ScriptedUpdateService`,
`RecordingInstaller`, `MemorySettings`, `UpdateRig`) and `pumpUpdateApp`, which
builds the app the way `lib/app.dart` does.
