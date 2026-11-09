using System.IO;
using PcDoctor.Core.Platform;
using PcDoctor.Core.Scanning;
using PcDoctor.Modules.Battery;
using PcDoctor.Modules.Crash;
using PcDoctor.Modules.Disk;
using PcDoctor.Modules.Drivers;
using PcDoctor.Modules.Integrity;
using PcDoctor.Modules.Malware;
using PcDoctor.Modules.Network;
using PcDoctor.Modules.Security;
using PcDoctor.Modules.Sensors;

namespace PcDoctor.App.Services;

public static class AppModules
{
    public static string ProgramDataFolder =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "PCDoctor");

    public static string JournalPath => Path.Combine(ProgramDataFolder, "journal", "journal.jsonl");

    /// <summary>Every scan module, in report order.</summary>
    public static IReadOnlyList<IModule> Create(AppServices services) =>
    [
        SecurityModule.ForWindows(Path.Combine(ProgramDataFolder, "config", "os-support.json")),
        MalwareModule.ForWindows(),
        PersistenceScanModule.ForWindows(() => VirusTotal(services)),
        NetworkModule.ForWindows(),
        CrashModule.ForWindows(new WindowsEventSource(), () => services.Settings.AllowSymbolDownload),
        DiskModule.ForWindows(),
        IntegrityModule.ForWindows(new WindowsEventSource()),
        DriversModule.ForWindows(),
        new BatteryModule(),
        new SensorModule(),
    ];

    private static readonly System.Net.Http.HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(30) };
    private static VtRateLimiter? _limiter;

    /// <summary>A VirusTotal client only when the user turned it on and saved a key.</summary>
    public static VirusTotalClient? VirusTotal(AppServices services)
    {
        if (!services.Settings.VirusTotalEnabled || services.Settings.ReadVirusTotalKey() is not { Length: > 0 } key)
        {
            return null;
        }
        _limiter ??= new VtRateLimiter(TimeProvider.System);
        return new VirusTotalClient(Http, key, _limiter, TimeProvider.System);
    }
}
