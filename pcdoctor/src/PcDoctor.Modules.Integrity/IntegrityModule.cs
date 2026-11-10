using System.Runtime.Versioning;
using PcDoctor.Core.Events;
using PcDoctor.Core.Findings;
using PcDoctor.Core.Ipc;
using PcDoctor.Core.Scanning;

namespace PcDoctor.Modules.Integrity;

public sealed record IntegritySnapshot
{
    /// <summary>Null = not read (needs administrator rights).</summary>
    public bool? SystemVolumeDirty { get; init; }
    public IReadOnlyList<EventRecordData> Events { get; init; } = [];
}

/// <summary>M6 in a scan: the dirty bit, Memory Diagnostic results and recent disk-check runs. Repairs are on demand.</summary>
public static class IntegrityAnalyzer
{
    public const string ModuleId = "M6";
    public const string MemoryResults = "Microsoft-Windows-MemoryDiagnostics-Results";

    public static ModuleResult Analyze(IntegritySnapshot s)
    {
        var checks = new List<CheckResult>();
        var findings = new List<Finding>();

        if (s.SystemVolumeDirty is null)
        {
            checks.Add(Checks.NeedsDeepScan("M6.dirty", new Text("m6.check.dirty")));
        }
        else
        {
            checks.Add(new CheckResult("M6.dirty", new Text("m6.check.dirty"), s.SystemVolumeDirty.Value ? CheckStatus.Warn : CheckStatus.Pass,
                new Text(s.SystemVolumeDirty.Value ? "m6.dirty.yes" : "m6.dirty.no"), FindingSource.MicrosoftTool));
            if (s.SystemVolumeDirty.Value)
            {
                findings.Add(Make("M6.dirty", Severity.Medium, "m6.dirtyFinding", [new Evidence("FSCTL_IS_VOLUME_DIRTY", "VOLUME_IS_DIRTY")]));
            }
        }

        // 1201: no errors; 1202: errors detected; 1101: results reported (message carries the outcome). VERIFY per build.
        var memory = s.Events.Where(e => string.Equals(e.Provider, MemoryResults, StringComparison.OrdinalIgnoreCase)).OrderByDescending(e => e.TimeCreated).ToList();
        if (memory.Count == 0)
        {
            checks.Add(Checks.NotAvailable("M6.memory", new Text("m6.check.memory"), new Text("m6.memory.never")));
        }
        else
        {
            var last = memory[0];
            var errors = last.EventId == 1202;
            checks.Add(new CheckResult("M6.memory", new Text("m6.check.memory"), errors ? CheckStatus.Fail : last.EventId == 1201 ? CheckStatus.Pass : CheckStatus.Info,
                new Text("m6.memory.detail", last.TimeCreated.ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture), last.EventId), FindingSource.EventLog));
            if (errors)
            {
                findings.Add(Make("M6.memoryErrors", Severity.High, "m6.memoryErrors",
                    [new Evidence(last.TimeCreated.ToString("yyyy-MM-dd HH:mm 'UTC'", System.Globalization.CultureInfo.InvariantCulture), $"{last.Provider} {last.EventId}"), new Evidence("Event XML", last.Xml, EvidenceKind.EventXml)]));
            }
        }

        checks.Add(new CheckResult("M6.repairs", new Text("m6.check.repairs"), CheckStatus.NotChecked, new Text("m6.repairs.onDemand")));
        return new ModuleResult { ModuleId = ModuleId, ModuleName = new Text("m6.name"), Checks = checks, Findings = findings };
    }

    private static Finding Make(string id, Severity severity, string key, IReadOnlyList<Evidence> evidence) => new()
    {
        Id = id,
        Module = ModuleId,
        Severity = severity,
        Confidence = Confidence.Confirmed,
        Source = FindingSource.MicrosoftTool,
        Title = new Text(key + ".title"),
        WhyItMatters = new Text(key + ".why"),
        Evidence = evidence,
        SuggestedAction = new Text(key + ".action"),
        Undo = UndoInfo.NothingChanged,
    };
}

public sealed class IntegrityModule(Func<IReadOnlyList<EventRecordData>> events) : IModule
{
    public string Id => IntegrityAnalyzer.ModuleId;
    public Text Name => new("m6.name");

    public async Task<ModuleResult> RunAsync(ScanContext context)
    {
        var list = await Task.Run(events, context.CancellationToken).ConfigureAwait(false);
        bool? dirty = context.Elevated is { } e ? await e.ReadAsync<bool?>(ElevatedData.VolumeDirty, context.CancellationToken).ConfigureAwait(false) : null;
        return IntegrityAnalyzer.Analyze(new IntegritySnapshot { SystemVolumeDirty = dirty, Events = list });
    }

    [SupportedOSPlatform("windows")]
    public static IntegrityModule ForWindows(IEventSource source) => new(() =>
        source.Read(new EventQuery("System", [(IntegrityAnalyzer.MemoryResults, [1101, 1201, 1202])], TimeSpan.FromDays(180), 20)));
}
