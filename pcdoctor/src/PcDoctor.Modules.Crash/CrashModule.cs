using System.Runtime.Versioning;
using Microsoft.Win32;
using PcDoctor.Core.Events;
using PcDoctor.Core.Findings;
using PcDoctor.Core.Platform;
using PcDoctor.Core.Scanning;

namespace PcDoctor.Modules.Crash;

public sealed class CrashModule(Func<CrashSnapshot> collect) : IModule
{
    public string Id => CrashAnalyzer.ModuleId;
    public Text Name => new("m5.name");

    public Task<ModuleResult> RunAsync(ScanContext context) =>
        Task.Run(() => CrashAnalyzer.Analyze(collect()), context.CancellationToken);

    [SupportedOSPlatform("windows")]
    public static CrashModule ForWindows(IEventSource events) => new(() => CrashCollector.Collect(events, TimeSpan.FromDays(30)));
}

[SupportedOSPlatform("windows")]
public static class CrashCollector
{
    public static CrashSnapshot Collect(IEventSource source, TimeSpan window)
    {
        var events = CrashEvents.Queries(window).SelectMany(source.Read).ToList();
        return new CrashSnapshot
        {
            DumpConfig = ReadDumpConfig(),
            HasPagefile = ReadHasPagefile(),
            Dumps = FindDumps(),
            Events = events,
            Stability = ReadStability(),
            Window = window,
        };
    }

    private static DumpConfig? ReadDumpConfig()
    {
        using var key = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Control\CrashControl");
        if (key is null)
        {
            return null;
        }
        return new DumpConfig(key.GetValue("CrashDumpEnabled") as int?,
            key.GetValue("MinidumpDir") is string md ? Environment.ExpandEnvironmentVariables(md) : null,
            key.GetValue("DumpFile") is string df ? Environment.ExpandEnvironmentVariables(df) : null,
            key.GetValue("AutoReboot") as int?);
    }

    private static bool? ReadHasPagefile()
    {
        try
        {
            if (Wmi.Query(@"root\cimv2", "SELECT AutomaticManagedPagefile FROM Win32_ComputerSystem")
                    .FirstOrDefault()?.Bool("AutomaticManagedPagefile") == true)
            {
                return true;
            }
            return Wmi.Query(@"root\cimv2", "SELECT Name FROM Win32_PageFileUsage").Count > 0;
        }
        catch (Exception)
        {
            return null;
        }
    }

    private static List<DumpFileInfo> FindDumps()
    {
        var windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var result = new List<DumpFileInfo>();
        void Add(string dir, string pattern, DumpKind kind, bool recurse)
        {
            try
            {
                if (!Directory.Exists(dir))
                {
                    return;
                }
                foreach (var f in new DirectoryInfo(dir).EnumerateFiles(pattern,
                             new EnumerationOptions { RecurseSubdirectories = recurse, IgnoreInaccessible = true }))
                {
                    result.Add(new DumpFileInfo(f.FullName, f.Length, f.LastWriteTimeUtc, kind));
                }
            }
            catch (UnauthorizedAccessException)
            {
                // Listing Minidump needs no admin on default ACLs; if it is locked down the count stays partial.
            }
        }
        Add(Path.Combine(windows, "Minidump"), "*.dmp", DumpKind.Minidump, false);
        var memory = Path.Combine(windows, "MEMORY.DMP");
        if (File.Exists(memory))
        {
            var fi = new FileInfo(memory);
            result.Add(new DumpFileInfo(fi.FullName, fi.Length, fi.LastWriteTimeUtc, DumpKind.KernelOrComplete));
        }
        Add(Path.Combine(windows, "LiveKernelReports"), "*.dmp", DumpKind.LiveKernel, true);
        Add(Path.Combine(local, "CrashDumps"), "*.dmp", DumpKind.UserMode, false);
        return result;
    }

    private static StabilityInfo? ReadStability()
    {
        try
        {
            var latest = Wmi.Query(@"root\cimv2", "SELECT SystemStabilityIndex, TimeGenerated FROM Win32_ReliabilityStabilityMetrics")
                .Select(r => (Index: Convert.ToDouble(r["SystemStabilityIndex"], System.Globalization.CultureInfo.InvariantCulture), Time: r.CimDate("TimeGenerated")))
                .Where(r => r.Time is not null)
                .OrderByDescending(r => r.Time)
                .FirstOrDefault();
            return latest.Time is { } t ? new StabilityInfo(latest.Index, new DateTimeOffset(t.ToUniversalTime())) : null;
        }
        catch (Exception)
        {
            // Reliability data is off when the RAC task is disabled; reported as not available.
            return null;
        }
    }
}
