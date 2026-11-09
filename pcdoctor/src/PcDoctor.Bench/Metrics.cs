using System.Diagnostics;
using System.Globalization;
using System.Net.NetworkInformation;
using System.Security.Cryptography;
using System.Xml.Linq;

namespace PcDoctor.Bench;

/// <summary>A metric's identity, units, direction and minimum practical effect.</summary>
public sealed record MetricInfo(string Id, string Unit, Direction Direction, double MinimumEffect, bool EnvironmentDependent = false)
{
    public static readonly MetricInfo CpuSingle = new("cpu.single", "ms", Direction.LowerIsBetter, 0.03);
    public static readonly MetricInfo CpuMulti = new("cpu.multi", "ms", Direction.LowerIsBetter, 0.03);
    public static readonly MetricInfo BootMainPath = new("boot.mainPath", "ms", Direction.LowerIsBetter, 0.05);
    public static readonly MetricInfo BootPostBoot = new("boot.postBoot", "ms", Direction.LowerIsBetter, 0.05);
    public static readonly MetricInfo CommitMb = new("bg.commit", "MB", Direction.LowerIsBetter, 0.03);
    public static readonly MetricInfo Processes = new("bg.processes", "", Direction.LowerIsBetter, 0.05);
    public static readonly MetricInfo DpcPercent = new("bg.dpc", "%", Direction.LowerIsBetter, 0.10);
    public static readonly MetricInfo DiskSeqRead = new("disk.seqRead", "MB/s", Direction.HigherIsBetter, 0.05);
    public static readonly MetricInfo DiskRandRead = new("disk.randRead", "IOPS", Direction.HigherIsBetter, 0.05);
    public static readonly MetricInfo DiskRandLatency = new("disk.randLatency", "ms", Direction.LowerIsBetter, 0.05);
    public static readonly MetricInfo FpsAverage = new("game.fps", "FPS", Direction.HigherIsBetter, 0.03);
    public static readonly MetricInfo FpsLow1 = new("game.low1", "FPS", Direction.HigherIsBetter, 0.05);
    public static readonly MetricInfo PingGateway = new("net.gateway", "ms", Direction.LowerIsBetter, 0.10, true);
    public static readonly MetricInfo PingPublic = new("net.public", "ms", Direction.LowerIsBetter, 0.10, true);
    public static readonly MetricInfo DnsLookup = new("net.dns", "ms", Direction.LowerIsBetter, 0.10, true);

    public static IReadOnlyList<MetricInfo> All { get; } =
        [CpuSingle, CpuMulti, BootMainPath, BootPostBoot, CommitMb, Processes, DpcPercent, DiskSeqRead, DiskRandRead, DiskRandLatency,
         FpsAverage, FpsLow1, PingGateway, PingPublic, DnsLookup];

    public static MetricInfo Find(string id) => All.First(m => m.Id == id);
}

/// <summary>Deterministic CPU workload: SHA-256 over a fixed buffer, single thread and all threads (ms per round).</summary>
public static class CpuWorkload
{
    private static readonly byte[] Buffer = CreateBuffer(32 * 1024 * 1024);

    private static byte[] CreateBuffer(int size)
    {
        var b = new byte[size];
        new Random(42).NextBytes(b);
        return b;
    }

    public static double SingleThreadMs(int rounds = 4)
    {
        var sw = Stopwatch.StartNew();
        for (var i = 0; i < rounds; i++)
        {
            SHA256.HashData(Buffer);
        }
        return sw.Elapsed.TotalMilliseconds;
    }

    public static double AllThreadsMs(int roundsPerThread = 2)
    {
        var sw = Stopwatch.StartNew();
        Parallel.For(0, Environment.ProcessorCount, new ParallelOptions { MaxDegreeOfParallelism = Environment.ProcessorCount }, _ =>
        {
            for (var i = 0; i < roundsPerThread; i++)
            {
                SHA256.HashData(Buffer);
            }
        });
        return sw.Elapsed.TotalMilliseconds;
    }
}

public sealed record PingStats(int Sent, int Received, double Median, double P95, double Jitter)
{
    public double Loss => Sent == 0 ? 0 : 1 - (double)Received / Sent;
}

public static class NetworkProbe
{
    /// <summary>Median, p95, loss and jitter (mean |ΔRTT| of consecutive replies).</summary>
    public static PingStats Summarize(IReadOnlyList<double?> rtts)
    {
        var ok = rtts.Where(r => r is not null).Select(r => r!.Value).ToList();
        var jitter = ok.Count > 1 ? ok.Zip(ok.Skip(1), (a, b) => Math.Abs(b - a)).Average() : 0;
        return new PingStats(rtts.Count, ok.Count, ok.Count == 0 ? double.NaN : Statistics.Quantile(ok, 0.5),
            ok.Count == 0 ? double.NaN : Statistics.Quantile(ok, 0.95), jitter);
    }

    public static async Task<PingStats> PingAsync(string host, int count, CancellationToken ct)
    {
        using var ping = new Ping();
        var rtts = new List<double?>();
        for (var i = 0; i < count; i++)
        {
            ct.ThrowIfCancellationRequested();
            try
            {
                var r = await ping.SendPingAsync(host, TimeSpan.FromSeconds(2), cancellationToken: ct).ConfigureAwait(false);
                rtts.Add(r.Status == IPStatus.Success ? r.RoundtripTime : null);
            }
            catch (PingException)
            {
                rtts.Add(null);
            }
            await Task.Delay(100, ct).ConfigureAwait(false);
        }
        return Summarize(rtts);
    }

    public static string? DefaultGateway() =>
        NetworkInterface.GetAllNetworkInterfaces()
            .Where(n => n.OperationalStatus == OperationalStatus.Up && n.NetworkInterfaceType != NetworkInterfaceType.Loopback)
            .SelectMany(n => n.GetIPProperties().GatewayAddresses)
            .Select(g => g.Address)
            .FirstOrDefault(a => a.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork && !a.Equals(System.Net.IPAddress.Any))?.ToString();

    /// <summary>DNS resolution time for random names (never cached), in ms. A "not found" answer still measures the resolver.</summary>
    public static async Task<double> DnsMsAsync(CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        try
        {
            await System.Net.Dns.GetHostAddressesAsync($"pcdoctor-{Guid.NewGuid():N}.invalid.example.com", ct).ConfigureAwait(false);
        }
        catch (System.Net.Sockets.SocketException)
        {
        }
        return sw.Elapsed.TotalMilliseconds;
    }
}

public sealed record DiskSpdResult(double MegabytesPerSecond, double Iops, double AverageLatencyMs);

/// <summary>
/// DiskSpd XML output (-Rxml): per-target ReadBytes/ReadCount/WriteBytes/WriteCount over TestTimeSeconds,
/// and the average latency when -L is given. VERIFY element names against diskspd 2.2.
/// </summary>
public static class DiskSpdParser
{
    public static DiskSpdResult Parse(string xml)
    {
        var doc = XDocument.Parse(xml);
        double D(XElement? e) => e is null ? 0 : double.Parse(e.Value, CultureInfo.InvariantCulture);
        var seconds = D(doc.Descendants("TestTimeSeconds").FirstOrDefault());
        var targets = doc.Descendants("Target").ToList();
        var bytes = targets.Sum(t => D(t.Element("ReadBytes")) + D(t.Element("WriteBytes")));
        var count = targets.Sum(t => D(t.Element("ReadCount")) + D(t.Element("WriteCount")));
        var latency = doc.Descendants("Latency").Elements("AverageTotalMilliseconds").FirstOrDefault()
                      ?? doc.Descendants("AverageReadLatencyMilliseconds").FirstOrDefault();
        return seconds <= 0
            ? new DiskSpdResult(0, 0, 0)
            : new DiskSpdResult(bytes / seconds / 1_048_576, count / seconds, D(latency));
    }

    /// <summary>The three runs from DESIGN M12, always on a temporary file (-c1G), never on a raw disk.</summary>
    public static IReadOnlyList<(string Name, string[] Args)> Profiles(string file) =>
    [
        ("seqRead", ["-c1G", "-b1M", "-o8", "-t1", "-w0", "-W2", "-d10", "-Sh", "-L", "-Rxml", file]),
        ("randRead", ["-c1G", "-b4K", "-o32", "-t1", "-r", "-w0", "-W2", "-d10", "-Sh", "-L", "-Rxml", file]),
        ("randLatency", ["-c1G", "-b4K", "-o1", "-t1", "-r", "-w0", "-W2", "-d10", "-Sh", "-L", "-Rxml", file]),
    ];
}

public sealed record FrameStats(int Frames, double AverageFps, double Low1Fps, double Low01Fps);

/// <summary>
/// PresentMon CSV: frame times in ms from "MsBetweenPresents" (v1) or "FrameTime"/"MsBetweenDisplayChange" (v2).
/// Average FPS = frames / total time; 1% / 0.1% low = 1000 / p99 / p99.9 frame time (documented definition).
/// </summary>
public static class PresentMonParser
{
    private static readonly string[] Columns = ["MsBetweenPresents", "FrameTime", "msBetweenPresents", "MsBetweenAppStart"];

    public static FrameStats Parse(string csv)
    {
        var lines = csv.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (lines.Length < 2)
        {
            return new FrameStats(0, 0, 0, 0);
        }
        var header = lines[0].Split(',');
        var col = Columns.Select(c => Array.IndexOf(header, c)).FirstOrDefault(i => i >= 0, -1);
        if (col < 0)
        {
            throw new FormatException("PresentMon CSV has no frame-time column.");
        }
        var frames = lines.Skip(1).Select(l => l.Split(',')).Where(p => p.Length > col)
            .Select(p => double.TryParse(p[col], NumberStyles.Float, CultureInfo.InvariantCulture, out var v) ? v : double.NaN)
            .Where(v => v > 0 && !double.IsNaN(v)).ToList();
        if (frames.Count == 0)
        {
            return new FrameStats(0, 0, 0, 0);
        }
        var total = frames.Sum();
        return new FrameStats(frames.Count, frames.Count / (total / 1000), 1000 / Statistics.Quantile(frames, 0.99), 1000 / Statistics.Quantile(frames, 0.999));
    }

    public static string[] Args(string process, string output) =>
        ["--process_name", process, "--delay", "5", "--timed", "60", "--terminate_after_timed", "--output_file", output, "--no_console_stats", "--stop_existing_session"];
}

/// <summary>Boot record from Diagnostics-Performance event 100 and the boot type from Kernel-Boot event 27.</summary>
public sealed record BootSample(DateTimeOffset Time, double MainPathMs, double PostBootMs, double TotalMs, bool IsDegradation, int BootType)
{
    /// <summary>Kernel-Boot 27: 0 cold (restart / full shutdown), 1 fast startup (hybrid), 2 resume from hibernation.</summary>
    public string BootTypeName => BootType switch { 0 => "cold", 1 => "fastStartup", 2 => "resume", _ => "unknown" };
}

public static class BootHistory
{
    /// <summary>Like-with-like: only boots of the same type are compared, and the first boot after an update is dropped.</summary>
    public static IReadOnlyList<BootSample> Comparable(IReadOnlyList<BootSample> boots, int bootType, IReadOnlyList<DateTimeOffset> updateTimes) =>
        boots.Where(b => b.BootType == bootType)
             .Where(b => !updateTimes.Any(u => u < b.Time && boots.Where(x => x.Time > u).OrderBy(x => x.Time).FirstOrDefault() == b))
             .ToList();
}
