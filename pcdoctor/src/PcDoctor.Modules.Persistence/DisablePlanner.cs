using PcDoctor.Core.Journal;
using PcDoctor.Core.Platform;

namespace PcDoctor.Modules.Persistence;

/// <summary>
/// How an entry is disabled without deleting anything: a Run value moves to PC Doctor's backup key,
/// a startup shortcut moves to a backup folder, a scheduled task is disabled, a service is set to
/// Disabled. Everything else (drivers, WMI, Winlogon, IFEO, ...) is reported for manual review only.
/// </summary>
public static class DisablePlanner
{
    public const string BackupKey = @"SOFTWARE\PCDoctor\DisabledAutoruns";

    public static bool CanDisable(AutorunEntry e) => e.Enabled && e.Category switch
    {
        AutorunCategory.RunKey => e.Value is not null && SplitHive(e.Location) is not null,
        AutorunCategory.StartupFolder => true,
        AutorunCategory.ScheduledTask => true,
        AutorunCategory.Service => e.Detail is "Automatic" or "Manual",
        _ => false,
    };

    /// <param name="backupFolder">Admin-only folder for moved shortcuts (%ProgramData%\PCDoctor\DisabledAutoruns).</param>
    public static IReadOnlyList<PlannedChange>? Plan(AutorunEntry e, string backupFolder)
    {
        if (!CanDisable(e))
        {
            return null;
        }
        switch (e.Category)
        {
            case AutorunCategory.RunKey:
            {
                var (hive, key) = SplitHive(e.Location)!.Value;
                var backupHive = hive;
                var backup = $@"{BackupKey}\{e.Id.Replace(':', '_')}";
                return
                [
                    new PlannedRegistrySet(backupHive, backup, "Location", new RegistryData("String", e.Location)),
                    new PlannedRegistrySet(backupHive, backup, e.Name, e.Value!),
                    new PlannedRegistryDelete(hive, key, e.Name),
                ];
            }
            case AutorunCategory.StartupFolder:
                return [new PlannedFileMove(e.Location, WinPath.Join(backupFolder, e.Id.Replace(':', '_'), WinPath.FileName(e.Location)))];
            case AutorunCategory.ScheduledTask:
                return [new PlannedTaskEnabled(e.Location, false)];
            case AutorunCategory.Service:
                return [new PlannedServiceStart(e.Name, "Disabled", false)];
            default:
                return null;
        }
    }

    /// <summary>"HKLM\SOFTWARE\..." → ("HKLM", "SOFTWARE\..."); "HKU\S-1-5-21-..\Software\..." → ("HKU\S-1-..", "Software\...").</summary>
    public static (string Hive, string Key)? SplitHive(string location)
    {
        if (location.StartsWith(@"HKLM\", StringComparison.OrdinalIgnoreCase))
        {
            return ("HKLM", location[5..]);
        }
        if (location.StartsWith(@"HKU\", StringComparison.OrdinalIgnoreCase))
        {
            var rest = location[4..];
            var slash = rest.IndexOf('\\');
            return slash > 0 ? (@"HKU\" + rest[..slash], rest[(slash + 1)..]) : null;
        }
        return null;
    }
}
