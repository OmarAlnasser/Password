using PcDoctor.Core.Findings;
using PcDoctor.Core.Ipc;

namespace PcDoctor.Core.Scanning;

public enum ScanMode
{
    /// <summary>Read-only, no administrator rights.</summary>
    HealthCheck,
    /// <summary>Also reads data that needs the elevated Broker.</summary>
    DeepScan,
}

/// <summary>Reads administrator-only data through the Broker. Null in a Health Check.</summary>
public interface IElevatedReader
{
    Task<T?> ReadAsync<T>(ElevatedData data, CancellationToken ct);
}

public sealed record ScanContext(
    ScanMode Mode,
    IElevatedReader? Elevated,
    TimeProvider Clock,
    CancellationToken CancellationToken)
{
    public DateTimeOffset Now => Clock.GetUtcNow();
}

public interface IModule
{
    /// <summary>Stable ID, e.g. "M11".</summary>
    string Id { get; }
    Text Name { get; }
    Task<ModuleResult> RunAsync(ScanContext context);
}

/// <summary>Shared helpers for the "not checked" and "not available" rows every module needs.</summary>
public static class Checks
{
    public static CheckResult NeedsDeepScan(string id, Text title) =>
        new(id, title, CheckStatus.NotChecked, new Text("check.needsDeepScan"));

    public static CheckResult NotAvailable(string id, Text title, Text? why = null) =>
        new(id, title, CheckStatus.NotAvailable, why ?? new Text("check.notAvailable"));

    public static CheckResult NotBuiltYet(string id, Text title, string phase) =>
        new(id, title, CheckStatus.NotChecked, new Text("check.notInThisVersion", phase));

    public static CheckResult Failed(string id, Text title, Exception ex) =>
        new(id, title, CheckStatus.NotChecked, new Text("check.readFailed", ex.GetType().Name, ex.Message));
}
