# PC Doctor

A Windows 10 (22H2) and Windows 11 (23H2 / 24H2 / 25H2) app that diagnoses PC problems, explains
them in plain English or Arabic, and (with your consent) makes reversible fixes.

PC Doctor **orchestrates and explains**. It has no antivirus engine of its own. Detection will come
from Microsoft Defender, and root causes from Microsoft's own tools, documented event IDs and WMI
classes. Every report says what was checked, by which source, and what was *not* checked. No report
ever says the PC is "clean".

## Status

All phases P0–P7 are implemented and tested on Linux CI fixtures plus a Windows CI job that renders
every page. **Nothing has been run on real hardware yet**, so this is a developer preview, not a
release. See "Not yet verified on hardware" below.

| Phase | Scope | State |
|---|---|---|
| P0 | Solution, MVVM shell, EN/AR + RTL, elevated Broker + named-pipe IPC, Finding model, change journal + undo, verified restore points, report export, CI with signing gate | Done |
| P1 | Read-only health: M11 security posture, M9 drivers, M7 disk, M10 battery, M5 event correlation | Done |
| P2 | Crash engine: cdb `!analyze` when Debugging Tools are installed, offline minidump header parser, WER reports, crash timeline | Done |
| P3 | M2 Defender orchestration (+AMSI, Safety Scanner, optional VirusTotal hash lookups), M3 persistence audit with WinVerifyTrust + catalog, M4 network/trust, M1 file inventory | Done |
| P4 | M6 integrity: DISM, SFC, chkdsk, Memory Diagnostic, Driver Verifier (expert), with consent and reboot flows | Done |
| P5 | Benchmarks (DiskSpd, PresentMon, boot/latency traces) with Mann-Whitney + bootstrap verdicts | Done |
| P6 | Debloat catalog (54 items), detect/apply/undo, presets, drift detection, and a "Windows AI and extras found on this PC" checklist (Copilot, Recall, Click to Do, AI in Paint/Notepad/Edge, preinstalled apps) | Done |
| P7 | M8 sensors (LibreHardwareMonitor; PawnIO detected, never installed), scan history compare, quiet scheduled Health Check, MSI installer with undo-all on uninstall, keyboard shortcuts | Done |

**Tell first, then ask.** Every action that changes or loads the PC first shows what it will do and
waits for a yes: tweaks and app removals (exact change list), fixes, undo, SFC/DISM/chkdsk, Driver
Verifier, benchmarks, the latency trace and the scheduled check. A test fails the build if a page
sends a change request without a consent dialog (`Every_change_request_in_the_app_is_preceded_by_a_consent_dialog`).
The audit record is in `docs/AUDIT.md`.

UI: Khazna's design language (`docs/DESIGN.md` in the repo root): dark-first tokens with Light and
High Contrast themes, Outfit / IBM Plex Sans Arabic / JetBrains Mono, staggered entrance motion,
hover lift, page transitions, count-up numbers and live indicators. All motion turns off when
Windows animations are off or "Reduce motion" is set in the app.

Keyboard: Ctrl+1…Ctrl+9 open pages, Ctrl+F focuses the findings search. Every control has an
automation name in both languages.

## Layout

```
src/
  PcDoctor.App                 WPF UI (asInvoker; never elevated), MVVM with CommunityToolkit.Mvvm
  PcDoctor.Broker              Elevated helper (requireAdministrator), started via UAC on demand
  PcDoctor.Core                Findings, localization, journal/undo, restore points, IPC, reports, diff, scan runner
  PcDoctor.Modules.Inventory   M1   PcDoctor.Modules.Malware    M2   PcDoctor.Modules.Persistence M3
  PcDoctor.Modules.Network     M4   PcDoctor.Modules.Crash      M5   PcDoctor.Modules.Integrity   M6
  PcDoctor.Modules.Disk        M7   PcDoctor.Modules.Sensors    M8   PcDoctor.Modules.Drivers     M9
  PcDoctor.Modules.Battery     M10  PcDoctor.Modules.Security   M11
  PcDoctor.Bench               Benchmark runner + statistics
  PcDoctor.Tweaks              Tweak engine + versioned tweaks.json
  PcDoctor.Platform.Appx       Store app removal (WinRT PackageManager)
installer/                     WiX v5 per-machine MSI (built in CI on Windows)
tests/PcDoctor.Tests           xUnit with fixtures; runs on any OS
tests/PcDoctor.App.Tests       Windows only: renders every page in both themes, languages and at 100%/150%
tools/                         String tables (strings_*.py) → .resx, bundled tool fetcher, signature check
third_party/                   Pinned DiskSpd / PresentMon hashes and their licenses
```

Each module is split into a **snapshot** (raw data), a pure **analyzer** (snapshot → checks + findings)
and a Windows **reader**. The analyzers have no Windows dependencies, so they are tested on any OS
against recorded fixtures.

## Design decisions worth knowing

- **The Broker cannot be used as a general-purpose admin tool.** The UI sends a fix *ID* from
  `FixCatalog`, which is compiled into the signed Broker. It never sends a registry path or a command
  line. The protocol has a fixed list of typed operations (`IpcTests.Protocol_has_no_generic_command_or_path_operation`).
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

## Acceptance tests

"Fixture" means the logic is tested against recorded data on every CI run. "VM" means the brief's
end-to-end check still has to be done by hand on a Windows 11 and a Windows 10 22H2 VM.

| # | Test | Automated coverage | Still needs a VM |
|---|---|---|---|
| 1 | Honesty phrases | `No_ui_string_in_either_language_makes_a_banned_claim`, `Generated_reports_contain_no_banned_phrase_and_always_carry_the_disclaimer` | – |
| 2 | Inventory coverage | `Inventoried_plus_skipped_accounts_for_every_entry`, `Cloud_placeholders_are_recognised_by_attribute`, `Unreadable_locations_are_listed_as_not_checked` | ACL folder, locked file, junction loop, 300-char path, OneDrive file stays cloud-only |
| 3 | Defender / EICAR / third-party AV | `Eicar_detection_is_reported_from_defender_with_its_path`, `Quarantine_list_is_parsed`, `Third_party_av_means_no_defender_scan` | Real EICAR detect → quarantine → restore |
| 4 | Exit code 2 = scan failed | `Exit_code_2_from_scan_errors_is_scan_failed_not_threat_found` | – |
| 5 | Persistence | `Ifeo_accessibility_wmi_and_amsi_are_reported_…`, `Signature_tiers_map_to_severities_…`, `Disable_plan_moves_run_values_to_backup_…`, `Disabling_a_task_and_moving_a_shortcut_undo_exactly` | Planted entries, catalog-signed System32 file, reboot |
| 6 | Crash | `Kernel_power_41_bugcheck_code_is_decimal`, `Offline_header_parser_reads_code_parameters_and_module_names`, `Analyze_output_fields_are_parsed` | NotMyFault dumps |
| 7 | Integrity | `Cbs_log_separates_repaired_from_unrepairable_since_the_run_started` | Deliberately corrupted file |
| 8 | Debloat undo | `Recommended_applied_through_the_journal_undoes_to_an_identical_registry_and_services`, `Presets_never_include_advanced_items_or_protected_components`, `Fix_is_not_applied_without_a_verified_restore_point` | Diff export on a VM |
| 9 | Drift | `A_setting_reset_by_a_feature_update_is_detected_as_drift` | – |
| 10 | Benchmarks | `Two_runs_with_no_change_are_almost_never_called_a_change` (false-positive rate < 1% over 1,000 pairs), `Injected_cpu_load_is_detected_as_worse` | Real runs |
| 11 | RTL / translation | `Arabic_strings_are_actually_translated`, `English_and_arabic_have_the_same_keys_and_placeholders`, `Every_literal_key_in_source_and_xaml_exists`, `Arabic_html_is_rtl_and_evidence_is_isolated_ltr`, Windows `ViewSmokeTests` | Visual check for clipping |
| 12 | Non-admin | `Ui_never_runs_elevated_and_broker_always_does`, `Protocol_has_no_generic_command_or_path_operation` | Real UAC prompt |
| 13 | Signing, no WinRing0 | `WinRing0_is_never_shipped`, `tools/verify-signatures.ps1` in CI | Signing secrets must be set |
| 14 | VirusTotal | `Limiter_never_allows_more_than_4_a_minute_or_500_a_day`, `No_upload_code_exists_anywhere`; off by default in `Settings` | – |

## Installer

`installer/` builds a per-machine MSI into Program Files with a Start menu shortcut. It adds no
service, driver, startup entry or scheduled task. On a full uninstall it runs the app with
`--uninstall-prompt`, which offers to undo every change still in the journal before the files go.
The journal in `%ProgramData%\PCDoctor` is kept so changes stay reviewable.

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
- LibreHardwareMonitor sensor names ("Distance to TjMax", "GPU Hot Spot") on current hardware.
- The WiX MSI and its uninstall prompt (built in CI, not yet installed on a VM).
- Task Scheduler registration of the scheduled Health Check.
