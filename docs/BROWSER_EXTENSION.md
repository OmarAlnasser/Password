# Browser extension

Khazna fills and saves logins in Chrome, Edge and Brave on Windows. The
extension keeps no passwords of its own: it asks the Khazna app running on the
same computer every time, and the app decides what a page may get.

## Setting it up (Windows)

1. In Khazna, open **Settings → Browser extension** and turn it on.
2. In the browser, open `chrome://extensions` (`edge://extensions` in Edge)
   and turn on **Developer mode**.
3. Click **Load unpacked** and choose the `extension` folder next to
   Khazna's exe. The Settings screen shows the path and has an **Open folder**
   button.
4. Click the Khazna icon in the toolbar and choose **Pair**. Khazna shows a
   six-digit code; allow it if it is the same code the browser shows.

After that:

* **Fill.** On a sign-in page, click the Khazna icon (or press Ctrl+Shift+L)
  and pick a login. Nothing is ever filled without that click.
* **Save and update.** After you sign in with a login Khazna does not have, or
  with a new password, the page shows "Save this login to Khazna?" or "Update
  the password…". Nothing is saved until you click Save or Update.
* **Activity.** Settings → Browser extension → Browser activity lists every
  fill, save, update and pairing. A badge on the home screen counts the lines
  you have not seen.

When Khazna updates, the extension folder is updated too. The browser picks the
new version up when it restarts, or when you press the reload button of the
extension in `chrome://extensions`; the popup says when they differ.

## How it fits together

```
 web page ── content.js ──┐
                          │ chrome.runtime messages
 popup.js ───────────── background.js (service worker)
                          │ native messaging (stdin/stdout, 4-byte length + JSON)
                    khazna_bridge.exe        (browser/bridge, plain Dart)
                          │ loopback TCP, same frames, token first
                    the Khazna app           (lib/services/browser)
                          │
                    the encrypted vault
```

* **browser/extension/**: the Manifest V3 extension. Its `key` gives it the
  fixed id `hanpnpoopbcidkdgeknbinmkhlkfmecf` wherever it is loaded from.
* **browser/bridge/**: the helper Chrome starts (`app.khazna.bridge`). With
  the app running it connects to the app's loopback port from
  `%LOCALAPPDATA%\Hisn\Browser\endpoint.json`, sends the app's per-run token
  and then copies bytes both ways. Without the app it answers once
  (`app_not_running`, or starts the app for "Open Khazna") and exits, so it
  never holds the install folder during an update.
* **lib/services/browser/**: `BrowserBridge` (the app's end: the loopback
  server, pairing and the requests), `BrowserRegistration` (the native
  messaging manifest and the per-user registry keys for Chrome, Edge and
  Brave) and `BrowserActivityLog` (in the encrypted database).
* **lib/ui/browser/**: the Settings screen, the pairing question and the
  activity log.

The Windows build gets the helper and the extension from
`tool/bundle_browser.py`, which the build and release workflows run after
`flutter build windows`.

## Requests

Every request is `{"id", "t", ...}`; every reply carries the same `id` and
`"ok"`, with `"error"` when it is false.

| `t`      | Needs                | Does |
|----------|----------------------|------|
| `hello`  | the extension's key  | Says whether this browser is paired (and then the vault state). |
| `pair`   | the key              | Asks the user in the app; waits up to two minutes. |
| `status` | paired               | `unlocked`, `locked` or `no_vault`. |
| `list`   | paired, unlocked     | The logins of an https page's host: id, title, username. |
| `fill`   | paired, unlocked     | Username and password of one of those logins. Logged. |
| `check`  | paired, unlocked     | After a sign-in: `save`, `update` (with the entry) or `none`. |
| `save`   | paired, unlocked     | Adds the login, or with `entry` changes its password. Logged. |
| `show`   | paired               | Brings the app's window to the front. |

Errors: `not_paired`, `locked`, `insecure_page` (not https), `not_found` (not
a login of that page), `denied`, `busy`, `bad_request`. From the extension's
side also `not_installed` (the helper is not registered) and
`app_not_running`.

See [SECURITY.md](SECURITY.md), item 21, for what this exposes and how it is
kept in check.

## Testing

* `flutter test test/services/browser test/ui/browser_extension_test.dart`:
  the app's end, the helper and the screens.
* `flutter test --run-skipped -t e2e test/tool/extension_e2e_test.dart`: the
  whole chain in a real Chromium (Playwright): pairing, fill, update and save
  on an https page, against a real vault. Needs Node, Playwright, Chromium and
  `dart` on PATH; the dev container has them.
* `python3 -I tool/test_bundle_browser.py`: the packaging script, the
  extension id and the extension's messages.
