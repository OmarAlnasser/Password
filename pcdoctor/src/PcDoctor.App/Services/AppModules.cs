using System.IO;
using PcDoctor.Core.Platform;
using PcDoctor.Core.Scanning;
using PcDoctor.Modules.Battery;
using PcDoctor.Modules.Crash;
using PcDoctor.Modules.Disk;
using PcDoctor.Modules.Drivers;
using PcDoctor.Modules.Security;

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
        CrashModule.ForWindows(new WindowsEventSource(), () => services.Settings.AllowSymbolDownload),
        DiskModule.ForWindows(),
        DriversModule.ForWindows(),
        new BatteryModule(),
    ];
}
