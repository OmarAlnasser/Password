# PC Doctor

A Windows 10 (22H2) and Windows 11 (23H2 / 24H2 / 25H2) app that diagnoses PC problems, explains
them in plain English or Arabic, and (with your consent) makes reversible fixes.

PC Doctor **orchestrates and explains**. It has no antivirus engine of its own. Detection will come
from Microsoft Defender, and root causes from Microsoft's own tools, documented event IDs and WMI
classes. Every report says what was checked, by which source, and what was *not* checked. No report
ever says the PC is "clean".

## Status

| Phase | Scope | State |
|---|---|---|
| P0 | Solution, MVVM shell, EN/AR + RTL, elevated Broker + named-pipe IPC, Finding model, change journal + undo, verified restore points, report export, CI with signing gate | **Done** |
| P1 | Read-only health: M11 security posture, M9 drivers/devices, M7 disk health, M10 battery, M5 event correlation + dump config | **Done** (see "Not yet verified on hardware") |
| P2 | Crash engine: cdb/dbgeng `!analyze`, offline minidump fallback, crash timeline UI | Not started. The bug check knowledge base is already in place (`src/PcDoctor.Modules.Crash/bugchecks.json`) |
| P3 | Defender orchestration + AMSI, persistence audit + WinVerifyTrust/catalog, network/trust, file inventory | Not started |
| P4 | DISM/SFC/chkdsk/mdsched with consent and reboot flows | Not started |
| P5 | Benchmarks with statistical verdicts | Not started |
| P6 | Debloat catalog, detect/apply/undo, presets, drift detection | Not started |
| P7 | Sensors (PawnIO), scheduling, history, installer, accessibility polish | Not started |

Inside the app, each part of a later phase shows up under "What was checked" as *Not checked: this
version does not include it yet (planned for phase Pn)*. Nothing is silently left out.

## Layout

```
src/
  PcDoctor.App               WPF UI (asInvoker; never elevated), MVVM with CommunityToolkit.Mvvm
  PcDoctor.Broker            Elevated helper (requireAdministrator), started via UAC on demand
  PcDoctor.Core              Finding model, localization, journal/undo, restore points, IPC, reports, scan runner
  PcDoctor.Modules.Security  M11
  PcDoctor.Modules.Crash     M5 (+ bugchecks.json knowledge base)
  PcDoctor.Modules.Disk      M7 (MSFT_PhysicalDisk, reliability counters, NVMe log 0x02, SATA SMART)
  PcDoctor.Modules.Drivers   M9 (+ WinRing0 detection)
  PcDoctor.Modules.Battery   M10
tests/PcDoctor.Tests         xUnit, with fixtures (event XML, battery report)
tools/                       String tables (strings_*.py) → .resx generator, CI signature check
```

Each module is split into a **snapshot** (raw data), a pure **analyzer** (snapshot → checks + findings)
and a Windows **reader**. The analyzers have no Windows dependencies, so they are tested on any OS
against recorded fixtures.

## Design decisions worth knowing

- **The Broker cannot be used as a general-purpose admin tool.** The UI sends a fix *ID* from
  `FixCatalog`, which is compiled into the signed Broker. It never sends a registry path or a command
  line. The protocol has six typed operations (`IpcTests.Protocol_has_no_generic_command_or_path_operation`).
  The pipe name is random, its ACL admits only the launching user's SID, and both ends check the
  other's process ID. The Broker also checks that its client is `PcDoctor.App.exe` from its own folder.
- **HKCU is resolved to `HKU\<user SID>`** before anything is recorded. Under over-the-shoulder
  elevation the Broker's own HKCU belongs to the admin account.
- **Write-ahead journal.** Each change is written to the journal as *Planned* with its old value before
  it is applied. If a batch fails partway, it is rolled back. Undo refuses to overwrite a value that
  something else changed since; you can force it per entry. The journal lives in
  `%ProgramData%\PCDoctor\journal` and only Administrators and SYSTEM can write to it.
- **Restore points are verified.** The sequence number must increase. The 24-hour creation throttle is
  lifted for the call and then put back exactly (including "value absent"). No verified restore point
  means no change.
- **Health Check vs Deep Scan.** The Health Check needs no admin rights. Data that does (reliability
  counters, the NVMe health log, SMART, TPM, BitLocker) is reported as *Needs a Deep Scan* until the
  Broker reads it.
- **Antivirus honesty.** If Defender is not in Normal mode and a third-party antivirus is active, the
  report names that product and shows no Defender verdicts (`SecurityTests.Third_party_av_means_no_defender_result_is_shown`).
- **Windows 10 ESU dates** live in `os-support.json`. They can be overridden by
  `%ProgramData%\PCDoctor\config\os-support.json`, and every row is marked unverified.

## Building and testing

```bash
cd pcdoctor
dotnet test PcDoctor.sln            # runs on Windows, Linux or macOS
dotnet publish src/PcDoctor.App -c Release -r win-x64 --self-contained false -o out/win-x64
```

The WPF app and Broker compile on any OS (`EnableWindowsTargeting`), but they run only on Windows.
To change UI text, edit `tools/strings_*.py` (English and Arabic side by side) and run
`python3 -I tools/gen_resx.py`. CI fails if the `.resx` files drift from the tables.

CI (`.github/workflows/pcdoctor.yml`) builds and tests on `windows-latest`, then publishes win-x64 and
win-arm64. If the repository secrets `PCDOCTOR_SIGNING_PFX_BASE64` / `PCDOCTOR_SIGNING_PFX_PASSWORD`
are set, every PE file is signed and verified, and an unsigned file fails the build. Without them the
build is marked "unsigned, not for distribution".

## Acceptance tests covered so far

| # | Test | Where |
|---|---|---|
| 1 | Honesty: no banned phrase in either language's strings, the knowledge base, or generated HTML/JSON/CSV | `HonestyAndLocalizationTests` |
| 8 (partial) | Apply → journal entry per change → undo all → registry byte-identical; Defender/WU/pagefile never in the fix catalog; verified restore point | `JournalTests`, `IpcTests`, `StaticSafetyTests` |
| 11 (partial) | Every string translated, EN/AR key and placeholder parity, every key used in code/XAML exists, evidence rendered LTR | `HonestyAndLocalizationTests` |
| 12 (partial) | UI manifest is `asInvoker`; Broker is `requireAdministrator`; elevated reads go through the Broker | `StaticSafetyTests` |
| 13 (partial) | No WinRing0 in the source tree; CI verifies signatures and rejects WinRing0 in the package | `StaticSafetyTests`, `tools/verify-signatures.ps1` |

Still to do: tests 2–7, 9–10 and 14, which belong to later phases. The RTL clipping screenshot test
at 100% / 150% (test 11) and the real-UAC test (test 12) need a Windows VM.

## Not yet verified on hardware (`// VERIFY` in code)

These were written from documentation and have fixture tests, but have not been run on a real
Windows machine yet:

- NVMe IOCTL buffer layout and Identify Controller WCTEMP/CCTEMP offsets.
- `MSFT_StorageReliabilityCounter.DeviceId` matching `MSFT_PhysicalDisk.DeviceId`.
- SMART `InstanceName` to disk mapping.
- BugCheck 1001 data names (`param1`, `param2`).
- The WER 1001 LiveKernelEvent data position.
- Whether Classpnp 157 is logged under `disk` or `Classpnp`.
- `MSFT_NetFirewallProfile` store (persistent vs active) and the NotConfigured value.
- The `SecurityCenter2` productState bit layout (undocumented).
- `Win32_QuickFixEngineering.InstalledOn` parsing on non-US locales.
- Battery report XML element names.
- System Protection detection (the restore-point verification catches a miss either way).
