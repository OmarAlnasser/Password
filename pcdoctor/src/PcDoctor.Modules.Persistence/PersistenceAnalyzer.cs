using PcDoctor.Core.Findings;
using PcDoctor.Core.Platform;
using PcDoctor.Core.Scanning;

namespace PcDoctor.Modules.Persistence;

public sealed record PersistenceSnapshot
{
    public IReadOnlyList<AutorunEntry> Entries { get; init; } = [];
    /// <summary>Categories that could not be read, with the reason (e.g. WMI subscriptions need admin).</summary>
    public IReadOnlyDictionary<AutorunCategory, string> Unread { get; init; } = new Dictionary<AutorunCategory, string>();
    public bool VirusTotalEnabled { get; init; }
}

/// <summary>
/// M3, Autoruns-style. Verdict tiers: Microsoft-signed → valid third party (listed, no finding) →
/// signed but invalid, expired or revoked (High) → unsigned (Medium: unsigned is not malicious).
/// Specific locations that are almost never legitimate add their own findings.
/// </summary>
public static class PersistenceAnalyzer
{
    public const string ModuleId = "M3";

    /// <summary>Default values that are not findings.</summary>
    private static readonly HashSet<string> DefaultLsaPackages = new(StringComparer.OrdinalIgnoreCase)
    {
        "", "\"\"", "msv1_0", "kerberos", "schannel", "wdigest", "tspkg", "pku2u", "cloudap", "negoexts", "livessp", "scecli",
        "rassfm", "msoidssp", "mshtml", "relog", "kerberos_ap", "wsauth",
    };

    private static readonly HashSet<string> BenignWmiConsumers = new(StringComparer.OrdinalIgnoreCase)
    {
        "SCM Event Log Consumer", "BVTConsumer", "NTEventLogEventConsumer",
    };

    public static ModuleResult Analyze(PersistenceSnapshot s)
    {
        var checks = new List<CheckResult>();
        var findings = new List<Finding>();

        foreach (var group in s.Entries.GroupBy(e => e.Category).OrderBy(g => g.Key))
        {
            var ms = group.Count(e => e.IsMicrosoft);
            checks.Add(new CheckResult($"M3.{group.Key}", new Text($"m3.cat.{group.Key}"), CheckStatus.Info,
                new Text("m3.check.counts", group.Count(), ms, group.Count() - ms), FindingSource.Heuristic));
        }
        foreach (var (category, reason) in s.Unread)
        {
            checks.Add(new CheckResult($"M3.{category}", new Text($"m3.cat.{category}"), CheckStatus.NotChecked, new Text(reason)));
        }
        if (!s.VirusTotalEnabled)
        {
            checks.Add(new CheckResult("M3.vt", new Text("m3.check.vt"), CheckStatus.NotChecked, new Text("m3.check.vt.off")));
        }

        foreach (var e in s.Entries)
        {
            findings.AddRange(ForEntry(e));
        }
        return new ModuleResult { ModuleId = ModuleId, ModuleName = new Text("m3.name"), Checks = checks, Findings = findings };
    }

    private static IEnumerable<Finding> ForEntry(AutorunEntry e)
    {
        var evidence = Evidence(e);

        // AMSI: the antivirus provider called it malware. Highest signal, stated as the AV's verdict.
        if (e.AmsiResult is >= 32768)
        {
            yield return Make(e, "amsi", Severity.Critical, Confidence.Probable, FindingSource.Defender, evidence, canDisable: true);
            yield break;
        }

        // VirusTotal is a second opinion only: raw counts, 1-2 engines is low confidence.
        if (e.VirusTotal is { Malicious: > 0 } vt)
        {
            yield return Make(e, "vt", vt.Malicious >= 3 ? Severity.High : Severity.Medium,
                vt.Malicious >= 3 ? Confidence.Probable : Confidence.Possible, FindingSource.VirusTotal, evidence, canDisable: true,
                vt.Malicious, vt.Malicious + vt.Suspicious + vt.Undetected + vt.Harmless);
        }

        switch (e.Category)
        {
            case AutorunCategory.Accessibility when !e.IsMicrosoft || e.Command.Length > 0 && e.Detail == "debugger":
                yield return Make(e, "accessibility", Severity.Critical, Confidence.Probable, FindingSource.Registry, evidence, canDisable: false);
                yield break;
            case AutorunCategory.ImageFileExecution:
                yield return Make(e, "ifeo", Severity.High, Confidence.Probable, FindingSource.Registry, evidence, canDisable: false);
                yield break;
            case AutorunCategory.WmiSubscription when !BenignWmiConsumers.Contains(e.Name):
                yield return Make(e, "wmi", Severity.High, Confidence.Probable, FindingSource.Wmi, evidence, canDisable: false);
                yield break;
            case AutorunCategory.AppInit when e.Command.Length > 0:
                yield return Make(e, "appinit", Severity.High, Confidence.Probable, FindingSource.Registry, evidence, canDisable: false);
                yield break;
            case AutorunCategory.Winlogon:
                yield return Make(e, "winlogon", Severity.High, Confidence.Probable, FindingSource.Registry, evidence, canDisable: false);
                yield break;
            case AutorunCategory.BootExecute when !e.Command.Trim().Equals("autocheck autochk *", StringComparison.OrdinalIgnoreCase):
                yield return Make(e, "bootexecute", Severity.Medium, Confidence.Possible, FindingSource.Registry, evidence, canDisable: false);
                yield break;
            case AutorunCategory.Lsa when !DefaultLsaPackages.Contains(e.Command.Trim()) && !e.IsMicrosoft:
                yield return Make(e, "lsa", Severity.High, Confidence.Possible, FindingSource.Registry, evidence, canDisable: false);
                yield break;
            case AutorunCategory.BrowserExtension when e.Detail == "policy":
                yield return Make(e, "forcedExtension", Severity.Medium, Confidence.Possible, FindingSource.Registry, evidence, canDisable: false);
                yield break;
            case AutorunCategory.BrowserExtension:
            case AutorunCategory.OfficeAddin:
            case AutorunCategory.PowerShellProfile when e.AmsiResult is null or < 32768:
                // Listed for review; extensions and add-ins are not signed binaries, so no signature tier.
                yield break;
            case AutorunCategory.ComHijack when e.ImageUserWritable || e.Signature?.Status is SignatureStatus.Unsigned:
                yield return Make(e, "comhijack", Severity.Medium, Confidence.Possible, FindingSource.Registry, evidence, canDisable: false);
                yield break;
        }

        if (e.Category == AutorunCategory.Service && CommandLines.IsUnquotedWithSpaces(e.Command) && !e.IsMicrosoft)
        {
            yield return Make(e, "unquoted", Severity.Medium, Confidence.Confirmed, FindingSource.Registry, evidence, canDisable: false);
        }
        if (e.ImageUserWritable && e.Category is AutorunCategory.Service or AutorunCategory.Driver or AutorunCategory.ScheduledTask)
        {
            yield return Make(e, "writable", Severity.High, Confidence.Confirmed, FindingSource.Heuristic, evidence, canDisable: e.Category != AutorunCategory.Driver);
        }

        switch (e.Signature?.Status)
        {
            case SignatureStatus.Invalid:
                yield return Make(e, "badsig", Severity.High, Confidence.Confirmed, FindingSource.Heuristic, evidence, canDisable: true, e.Signature.Detail ?? "");
                break;
            case SignatureStatus.Unsigned:
                yield return Make(e, "unsigned", Severity.Medium, Confidence.Confirmed, FindingSource.Heuristic, evidence, canDisable: true);
                break;
            case SignatureStatus.NotFound when e.Enabled && e.Category is AutorunCategory.RunKey or AutorunCategory.ScheduledTask or AutorunCategory.Service:
                yield return Make(e, "missing", Severity.Low, Confidence.Confirmed, FindingSource.Heuristic, evidence, canDisable: true);
                break;
        }
    }

    private static List<Evidence> Evidence(AutorunEntry e)
    {
        var list = new List<Evidence>
        {
            new("Location", e.Location, EvidenceKind.RegistryValue),
            new("Entry", e.Name),
            new("Command", e.Command, EvidenceKind.CommandOutput),
        };
        if (e.Image is not null)
        {
            list.Add(new Evidence("Image", e.Image, EvidenceKind.Path));
        }
        if (e.Signature is { } sig)
        {
            list.Add(new Evidence("Signature", $"{sig.Status}{(sig.ViaCatalog ? " (catalog)" : "")} {SignatureVerifier_Display(sig.Publisher)} {sig.Detail}".Trim()));
        }
        if (e.Sha256 is not null)
        {
            list.Add(new Evidence("SHA-256", e.Sha256));
        }
        if (e.VirusTotal is { } vt)
        {
            list.Add(new Evidence("VirusTotal", $"malicious={vt.Malicious} suspicious={vt.Suspicious} undetected={vt.Undetected} harmless={vt.Harmless} ({vt.CheckedUtc.ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture)})"));
        }
        if (e.AmsiResult is { } amsi)
        {
            list.Add(new Evidence("AMSI result", amsi.ToString(System.Globalization.CultureInfo.InvariantCulture)));
        }
        if (e.ScriptText is { Length: > 0 } script)
        {
            list.Add(new Evidence("Script", script.Length > 2000 ? script[..2000] + "…" : script, EvidenceKind.CommandOutput));
        }
        return list;
    }

    private static string SignatureVerifier_Display(string? publisher) => publisher?.Split(" | ")[0] ?? "";

    private static Finding Make(AutorunEntry e, string kind, Severity severity, Confidence confidence, FindingSource source,
        IReadOnlyList<Evidence> evidence, bool canDisable, params object[] extra) => new()
    {
        Id = $"M3.{kind}.{e.Id}",
        Module = ModuleId,
        Severity = severity,
        Confidence = confidence,
        Source = source,
        Title = new Text($"m3.{kind}.title", [e.Name, WinPath.FileName(e.Image ?? e.Command), .. extra]),
        WhyItMatters = new Text($"m3.{kind}.why"),
        Evidence = evidence,
        SuggestedAction = new Text(canDisable && DisablePlanner.CanDisable(e) ? "m3.action.disable" : $"m3.{kind}.action"),
        Undo = canDisable && DisablePlanner.CanDisable(e)
            ? UndoInfo.Reversible(new Text("m3.undo.disable"))
            : UndoInfo.NothingChanged,
        FixId = canDisable && DisablePlanner.CanDisable(e) ? "autorun:" + e.Id : null,
    };
}
