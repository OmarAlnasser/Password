using System.Globalization;
using System.Runtime.Versioning;
using PcDoctor.Core.Findings;
using PcDoctor.Core.Platform;
using PcDoctor.Core.Scanning;

namespace PcDoctor.Modules.Drivers;

/// <summary>Win32_PnPEntity with ConfigManagerErrorCode &lt;&gt; 0.</summary>
public sealed record ProblemDevice(string Name, string DeviceId, int ErrorCode, string? PnpClass);

/// <summary>Win32_PnPSignedDriver.</summary>
public sealed record SignedDriver(string DeviceName, string? Provider, string? Version, DateTime? Date, bool? IsSigned, string? InfName);

/// <summary>Win32_SystemDriver: every kernel driver service, including ones loaded from app folders.</summary>
public sealed record SystemDriver(string Name, string? PathName, string? State, string? StartMode);

public sealed record DriversSnapshot
{
    public IReadOnlyList<ProblemDevice>? ProblemDevices { get; init; }
    public IReadOnlyList<SignedDriver>? Drivers { get; init; }
    public IReadOnlyList<SystemDriver>? SystemDrivers { get; init; }
}

/// <summary>M9 drivers and devices.</summary>
public static class DriversAnalyzer
{
    public const string ModuleId = "M9";

    /// <summary>Device Manager problem codes PC Doctor explains. Others show their number only.</summary>
    public static readonly IReadOnlySet<int> KnownCodes = new HashSet<int> { 1, 3, 10, 12, 14, 18, 19, 21, 22, 24, 28, 31, 39, 43, 45, 48, 52 };

    /// <summary>45 = not connected, 22 = disabled by the user: normal, hidden by default.</summary>
    public static readonly IReadOnlySet<int> HiddenCodes = new HashSet<int> { 22, 45 };

    public static readonly TimeSpan OldDriverAge = TimeSpan.FromDays(365 * 8);

    public static ModuleResult Analyze(DriversSnapshot s, DateTimeOffset now)
    {
        var checks = new List<CheckResult>();
        var findings = new List<Finding>();

        if (s.ProblemDevices is null)
        {
            checks.Add(Checks.NotAvailable("M9.devices", new Text("m9.check.devices")));
        }
        else
        {
            var visible = s.ProblemDevices.Where(d => !HiddenCodes.Contains(d.ErrorCode)).ToList();
            var hidden = s.ProblemDevices.Count - visible.Count;
            checks.Add(new CheckResult("M9.devices", new Text("m9.check.devices"),
                visible.Count == 0 ? CheckStatus.Pass : CheckStatus.Warn,
                new Text("m9.check.devices.detail", visible.Count, hidden), FindingSource.Wmi));
            foreach (var d in s.ProblemDevices)
            {
                var codeKey = KnownCodes.Contains(d.ErrorCode) ? $"m9.code.{d.ErrorCode}" : "m9.code.other";
                findings.Add(new Finding
                {
                    Id = $"M9.device.{d.DeviceId}",
                    Module = ModuleId,
                    Severity = HiddenCodes.Contains(d.ErrorCode) ? Severity.Info : d.ErrorCode is 43 or 10 ? Severity.Medium : Severity.Low,
                    Confidence = Confidence.Confirmed,
                    Source = FindingSource.Wmi,
                    Title = new Text("m9.device.title", d.Name, d.ErrorCode),
                    WhyItMatters = new Text(codeKey, d.ErrorCode),
                    Evidence =
                    [
                        new Evidence("DeviceID", d.DeviceId, EvidenceKind.Value),
                        new Evidence("ConfigManagerErrorCode", d.ErrorCode.ToString(CultureInfo.InvariantCulture)),
                        new Evidence("PNPClass", d.PnpClass ?? "?"),
                    ],
                    SuggestedAction = new Text("m9.device.action"),
                    Undo = UndoInfo.NothingChanged,
                    HiddenByDefault = HiddenCodes.Contains(d.ErrorCode),
                });
            }
        }

        if (s.Drivers is null)
        {
            checks.Add(Checks.NotAvailable("M9.drivers", new Text("m9.check.drivers")));
        }
        else
        {
            checks.Add(new CheckResult("M9.drivers", new Text("m9.check.drivers"), CheckStatus.Info,
                new Text("m9.check.drivers.detail", s.Drivers.Count), FindingSource.Wmi));

            var unsigned = s.Drivers.Where(d => d.IsSigned == false).ToList();
            if (unsigned.Count > 0)
            {
                findings.Add(new Finding
                {
                    Id = "M9.unsigned",
                    Module = ModuleId,
                    Severity = Severity.Medium,
                    Confidence = Confidence.Confirmed,
                    Source = FindingSource.Wmi,
                    Title = new Text("m9.unsigned.title", unsigned.Count),
                    WhyItMatters = new Text("m9.unsigned.why"),
                    Evidence = unsigned.Select(d => new Evidence(d.DeviceName, $"{d.InfName} {d.Provider} {d.Version}")).ToList(),
                    SuggestedAction = new Text("m9.unsigned.action"),
                    Undo = UndoInfo.NothingChanged,
                });
            }

            // Inbox drivers carry fixed old dates (e.g. 2006-06-21), so Microsoft-provided ones are excluded.
            var old = s.Drivers
                .Where(d => d.Date is { } date && now - date > OldDriverAge &&
                            !string.Equals(d.Provider, "Microsoft", StringComparison.OrdinalIgnoreCase))
                .DistinctBy(d => d.InfName ?? d.DeviceName)
                .ToList();
            if (old.Count > 0)
            {
                findings.Add(new Finding
                {
                    Id = "M9.old",
                    Module = ModuleId,
                    Severity = Severity.Info,
                    Confidence = Confidence.Possible,
                    Source = FindingSource.Heuristic,
                    Title = new Text("m9.old.title", old.Count, 8),
                    WhyItMatters = new Text("m9.old.why"),
                    Evidence = old.Select(d => new Evidence(d.DeviceName,
                        $"{d.Provider} {d.Version} {d.Date:yyyy-MM-dd} {d.InfName}")).ToList(),
                    SuggestedAction = new Text("m9.old.action"),
                    Undo = UndoInfo.NothingChanged,
                });
            }
        }

        if (s.SystemDrivers is null)
        {
            checks.Add(Checks.NotAvailable("M9.knownBad", new Text("m9.check.knownBad")));
        }
        else
        {
            var winring0 = s.SystemDrivers.Where(IsWinRing0).ToList();
            checks.Add(new CheckResult("M9.knownBad", new Text("m9.check.knownBad"),
                winring0.Count == 0 ? CheckStatus.Pass : CheckStatus.Fail, null, FindingSource.Wmi));
            foreach (var d in winring0)
            {
                var owner = DirectoryOf(d.PathName);
                findings.Add(new Finding
                {
                    Id = $"M9.winring0.{d.Name}",
                    Module = ModuleId,
                    Severity = Severity.High,
                    Confidence = Confidence.Confirmed,
                    Source = FindingSource.Wmi,
                    Title = new Text("m9.winring0.title", owner),
                    WhyItMatters = new Text("m9.winring0.why"),
                    Evidence =
                    [
                        new Evidence("Service", d.Name),
                        new Evidence("Path", d.PathName ?? "?", EvidenceKind.Path),
                        new Evidence("State / start", $"{d.State} / {d.StartMode}"),
                    ],
                    SuggestedAction = new Text("m9.winring0.action"),
                    Undo = UndoInfo.NothingChanged,
                });
            }
        }

        checks.Add(Checks.NotBuiltYet("M9.crashStacks", new Text("m9.check.crashStacks"), "P2"));
        return new ModuleResult { ModuleId = ModuleId, ModuleName = new Text("m9.name"), Checks = checks, Findings = findings };
    }

    /// <summary>WinRing0 (CVE-2020-14979; Defender: HackTool:Win32/Winring0) under its usual file and service names.</summary>
    public static bool IsWinRing0(SystemDriver d) =>
        d.Name.StartsWith("WinRing0", StringComparison.OrdinalIgnoreCase) ||
        FileNameOf(d.PathName).StartsWith("WinRing0", StringComparison.OrdinalIgnoreCase);

    // Windows paths are parsed by hand so the analyzer behaves the same when tests run on Linux.
    private static string FileNameOf(string? path)
    {
        var p = path?.Trim('"') ?? "";
        return p[(p.LastIndexOfAny(['\\', '/']) + 1)..];
    }

    private static string DirectoryOf(string? path)
    {
        var p = path?.Trim('"') ?? "";
        var i = p.LastIndexOfAny(['\\', '/']);
        return i > 0 ? p[..i] : "?";
    }
}

public sealed class DriversModule(Func<DriversSnapshot> collect) : IModule
{
    public string Id => DriversAnalyzer.ModuleId;
    public Text Name => new("m9.name");

    public Task<ModuleResult> RunAsync(ScanContext context) =>
        Task.Run(() => DriversAnalyzer.Analyze(collect(), context.Now), context.CancellationToken);

    [SupportedOSPlatform("windows")]
    public static DriversModule ForWindows() => new(DriversReader.Read);
}

[SupportedOSPlatform("windows")]
public static class DriversReader
{
    public static DriversSnapshot Read() => new()
    {
        ProblemDevices = Wmi.TryQuery(@"root\cimv2",
                "SELECT Name, DeviceID, ConfigManagerErrorCode, PNPClass FROM Win32_PnPEntity WHERE ConfigManagerErrorCode <> 0")
            ?.Select(r => new ProblemDevice(r.Str("Name") ?? r.Str("DeviceID") ?? "?", r.Str("DeviceID") ?? "?",
                (int)(r.Long("ConfigManagerErrorCode") ?? 0), r.Str("PNPClass")))
            .ToList(),
        Drivers = Wmi.TryQuery(@"root\cimv2",
                "SELECT DeviceName, DriverProviderName, DriverVersion, DriverDate, IsSigned, InfName FROM Win32_PnPSignedDriver")
            ?.Where(r => r.Str("InfName") is not null)
            .Select(r => new SignedDriver(r.Str("DeviceName") ?? "?", r.Str("DriverProviderName"), r.Str("DriverVersion"),
                r.CimDate("DriverDate"), r.Bool("IsSigned"), r.Str("InfName")))
            .ToList(),
        SystemDrivers = Wmi.TryQuery(@"root\cimv2", "SELECT Name, PathName, State, StartMode FROM Win32_SystemDriver")
            ?.Select(r => new SystemDriver(r.Str("Name") ?? "?", r.Str("PathName"), r.Str("State"), r.Str("StartMode")))
            .ToList(),
    };
}
