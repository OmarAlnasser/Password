using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using PcDoctor.Core.Findings;
using PcDoctor.Core.Scanning;

namespace PcDoctor.Modules.Activity;

/// <summary>One program during the sample. Programs with several processes (browsers) are added up under one name.</summary>
public sealed record ProgramActivity(string Name, int Processes, double CpuPercent, long MemoryBytes, int Handles, int Threads);

public sealed record ActivitySnapshot
{
    public required IReadOnlyList<ProgramActivity> Programs { get; init; }
    public required double SampleSeconds { get; init; }
    public long TotalMemoryBytes { get; init; }
    public long AvailableMemoryBytes { get; init; }
    /// <summary>Processes that could not be read (protected system processes without administrator rights).</summary>
    public int Unreadable { get; init; }
}

/// <summary>
/// M14 "what is using this PC right now". A short sample, so every finding says it is a moment in time:
/// a program busy for three seconds may be doing honest work. Thresholds are heuristics and labelled so.
/// </summary>
public static class ActivityAnalyzer
{
    public const string ModuleId = "M14";
    public const double CpuHogPercent = 50;
    public const double LowMemoryFraction = 0.10;
    public const int HandleLeakCount = 50_000;
    public const double HeavyMemoryFraction = 0.25;
    private const long Gib = 1024L * 1024 * 1024;

    public static ModuleResult Analyze(ActivitySnapshot? s)
    {
        var checks = new List<CheckResult>();
        var findings = new List<Finding>();
        if (s is null || s.Programs.Count == 0)
        {
            checks.Add(Checks.NotAvailable("M14.cpu", new Text("m14.check.cpu")));
            return new ModuleResult { ModuleId = ModuleId, ModuleName = new Text("m14.name"), Checks = checks, Findings = findings };
        }

        var byCpu = s.Programs.OrderByDescending(p => p.CpuPercent).ToList();
        var byMemory = s.Programs.OrderByDescending(p => p.MemoryBytes).ToList();
        var busy = Math.Min(100, Math.Round(s.Programs.Sum(p => p.CpuPercent), 0));
        checks.Add(new CheckResult("M14.cpu", new Text("m14.check.cpu"), busy >= 90 ? CheckStatus.Warn : CheckStatus.Info,
            new Text("m14.cpu.detail", busy, Math.Round(s.SampleSeconds, 0), Top(byCpu.Take(3), p => $"{p.Name} {Math.Round(p.CpuPercent, 0)}%")), FindingSource.Heuristic));

        var memoryKnown = s.TotalMemoryBytes > 0;
        var freeFraction = memoryKnown ? (double)s.AvailableMemoryBytes / s.TotalMemoryBytes : 1;
        if (memoryKnown)
        {
            checks.Add(new CheckResult("M14.memory", new Text("m14.check.memory"), freeFraction < LowMemoryFraction ? CheckStatus.Warn : CheckStatus.Info,
                new Text("m14.memory.detail", Math.Round(100 * (1 - freeFraction), 0), Gb(s.TotalMemoryBytes), Top(byMemory.Take(3), p => $"{p.Name} {Gb(p.MemoryBytes)} GB")),
                FindingSource.Heuristic));
        }
        else
        {
            checks.Add(Checks.NotAvailable("M14.memory", new Text("m14.check.memory")));
        }
        if (s.Unreadable > 0)
        {
            checks.Add(new CheckResult("M14.unreadable", new Text("m14.check.unreadable"), CheckStatus.Info, new Text("m14.unreadable.detail", s.Unreadable), FindingSource.Heuristic));
        }

        foreach (var p in byCpu.Where(p => p.CpuPercent >= CpuHogPercent).Take(3))
        {
            findings.Add(Make($"M14.cpu.{p.Name}", Severity.Medium, "m14.cpuHog", [p.Name, Math.Round(p.CpuPercent, 0), Math.Round(s.SampleSeconds, 0)], Evidence(p, s)));
        }
        if (memoryKnown && freeFraction < LowMemoryFraction)
        {
            findings.Add(Make("M14.memLow", Severity.Medium, "m14.memLow", [Math.Round(100 * freeFraction, 0)],
            [
                new Evidence("Installed memory (GB)", Gb(s.TotalMemoryBytes)),
                new Evidence("Available memory (GB)", Gb(s.AvailableMemoryBytes)),
                .. byMemory.Take(5).Select(p => new Evidence(p.Name, $"{Gb(p.MemoryBytes)} GB in {p.Processes} process(es)")),
            ]));
        }
        foreach (var p in s.Programs.Where(p => p.Handles >= HandleLeakCount * Math.Max(1, p.Processes) && !IsSystem(p.Name)).OrderByDescending(p => p.Handles).Take(3))
        {
            findings.Add(Make($"M14.handles.{p.Name}", Severity.Low, "m14.handles", [p.Name, p.Handles], Evidence(p, s)));
        }
        foreach (var p in byMemory.Where(p => memoryKnown && p.MemoryBytes >= 4 * Gib && p.MemoryBytes >= HeavyMemoryFraction * s.TotalMemoryBytes && !IsSystem(p.Name)).Take(3))
        {
            findings.Add(Make($"M14.memHeavy.{p.Name}", Severity.Low, "m14.memHeavy", [p.Name, Gb(p.MemoryBytes)], Evidence(p, s)));
        }
        return new ModuleResult { ModuleId = ModuleId, ModuleName = new Text("m14.name"), Checks = checks, Findings = findings };
    }

    private static bool IsSystem(string name) => name is "System" or "Memory Compression" or "Registry" or "Secure System" or "Idle";

    private static string Top(IEnumerable<ProgramActivity> programs, Func<ProgramActivity, string> show) => string.Join(", ", programs.Select(show));

    private static string Gb(long bytes) => ((double)bytes / Gib).ToString("0.0", CultureInfo.InvariantCulture);

    private static List<Evidence> Evidence(ProgramActivity p, ActivitySnapshot s) =>
    [
        new("Program", p.Name),
        new("Processes", p.Processes.ToString(CultureInfo.InvariantCulture)),
        new("Processor use during the sample", $"{Math.Round(p.CpuPercent, 1).ToString(CultureInfo.InvariantCulture)}% of the whole PC"),
        new("Memory (GB)", Gb(p.MemoryBytes)),
        new("Handles", p.Handles.ToString(CultureInfo.InvariantCulture)),
        new("Threads", p.Threads.ToString(CultureInfo.InvariantCulture)),
        new("Sample length (s)", Math.Round(s.SampleSeconds, 1).ToString(CultureInfo.InvariantCulture)),
    ];

    private static Finding Make(string id, Severity severity, string key, object[] titleArgs, IReadOnlyList<Evidence> evidence) => new()
    {
        Id = id,
        Module = ModuleId,
        Severity = severity,
        Confidence = Confidence.Possible,
        Source = FindingSource.Heuristic,
        Title = new Text(key + ".title", titleArgs),
        WhyItMatters = new Text(key + ".why"),
        Evidence = evidence,
        SuggestedAction = new Text(key + ".action"),
        Undo = UndoInfo.NothingChanged,
    };
}

/// <summary>
/// Reads every process twice, a few seconds apart, and works out who used the processor in between.
/// Read-only. Every Process object is disposed and nothing is kept between scans, so the reader itself
/// cannot grow in memory however often it runs.
/// </summary>
public static partial class ActivityReader
{
    private sealed record Raw(int Pid, string Name, TimeSpan Cpu, long Memory, int Handles, int Threads);

    public static async Task<ActivitySnapshot> ReadAsync(TimeSpan sample, CancellationToken ct)
    {
        var self = Environment.ProcessId;
        var clock = Stopwatch.StartNew();
        var (first, _) = Capture(self);
        await Task.Delay(sample, ct).ConfigureAwait(false);
        var (second, unreadable) = Capture(self);
        var seconds = Math.Max(0.1, clock.Elapsed.TotalSeconds);
        var cores = Math.Max(1, Environment.ProcessorCount);

        var programs = second.Values
            .GroupBy(p => p.Name, StringComparer.OrdinalIgnoreCase)
            .Select(g => new ProgramActivity(
                g.Key,
                g.Count(),
                // Only processes seen in both readings, with the same name (a process ID can be reused), count towards processor use.
                g.Sum(p => first.TryGetValue(p.Pid, out var before) && before.Name == p.Name
                    ? Math.Max(0, (p.Cpu - before.Cpu).TotalSeconds) / (seconds * cores) * 100
                    : 0),
                g.Sum(p => p.Memory),
                g.Sum(p => p.Handles),
                g.Sum(p => p.Threads)))
            .ToList();
        var (total, available) = OperatingSystem.IsWindows() ? Memory() : (0, 0);
        return new ActivitySnapshot { Programs = programs, SampleSeconds = seconds, TotalMemoryBytes = total, AvailableMemoryBytes = available, Unreadable = unreadable };
    }

    private static (Dictionary<int, Raw> Seen, int Unreadable) Capture(int self)
    {
        var seen = new Dictionary<int, Raw>();
        var unreadable = 0;
        foreach (var p in Process.GetProcesses())
        {
            using (p)
            {
                try
                {
                    if (p.Id == self || p.Id == 0)
                    {
                        continue;
                    }
                    seen[p.Id] = new Raw(p.Id, p.ProcessName, p.TotalProcessorTime, p.PrivateMemorySize64, p.HandleCount, p.Threads.Count);
                }
                catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or InvalidOperationException or NotSupportedException)
                {
                    unreadable++; // exited in between, or protected
                }
            }
        }
        return (seen, unreadable);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MEMORYSTATUSEX
    {
        public uint Length;
        public uint MemoryLoad;
        public ulong TotalPhys;
        public ulong AvailPhys;
        public ulong TotalPageFile;
        public ulong AvailPageFile;
        public ulong TotalVirtual;
        public ulong AvailVirtual;
        public ulong AvailExtendedVirtual;
    }

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX status);

    private static (long Total, long Available) Memory()
    {
        var status = new MEMORYSTATUSEX { Length = (uint)Marshal.SizeOf<MEMORYSTATUSEX>() };
        return GlobalMemoryStatusEx(ref status) ? ((long)status.TotalPhys, (long)status.AvailPhys) : (0, 0);
    }
}

public sealed class ActivityModule : IModule
{
    public string Id => ActivityAnalyzer.ModuleId;
    public Text Name => new("m14.name");

    public async Task<ModuleResult> RunAsync(ScanContext context)
    {
        try
        {
            return ActivityAnalyzer.Analyze(await ActivityReader.ReadAsync(TimeSpan.FromSeconds(3), context.CancellationToken).ConfigureAwait(false));
        }
        catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or InvalidOperationException or PlatformNotSupportedException)
        {
            return ActivityAnalyzer.Analyze(null);
        }
    }
}
