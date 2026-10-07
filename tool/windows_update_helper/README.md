# Windows update helper

The Windows build of the app is a plain folder (exe, dlls, `data/`) that the
user unzipped somewhere they can write: Downloads, the Desktop, `C:\Users\x\Apps`.
There is no installer. To update itself the app therefore has to replace its own
files, and a running program cannot overwrite its own exe. This folder holds the
small PowerShell script that does the swap after the app has exited.

| File | What it is |
|---|---|
| `apply_update.ps1` | The swap script. **Source of truth.** ASCII only, LF line ends, Windows PowerShell 5.1 compatible. |
| `embed_script.py` | Copies the script into `lib/services/update/windows_installer.dart` as the raw string `windowsApplyUpdateScript`. |
| `.gitattributes` | Keeps the script on LF line ends on every checkout. |

The app does not read the `.ps1` from the repo at run time (the release folder
does not contain `tool/`). It writes its own embedded copy into the private
update folder and runs that. A unit test fails when the two differ:

```
python3 tool/windows_update_helper/embed_script.py          # rewrite the Dart copy
python3 tool/windows_update_helper/embed_script.py --check  # exit 1 when stale
```

## Flow

`WindowsUpdateInstaller.install` (`lib/services/update/windows_installer.dart`):

1. The install folder is the folder of the running exe. A `\\server\share` path
   or a drive root is refused. A probe file is created and deleted in the folder;
   if that fails nothing else happens (`WindowsInstallError.notWritable`, the UI
   explains and opens the release page).
2. `SafeZipExtractor` unpacks the verified zip into `<private update folder>/stage`
   (zip slip, absolute paths, drive letters, `:` streams, device names, links,
   reparse points, duplicates and case collisions, entry-count and size bombs,
   sizes that lie; every cap is enforced while the bytes are produced).
   The tree must hold the same exe name as the running program (starting with
   `MZ`), `flutter_windows.dll` and `data/`, and a plausible total size.
3. The embedded script is written next to it.
4. `prepareExit()` locks the vault and wipes the keys.
5. `powershell.exe` is started detached with the arguments as a list (never one
   command string), from `%SystemRoot%\System32\WindowsPowerShell\v1.0` when that
   exists. The script validates everything (`validate` phase), then writes `ready`
   into the private folder. The app waits up to 20 s for it. No `ready` (execution
   policy, antivirus, constrained language mode) or `abort ...`: the helper is
   stopped, the staging files are deleted, the app keeps running and the install
   is reported as failed.
6. `exit(0)`.

The script then:

1. waits for the process id (checking that the id still belongs to a program with
   the exe's name) and for every other program whose file lies in the install
   folder (a second window of the app), at most `-WaitSeconds` (60) in total;
2. stops quietly if the app deleted the `ready` file meanwhile (it gave up);
3. copies only the files it will overwrite to `<private folder>/backup`;
4. clears read-only attributes on those targets and runs
   `robocopy <staging> <install> /E /IS /IT /R:2 /W:1 /XJ` (up to 3 attempts,
   exit codes below 8 are success). No purge or mirror option: files the update
   does not contain, including the user's own files, are never deleted;
5. checks size and SHA-256 of every copied file;
6. on any failure after step 3: copies the backed up files back and starts the
   OLD exe;
7. on success: starts the NEW exe, deletes the staging and backup folders;
8. writes `update-helper.log` in `%TEMP%`.

The script never touches the network, never evaluates strings, and its log holds
only step names, counts, exception type names, HRESULTs and a final
`RESULT <token>` line, no path, no user name, no secret. The app reads that last
line at its next start with `WindowsUpdateInstaller.readHelperResult()` to tell
the user when an update was rolled back (`rolledBack`, `rollbackFailed`) or never
started (`aborted`).

## Exit codes

| Code | Meaning | App relaunched |
|---|---|---|
| 0 | updated | new version |
| 2 | bad arguments (not a local absolute path, folders overlap, ...) | no (app never closed) |
| 3 | another update of this folder is running | no |
| 10 | the app or another program from the folder did not exit in time | only if nothing from the folder runs |
| 11 | staged files or install folder not as expected | no before the wait, old version after |
| 12 | the app took its go-ahead back | no |
| 20 | swap failed, old files put back | old version |
| 21 | swap failed and putting the old files back failed too | old version, may be damaged |
| 30 | unexpected error | per phase |

## Edge cases handled

* Paths with spaces, quotes, `& ; $ [ ] ( )` and non-ASCII letters: arguments go
  through `Process.start(list)` and PowerShell `-File`, never through a command
  string, and the script uses `-LiteralPath` and .NET calls.
* UNC and device paths, drive roots, staging or backup inside the install folder
  (or the reverse): refused before anything is touched.
* Antivirus or the search indexer holding a file: copies are retried, robocopy
  retries, a short pause after the app exits.
* Read-only attribute on an installed file: cleared on the files that are replaced.
* The same update twice: a lock (named mutex per install folder) and a leftover
  backup folder both stop the second run.
* A second instance of the app: waited for; if it does not exit the update is
  abandoned and nothing is changed.
* An exe that was renamed by the user: the staged tree has no file of that name,
  the update is refused (the UI falls back to the release page).
* A new release that no longer contains a file: the old file stays (no deletes).

## Testing

`test/services/update/windows_installer_test.dart` covers the zip extractor
(including hostile and damaged zips), the argument list, the hand-over order and
failure paths with a fake process starter, and the script itself. The script tests
need PowerShell 7 (`pwsh`, preinstalled on GitHub's ubuntu runners; they are
skipped when it is missing) and run `apply_update.ps1` against a fake install
tree with a shell stand-in for `robocopy.exe`: success, rollback, retry, waiting
for a running program, refusal of bad paths, a user file that must survive, and a
log without paths. They also parse the script with PowerShell's own parser and
fail on syntax newer than Windows PowerShell 5.1.

What cannot be tested on Linux: the real `robocopy.exe`, file locking by running
programs and antivirus, `Process.Path` of Windows processes, and Windows
PowerShell 5.1 itself. Before the first release that carries the updater, do this
once on Windows 10/11:

1. Unzip release N into `C:\Users\<you>\Apps\Test Folder (1)\` (with a space and a
   bracket on purpose) and start it. Keep a second window of it open.
2. Publish release N+1, let the first window update. Expect: the second window
   blocks the swap (code 10 after 60 s, nothing changed). Close it and retry:
   the new version starts.
3. Put the app in `C:\Program Files\...`: the update must refuse with the
   not-writable message.
4. Mark `data\app.so` read-only and update: it must still work.
5. Read `%TEMP%\update-helper.log`: no paths, last line `RESULT success`.
