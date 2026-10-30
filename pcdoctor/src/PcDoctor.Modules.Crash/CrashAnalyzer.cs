using System.Globalization;
using System.Text.RegularExpressions;
using PcDoctor.Core.Events;
using PcDoctor.Core.Findings;
using PcDoctor.Core.Scanning;

namespace PcDoctor.Modules.Crash;

public enum CrashKind { BlueScreen, ForcedOff, PowerLossOrHang }

/// <summary>One unexpected stop, merged from Kernel-Power 41, BugCheck 1001 and EventLog 6008.</summary>
public sealed record CrashIncident(
    DateTimeOffset Time,
    CrashKind Kind,
    uint? BugcheckCode,
    IReadOnlyList<string> Parameters,
    string? DumpPath,
    IReadOnlyList<EventRecordData> Events,
    IReadOnlyList<EventRecordData> Preceding);

/// <summary>M5 event correlation and dump configuration. Pure: everything comes in through the snapshot.</summary>
public static partial class CrashAnalyzer
{
    public const string ModuleId = "M5";
    private static readonly TimeSpan MergeWindow = TimeSpan.FromMinutes(10);

    public static ModuleResult Analyze(CrashSnapshot s)
    {
        BugcheckKnowledgeBase.EnsureRegistered();
        var checks = new List<CheckResult>();
        var findings = new List<Finding>();

        AnalyzeDumpConfig(s, checks, findings);

        var events = s.Events.OrderBy(e => e.TimeCreated).ToList();
        var incidents = BuildIncidents(events);
        checks.Add(new CheckResult("M5.events", new Text("m5.check.events"), CheckStatus.Info,
            new Text("m5.check.events.detail", events.Count, (int)s.Window.TotalDays, incidents.Count), FindingSource.EventLog));

        findings.AddRange(BlueScreenFindings(incidents, s.Window));
        findings.AddRange(StopFindings(incidents, CrashKind.ForcedOff, "M5.forcedOff", "m5.forcedOff", Severity.Medium));
        findings.AddRange(StopFindings(incidents, CrashKind.PowerLossOrHang, "M5.powerLoss", "m5.powerLoss", Severity.Medium));
        findings.AddRange(WheaFindings(events));
        findings.AddRange(CountedFinding(events.Where(e => e.Is(CrashEvents.Display, 4101)).ToList(),
            "M5.tdr", "m5.tdr", n => n >= 3 ? Severity.Medium : Severity.Low, Confidence.Confirmed));
        findings.AddRange(CountedFinding(events.Where(e => e.Is(CrashEvents.ProcessorPower, 37)).ToList(),
            "M5.firmwareLimit", "m5.firmwareLimit", _ => Severity.Info, Confidence.Confirmed));
        findings.AddRange(StorageFindings(events));
        findings.AddRange(ServiceFindings(events));
        findings.AddRange(AppFindings(events));

        var suppressed = events.Count(IsBenignWudfRd);
        if (suppressed > 0)
        {
            checks.Add(new CheckResult("M5.suppressed", new Text("m5.check.suppressed"), CheckStatus.Info,
                new Text("m5.check.suppressed.detail", suppressed), FindingSource.EventLog));
        }

        checks.Add(s.Stability is { } st
            ? new CheckResult("M5.stability", new Text("m5.check.stability"), CheckStatus.Info,
                new Text("m5.check.stability.detail", st.Index.ToString("0.0", CultureInfo.InvariantCulture), st.Time), FindingSource.Wmi)
            : Checks.NotAvailable("M5.stability", new Text("m5.check.stability"), new Text("m5.check.stability.none")));
        checks.Add(Checks.NotBuiltYet("M5.dumpAnalysis", new Text("m5.check.dumpAnalysis"), "P2"));

        return new ModuleResult
        {
            ModuleId = ModuleId,
            ModuleName = new Text("m5.name"),
            Checks = checks,
            Findings = findings,
        };
    }

    private static void AnalyzeDumpConfig(CrashSnapshot s, List<CheckResult> checks, List<Finding> findings)
    {
        var title = new Text("m5.check.dumpConfig");
        if (s.DumpConfig is not { } cfg)
        {
            checks.Add(Checks.NotAvailable("M5.dumpConfig", title));
        }
        else
        {
            var mode = cfg.CrashDumpEnabled ?? -1;
            var modeKey = mode switch
            {
                0 => "m5.dumpMode.none",
                1 => "m5.dumpMode.complete",
                2 => "m5.dumpMode.kernel",
                3 => "m5.dumpMode.small",
                7 => "m5.dumpMode.automatic",
                _ => "m5.dumpMode.unknown",
            };
            checks.Add(new CheckResult("M5.dumpConfig", title, mode == 0 ? CheckStatus.Warn : CheckStatus.Pass,
                new Text(modeKey), FindingSource.Registry));
            if (mode == 0)
            {
                findings.Add(new Finding
                {
                    Id = "M5.dumpsDisabled",
                    Module = ModuleId,
                    Severity = Severity.Medium,
                    Confidence = Confidence.Confirmed,
                    Source = FindingSource.Registry,
                    Title = new Text("m5.dumpsDisabled.title"),
                    WhyItMatters = new Text("m5.dumpsDisabled.why"),
                    Evidence = [new Evidence(@"HKLM\SYSTEM\CurrentControlSet\Control\CrashControl\CrashDumpEnabled", "0", EvidenceKind.RegistryValue)],
                    SuggestedAction = new Text("m5.dumpsDisabled.action"),
                    Undo = UndoInfo.Reversible(new Text("m5.dumpsDisabled.undo")),
                    FixId = "crash.dumps.automatic",
                });
            }
            else if (s.HasPagefile == false)
            {
                findings.Add(new Finding
                {
                    Id = "M5.noPagefile",
                    Module = ModuleId,
                    Severity = Severity.Low,
                    Confidence = Confidence.Probable,
                    Source = FindingSource.Wmi,
                    Title = new Text("m5.noPagefile.title"),
                    WhyItMatters = new Text("m5.noPagefile.why"),
                    Evidence = [new Evidence("Win32_PageFileUsage", "0 instances")],
                    SuggestedAction = new Text("m5.noPagefile.action"),
                    Undo = UndoInfo.NothingChanged,
                });
            }
        }

        var failedDumps = s.Events.Where(e => e.Is(CrashEvents.Volmgr, 161)).ToList();
        if (failedDumps.Count > 0)
        {
            findings.Add(new Finding
            {
                Id = "M5.dumpFailed",
                Module = ModuleId,
                Severity = Severity.Medium,
                Confidence = Confidence.Confirmed,
                Source = FindingSource.EventLog,
                Title = new Text("m5.dumpFailed.title", failedDumps.Count),
                WhyItMatters = new Text("m5.dumpFailed.why"),
                Evidence = EventEvidence(failedDumps),
                SuggestedAction = new Text("m5.dumpFailed.action"),
                Undo = UndoInfo.NothingChanged,
            });
        }

        checks.Add(s.Dumps.Count > 0
            ? new CheckResult("M5.dumps", new Text("m5.check.dumps"), CheckStatus.Info,
                new Text("m5.check.dumps.detail", s.Dumps.Count, s.Dumps.Max(d => d.LastWriteUtc)), FindingSource.Registry)
            : Checks.NotAvailable("M5.dumps", new Text("m5.check.dumps"), new Text("m5.check.dumps.none")));
    }

    /// <summary>
    /// Kernel-Power 41 stores BugcheckCode in decimal (159 = 0x9F). BugcheckCode != 0 is a blue
    /// screen; PowerButtonTimestamp != 0 means the user held the power button on a frozen PC; both
    /// zero means power was lost or the PC hung hard. A BugCheck 1001 within the merge window is the
    /// same stop and supplies the parameters and dump path.
    /// </summary>
    public static IReadOnlyList<CrashIncident> BuildIncidents(IReadOnlyList<EventRecordData> events)
    {
        var incidents = new List<CrashIncident>();
        var bugchecks = events.Where(e => e.Is(CrashEvents.BugCheck, 1001)).ToList();
        var used1001 = new HashSet<EventRecordData>();

        foreach (var kp in events.Where(e => e.Is(CrashEvents.KernelPower, 41)))
        {
            var code = (uint)(kp.GetLong("BugcheckCode") ?? 0);
            var button = kp.GetLong("PowerButtonTimestamp") ?? 0;
            var related = new List<EventRecordData> { kp };
            uint? bugcheck = code != 0 ? code : null;
            string[] parameters = code != 0
                ? Enumerable.Range(1, 4).Select(i => kp.Get($"BugcheckParameter{i}") ?? "").ToArray()
                : [];
            string? dump = null;

            var match = bugchecks.FirstOrDefault(b => !used1001.Contains(b) && Near(b.TimeCreated, kp.TimeCreated));
            if (match is not null && ParseBugCheck1001(match) is { } parsed && (bugcheck is null || bugcheck == parsed.Code))
            {
                used1001.Add(match);
                related.Add(match);
                bugcheck = parsed.Code;
                parameters = parsed.Parameters;
                dump = parsed.DumpPath;
            }
            related.AddRange(events.Where(e => e.Is(CrashEvents.EventLog, 6008) && Near(e.TimeCreated, kp.TimeCreated)));

            var kind = bugcheck is not null ? CrashKind.BlueScreen
                : button != 0 ? CrashKind.ForcedOff
                : CrashKind.PowerLossOrHang;
            incidents.Add(new CrashIncident(kp.TimeCreated, kind, bugcheck, parameters, dump, related,
                PrecedingSignals(events, kp.TimeCreated)));
        }

        // A 1001 without a Kernel-Power 41 nearby (for example the PC rebooted cleanly after the dump).
        foreach (var b in bugchecks.Where(b => !used1001.Contains(b)))
        {
            if (ParseBugCheck1001(b) is { } parsed)
            {
                incidents.Add(new CrashIncident(b.TimeCreated, CrashKind.BlueScreen, parsed.Code, parsed.Parameters,
                    parsed.DumpPath, [b], PrecedingSignals(events, b.TimeCreated)));
            }
        }
        return incidents.OrderBy(i => i.Time).ToList();
    }

    [GeneratedRegex(@"0x([0-9a-fA-F]+)\s*\(([^)]*)\)")]
    private static partial Regex BugCheckParam1();

    /// <summary>
    /// BugCheck 1001: param1 is "0x0000009f (0x…, 0x…, 0x…, 0x…)", param2 the dump path.
    /// VERIFY: data names (param1/param2) on 22H2–25H2; positional fallback covers unnamed data.
    /// </summary>
    public static (uint Code, string[] Parameters, string? DumpPath)? ParseBugCheck1001(EventRecordData e)
    {
        var p1 = e.Get("param1", 0);
        if (p1 is null)
        {
            return null;
        }
        var m = BugCheckParam1().Match(p1);
        if (!m.Success || !uint.TryParse(m.Groups[1].Value, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var code))
        {
            return null;
        }
        var parameters = m.Groups[2].Value.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
        var dump = e.Get("param2", 1);
        return (code, parameters, string.IsNullOrWhiteSpace(dump) ? null : dump);
    }

    /// <summary>Signals in the 10 minutes before a stop that explain a freeze: TDRs, storage resets, live kernel events.</summary>
    private static List<EventRecordData> PrecedingSignals(IReadOnlyList<EventRecordData> events, DateTimeOffset t) =>
        events.Where(e => e.TimeCreated < t && t - e.TimeCreated <= MergeWindow &&
                          (e.Is(CrashEvents.Display, 4101) || e.Is(CrashEvents.Storport, 129) ||
                           e.Is(CrashEvents.Whea, 18) || e.Is(CrashEvents.Whea, 17) || e.Is(CrashEvents.Whea, 19) ||
                           IsLiveKernelEvent(e)))
              .ToList();

    /// <summary>WER 1001 with event name LiveKernelEvent (117 = TDR, 141 = GPU engine timeout). VERIFY positions.</summary>
    private static bool IsLiveKernelEvent(EventRecordData e) =>
        e.Is(CrashEvents.Wer, 1001) && string.Equals(e.Get("#2"), "LiveKernelEvent", StringComparison.OrdinalIgnoreCase);

    private static bool Near(DateTimeOffset a, DateTimeOffset b) => (a - b).Duration() <= MergeWindow;

    private static IEnumerable<Finding> BlueScreenFindings(IReadOnlyList<CrashIncident> incidents, TimeSpan window)
    {
        var blue = incidents.Where(i => i.Kind == CrashKind.BlueScreen).ToList();
        foreach (var cluster in blue.GroupBy(i => i.BugcheckCode!.Value).OrderByDescending(g => g.Count()))
        {
            var code = cluster.Key;
            var hex = BugcheckKnowledgeBase.Format(code);
            var kb = BugcheckKnowledgeBase.Find(code);
            var latest = cluster.Last();
            var evidence = new List<Evidence>();
            foreach (var i in cluster.TakeLast(5))
            {
                evidence.Add(new Evidence(Loc(i.Time), $"{hex} ({string.Join(", ", i.Parameters)})"));
                if (i.DumpPath is not null)
                {
                    evidence.Add(new Evidence("Dump", i.DumpPath, EvidenceKind.Path));
                }
            }
            evidence.Add(new Evidence("Event XML", latest.Events[0].Xml, EvidenceKind.EventXml));

            yield return new Finding
            {
                Id = $"M5.bsod.{hex}",
                Module = ModuleId,
                Severity = cluster.Count() >= 2 ? Severity.High : Severity.Medium,
                // Windows recorded the stop code (confirmed); the cause below is the usual one for this code.
                Confidence = Confidence.Possible,
                Source = FindingSource.EventLog,
                Title = new Text("m5.bsod.title", cluster.Count(), blue.Count, (int)window.TotalDays, hex, kb?.Name ?? "?"),
                WhyItMatters = kb is null ? new Text("m5.bsod.why.unknown") : new Text($"kb.{hex}.cause"),
                Evidence = evidence,
                SuggestedAction = kb is null ? new Text("m5.bsod.action.unknown") : new Text($"kb.{hex}.next"),
                Undo = UndoInfo.NothingChanged,
            };
        }
    }

    private static IEnumerable<Finding> StopFindings(IReadOnlyList<CrashIncident> incidents, CrashKind kind, string id, string key, Severity severity)
    {
        var list = incidents.Where(i => i.Kind == kind).ToList();
        if (list.Count == 0)
        {
            yield break;
        }
        var preceding = list.SelectMany(i => i.Preceding).Distinct().ToList();
        var evidence = list.TakeLast(5).Select(i => new Evidence(Loc(i.Time),
            $"Kernel-Power 41 BugcheckCode={i.Events[0].Get("BugcheckCode")} PowerButtonTimestamp={i.Events[0].Get("PowerButtonTimestamp")}")).ToList();
        evidence.AddRange(preceding.Take(5).Select(p => new Evidence(Loc(p.TimeCreated), $"{p.Provider} {p.EventId}")));
        yield return new Finding
        {
            Id = id,
            Module = ModuleId,
            Severity = severity,
            Confidence = Confidence.Confirmed,
            Source = FindingSource.EventLog,
            Title = new Text(key + ".title", list.Count),
            WhyItMatters = new Text(key + ".why"),
            Evidence = evidence,
            SuggestedAction = preceding.Count > 0 ? new Text(key + ".action.related", preceding.Count) : new Text(key + ".action"),
            Undo = UndoInfo.NothingChanged,
        };
    }

    [GeneratedRegex(@"PCI\\VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4}", RegexOptions.IgnoreCase)]
    private static partial Regex PciId();

    private static IEnumerable<Finding> WheaFindings(IReadOnlyList<EventRecordData> events)
    {
        var fatal = events.Where(e => e.Is(CrashEvents.Whea, 18)).ToList();
        if (fatal.Count > 0)
        {
            yield return new Finding
            {
                Id = "M5.wheaFatal",
                Module = ModuleId,
                Severity = Severity.High,
                Confidence = Confidence.Confirmed,
                Source = FindingSource.EventLog,
                Title = new Text("m5.wheaFatal.title", fatal.Count),
                WhyItMatters = new Text("m5.wheaFatal.why"),
                Evidence = EventEvidence(fatal),
                SuggestedAction = new Text("kb.0x124.next"),
                Undo = UndoInfo.NothingChanged,
            };
        }

        foreach (var group in events.Where(e => e.Is(CrashEvents.Whea, 17))
                     .GroupBy(e => PciId().Match(string.Join(" ", e.Data.Values)) is { Success: true } m ? m.Value.ToUpperInvariant() : "?"))
        {
            var n = group.Count();
            yield return new Finding
            {
                Id = $"M5.wheaPcie.{group.Key}",
                Module = ModuleId,
                Severity = n >= 10 ? Severity.Medium : Severity.Low,
                Confidence = Confidence.Confirmed,
                Source = FindingSource.EventLog,
                Title = new Text("m5.wheaPcie.title", n, group.Key),
                WhyItMatters = new Text("m5.wheaPcie.why"),
                Evidence = EventEvidence(group.ToList()),
                SuggestedAction = new Text("m5.wheaPcie.action"),
                Undo = UndoInfo.NothingChanged,
            };
        }

        var corrected = events.Where(e => e.Is(CrashEvents.Whea, 19) || e.Is(CrashEvents.Whea, 47)).ToList();
        if (corrected.Count > 0)
        {
            yield return new Finding
            {
                Id = "M5.wheaCorrected",
                Module = ModuleId,
                Severity = corrected.Count >= 10 ? Severity.Medium : Severity.Low,
                Confidence = Confidence.Confirmed,
                Source = FindingSource.EventLog,
                Title = new Text("m5.wheaCorrected.title", corrected.Count),
                WhyItMatters = new Text("m5.wheaCorrected.why"),
                Evidence = EventEvidence(corrected),
                SuggestedAction = new Text("kb.0x124.next"),
                Undo = UndoInfo.NothingChanged,
            };
        }
    }

    private static IEnumerable<Finding> StorageFindings(IReadOnlyList<EventRecordData> events)
    {
        (string Provider, int Id, Severity Severity)[] rules =
        [
            (CrashEvents.Disk, 7, Severity.High),
            (CrashEvents.Disk, 11, Severity.Medium),
            (CrashEvents.Disk, 51, Severity.Medium),
            (CrashEvents.Ntfs, 55, Severity.High),
            (CrashEvents.Ntfs, 98, Severity.High),
            (CrashEvents.Ntfs, 50, Severity.Medium),
            (CrashEvents.Ntfs, 140, Severity.Low),
            (CrashEvents.Storport, 129, Severity.Medium),
            (CrashEvents.Storport, 153, Severity.Medium),
            (CrashEvents.Classpnp, 157, Severity.Low),
            (CrashEvents.Disk, 157, Severity.Low),
        ];
        foreach (var (provider, id, severity) in rules)
        {
            var list = events.Where(e => e.Is(provider, id)).ToList();
            if (list.Count == 0)
            {
                continue;
            }
            var key = $"m5.storage.{(provider == CrashEvents.Classpnp ? "disk" : provider.Split('-').Last().ToLowerInvariant())}{id}";
            yield return new Finding
            {
                Id = $"M5.storage.{provider}.{id}",
                Module = ModuleId,
                Severity = severity,
                Confidence = Confidence.Confirmed,
                Source = FindingSource.EventLog,
                Title = new Text(key + ".title", list.Count),
                WhyItMatters = new Text(key + ".why"),
                Evidence = EventEvidence(list),
                SuggestedAction = new Text(severity >= Severity.High ? "m5.storage.action.backup" : "m5.storage.action"),
                Undo = UndoInfo.NothingChanged,
            };
        }
    }

    private static IEnumerable<Finding> ServiceFindings(IReadOnlyList<EventRecordData> events)
    {
        var crashed = events.Where(e => e.Is(CrashEvents.Scm, 7031) || e.Is(CrashEvents.Scm, 7034))
            .GroupBy(e => e.Get("param1", 0) ?? "?");
        foreach (var g in crashed)
        {
            var n = g.Count();
            yield return new Finding
            {
                Id = $"M5.serviceCrash.{g.Key}",
                Module = ModuleId,
                Severity = n >= 3 ? Severity.Medium : Severity.Low,
                Confidence = Confidence.Confirmed,
                Source = FindingSource.EventLog,
                Title = new Text("m5.serviceCrash.title", g.Key, n),
                WhyItMatters = new Text("m5.serviceCrash.why"),
                Evidence = EventEvidence(g.ToList()),
                SuggestedAction = new Text("m5.serviceCrash.action"),
                Undo = UndoInfo.NothingChanged,
            };
        }

        // Start failures are noisy on healthy PCs; one grouped informational finding.
        var failed = events.Where(e => e.Is(CrashEvents.Scm, 7000) || e.Is(CrashEvents.Scm, 7009) || e.Is(CrashEvents.Scm, 7011))
            .GroupBy(e => e.Get("param1", 0) ?? "?").ToList();
        if (failed.Count > 0)
        {
            yield return new Finding
            {
                Id = "M5.serviceStart",
                Module = ModuleId,
                Severity = Severity.Info,
                Confidence = Confidence.Confirmed,
                Source = FindingSource.EventLog,
                Title = new Text("m5.serviceStart.title", failed.Count),
                WhyItMatters = new Text("m5.serviceStart.why"),
                Evidence = failed.Select(g => new Evidence(g.Key, $"{g.Count()} × (7000/7009/7011), last {Loc(g.Max(e => e.TimeCreated))}")).ToList(),
                SuggestedAction = new Text("m5.serviceStart.action"),
                Undo = UndoInfo.NothingChanged,
            };
        }
    }

    private static IEnumerable<Finding> AppFindings(IReadOnlyList<EventRecordData> events)
    {
        // Application Error 1000 / Application Hang 1002: AppName is data #0 on every build. VERIFY 1026 layout.
        var apps = events.Where(e => e.Is(CrashEvents.AppError, 1000) || e.Is(CrashEvents.AppHang, 1002) || e.Is(CrashEvents.DotNet, 1026))
            .GroupBy(e => AppName(e), StringComparer.OrdinalIgnoreCase);
        foreach (var g in apps.Where(g => g.Count() >= 2).OrderByDescending(g => g.Count()))
        {
            var hangs = g.Count(e => e.EventId == 1002);
            yield return new Finding
            {
                Id = $"M5.app.{g.Key}",
                Module = ModuleId,
                Severity = g.Count() >= 5 ? Severity.Low : Severity.Info,
                Confidence = Confidence.Confirmed,
                Source = FindingSource.EventLog,
                Title = new Text("m5.app.title", g.Key, g.Count() - hangs, hangs),
                WhyItMatters = new Text("m5.app.why"),
                Evidence = g.TakeLast(5).Select(e => new Evidence(Loc(e.TimeCreated),
                    $"{e.Provider} {e.EventId}: module={e.Get("ModuleName", 3) ?? "?"} exception={e.Get("ExceptionCode", 6) ?? "?"}")).ToList(),
                SuggestedAction = new Text("m5.app.action"),
                Undo = UndoInfo.NothingChanged,
            };
        }
    }

    private static string AppName(EventRecordData e)
    {
        if (e.EventId == 1026)
        {
            // .NET 1026 message text: "Application: foo.exe\nFramework Version: …"
            var text = e.Get("#0") ?? "";
            var line = text.Split('\n').FirstOrDefault(l => l.StartsWith("Application:", StringComparison.OrdinalIgnoreCase));
            return line?["Application:".Length..].Trim() ?? "?";
        }
        return e.Get("AppName", 0) ?? "?";
    }

    /// <summary>Kernel-PnP 219 for \Driver\WudfRd during boot is a known benign timing message.</summary>
    public static bool IsBenignWudfRd(EventRecordData e) =>
        e.Is(CrashEvents.KernelPnp, 219) && e.Xml.Contains(@"\Driver\WudfRd", StringComparison.OrdinalIgnoreCase);

    private static IEnumerable<Finding> CountedFinding(List<EventRecordData> list, string id, string key,
        Func<int, Severity> severity, Confidence confidence)
    {
        if (list.Count == 0)
        {
            yield break;
        }
        yield return new Finding
        {
            Id = id,
            Module = ModuleId,
            Severity = severity(list.Count),
            Confidence = confidence,
            Source = FindingSource.EventLog,
            Title = new Text(key + ".title", list.Count),
            WhyItMatters = new Text(key + ".why"),
            Evidence = EventEvidence(list),
            SuggestedAction = new Text(key + ".action"),
            Undo = UndoInfo.NothingChanged,
        };
    }

    private static List<Evidence> EventEvidence(IReadOnlyList<EventRecordData> list)
    {
        var evidence = list.TakeLast(5).Select(e => new Evidence(Loc(e.TimeCreated), $"{e.Provider} {e.EventId}")).ToList();
        if (list.Count > 5)
        {
            evidence.Insert(0, new Evidence("Total", list.Count.ToString(CultureInfo.InvariantCulture)));
        }
        evidence.Add(new Evidence("Event XML", list[^1].Xml, EvidenceKind.EventXml));
        return evidence;
    }

    private static string Loc(DateTimeOffset t) => t.ToString("yyyy-MM-dd HH:mm 'UTC'", CultureInfo.InvariantCulture);
}
