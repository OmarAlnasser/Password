using PcDoctor.Core.Events;

namespace PcDoctor.Modules.Crash;

/// <summary>HKLM\SYSTEM\CurrentControlSet\Control\CrashControl. Null fields were absent.</summary>
public sealed record DumpConfig(int? CrashDumpEnabled, string? MinidumpDir, string? DumpFile, int? AutoReboot);

public enum DumpKind { Minidump, KernelOrComplete, LiveKernel, UserMode }

public sealed record DumpFileInfo(string Path, long SizeBytes, DateTimeOffset LastWriteUtc, DumpKind Kind);

public sealed record StabilityInfo(double Index, DateTimeOffset Time);

public sealed record CrashSnapshot
{
    public DumpConfig? DumpConfig { get; init; }
    /// <summary>Null if it could not be read.</summary>
    public bool? HasPagefile { get; init; }
    public IReadOnlyList<DumpFileInfo> Dumps { get; init; } = [];
    public IReadOnlyList<EventRecordData> Events { get; init; } = [];
    public StabilityInfo? Stability { get; init; }
    public TimeSpan Window { get; init; } = TimeSpan.FromDays(30);
    /// <summary>Null = not read (dump files need administrator rights: Deep Scan).</summary>
    public IReadOnlyList<DumpAnalysis>? DumpAnalyses { get; init; }
    /// <summary>Whether the Windows debugger (cdb.exe) was found when the dumps were read.</summary>
    public bool DebuggerAvailable { get; init; }
    public IReadOnlyList<WerReport> WerReports { get; init; } = [];
}
