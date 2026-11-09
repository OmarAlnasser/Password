using PcDoctor.Core.Ipc;

namespace PcDoctor.Broker;

/// <summary>Repair jobs (DISM, SFC, chkdsk). Filled in by phase P4.</summary>
internal static class BrokerRepairs
{
    public static Task<object?> Run(JobKind kind, IJobProgress progress, CancellationToken ct) =>
        throw new NotSupportedException($"{kind} is not available in this build.");
}

/// <summary>Debloat tweaks. Filled in by phase P6.</summary>
internal static class BrokerTweaks
{
    public static IReadOnlyList<PcDoctor.Core.Journal.PlannedChange>? Resolve(IReadOnlyList<string> ids) => null;
}
