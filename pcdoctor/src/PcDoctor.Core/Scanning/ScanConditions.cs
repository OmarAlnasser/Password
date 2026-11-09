namespace PcDoctor.Core.Scanning;

public enum PowerSource { Unknown, AC, Battery }

/// <summary>The conditions a scan or benchmark ran under, recorded in every report.</summary>
public sealed record ScanConditions
{
    public required string AppVersion { get; init; }
    public required string OsProductName { get; init; }
    /// <summary>e.g. 10.0.26100.2314</summary>
    public required string OsBuild { get; init; }
    /// <summary>e.g. 24H2. Empty on builds that do not record it.</summary>
    public required string OsDisplayVersion { get; init; }
    public required string OsEdition { get; init; }
    public required string Architecture { get; init; }
    public required TimeSpan Uptime { get; init; }
    public required PowerSource PowerSource { get; init; }
    public required string PowerPlan { get; init; }
    public required bool Elevated { get; init; }
    public required ScanMode Mode { get; init; }
    public required string UiCulture { get; init; }
    public string MachineName { get; init; } = "";
    public string UserName { get; init; } = "";

    [System.Text.Json.Serialization.JsonIgnore]
    public int BuildNumber =>
        OsBuild.Split('.') is { Length: >= 3 } parts && int.TryParse(parts[2], out var b) ? b : 0;

    [System.Text.Json.Serialization.JsonIgnore]
    public bool IsWindows10 => BuildNumber is > 0 and < 22000;
}

public interface IConditionsReader
{
    ScanConditions Read(ScanMode mode);
}
