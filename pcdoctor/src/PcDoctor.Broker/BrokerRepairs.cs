using PcDoctor.Core.Ipc;

namespace PcDoctor.Broker;

/// <summary>Repair jobs (DISM, SFC, chkdsk, offline scan, Driver Verifier).</summary>
internal static class BrokerRepairs
{
    public static Task<object?> Run(JobKind kind, string? target, IJobProgress progress, CancellationToken ct) =>
        PcDoctor.Modules.Integrity.RepairRunner.Run(kind, target, progress, ct);
}

/// <summary>Debloat tweaks from the catalog compiled into the Broker; state is read with the Broker's own access.</summary>
internal static class BrokerTweaks
{
    private static readonly PcDoctor.Tweaks.TweakCatalog Catalog = PcDoctor.Tweaks.TweakCatalog.Load();

    public static string ManifestPath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "PCDoctor", "tweaks-applied.json");

    public static PcDoctor.Tweaks.OsInfo Os()
    {
        using var cv = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion");
        return new PcDoctor.Tweaks.OsInfo(int.TryParse(cv?.GetValue("CurrentBuildNumber") as string, out var b) ? b : 0, cv?.GetValue("EditionID") as string ?? "", false);
    }

    public static string OsVersion()
    {
        using var cv = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion");
        return $"{cv?.GetValue("CurrentBuildNumber")}.{cv?.GetValue("UBR")} {cv?.GetValue("DisplayVersion")}";
    }

    public static Func<IReadOnlyList<string>, IReadOnlyList<PcDoctor.Core.Journal.PlannedChange>?> Resolver(string clientSid) => ids =>
        PcDoctor.Tweaks.TweakEngine.Plan(Catalog, ids, Os(), new PcDoctor.Tweaks.DetectContext(
            new PcDoctor.Core.Platform.WindowsRegistryAccess(), new PcDoctor.Core.Platform.WindowsServiceConfigAccess(),
            new PcDoctor.Core.Platform.WindowsTaskSchedulerAccess(), new PcDoctor.Platform.Appx.WindowsAppxAccess(true), $@"HKU\{clientSid}"));

    /// <summary>Merges applied IDs into the drift manifest, stamped with the current OS version.</summary>
    public static void RecordApplied(IReadOnlyList<string> ids)
    {
        var previous = Load()?.TweakIds ?? [];
        var manifest = new PcDoctor.Tweaks.AppliedManifest(OsVersion(), previous.Union(ids).ToList(), DateTimeOffset.UtcNow);
        File.WriteAllText(ManifestPath, System.Text.Json.JsonSerializer.Serialize(manifest, PcDoctor.Tweaks.TweakCatalog.Json));
    }

    private static PcDoctor.Tweaks.AppliedManifest? Load()
    {
        try
        {
            return File.Exists(ManifestPath)
                ? System.Text.Json.JsonSerializer.Deserialize<PcDoctor.Tweaks.AppliedManifest>(File.ReadAllText(ManifestPath), PcDoctor.Tweaks.TweakCatalog.Json)
                : null;
        }
        catch (System.Text.Json.JsonException)
        {
            return null;
        }
    }
}
