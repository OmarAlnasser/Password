namespace PcDoctor.Core.Findings;

public enum CheckStatus
{
    Pass,
    Warn,
    Fail,
    /// <summary>Informational: reported, no judgement.</summary>
    Info,
    /// <summary>The data does not exist on this PC (no battery, no dumps, no sensor driver).</summary>
    NotAvailable,
    /// <summary>PC Doctor did not look (needs administrator / Deep Scan, or not built yet).</summary>
    NotChecked,
}

/// <summary>
/// One thing a module checked (or could not check). The list of checks is the "what was checked"
/// half of every summary; findings are only the actionable subset.
/// </summary>
public sealed record CheckResult(
    string Id,
    Text Title,
    CheckStatus Status,
    Text? Detail = null,
    FindingSource? Source = null);

public sealed record ModuleResult
{
    public required string ModuleId { get; init; }
    public required Text ModuleName { get; init; }
    public IReadOnlyList<CheckResult> Checks { get; init; } = [];
    public IReadOnlyList<Finding> Findings { get; init; } = [];
}
