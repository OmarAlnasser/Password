using PcDoctor.Core.Ipc;

namespace PcDoctor.Broker;

/// <summary>Repair jobs (DISM, SFC, chkdsk, offline scan, Driver Verifier).</summary>
internal static class BrokerRepairs
{
    public static Task<object?> Run(JobKind kind, string? target, IJobProgress progress, CancellationToken ct) =>
        PcDoctor.Modules.Integrity.RepairRunner.Run(kind, target, progress, ct);
}

/// <summary>Debloat tweaks. Filled in by phase P6.</summary>
internal static class BrokerTweaks
{
    public static IReadOnlyList<PcDoctor.Core.Journal.PlannedChange>? Resolve(IReadOnlyList<string> ids) => null;
}
