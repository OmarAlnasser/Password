# PC Doctor audit record

Honest summary of the read-through audit asked for in `docs/OVERHAUL-PROMPT.md` (Phase 1), what was
fixed, and what is still open. Nothing here has been run on a real PC: results come from the Linux
test suite and the Windows CI job.

## How it was checked

| Area | How |
|---|---|
| `PcDoctor.Core`, `PcDoctor.Broker`, every `PcDoctor.Modules.*`, `PcDoctor.Tweaks` (+ `tweaks.json`), `PcDoctor.Bench`, `PcDoctor.Platform.Appx` | Read line by line |
| `PcDoctor.App`: Services, ViewModels, Controls, Pages, view code-behind, `MainWindow.xaml`, `App.xaml`, manifest, project files | Read line by line |
| `tools/*.py`, `bundled-tools.json`, CI workflow, installer | Read line by line |
| Other XAML views and theme dictionaries | **Not** read line by line. Covered by a script that resolved every binding path, the resource-key tests, and the Windows job that renders every page |
| String tables (1061 keys, English + Arabic) | **Not** read line by line. Covered by parity, missing-key, untranslated-prose and honesty-wording tests |
| Test files | Read only where a fix touched them |

## Fixed

**Safety of the PC**
- Child processes are killed on any cancel or timeout and run below normal priority; the Broker itself runs below normal priority.
- A scan module that hangs is cut off after 10 minutes and reported as not checked.
- NVMe health is read with access 0: the handle cannot write to the disk.
- Driver Verifier is reset if its automatic switch-off ("reset on unusual shutdown") cannot be set.
- The disk benchmark needs 8 GB free, deletes stale test files, and the CPU-test buffer (32 MB) is released after a run.
- The CPU-load test no longer uses above-normal threads (the likely reason the test PC felt heavy while tests ran).
- Broker jobs: duplicates refused, finished jobs pruned, all jobs cancelled and awaited on exit.
- Journal recovery runs at Broker start; the data folder must be owned by Administrators/SYSTEM with no reparse points.
- The tweak that turned off Memory integrity was removed. The catalog validator now rejects anything touching VBS/HVCI, SmartScreen, UAC, exploit mitigations, Defender or Windows Update, and more system packages are protected from removal.
- App removal matches the exact package name, never a prefix.

**Nothing without permission**
- Single undo, SFC, Driver Verifier reset, benchmarks, the latency trace and the scheduled check now explain and ask first. Tweaks, fixes, DISM repair, chkdsk, offline scan, quarantine restore and undo-all already did.
- Windows AI features and extra apps are never applied by a preset button: they are listed first, ticked by the user, previewed, then confirmed.

**Stability and leaks**
- Global exception handlers; errors go to a capped local log (`%LocalAppData%\PCDoctor\errors.log`), never uploaded.
- Broker client: one start at a time, response IDs checked, a lost pipe is a normal failure.
- Registry handles and certificate objects are disposed; the progress-bar animation stops when its page unloads.
- Clipboard, export and settings writes cannot crash the app; settings are saved atomically.
- Sensors polling stops when its page is hidden.

**Detection quality**
- New: startup entries that make a Microsoft-signed tool run hidden/encoded commands or download and run something (PowerShell, mshta, regsvr32, rundll32, certutil, bitsadmin, msiexec, script hosts). Tested against a labelled set of 12 abusive and 14 ordinary command lines.
- Startup entries switched off in Task Manager are read as disabled; shortcut arguments are kept and judged; Brave and Vivaldi extensions are listed; one unreadable location costs one category, not the scan; the persistence reader no longer leaks a registry handle per lookup.
- No "no antivirus" Critical when the state could not be read.
- The user root-certificate store no longer reports every machine-wide root.
- A sign-in accessibility tool whose signature could not be checked is no longer a Critical alarm.
- Defender detections without a time are not counted as found by the current scan; duplicate threat IDs no longer lose all detections.
- VirusTotal: waits are capped per scan (2 minutes), timeouts and bad answers give "no verdict", and a failed lookup is never cached as "never seen".
- Windows 11 end-of-servicing by version and edition (dates from memory: verify against Microsoft's lifecycle page).
- Exports: dates are culture-independent, redaction covers paths and HTML.

## Still open

These were found and are not fixed yet.

- "Microsoft-signed" is decided from the signer name; the chain root is not yet pinned to a Microsoft root.
- Startup script files are not sent to AMSI; Opera extensions are not listed.
- WMI event subscriptions are not read through the Broker, so they are never checked without elevation.
- The security reader catches too few exception types in places: one unreadable key can drop a whole check.
- Hosts-file check can flag ordinary entries that contain a sensitive word.
- File inventory: memory use on very large disks, non-NTFS volumes silently skipped, walk runs at normal priority in the app process.
- CBS.log is read fully into memory; debugger output is not capped; symbol cache grows without limit.
- BitLocker and Winlogon checks assume `C:` in places.
- Known-vulnerable driver list is short and does not check the Microsoft blocklist setting.
- VirusTotal daily quota is not persisted across restarts.
- Long lists are not virtualized; scroll position is not reset on navigation.
- No warning before a benchmark on battery power; old benchmark sessions are never pruned.

## Not done from the overhaul prompt

- Phase 2 soak and leak runs on a real PC (needs a Windows machine).
- Phase 4: comparison with other PCs of the same specification and ranked cause diagnosis.
- Phase 6 quality-of-life features other than the checklist and consent work.
- Driver advisor and the deep-research pass.
