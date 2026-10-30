namespace PcDoctor.Core.Findings;

public enum Severity { Info, Low, Medium, High, Critical }

/// <summary>How sure we are. Only evidence that is conclusive on its own is Confirmed.</summary>
public enum Confidence { Confirmed, Probable, Possible }

/// <summary>Where a finding came from. PC Doctor's own heuristics are never presented as an engine verdict.</summary>
public enum FindingSource
{
    Defender,
    MicrosoftTool,
    EventLog,
    Wmi,
    /// <summary>A documented registry value read directly (UAC, Secure Boot state, dump settings).</summary>
    Registry,
    Heuristic,
    VirusTotal,
}

public enum EvidenceKind { Value, Path, RegistryValue, EventXml, CommandOutput }

/// <summary>Raw evidence. Rendered left-to-right in every language and never translated.</summary>
public sealed record Evidence(string Label, string Value, EvidenceKind Kind = EvidenceKind.Value);

public enum UndoKind
{
    /// <summary>The finding only reports something; PC Doctor changed nothing.</summary>
    NothingChanged,
    Reversible,
    NotReversible,
}

public sealed record UndoInfo(UndoKind Kind, Text? Explanation = null)
{
    public static UndoInfo NothingChanged { get; } = new(UndoKind.NothingChanged);
    public static UndoInfo Reversible(Text how) => new(UndoKind.Reversible, how);
    public static UndoInfo NotReversible(Text reason) => new(UndoKind.NotReversible, reason);
}

/// <summary>
/// One actionable result. Every field in the honesty rules is required, so a finding cannot be built
/// without its evidence, its source and an undo statement.
/// </summary>
public sealed record Finding
{
    public required string Id { get; init; }
    public required string Module { get; init; }
    public required Severity Severity { get; init; }
    public required Confidence Confidence { get; init; }
    public required FindingSource Source { get; init; }
    public required Text Title { get; init; }
    public required Text WhyItMatters { get; init; }
    public required IReadOnlyList<Evidence> Evidence { get; init; }
    public required Text SuggestedAction { get; init; }
    public required UndoInfo Undo { get; init; }

    /// <summary>A fix in <see cref="Fixes.FixCatalog"/> the user can apply through the Broker, if any.</summary>
    public string? FixId { get; init; }

    /// <summary>Hidden by default in the dashboard (for example device problem code 45, not connected).</summary>
    public bool HiddenByDefault { get; init; }
}
