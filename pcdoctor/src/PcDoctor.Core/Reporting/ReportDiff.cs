using PcDoctor.Core.Findings;

namespace PcDoctor.Core.Reporting;

public sealed record ReportDifference(
    IReadOnlyList<Finding> New,
    IReadOnlyList<Finding> Resolved,
    IReadOnlyList<Finding> Persisting,
    int CheckedBefore,
    int CheckedAfter);

/// <summary>Compares two scans by finding ID. "Resolved" means not found this time, which can also mean not checked.</summary>
public static class ReportDiff
{
    public static ReportDifference Compare(ScanReport older, ScanReport newer)
    {
        var before = older.AllFindings.Where(f => !f.HiddenByDefault).GroupBy(f => f.Id).ToDictionary(g => g.Key, g => g.First());
        var after = newer.AllFindings.Where(f => !f.HiddenByDefault).GroupBy(f => f.Id).ToDictionary(g => g.Key, g => g.First());
        var checkedIds = newer.AllChecks.Where(c => c.Status is not (CheckStatus.NotChecked or CheckStatus.NotAvailable)).Select(c => c.Id).ToHashSet();
        return new ReportDifference(
            after.Values.Where(f => !before.ContainsKey(f.Id)).OrderByDescending(f => f.Severity).ToList(),
            before.Values.Where(f => !after.ContainsKey(f.Id) && newer.Modules.Any(m => m.ModuleId == f.Module)).OrderByDescending(f => f.Severity).ToList(),
            after.Values.Where(f => before.ContainsKey(f.Id)).OrderByDescending(f => f.Severity).ToList(),
            older.AllChecks.Count(c => c.Status is not (CheckStatus.NotChecked or CheckStatus.NotAvailable)),
            checkedIds.Count);
    }

    /// <summary>What a scheduled scan notifies about: new findings of High or Critical severity only.</summary>
    public static IReadOnlyList<Finding> WorthNotifying(ScanReport? previous, ScanReport current) =>
        (previous is null ? current.AllFindings.Where(f => !f.HiddenByDefault) : Compare(previous, current).New)
            .Where(f => f.Severity >= Severity.High).ToList();
}
