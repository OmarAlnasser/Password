# PC Doctor overhaul prompt

You are working on PC Doctor (`pcdoctor/` in OmarAlnasser/Password): a C#/.NET 8 WPF Windows
diagnostic app with a non-elevated App and an elevated Broker. Read `pcdoctor/README.md` first.

## Goal
Audit and harden the whole project so it is safe to run on a real PC, improve detection, add
hardware-matched performance comparison, and add the quality-of-life features below.

## Phase 1: full audit (every file, every line)
1. List every source file under `pcdoctor/` (src, tests, tools, installer, CI). Keep a checklist
   in `pcdoctor/docs/AUDIT.md` and tick each file when it has been read in full.
2. Look for: logic bugs, unhandled exceptions, races and deadlocks, resource leaks (handles,
   streams, COM objects, timers, event handlers, unbounded collections), privilege-boundary
   mistakes in the Broker, path or argument injection, unsafe P/Invoke signatures, wrong Windows
   API assumptions, and anything marked `// VERIFY`.
3. Record each finding: file:line, what is wrong, a concrete failure scenario, severity.
4. Fix each at its root cause with a test that fails before and passes after. Never skip or
   disable a test.

## Phase 2: safety for the machine it runs on
- No thread or process above Normal priority; background work runs BelowNormal.
- Every CPU, disk or GPU stress has a hard time limit, a cancel path, and stops on battery or at
  a safe temperature limit.
- No unbounded memory growth: soak-test scans, live sensors and page switching; working set and
  handle count stay flat.
- Disk tests write only to a size-capped temp file after a free-space check, never raw devices.
  Nothing writes to firmware, fan, voltage or clock controls. Sensors are read-only.
- Every system change needs consent, a verified restore point, a journal entry and a working
  undo. The NEVER list in the README stays intact.
- Tests are safe on a developer's own PC: read-only by default; system-changing checks run only
  against fakes or are marked VM-only.

## Phase 3: detection quality (honest, layered)
- Defender stays the engine: quick, full, custom and offline scans; signature freshness; PUA,
  tamper-protection and cloud-protection state.
- Strengthen: persistence audit across all autorun locations, signature and catalog checks,
  unsigned or recently dropped binaries in autorun paths, suspicious tasks and services, WMI
  consumers, hosts/proxy/DNS/root-certificate tampering, browser extension and policy review,
  optional VirusTotal hash lookups (own key, off by default, hashes only).
- Measure it with a labelled corpus (EICAR, benign samples, simulated persistence on a VM) and
  report detection and false-positive rates.
- Reports always say what was checked, by which engine, and what was not. Never "clean",
  "100%" or "all viruses".

## Phase 4: performance versus expected for this hardware
- Detect exact hardware: CPU, GPU and driver version, RAM size, speed and XMP/EXPO state,
  storage model and interface, motherboard and BIOS version, power plan, thermal state.
- Compare the app's own benchmark results with an expected range for that hardware from a
  versioned reference table with cited public sources. An opt-in online refresh may send only
  hardware model names. With no reference, say so.
- When a result is below range, rank likely causes with evidence: thermal throttling,
  single-channel or slow RAM, XMP off, power plan, outdated or generic driver, background load,
  storage health or a nearly full drive, PCIe link speed, battery or power limits.
- Keep the statistical rule: no verdict without enough runs and a significant difference.

## Phase 5: verify and report
- Full suite green on Linux and Windows CI.
- Real-PC pass in read-only mode first, then VM-only checks.
- Deliver `AUDIT.md`, an updated README, and a summary of what is verified, what is not, and
  what needs a human on a VM.

## Phase 6: quality of life
Understanding:
- Plain-words summary with the single most important action first.
- "What changed since last time" on the Overview page.
- Search across findings, settings, startup entries and drivers.
- One-sentence explanation for every technical term, in English and Arabic.

Fixing:
- Guided steps with a re-check for findings the app cannot fix itself.
- Buttons that open the exact Windows Settings page.
- One-sentence fix preview before consent; a visible Undo for a few minutes after a fix.

Everyday problems:
- "Why is my PC slow right now?": a 60-second look that names the process, disk, memory
  pressure or thermal throttling responsible.
- Storage view: largest folders and files; only Windows' own cleanup is offered.
- Startup impact per app; battery wear, drain and runtime; upgrade checks (Windows version
  eligibility, free RAM slots).

Sharing:
- Technician report with redaction on by default and a pasteable text summary.
- Copy-as-text on every finding.

Comfort:
- Quiet mode while gaming or presenting; low-impact scanning that pauses under heavy use.
- First-run tour; font size and density settings; tray icon with last scan time and Scan now.

Build order: slow-right-now, low-impact scanning and quiet mode, plain summary, guided fixes,
technician report, then the rest.

## Rules
- Ask before any decision that is the owner's (paid APIs, new network calls, anything that
  changes their PC). Otherwise proceed.
- Small, reviewable commits on the PR branch; keep CI green.
- State plainly anything not verified. Do not claim "bug-free".
