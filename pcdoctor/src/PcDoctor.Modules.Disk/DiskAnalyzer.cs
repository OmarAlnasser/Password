using System.Globalization;
using PcDoctor.Core.Findings;
using PcDoctor.Core.Scanning;

namespace PcDoctor.Modules.Disk;

/// <summary>M7 disk health. Never says a disk is healthy beyond "Windows reports Healthy".</summary>
public static class DiskAnalyzer
{
    public const string ModuleId = "M7";
    private const long LatencyProblemMs = 10_000;

    public static ModuleResult Analyze(DiskSnapshot s)
    {
        var checks = new List<CheckResult>();
        var findings = new List<Finding>();

        if (s.Disks is null)
        {
            checks.Add(Checks.NotAvailable("M7.disks", new Text("m7.check.disks"), new Text("m7.check.disks.none")));
        }
        else
        {
            foreach (var d in s.Disks)
            {
                AnalyzeHealthStatus(d, checks, findings);
            }
        }

        if (s.Reliability is null)
        {
            checks.Add(Checks.NeedsDeepScan("M7.reliability", new Text("m7.check.reliability")));
        }
        else
        {
            foreach (var r in s.Reliability)
            {
                AnalyzeReliability(r, NameOf(s, r.DeviceId), checks, findings);
            }
        }

        if (s.Nvme is null)
        {
            if (s.Disks?.Any(d => d.IsNvme) != false)
            {
                checks.Add(Checks.NeedsDeepScan("M7.nvme", new Text("m7.check.nvme")));
            }
        }
        else
        {
            foreach (var n in s.Nvme)
            {
                AnalyzeNvme(n, NameOf(s, n.DeviceId), checks, findings);
            }
        }

        if (s.Smart is null)
        {
            if (s.Disks?.Any(d => d.BusType == PhysicalDiskInfo.BusSata) != false)
            {
                checks.Add(Checks.NeedsDeepScan("M7.smart", new Text("m7.check.smart")));
            }
        }
        else
        {
            foreach (var sm in s.Smart)
            {
                AnalyzeSmart(sm, checks, findings);
            }
        }
        if (s.Disks?.Any(d => d.BusType is PhysicalDiskInfo.BusUsb or PhysicalDiskInfo.BusRaid) == true)
        {
            checks.Add(Checks.NotAvailable("M7.usbRaid", new Text("m7.check.usbRaid"), new Text("m7.check.usbRaid.detail")));
        }

        return new ModuleResult { ModuleId = ModuleId, ModuleName = new Text("m7.name"), Checks = checks, Findings = findings };
    }

    private static string NameOf(DiskSnapshot s, string deviceId) =>
        s.Disks?.FirstOrDefault(d => d.DeviceId == deviceId)?.FriendlyName is { } n ? $"{n} (disk {deviceId})" : $"disk {deviceId}";

    private static void AnalyzeHealthStatus(PhysicalDiskInfo d, List<CheckResult> checks, List<Finding> findings)
    {
        var name = $"{d.FriendlyName} (disk {d.DeviceId})";
        // MSFT_PhysicalDisk.HealthStatus: 0 Healthy, 1 Warning, 2 Unhealthy, 5 Unknown.
        var status = d.HealthStatus switch
        {
            0 => CheckStatus.Pass,
            1 => CheckStatus.Warn,
            2 => CheckStatus.Fail,
            _ => CheckStatus.NotAvailable,
        };
        checks.Add(new CheckResult($"M7.health.{d.DeviceId}", new Text("m7.check.health", name), status,
            new Text("m7.health." + (d.HealthStatus switch { 0 => "healthy", 1 => "warning", 2 => "unhealthy", _ => "unknown" })),
            FindingSource.Wmi));
        if (d.HealthStatus is 1 or 2)
        {
            findings.Add(new Finding
            {
                Id = $"M7.health.{d.DeviceId}",
                Module = ModuleId,
                Severity = d.HealthStatus == 2 ? Severity.Critical : Severity.High,
                Confidence = Confidence.Confirmed,
                Source = FindingSource.Wmi,
                Title = new Text(d.HealthStatus == 2 ? "m7.unhealthy.title" : "m7.warning.title", name),
                WhyItMatters = new Text("m7.unhealthy.why"),
                Evidence =
                [
                    new Evidence("MSFT_PhysicalDisk.HealthStatus", d.HealthStatus.Value.ToString(CultureInfo.InvariantCulture)),
                    new Evidence("OperationalStatus", string.Join(", ", d.OperationalStatus)),
                    new Evidence("SerialNumber", d.SerialNumber ?? "?"),
                ],
                SuggestedAction = new Text("m7.backupNow"),
                Undo = UndoInfo.NothingChanged,
            });
        }
    }

    private static void AnalyzeReliability(ReliabilityCounters r, string name, List<CheckResult> checks, List<Finding> findings)
    {
        string N(long? v) => v?.ToString(CultureInfo.InvariantCulture) ?? "not reported";
        var evidence = new List<Evidence>
        {
            new("Temperature (°C)", N(r.Temperature)),
            new("TemperatureMax (°C)", N(r.TemperatureMax)),
            new("Wear (%)", N(r.Wear)),
            new("ReadErrorsUncorrected", N(r.ReadErrorsUncorrected)),
            new("WriteErrorsUncorrected", N(r.WriteErrorsUncorrected)),
            new("ReadLatencyMax (ms)", N(r.ReadLatencyMaxMs)),
            new("WriteLatencyMax (ms)", N(r.WriteLatencyMaxMs)),
            new("PowerOnHours", N(r.PowerOnHours)),
        };
        var anyReported = r.Temperature is not null || r.Wear is not null || r.ReadErrorsUncorrected is not null || r.PowerOnHours is not null;
        checks.Add(new CheckResult($"M7.reliability.{r.DeviceId}", new Text("m7.check.reliabilityFor", name),
            anyReported ? CheckStatus.Info : CheckStatus.NotAvailable,
            anyReported ? null : new Text("m7.notReported"), FindingSource.Wmi));

        var uncorrected = (r.ReadErrorsUncorrected ?? 0) + (r.WriteErrorsUncorrected ?? 0);
        if (uncorrected > 0)
        {
            findings.Add(Make($"M7.uncorrected.{r.DeviceId}", Severity.High, FindingSource.Wmi,
                new Text("m7.uncorrected.title", name, uncorrected), new Text("m7.uncorrected.why"), evidence, new Text("m7.backupNow")));
        }
        var latency = Math.Max(r.ReadLatencyMaxMs ?? 0, r.WriteLatencyMaxMs ?? 0);
        if (latency > LatencyProblemMs)
        {
            findings.Add(Make($"M7.latency.{r.DeviceId}", Severity.Medium, FindingSource.Wmi,
                new Text("m7.latency.title", name, latency / 1000), new Text("m7.latency.why"), evidence, new Text("m7.latency.action")));
        }
        if (r.Wear is >= 80)
        {
            findings.Add(Make($"M7.wear.{r.DeviceId}", Severity.Medium, FindingSource.Wmi,
                new Text("m7.wear.title", name, r.Wear.Value), new Text("m7.wear.why"), evidence, new Text("m7.wear.action")));
        }
    }

    private static void AnalyzeNvme(NvmeRawData raw, string name, List<CheckResult> checks, List<Finding> findings)
    {
        NvmeHealthLog log;
        try
        {
            log = NvmeHealthLog.Parse(raw.HealthLog);
        }
        catch (ArgumentException)
        {
            checks.Add(Checks.NotAvailable($"M7.nvme.{raw.DeviceId}", new Text("m7.check.nvmeFor", name), new Text("m7.nvme.badLog")));
            return;
        }
        var thresholds = raw.IdentifyController is { } id ? NvmeThresholds.Parse(id) : null;
        var evidence = new List<Evidence>
        {
            new("CriticalWarning", $"0x{log.CriticalWarning:X2} ({log.Warnings})"),
            new("Composite temperature", $"{log.CompositeTemperatureCelsius} °C ({log.CompositeTemperatureKelvin} K)"),
            new("Available spare", $"{log.AvailableSparePercent}% (threshold {log.AvailableSpareThresholdPercent}%)"),
            new("Percentage used", $"{log.PercentageUsed}%"),
            new("Media and data integrity errors", log.MediaErrors.ToString(CultureInfo.InvariantCulture)),
            new("Unsafe shutdowns", log.UnsafeShutdowns.ToString(CultureInfo.InvariantCulture)),
            new("Power-on hours", log.PowerOnHours.ToString(CultureInfo.InvariantCulture)),
            new("Data written", $"{log.BytesWritten / 1_000_000_000_000} TB"),
        };
        if (thresholds is { WarningKelvin: > 0 })
        {
            evidence.Add(new Evidence("WCTEMP / CCTEMP", $"{thresholds.WarningKelvin - 273} °C / {thresholds.CriticalKelvin - 273} °C"));
        }
        checks.Add(new CheckResult($"M7.nvme.{raw.DeviceId}", new Text("m7.check.nvmeFor", name),
            log.CriticalWarning != 0 ? CheckStatus.Fail : log.PercentageUsed >= 80 ? CheckStatus.Warn : CheckStatus.Info,
            new Text("m7.nvme.summary", log.PercentageUsed, log.AvailableSparePercent, log.CompositeTemperatureCelsius),
            FindingSource.MicrosoftTool));

        if (log.CriticalWarning != 0 || log.AvailableSparePercent < log.AvailableSpareThresholdPercent)
        {
            findings.Add(Make($"M7.nvmeCritical.{raw.DeviceId}", Severity.Critical, FindingSource.MicrosoftTool,
                new Text("m7.nvmeCritical.title", name, log.Warnings.ToString()), new Text("m7.nvmeCritical.why"), evidence, new Text("m7.backupNow")));
        }
        if (log.MediaErrors > 0)
        {
            findings.Add(Make($"M7.nvmeMedia.{raw.DeviceId}", Severity.High, FindingSource.MicrosoftTool,
                new Text("m7.nvmeMedia.title", name, log.MediaErrors.ToString(CultureInfo.InvariantCulture)), new Text("m7.nvmeMedia.why"),
                evidence, new Text("m7.backupNow")));
        }
        if (log.PercentageUsed >= 80)
        {
            findings.Add(Make($"M7.nvmeWear.{raw.DeviceId}", log.PercentageUsed >= 100 ? Severity.High : Severity.Medium, FindingSource.MicrosoftTool,
                new Text("m7.wear.title", name, log.PercentageUsed), new Text("m7.wear.why"), evidence, new Text("m7.wear.action")));
        }
        if (thresholds is { WarningKelvin: > 0 } t && log.CompositeTemperatureKelvin >= t.WarningKelvin)
        {
            findings.Add(Make($"M7.nvmeTemp.{raw.DeviceId}", Severity.Medium, FindingSource.MicrosoftTool,
                new Text("m7.nvmeTemp.title", name, log.CompositeTemperatureCelsius), new Text("m7.nvmeTemp.why"), evidence,
                new Text("m7.nvmeTemp.action")));
        }
    }

    private static void AnalyzeSmart(SmartRawData raw, List<CheckResult> checks, List<Finding> findings)
    {
        var attrs = SmartAttributes.Parse(raw.VendorSpecific);
        checks.Add(new CheckResult($"M7.smart.{raw.InstanceName}", new Text("m7.check.smartFor", raw.InstanceName),
            attrs.Count > 0 ? CheckStatus.Info : CheckStatus.NotAvailable, null, FindingSource.Wmi));
        var bad = attrs.Where(a => a.Id is SmartAttributes.Reallocated or SmartAttributes.UncorrectableReported
                                       or SmartAttributes.Pending or SmartAttributes.OfflineUncorrectable && a.Raw > 0).ToList();
        if (bad.Count == 0)
        {
            return;
        }
        findings.Add(Make($"M7.smart.{raw.InstanceName}", bad.Any(a => a.Id != SmartAttributes.Reallocated) ? Severity.High : Severity.Medium,
            FindingSource.Wmi, new Text("m7.smart.title", raw.InstanceName), new Text("m7.smart.why"),
            bad.Select(a => new Evidence($"SMART {a.Id}", $"raw={a.Raw} current={a.Current} worst={a.Worst}")).ToList(),
            new Text("m7.backupNow")));
    }

    private static Finding Make(string id, Severity severity, FindingSource source, Text title, Text why,
        IReadOnlyList<Evidence> evidence, Text action) => new()
    {
        Id = id,
        Module = ModuleId,
        Severity = severity,
        Confidence = Confidence.Confirmed,
        Source = source,
        Title = title,
        WhyItMatters = why,
        Evidence = evidence,
        SuggestedAction = action,
        Undo = UndoInfo.NothingChanged,
    };
}
