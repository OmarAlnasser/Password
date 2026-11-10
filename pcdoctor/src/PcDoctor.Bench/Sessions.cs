using System.Security.Cryptography;
using System.Text.Json;

namespace PcDoctor.Bench;

/// <summary>Conditions a benchmark ran under. Differences between two sessions are shown next to the verdict.</summary>
public sealed record BenchConditions(
    string OsBuild,
    TimeSpan Uptime,
    string PowerSource,
    string PowerPlan,
    string AppVersion,
    double IdleCpuPercent,
    bool PendingReboot,
    bool DiskSpdAvailable)
{
    public IReadOnlyList<string> DifferencesFrom(BenchConditions other)
    {
        var d = new List<string>();
        if (OsBuild != other.OsBuild) d.Add("build");
        if (PowerSource != other.PowerSource) d.Add("power");
        if (PowerPlan != other.PowerPlan) d.Add("plan");
        if (Math.Abs(IdleCpuPercent - other.IdleCpuPercent) > 5) d.Add("idle");
        if (PendingReboot != other.PendingReboot) d.Add("reboot");
        return d;
    }

    /// <summary>Pre-flight problems that make results less comparable (shown before running, recorded after).</summary>
    public IReadOnlyList<string> Warnings()
    {
        var w = new List<string>();
        if (PowerSource == "Battery") w.Add("battery");
        if (Uptime < TimeSpan.FromMinutes(5)) w.Add("justBooted");
        if (IdleCpuPercent > 5) w.Add("busy");
        if (PendingReboot) w.Add("reboot");
        return w;
    }
}

public sealed record BenchSession
{
    public required Guid Id { get; init; }
    public required string Label { get; init; }
    public required DateTimeOffset StartedUtc { get; init; }
    public required BenchConditions Conditions { get; init; }
    public Dictionary<string, List<double>> Metrics { get; init; } = new();
    public string? Note { get; init; }
}

public sealed record MetricComparison(MetricInfo Metric, Comparison Result);

public static class SessionComparer
{
    public static IReadOnlyList<MetricComparison> Compare(BenchSession before, BenchSession after) =>
        before.Metrics.Keys.Intersect(after.Metrics.Keys)
            .Select(id => MetricInfo.All.FirstOrDefault(m => m.Id == id))
            .OfType<MetricInfo>()
            .Select(m => new MetricComparison(m, Statistics.Compare(before.Metrics[m.Id], after.Metrics[m.Id], m.Direction, m.MinimumEffect)))
            .ToList();
}

public sealed class SessionStore(string folder)
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web) { WriteIndented = true };

    public void Save(BenchSession s)
    {
        Directory.CreateDirectory(folder);
        File.WriteAllText(Path.Combine(folder, $"{s.StartedUtc.ToString("yyyyMMdd-HHmmss", System.Globalization.CultureInfo.InvariantCulture)}-{s.Id:N}.json"), JsonSerializer.Serialize(s, Json));
    }

    public IReadOnlyList<BenchSession> Load() =>
        !Directory.Exists(folder)
            ? []
            : Directory.GetFiles(folder, "*.json").OrderByDescending(f => f).Select(f =>
            {
                try
                {
                    return JsonSerializer.Deserialize<BenchSession>(File.ReadAllText(f), Json);
                }
                catch (JsonException)
                {
                    return null;
                }
            }).OfType<BenchSession>().ToList();
}

/// <summary>The pinned tools manifest: a bundled tool runs only if its SHA-256 matches.</summary>
public static class BundledTools
{
    private sealed record Entry(string Name, string Arch, string Sha256);

    private static readonly Lazy<IReadOnlyList<Entry>> Manifest = new(() =>
    {
        using var stream = typeof(BundledTools).Assembly.GetManifestResourceStream("PcDoctor.Bench.bundled-tools.json")!;
        using var doc = JsonDocument.Parse(stream);
        return doc.RootElement.GetProperty("tools").EnumerateArray()
            .Select(t => new Entry(t.GetProperty("name").GetString()!, t.GetProperty("arch").GetString()!, t.GetProperty("sha256").GetString()!))
            .ToList();
    });

    public static string? Resolve(string name, string folder, string arch)
    {
        var entry = Manifest.Value.FirstOrDefault(e => e.Name.Equals(name, StringComparison.OrdinalIgnoreCase) && e.Arch == arch);
        var path = Path.Combine(folder, name);
        if (entry is null || !File.Exists(path))
        {
            return null;
        }
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream)).Equals(entry.Sha256, StringComparison.OrdinalIgnoreCase) ? path : null;
    }

    public static string Arch => System.Runtime.InteropServices.RuntimeInformation.OSArchitecture.ToString();
}
