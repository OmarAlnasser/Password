using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using Microsoft.Diagnostics.Tracing;
using Microsoft.Diagnostics.Tracing.Parsers;
using Microsoft.Diagnostics.Tracing.Parsers.Kernel;
using Microsoft.Diagnostics.Tracing.Session;
using PcDoctor.Core.Events;
using PcDoctor.Core.Platform;

namespace PcDoctor.Bench;

/// <summary>Background load counters through PDH with their English names, so they work on any Windows language.</summary>
[SupportedOSPlatform("windows")]
public static partial class Pdh
{
    public static Dictionary<string, double> Sample(TimeSpan interval, params string[] englishPaths)
    {
        var result = new Dictionary<string, double>();
        if (PdhOpenQueryW(null, IntPtr.Zero, out var query) != 0)
        {
            return result;
        }
        try
        {
            var counters = new Dictionary<string, IntPtr>();
            foreach (var p in englishPaths)
            {
                if (PdhAddEnglishCounterW(query, p, IntPtr.Zero, out var c) == 0)
                {
                    counters[p] = c;
                }
            }
            PdhCollectQueryData(query);
            Thread.Sleep(interval);
            PdhCollectQueryData(query);
            foreach (var (path, c) in counters)
            {
                if (PdhGetFormattedCounterValue(c, 0x00000200 /* PDH_FMT_DOUBLE */, IntPtr.Zero, out var v) == 0)
                {
                    result[path] = v.DoubleValue;
                }
            }
        }
        finally
        {
            PdhCloseQuery(query);
        }
        return result;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct PDH_FMT_COUNTERVALUE
    {
        [FieldOffset(0)] public uint CStatus;
        [FieldOffset(8)] public double DoubleValue;
    }

    [LibraryImport("pdh.dll", StringMarshalling = StringMarshalling.Utf16)]
    private static partial int PdhOpenQueryW(string? source, IntPtr user, out IntPtr query);

    [LibraryImport("pdh.dll", StringMarshalling = StringMarshalling.Utf16)]
    private static partial int PdhAddEnglishCounterW(IntPtr query, string path, IntPtr user, out IntPtr counter);

    [LibraryImport("pdh.dll")]
    private static partial int PdhCollectQueryData(IntPtr query);

    [LibraryImport("pdh.dll")]
    private static partial int PdhGetFormattedCounterValue(IntPtr counter, uint format, IntPtr type, out PDH_FMT_COUNTERVALUE value);

    [LibraryImport("pdh.dll")]
    private static partial int PdhCloseQuery(IntPtr query);
}

[SupportedOSPlatform("windows")]
public static class WindowsBench
{
    public static double IdleCpuPercent() =>
        Pdh.Sample(TimeSpan.FromSeconds(3), @"\Processor(_Total)\% Processor Time").GetValueOrDefault(@"\Processor(_Total)\% Processor Time", double.NaN);

    /// <summary>Commit charge (MB), process count and % DPC time: the background load that tweaks claim to reduce.</summary>
    public static (double CommitMb, double Processes, double DpcPercent) BackgroundLoad()
    {
        var s = Pdh.Sample(TimeSpan.FromSeconds(2), @"\Memory\Committed Bytes", @"\System\Processes", @"\Processor(_Total)\% DPC Time");
        return (s.GetValueOrDefault(@"\Memory\Committed Bytes") / 1_048_576, s.GetValueOrDefault(@"\System\Processes"), s.GetValueOrDefault(@"\Processor(_Total)\% DPC Time"));
    }

    /// <summary>Boots from Diagnostics-Performance event 100, with the boot type from the nearest Kernel-Boot 27 before it.</summary>
    public static List<BootSample> BootHistory(IEventSource events)
    {
        var perf = events.Read(new EventQuery("Microsoft-Windows-Diagnostics-Performance/Operational",
            [("Microsoft-Windows-Diagnostics-Performance", [100])], TimeSpan.FromDays(120), 60));
        var kb = events.Read(new EventQuery("System", [("Microsoft-Windows-Kernel-Boot", [27])], TimeSpan.FromDays(120), 200));
        return perf.Select(e =>
        {
            var type = kb.Where(k => k.TimeCreated <= e.TimeCreated).OrderByDescending(k => k.TimeCreated).FirstOrDefault()?.GetLong("BootType") ?? -1;
            return new BootSample(e.TimeCreated, e.GetLong("MainPathBootTime") ?? 0, e.GetLong("BootPostBootTime") ?? 0, e.GetLong("BootTime") ?? 0,
                (e.GetLong("IsDegradation") ?? 0) != 0, (int)type);
        }).Where(b => b.TotalMs > 0).OrderBy(b => b.Time).ToList();
    }

    /// <summary>DiskSpd on a 1 GB temporary file (never a raw disk), deleted afterwards.</summary>
    public static async Task<Dictionary<string, double>> DiskAsync(string diskspd, CancellationToken ct)
    {
        var file = Path.Combine(Path.GetTempPath(), $"pcdoctor-diskspd-{Guid.NewGuid():N}.dat");
        var result = new Dictionary<string, double>();
        try
        {
            foreach (var (name, args) in DiskSpdParser.Profiles(file))
            {
                var r = await ProcessRunner.RunTrustedPathAsync(diskspd, args, TimeSpan.FromMinutes(2), ct);
                var parsed = DiskSpdParser.Parse(r.StdOut);
                switch (name)
                {
                    case "seqRead": result[MetricInfo.DiskSeqRead.Id] = parsed.MegabytesPerSecond; break;
                    case "randRead": result[MetricInfo.DiskRandRead.Id] = parsed.Iops; break;
                    case "randLatency": result[MetricInfo.DiskRandLatency.Id] = parsed.AverageLatencyMs; break;
                }
            }
        }
        finally
        {
            File.Delete(file);
        }
        return result;
    }

    /// <summary>One PresentMon capture of a running game (5 s delay, 60 s).</summary>
    public static async Task<FrameStats> FramesAsync(string presentMon, string process, CancellationToken ct)
    {
        var csv = Path.Combine(Path.GetTempPath(), $"pcdoctor-presentmon-{Guid.NewGuid():N}.csv");
        try
        {
            await ProcessRunner.RunTrustedPathAsync(presentMon, PresentMonParser.Args(process, csv), TimeSpan.FromMinutes(3), ct);
            return File.Exists(csv) ? PresentMonParser.Parse(await File.ReadAllTextAsync(csv, ct)) : new FrameStats(0, 0, 0, 0);
        }
        finally
        {
            File.Delete(csv);
        }
    }
}

public sealed record DriverLatency(string Driver, int Dpcs, int Isrs, double DpcMaxUs, double DpcP99Us, double IsrMaxUs, double IsrP99Us)
{
    /// <summary>Microsoft's guidance: DPCs ≤ 100 µs, ISRs ≤ 25 µs.</summary>
    public bool OverGuidance => DpcMaxUs > 100 || IsrMaxUs > 25;
}

public sealed record LatencyTraceResult(TimeSpan Duration, IReadOnlyList<DriverLatency> Drivers, string? Conflict);

/// <summary>
/// DPC and ISR durations per driver from a kernel ETW session (needs administrator rights, Broker).
/// Routine addresses are mapped to drivers through image-load events. Refuses to start if another
/// kernel logger (LatencyMon, WPR) is running.
/// </summary>
[SupportedOSPlatform("windows")]
public static class LatencyTracer
{
    public static LatencyTraceResult Run(TimeSpan duration, CancellationToken ct)
    {
        if (TraceEventSession.GetActiveSessionNames().Contains(KernelTraceEventParser.KernelSessionName))
        {
            return new LatencyTraceResult(TimeSpan.Zero, [], "kernelLoggerBusy");
        }
        var images = new List<(ulong Base, ulong End, string Name)>();
        var dpc = new Dictionary<string, List<double>>(StringComparer.OrdinalIgnoreCase);
        var isr = new Dictionary<string, List<double>>(StringComparer.OrdinalIgnoreCase);
        string Owner(ulong address)
        {
            foreach (var (b, e, n) in images)
            {
                if (address >= b && address < e)
                {
                    return n;
                }
            }
            return "unknown";
        }

        using var session = new TraceEventSession(KernelTraceEventParser.KernelSessionName);
        session.EnableKernelProvider(KernelTraceEventParser.Keywords.DeferedProcedureCalls | KernelTraceEventParser.Keywords.Interrupt |
                                     KernelTraceEventParser.Keywords.ImageLoad);
        var kernel = session.Source.Kernel;
        void Image(ImageLoadTraceData d) => images.Add((d.ImageBase, d.ImageBase + (ulong)d.ImageSize, Path.GetFileName(d.FileName)));
        kernel.ImageLoad += Image;
        kernel.ImageDCStart += Image;
        kernel.PerfInfoDPC += d => Add(dpc, Owner(d.Routine), d.ElapsedTimeMSec * 1000);
        kernel.PerfInfoThreadedDPC += d => Add(dpc, Owner(d.Routine), d.ElapsedTimeMSec * 1000);
        kernel.PerfInfoTimerDPC += d => Add(dpc, Owner(d.Routine), d.ElapsedTimeMSec * 1000);
        kernel.PerfInfoISR += d => Add(isr, Owner(d.Routine), d.ElapsedTimeMSec * 1000);

        using var stop = new Timer(_ => session.Stop(), null, duration, Timeout.InfiniteTimeSpan);
        using var reg = ct.Register(() => session.Stop());
        session.Source.Process();

        var drivers = dpc.Keys.Union(isr.Keys).Select(n =>
        {
            var d = dpc.GetValueOrDefault(n) ?? [];
            var i = isr.GetValueOrDefault(n) ?? [];
            return new DriverLatency(n, d.Count, i.Count, d.Count > 0 ? d.Max() : 0, d.Count > 0 ? Statistics.Quantile(d, 0.99) : 0,
                i.Count > 0 ? i.Max() : 0, i.Count > 0 ? Statistics.Quantile(i, 0.99) : 0);
        }).OrderByDescending(d => Math.Max(d.DpcMaxUs, d.IsrMaxUs * 4)).Take(40).ToList();
        return new LatencyTraceResult(duration, drivers, null);
    }

    private static void Add(Dictionary<string, List<double>> map, string key, double us)
    {
        if (!map.TryGetValue(key, out var list))
        {
            map[key] = list = [];
        }
        list.Add(us);
    }
}
