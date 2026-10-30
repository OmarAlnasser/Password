using PcDoctor.Core.Findings;
using PcDoctor.Core.Scanning;

namespace PcDoctor.Core.Reporting;

public sealed record ScanReport
{
    public required Guid Id { get; init; }
    public required DateTimeOffset StartedUtc { get; init; }
    public required DateTimeOffset FinishedUtc { get; init; }
    public required ScanConditions Conditions { get; init; }
    public required IReadOnlyList<ModuleResult> Modules { get; init; }

    [System.Text.Json.Serialization.JsonIgnore]
    public IEnumerable<Finding> AllFindings => Modules.SelectMany(m => m.Findings);
    [System.Text.Json.Serialization.JsonIgnore]
    public IEnumerable<CheckResult> AllChecks => Modules.SelectMany(m => m.Checks);
}

/// <summary>
/// Builds the summary lines. It always says what was checked, by what, and what was not, and it
/// always ends with the disclaimer. There is no code path that produces an all-clear message.
/// </summary>
public static class ReportSummary
{
    public static IReadOnlyList<Text> Build(ScanReport report)
    {
        var checks = report.AllChecks.ToList();
        var findings = report.AllFindings.Where(f => !f.HiddenByDefault).ToList();
        var lines = new List<Text>
        {
            new("summary.checked",
                checks.Count(c => c.Status is CheckStatus.Pass or CheckStatus.Warn or CheckStatus.Fail or CheckStatus.Info),
                report.Modules.Count),
            new("summary.notChecked",
                checks.Count(c => c.Status == CheckStatus.NotChecked),
                checks.Count(c => c.Status == CheckStatus.NotAvailable)),
        };

        var bySeverity = findings.GroupBy(f => f.Severity).ToDictionary(g => g.Key, g => g.Count());
        lines.Add(findings.Count == 0
            ? new Text("summary.noActionableFindings")
            : new Text("summary.findings",
                findings.Count,
                bySeverity.GetValueOrDefault(Severity.Critical),
                bySeverity.GetValueOrDefault(Severity.High),
                bySeverity.GetValueOrDefault(Severity.Medium),
                bySeverity.GetValueOrDefault(Severity.Low) + bySeverity.GetValueOrDefault(Severity.Info)));

        if (report.Conditions.Mode == ScanMode.HealthCheck)
        {
            lines.Add(new Text("summary.healthCheckScope"));
        }
        lines.Add(new Text("summary.disclaimer"));
        return lines;
    }
}
