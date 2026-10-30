using System.Globalization;
using System.Xml.Linq;
using PcDoctor.Core.Findings;
using PcDoctor.Core.Platform;
using PcDoctor.Core.Scanning;

namespace PcDoctor.Modules.Battery;

public sealed record BatteryInfo(string Id, string? Manufacturer, long DesignCapacityMwh, long FullChargeCapacityMwh, int? CycleCount)
{
    public double HealthPercent => DesignCapacityMwh > 0 ? 100.0 * FullChargeCapacityMwh / DesignCapacityMwh : 0;
}

/// <summary>
/// Parses `powercfg /batteryreport /xml`. Elements are matched by local name so the report's
/// namespace (http://schemas.microsoft.com/battery/2012) does not have to be hard-coded.
/// VERIFY element names on 22H2–25H2.
/// </summary>
public static class BatteryReportParser
{
    public static IReadOnlyList<BatteryInfo> Parse(string xml)
    {
        var doc = XDocument.Parse(xml);
        long L(XElement b, string name) =>
            long.TryParse(b.Elements().FirstOrDefault(e => e.Name.LocalName == name)?.Value, NumberStyles.Integer,
                CultureInfo.InvariantCulture, out var v) ? v : 0;
        string? S(XElement b, string name) => b.Elements().FirstOrDefault(e => e.Name.LocalName == name)?.Value.Trim();

        return doc.Descendants()
            .Where(e => e.Name.LocalName == "Battery" && e.Parent?.Name.LocalName == "Batteries")
            .Select(b => new BatteryInfo(S(b, "Id") ?? "?", S(b, "Manufacturer"), L(b, "DesignCapacity"),
                L(b, "FullChargeCapacity"), int.TryParse(S(b, "CycleCount"), NumberStyles.Integer, CultureInfo.InvariantCulture, out var c) ? c : null))
            .ToList();
    }
}

/// <summary>M10 battery. Thresholds (80% worn, 60% consider replacing) are heuristics and labelled so.</summary>
public static class BatteryAnalyzer
{
    public const string ModuleId = "M10";

    public static ModuleResult Analyze(IReadOnlyList<BatteryInfo>? batteries)
    {
        var checks = new List<CheckResult>();
        var findings = new List<Finding>();
        if (batteries is null)
        {
            checks.Add(Checks.NotAvailable("M10.report", new Text("m10.check.battery"), new Text("m10.check.reportFailed")));
        }
        else if (batteries.Count == 0)
        {
            checks.Add(Checks.NotAvailable("M10.report", new Text("m10.check.battery"), new Text("m10.check.noBattery")));
        }
        foreach (var b in batteries ?? [])
        {
            var health = Math.Round(b.HealthPercent, 1);
            var cycles = b.CycleCount?.ToString(CultureInfo.InvariantCulture) ?? "?";
            if (b.DesignCapacityMwh <= 0)
            {
                checks.Add(Checks.NotAvailable($"M10.{b.Id}", new Text("m10.check.batteryFor", b.Id), new Text("m10.check.noDesign")));
                continue;
            }
            checks.Add(new CheckResult($"M10.{b.Id}", new Text("m10.check.batteryFor", b.Id),
                health < 60 ? CheckStatus.Fail : health < 80 ? CheckStatus.Warn : CheckStatus.Info,
                new Text("m10.check.detail", b.FullChargeCapacityMwh, b.DesignCapacityMwh, health, cycles), FindingSource.MicrosoftTool));
            if (health < 80)
            {
                findings.Add(new Finding
                {
                    Id = $"M10.worn.{b.Id}",
                    Module = ModuleId,
                    Severity = health < 60 ? Severity.Medium : Severity.Low,
                    Confidence = Confidence.Probable,
                    Source = FindingSource.MicrosoftTool,
                    Title = new Text(health < 60 ? "m10.replace.title" : "m10.worn.title", health),
                    WhyItMatters = new Text("m10.worn.why"),
                    Evidence =
                    [
                        new Evidence("DesignCapacity (mWh)", b.DesignCapacityMwh.ToString(CultureInfo.InvariantCulture)),
                        new Evidence("FullChargeCapacity (mWh)", b.FullChargeCapacityMwh.ToString(CultureInfo.InvariantCulture)),
                        new Evidence("CycleCount", cycles),
                        new Evidence("Manufacturer / Id", $"{b.Manufacturer} / {b.Id}"),
                    ],
                    SuggestedAction = new Text(health < 60 ? "m10.replace.action" : "m10.worn.action"),
                    Undo = UndoInfo.NothingChanged,
                });
            }
        }
        checks.Add(Checks.NotBuiltYet("M10.energy", new Text("m10.check.energy"), "P4"));
        return new ModuleResult { ModuleId = ModuleId, ModuleName = new Text("m10.name"), Checks = checks, Findings = findings };
    }
}

public sealed class BatteryModule : IModule
{
    public string Id => BatteryAnalyzer.ModuleId;
    public Text Name => new("m10.name");

    public async Task<ModuleResult> RunAsync(ScanContext context)
    {
        if (!OperatingSystem.IsWindows())
        {
            return BatteryAnalyzer.Analyze(null);
        }
        var dir = Directory.CreateTempSubdirectory("pcdoctor-battery-");
        try
        {
            var output = Path.Combine(dir.FullName, "battery.xml");
            var result = await ProcessRunner.RunAsync(Tool.Powercfg, ["/batteryreport", "/xml", "/output", output],
                TimeSpan.FromSeconds(60), context.CancellationToken).ConfigureAwait(false);
            // Exit code, not console text: the console output is localized.
            if (result.ExitCode != 0 || !File.Exists(output))
            {
                return BatteryAnalyzer.Analyze(null);
            }
            return BatteryAnalyzer.Analyze(BatteryReportParser.Parse(await File.ReadAllTextAsync(output, context.CancellationToken).ConfigureAwait(false)));
        }
        finally
        {
            dir.Delete(recursive: true);
        }
    }
}
