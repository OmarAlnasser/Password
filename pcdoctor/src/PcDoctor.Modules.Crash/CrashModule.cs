using System.Runtime.Versioning;
using Microsoft.Win32;
using PcDoctor.Core.Events;
using PcDoctor.Core.Findings;
using PcDoctor.Core.Ipc;
using PcDoctor.Core.Platform;
using PcDoctor.Core.Scanning;

namespace PcDoctor.Modules.Crash;

public sealed class CrashModule(Func<CrashSnapshot> collect, Func<bool>? allowSymbolDownload = null) : IModule
{
    public string Id => CrashAnalyzer.ModuleId;
    public Text Name => new("m5.name");

    public async Task<ModuleResult> RunAsync(ScanContext context)
    {
        var snapshot = await Task.Run(collect, context.CancellationToken).ConfigureAwait(false);
        if (context.Elevated is { } e)
        {
            var symbols = allowSymbolDownload?.Invoke() == true;
            var dumps = await e.ReadAsync<List<DumpAnalysis>>(symbols ? ElevatedData.CrashDumpsWithSymbols : ElevatedData.CrashDumps,
                context.CancellationToken).ConfigureAwait(false);
            snapshot = snapshot with { DumpAnalyses = dumps, DebuggerAvailable = CdbLocator.Find() is not null };
        }
        return CrashAnalyzer.Analyze(snapshot);
    }

    [SupportedOSPlatform("windows")]
    public static CrashModule ForWindows(IEventSource events, Func<bool> allowSymbolDownload) =>
        new(() => CrashCollector.Collect(events, TimeSpan.FromDays(30)), allowSymbolDownload);
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
            WerReports = WerReader.Read(window),
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

/// <summary>Finds cdb.exe from "Debugging Tools for Windows" (Windows SDK). Only Program Files locations are trusted.</summary>
public static class CdbLocator
{
    public static string? Find()
    {
        var arch = System.Runtime.InteropServices.RuntimeInformation.OSArchitecture switch
        {
            System.Runtime.InteropServices.Architecture.Arm64 => "arm64",
            System.Runtime.InteropServices.Architecture.X86 => "x86",
            _ => "x64",
        };
        foreach (var root in new[] { Environment.SpecialFolder.ProgramFilesX86, Environment.SpecialFolder.ProgramFiles })
        {
            var dir = Environment.GetFolderPath(root);
            if (dir.Length == 0)
            {
                continue;
            }
            var path = Path.Combine(dir, "Windows Kits", "10", "Debuggers", arch, "cdb.exe");
            if (File.Exists(path))
            {
                return path;
            }
        }
        return null;
    }
}

/// <summary>Administrator only (Broker): reads every kernel dump and, if cdb is installed, analyses the newest ones.</summary>
[SupportedOSPlatform("windows")]
public static class DumpReader
{
    private const int MaxAnalysed = 10;
    private const long MaxModuleScanBytes = 16 * 1024 * 1024;

    public static List<DumpAnalysis> Read(bool allowSymbolDownload, CancellationToken ct)
    {
        var windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        var files = new List<FileInfo>();
        var minidump = Path.Combine(windows, "Minidump");
        if (Directory.Exists(minidump))
        {
            files.AddRange(new DirectoryInfo(minidump).EnumerateFiles("*.dmp"));
        }
        var memory = new FileInfo(Path.Combine(windows, "MEMORY.DMP"));
        if (memory.Exists)
        {
            files.Add(memory);
        }

        var cdb = CdbLocator.Find();
        var symbols = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "PCDoctor", "symbols");
        Directory.CreateDirectory(symbols);
        var symbolPath = allowSymbolDownload
            ? $"srv*{symbols}*https://msdl.microsoft.com/download/symbols"
            : $"cache*{symbols}";

        var result = new List<DumpAnalysis>();
        var index = 0;
        foreach (var f in files.OrderByDescending(f => f.LastWriteTimeUtc))
        {
            ct.ThrowIfCancellationRequested();
            DumpHeader? header = null;
            IReadOnlyList<string> modules = [];
            AnalyzeResult? analyze = null;
            string? error = null;
            try
            {
                using var stream = new FileStream(f.FullName, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
                var head = new byte[0x2000];
                var read = stream.Read(head, 0, head.Length);
                header = DumpHeaderParser.Parse(head.AsSpan(0, read));
                if (f.Length <= MaxModuleScanBytes)
                {
                    stream.Position = 0;
                    var all = new byte[f.Length];
                    stream.ReadExactly(all);
                    modules = DumpHeaderParser.ModuleNames(all);
                }
                if (cdb is not null && index < MaxAnalysed)
                {
                    var follow = AnalyzeOutputParser.FollowUps(header?.BugcheckCode, header?.Parameters);
                    var run = ProcessRunner.RunProgramFilesToolAsync(cdb,
                        ["-z", f.FullName, "-y", symbolPath, "-c", "!analyze -v" + follow + "; q"],
                        TimeSpan.FromMinutes(allowSymbolDownload ? 6 : 3), ct,
                        new Dictionary<string, string> { ["_NT_SYMBOL_PATH"] = symbolPath }).GetAwaiter().GetResult();
                    if (!run.TimedOut)
                    {
                        analyze = AnalyzeOutputParser.Parse(run.StdOut);
                    }
                    else
                    {
                        error = "debugger timed out";
                    }
                }
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidOperationException)
            {
                error = ex.GetType().Name + ": " + ex.Message;
            }
            result.Add(new DumpAnalysis(f.FullName, f.LastWriteTimeUtc, f.Length, header, analyze, modules, error));
            index++;
        }
        return result;
    }
}

/// <summary>Report.wer files from the machine and user WER archives and queues.</summary>
[SupportedOSPlatform("windows")]
public static class WerReader
{
    public static List<WerReport> Read(TimeSpan window, int max = 300)
    {
        var roots = new[]
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "Microsoft", "Windows", "WER"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Microsoft", "Windows", "WER"),
        };
        var cutoff = DateTime.UtcNow - window;
        var reports = new List<WerReport>();
        foreach (var root in roots)
        {
            foreach (var sub in new[] { "ReportArchive", "ReportQueue" })
            {
                var dir = Path.Combine(root, sub);
                if (!Directory.Exists(dir))
                {
                    continue;
                }
                IEnumerable<string> files;
                try
                {
                    files = Directory.EnumerateFiles(dir, "Report.wer", new EnumerationOptions { RecurseSubdirectories = true, IgnoreInaccessible = true, MaxRecursionDepth = 2 });
                }
                catch (UnauthorizedAccessException)
                {
                    continue;
                }
                foreach (var file in files)
                {
                    if (reports.Count >= max)
                    {
                        return reports;
                    }
                    try
                    {
                        if (File.GetLastWriteTimeUtc(file) < cutoff)
                        {
                            continue;
                        }
                        if (WerReportParser.Parse(file, File.ReadAllBytes(file)) is { } r)
                        {
                            reports.Add(r);
                        }
                    }
                    catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
                    {
                        // Unreadable report: skipped; the count in the check is what was read.
                    }
                }
            }
        }
        return reports;
    }
}
