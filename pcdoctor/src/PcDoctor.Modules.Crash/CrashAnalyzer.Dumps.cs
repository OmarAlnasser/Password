using System.Globalization;
using PcDoctor.Core.Events;
using PcDoctor.Core.Findings;
using PcDoctor.Core.Scanning;

namespace PcDoctor.Modules.Crash;

public static partial class CrashAnalyzer
{
    /// <summary>Kernel images that appear in many stacks; naming them is a symptom, not a culprit.</summary>
    private static readonly HashSet<string> CoreImages = new(StringComparer.OrdinalIgnoreCase)
    {
        "ntoskrnl.exe", "ntkrnlmp.exe", "ntkrnlpa.exe", "ntkrpamp.exe", "hal.dll", "win32k.sys", "win32kfull.sys", "win32kbase.sys",
    };

    /// <summary>
    /// Links each stop to its dump: by the dump path the BugCheck event named, else the newest dump
    /// written up to two hours before the stop was logged. Dumps that match no event become
    /// incidents of their own (the event log may have been cleared).
    /// </summary>
    internal static IReadOnlyList<CrashIncident> AttachDumps(IReadOnlyList<CrashIncident> incidents, IReadOnlyList<DumpAnalysis>? dumps)
    {
        if (dumps is null || dumps.Count == 0)
        {
            return incidents;
        }
        var used = new HashSet<DumpAnalysis>();
        var result = new List<CrashIncident>();
        foreach (var i in incidents)
        {
            DumpAnalysis? match = null;
            if (i.DumpPath is { } path)
            {
                match = dumps.FirstOrDefault(d => !used.Contains(d) &&
                    string.Equals(Path.GetFileName(d.Path), Path.GetFileName(path), StringComparison.OrdinalIgnoreCase));
            }
            if (match is null && i.Kind == CrashKind.BlueScreen)
            {
                match = dumps.Where(d => !used.Contains(d) && d.LastWriteUtc <= i.Time.AddMinutes(1) && i.Time - d.LastWriteUtc <= TimeSpan.FromHours(2))
                    .OrderByDescending(d => d.LastWriteUtc).FirstOrDefault();
            }
            if (match is not null)
            {
                used.Add(match);
                var code = i.BugcheckCode ?? match.Analyze?.BugcheckCode ?? match.Header?.BugcheckCode;
                result.Add(i with { Dump = match, BugcheckCode = code, Kind = code is > 0 ? CrashKind.BlueScreen : i.Kind });
            }
            else
            {
                result.Add(i);
            }
        }
        foreach (var d in dumps.Where(d => !used.Contains(d)))
        {
            var code = d.Analyze?.BugcheckCode ?? d.Header?.BugcheckCode;
            if (code is > 0)
            {
                var parameters = d.Header?.Parameters.Select(p => "0x" + p.ToString("x16", CultureInfo.InvariantCulture)).ToList()
                                 ?? d.Analyze?.Parameters.ToList() ?? [];
                result.Add(new CrashIncident(d.LastWriteUtc, CrashKind.BlueScreen, code, parameters, d.Path, [], []) { Dump = d });
            }
        }
        return result.OrderBy(i => i.Time).ToList();
    }

    /// <summary>The image the debugger blamed, ignoring kernel images that are only where the crash surfaced.</summary>
    public static string? Culprit(AnalyzeResult? a)
    {
        if (a is null)
        {
            return null;
        }
        var image = a.ImageName ?? a.ProbablyCausedBy?.Split(' ', '(')[0];
        if (string.IsNullOrWhiteSpace(image) || image.Equals("Unknown_Image", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }
        return image.Trim();
    }

    /// <summary>
    /// One verdict per blamed driver: "4 of 5 blue screens in 30 days name nvlddmkm.sys (NVIDIA
    /// display driver)". Probable when it repeats and symbols were loaded; Possible otherwise.
    /// </summary>
    private static IEnumerable<Finding> DriverVerdicts(IReadOnlyList<CrashIncident> incidents, TimeSpan window)
    {
        var blue = incidents.Where(i => i.Kind == CrashKind.BlueScreen).ToList();
        var analysed = blue.Where(i => Culprit(i.Dump?.Analyze) is not null).ToList();
        foreach (var group in analysed.GroupBy(i => Culprit(i.Dump!.Analyze)!, StringComparer.OrdinalIgnoreCase).OrderByDescending(g => g.Count()))
        {
            var image = group.Key;
            var n = group.Count();
            var core = CoreImages.Contains(image);
            var symbols = group.All(i => i.Dump!.Analyze!.SymbolsLoaded);
            var info = DriverCatalog.Find(image);
            var codes = string.Join(", ", group.Select(i => i.BugcheckCode is { } c ? BugcheckKnowledgeBase.Format(c) : "?").Distinct());
            var evidence = group.TakeLast(5).Select(i => new Evidence(
                i.Time.ToString("yyyy-MM-dd HH:mm 'UTC'", CultureInfo.InvariantCulture),
                $"{(i.BugcheckCode is { } c ? BugcheckKnowledgeBase.Format(c) : "?")} IMAGE_NAME={i.Dump!.Analyze!.ImageName} MODULE_NAME={i.Dump.Analyze.ModuleName} FAILURE_BUCKET_ID={i.Dump.Analyze.FailureBucketId}"))
                .ToList();
            evidence.Add(new Evidence("Dump", group.Last().Dump!.Path, EvidenceKind.Path));
            if (group.Last().Dump!.Analyze!.Stack.Count > 0)
            {
                evidence.Add(new Evidence("STACK_TEXT", string.Join("\n", group.Last().Dump!.Analyze!.Stack.Take(12)), EvidenceKind.CommandOutput));
            }

            yield return new Finding
            {
                Id = $"M5.culprit.{image.ToLowerInvariant()}",
                Module = ModuleId,
                Severity = core ? Severity.Medium : n >= 2 ? Severity.High : Severity.Medium,
                Confidence = !core && symbols && n >= 2 && n * 2 >= blue.Count ? Confidence.Probable : Confidence.Possible,
                Source = FindingSource.MicrosoftTool,
                Title = core
                    ? new Text("m5.culprit.core.title", n, blue.Count, (int)window.TotalDays, image)
                    : new Text("m5.culprit.title", n, blue.Count, (int)window.TotalDays, image,
                        info is null ? image : Core.Localization.Loc.Get($"driver.{info.Key}.name"), codes),
                WhyItMatters = core
                    ? new Text("m5.culprit.core.why")
                    : info is null ? new Text("m5.culprit.why.unknown") : new Text($"driver.{info.Key}.why"),
                Evidence = evidence,
                SuggestedAction = core
                    ? new Text("m5.culprit.core.action")
                    : info is null ? new Text("m5.culprit.action.unknown", image) : new Text($"driver.{info.Key}.action"),
                Undo = UndoInfo.NothingChanged,
            };
        }
    }

    private static void AnalyzeDumpCoverage(CrashSnapshot s, IReadOnlyList<CrashIncident> incidents, List<CheckResult> checks, List<Finding> findings)
    {
        // Replace the "not built yet" placeholder now that the engine exists.
        checks.RemoveAll(c => c.Id == "M5.dumpAnalysis");
        var title = new Text("m5.check.dumpAnalysis");
        if (s.DumpAnalyses is null)
        {
            checks.Add(Checks.NeedsDeepScan("M5.dumpAnalysis", title));
            return;
        }
        if (s.DumpAnalyses.Count == 0)
        {
            checks.Add(Checks.NotAvailable("M5.dumpAnalysis", title, new Text("m5.check.dumps.none")));
            return;
        }
        var analysed = s.DumpAnalyses.Count(d => d.Analyze is not null);
        var headers = s.DumpAnalyses.Count(d => d.Header is not null);
        checks.Add(new CheckResult("M5.dumpAnalysis", title, CheckStatus.Info,
            s.DebuggerAvailable
                ? new Text("m5.check.dumpAnalysis.debugger", analysed, s.DumpAnalyses.Count)
                : new Text("m5.check.dumpAnalysis.offline", headers, s.DumpAnalyses.Count),
            s.DebuggerAvailable ? FindingSource.MicrosoftTool : FindingSource.Heuristic));

        if (!s.DebuggerAvailable && incidents.Any(i => i.Kind == CrashKind.BlueScreen && i.Dump is not null))
        {
            var names = s.DumpAnalyses.SelectMany(d => d.ModuleNames).Where(n => !n.StartsWith("nt", StringComparison.Ordinal)).Distinct().Take(40);
            findings.Add(new Finding
            {
                Id = "M5.needDebugger",
                Module = ModuleId,
                Severity = Severity.Info,
                Confidence = Confidence.Confirmed,
                Source = FindingSource.Heuristic,
                Title = new Text("m5.needDebugger.title"),
                WhyItMatters = new Text("m5.needDebugger.why"),
                Evidence =
                [
                    .. s.DumpAnalyses.Where(d => d.Header is not null).Take(5).Select(d => new Evidence(Path.GetFileName(d.Path),
                        $"{BugcheckKnowledgeBase.Format(d.Header!.BugcheckCode)} ({string.Join(", ", d.Header.Parameters.Select(p => "0x" + p.ToString("x", CultureInfo.InvariantCulture)))})")),
                    new Evidence("Modules named in the dumps (not a verdict)", string.Join(", ", names)),
                ],
                SuggestedAction = new Text("m5.needDebugger.action"),
                Undo = UndoInfo.NothingChanged,
            });
        }
        foreach (var d in s.DumpAnalyses.Where(d => d.Error is not null).Take(3))
        {
            checks.Add(new CheckResult("M5.dumpError." + Path.GetFileName(d.Path), new Text("m5.check.dumpRead", Path.GetFileName(d.Path)),
                CheckStatus.NotChecked, new Text("check.readFailed", "dump", d.Error!)));
        }
    }

    private static IEnumerable<Finding> WerFindings(IReadOnlyList<WerReport> reports, List<CheckResult> checks)
    {
        if (reports.Count == 0)
        {
            yield break;
        }
        checks.Add(new CheckResult("M5.wer", new Text("m5.check.wer"), CheckStatus.Info, new Text("m5.check.wer.detail", reports.Count),
            FindingSource.MicrosoftTool));
        // LiveKernelEvent 117 / 141: the graphics driver or GPU hung and Windows reset it.
        var gpu = reports.Where(r => r.EventType.Equals("LiveKernelEvent", StringComparison.OrdinalIgnoreCase) &&
                                     r.Signature.Values.Any(v => v is "117" or "141" or "1a1" or "1a8")).ToList();
        if (gpu.Count > 0)
        {
            yield return new Finding
            {
                Id = "M5.liveKernelGpu",
                Module = ModuleId,
                Severity = gpu.Count >= 3 ? Severity.Medium : Severity.Low,
                Confidence = Confidence.Confirmed,
                Source = FindingSource.MicrosoftTool,
                Title = new Text("m5.liveKernelGpu.title", gpu.Count),
                WhyItMatters = new Text("m5.tdr.why"),
                Evidence = gpu.Take(5).Select(r => new Evidence(r.Time?.ToString("yyyy-MM-dd HH:mm 'UTC'", CultureInfo.InvariantCulture) ?? "?",
                    string.Join(" ", r.Signature.Select(kv => $"{kv.Key}={kv.Value}")))).Append(new Evidence("Report", gpu[^1].Path, EvidenceKind.Path)).ToList(),
                SuggestedAction = new Text("m5.tdr.action"),
                Undo = UndoInfo.NothingChanged,
            };
        }
    }

    private static IReadOnlyList<TimelineEntry> BuildTimeline(IReadOnlyList<CrashIncident> incidents, IReadOnlyList<EventRecordData> events)
    {
        var timeline = new List<TimelineEntry>();
        foreach (var i in incidents)
        {
            var culprit = Culprit(i.Dump?.Analyze);
            timeline.Add(i.Kind switch
            {
                CrashKind.BlueScreen => new TimelineEntry(i.Time, Severity.High,
                    new Text("m5.timeline.bsod", i.BugcheckCode is { } c ? BugcheckKnowledgeBase.Format(c) : "?",
                        i.BugcheckCode is { } k ? BugcheckKnowledgeBase.Find(k)?.Name ?? "" : ""),
                    culprit is null ? null : new Text("m5.timeline.culprit", culprit), "bsod"),
                CrashKind.ForcedOff => new TimelineEntry(i.Time, Severity.Medium, new Text("m5.timeline.forced"), null, "forced"),
                _ => new TimelineEntry(i.Time, Severity.Medium, new Text("m5.timeline.power"), null, "power"),
            });
        }
        foreach (var e in events)
        {
            TimelineEntry? entry = e switch
            {
                _ when e.Is(CrashEvents.Whea, 18) => new(e.TimeCreated, Severity.High, new Text("m5.timeline.whea"), null, "hardware"),
                _ when e.Is(CrashEvents.Display, 4101) => new(e.TimeCreated, Severity.Low, new Text("m5.timeline.tdr"), null, "gpu"),
                _ when e.Is(CrashEvents.Disk, 7) || e.Is(CrashEvents.Ntfs, 55) => new(e.TimeCreated, Severity.High, new Text("m5.timeline.disk"), null, "disk"),
                _ when e.Is(CrashEvents.Volmgr, 161) => new(e.TimeCreated, Severity.Medium, new Text("m5.timeline.dumpFailed"), null, "dump"),
                _ => null,
            };
            if (entry is not null)
            {
                timeline.Add(entry);
            }
        }
        return timeline.OrderByDescending(t => t.Time).Take(200).ToList();
    }
}

/// <summary>Common drivers that appear in crash dumps, with plain-language names (bugchecks.json "drivers").</summary>
public sealed record DriverInfo(string Key, IReadOnlyList<string> Files);

public static class DriverCatalog
{
    private static readonly Lazy<IReadOnlyList<DriverInfo>> Drivers = new(Load);

    public static DriverInfo? Find(string image) =>
        Drivers.Value.FirstOrDefault(d => d.Files.Any(f => f.EndsWith('*')
            ? image.StartsWith(f[..^1], StringComparison.OrdinalIgnoreCase)
            : image.Equals(f, StringComparison.OrdinalIgnoreCase)));

    public static IReadOnlyList<DriverInfo> All => Drivers.Value;

    private static IReadOnlyList<DriverInfo> Load()
    {
        BugcheckKnowledgeBase.EnsureRegistered();
        return BugcheckKnowledgeBase.DriverEntries;
    }
}
