using System.Globalization;
using System.Runtime.Versioning;
using LibreHardwareMonitor.Hardware;
using Microsoft.Win32;
using PcDoctor.Core.Findings;
using PcDoctor.Core.Ipc;
using PcDoctor.Core.Scanning;

namespace PcDoctor.Modules.Sensors;

public sealed record SensorReading(string Hardware, string HardwareType, string Name, string Type, double? Value, double? Max);

public sealed record SensorSnapshot
{
    public bool PawnIoInstalled { get; init; }
    /// <summary>Null = not read (needs the Broker); empty = read, nothing reported.</summary>
    public IReadOnlyList<SensorReading>? Readings { get; init; }
}

/// <summary>
/// M8: temperatures, fans and throttling. Thresholds are heuristics and say so; they are never a
/// verdict about the hardware.
/// </summary>
public static class SensorAnalyzer
{
    public const string ModuleId = "M8";

    public static ModuleResult Analyze(SensorSnapshot s)
    {
        var checks = new List<CheckResult>();
        var findings = new List<Finding>();
        checks.Add(new CheckResult("M8.pawnio", new Text("m8.check.pawnio"), s.PawnIoInstalled ? CheckStatus.Pass : CheckStatus.Info,
            new Text(s.PawnIoInstalled ? "m8.pawnio.yes" : "m8.pawnio.no"), FindingSource.Registry));

        if (s.Readings is null)
        {
            checks.Add(Checks.NeedsDeepScan("M8.sensors", new Text("m8.check.sensors")));
            return Result(checks, findings);
        }
        if (s.Readings.Count == 0)
        {
            checks.Add(Checks.NotAvailable("M8.sensors", new Text("m8.check.sensors"), new Text("m8.sensors.none")));
            return Result(checks, findings);
        }
        checks.Add(new CheckResult("M8.sensors", new Text("m8.check.sensors"), CheckStatus.Info, new Text("m8.sensors.detail", s.Readings.Count),
            FindingSource.Heuristic));

        // Intel reports "Distance to TjMax" per core: 5 °C or less means the CPU is at its throttle point.
        var tjmax = s.Readings.Where(r => r.Type == "Temperature" && r.Name.Contains("Distance to TjMax", StringComparison.OrdinalIgnoreCase) && r.Value is not null).ToList();
        var hot = tjmax.Where(r => r.Value <= 5).ToList();
        if (hot.Count > 0)
        {
            findings.Add(Make("M8.cpuTjMax", Severity.Medium, new Text("m8.cpuHot.title", hot.Min(r => r.Value!.Value).ToString("0", CultureInfo.InvariantCulture)), "m8.cpuHot", hot));
        }
        var gpuHot = s.Readings.Where(r => r.HardwareType.StartsWith("Gpu", StringComparison.OrdinalIgnoreCase) && r.Type == "Temperature" &&
                                           r.Name.Contains("Hot Spot", StringComparison.OrdinalIgnoreCase) && r.Value >= 100).ToList();
        if (gpuHot.Count > 0)
        {
            findings.Add(Make("M8.gpuHotspot", Severity.Medium, new Text("m8.gpuHot.title", gpuHot.Max(r => r.Value!.Value).ToString("0", CultureInfo.InvariantCulture)), "m8.gpuHot", gpuHot));
        }
        var cpuTemps = s.Readings.Where(r => r.HardwareType == "Cpu" && r.Type == "Temperature" && !r.Name.Contains("Distance", StringComparison.OrdinalIgnoreCase)).ToList();
        if (cpuTemps.Count == 0 && !s.PawnIoInstalled)
        {
            checks.Add(new CheckResult("M8.cpuTemp", new Text("m8.check.cpuTemp"), CheckStatus.NotAvailable, new Text("m8.cpuTemp.needsPawnIo")));
        }
        return Result(checks, findings);
    }

    private static ModuleResult Result(List<CheckResult> c, List<Finding> f) => new() { ModuleId = ModuleId, ModuleName = new Text("m8.name"), Checks = c, Findings = f };

    private static Finding Make(string id, Severity severity, Text title, string key, IReadOnlyList<SensorReading> readings) => new()
    {
        Id = id,
        Module = ModuleId,
        Severity = severity,
        Confidence = Confidence.Possible,
        Source = FindingSource.Heuristic,
        Title = title,
        WhyItMatters = new Text(key + ".why"),
        Evidence = readings.Take(10).Select(r => new Evidence($"{r.Hardware} · {r.Name}",
            $"{r.Value?.ToString("0.#", CultureInfo.InvariantCulture)} (max {r.Max?.ToString("0.#", CultureInfo.InvariantCulture)})")).ToList(),
        SuggestedAction = new Text(key + ".action"),
        Undo = UndoInfo.NothingChanged,
    };
}

public sealed class SensorModule : IModule
{
    public string Id => SensorAnalyzer.ModuleId;
    public Text Name => new("m8.name");

    public async Task<ModuleResult> RunAsync(ScanContext context)
    {
        var pawn = OperatingSystem.IsWindows() && SensorReader.PawnIoInstalled();
        var readings = context.Elevated is { } e ? await e.ReadAsync<List<SensorReading>>(ElevatedData.Sensors, context.CancellationToken).ConfigureAwait(false) : null;
        return SensorAnalyzer.Analyze(new SensorSnapshot { PawnIoInstalled = pawn, Readings = readings });
    }
}

/// <summary>
/// LibreHardwareMonitor in the Broker. Memory-module (SPD) readout stays off: its helper library can use
/// an already-installed WinRing0 driver, and PC Doctor never loads WinRing0.
/// </summary>
[SupportedOSPlatform("windows")]
public static class SensorReader
{
    private static readonly object Gate = new();
    private static Computer? _computer;

    public static bool PawnIoInstalled()
    {
        using var k = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Services\PawnIO");
        return k is not null;
    }

    public static List<SensorReading> Read()
    {
        lock (Gate)
        {
            _computer ??= Open();
            var list = new List<SensorReading>();
            foreach (var hw in _computer.Hardware)
            {
                Visit(hw, list);
            }
            return list;
        }
    }

    private static Computer Open()
    {
        var c = new Computer
        {
            IsCpuEnabled = true,
            IsGpuEnabled = true,
            IsMotherboardEnabled = true,
            IsControllerEnabled = true,
            IsStorageEnabled = true,
            IsBatteryEnabled = true,
            IsPsuEnabled = true,
            IsMemoryEnabled = false,
            IsNetworkEnabled = false,
        };
        c.Open();
        return c;
    }

    private static void Visit(IHardware hw, List<SensorReading> list)
    {
        hw.Update();
        foreach (var s in hw.Sensors)
        {
            list.Add(new SensorReading(hw.Name, hw.HardwareType.ToString(), s.Name, s.SensorType.ToString(), s.Value, s.Max));
        }
        foreach (var sub in hw.SubHardware)
        {
            Visit(sub, list);
        }
    }
}
