using System.Text.Json;
using System.Text.Json.Serialization;
using PcDoctor.Core.Journal;
using PcDoctor.Core.Platform;

namespace PcDoctor.Tweaks;

public enum Tier { Recommended, Limited, Advanced }

public enum TweakState { Applied, NotApplied, Partial, NotApplicable, Unknown }

/// <summary>One change a tweak makes, also used as its detect probe ("is it already like this?").</summary>
[JsonPolymorphic(TypeDiscriminatorPropertyName = "type")]
[JsonDerivedType(typeof(RegistryAction), "registry")]
[JsonDerivedType(typeof(ServiceAction), "service")]
[JsonDerivedType(typeof(TaskAction), "task")]
[JsonDerivedType(typeof(AppxAction), "appx")]
public abstract record TweakAction;

/// <param name="Hive">HKLM or HKCU.</param>
public sealed record RegistryAction(string Hive, string Key, string Name, string Kind, string Value) : TweakAction;

public sealed record ServiceAction(string Service, string StartType) : TweakAction;

public sealed record TaskAction(string Path, bool Enabled) : TweakAction;

/// <summary>Removes an app for every user and deprovisions it so feature updates do not bring it back.</summary>
public sealed record AppxAction(string PackageFamilyPrefix, string StoreId) : TweakAction;

public sealed record AppliesTo(int MinBuild = 0, int MaxBuild = int.MaxValue, IReadOnlyList<string>? Editions = null, bool CopilotPlusOnly = false);

public sealed record Tweak
{
    public required string Id { get; init; }
    public required string Category { get; init; }
    public required Tier Tier { get; init; }
    public AppliesTo AppliesTo { get; init; } = new();
    public required IReadOnlyList<TweakAction> Actions { get; init; }
    public bool RequiresRestart { get; init; }
    public bool SignOut { get; init; }
    public bool ExplorerRestart { get; init; }
    /// <summary>A policy value: the setting shows as "managed by your organization" in Settings until undone.</summary>
    public bool LocksSetting { get; init; }
    /// <summary>Shown before applying, and per item for Advanced.</summary>
    public bool HasWarning { get; init; }
    public IReadOnlyList<string> References { get; init; } = [];
}

public sealed record TweakCatalog(int Version, IReadOnlyList<Tweak> Tweaks)
{
    public static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter() },
        ReadCommentHandling = JsonCommentHandling.Skip,
    };

    public static TweakCatalog Load()
    {
        using var stream = typeof(TweakCatalog).Assembly.GetManifestResourceStream("PcDoctor.Tweaks.tweaks.json")!;
        return JsonSerializer.Deserialize<TweakCatalog>(stream, Json)!;
    }

    public Tweak? Find(string id) => Tweaks.FirstOrDefault(t => t.Id == id);
}

public sealed record OsInfo(int Build, string Edition, bool CopilotPlus);

/// <summary>Read-only state for detection; the Windows implementations are the same ones the journal uses.</summary>
public interface IAppxAccess
{
    /// <summary>True if any user has the package installed or it is provisioned for new users.</summary>
    bool IsPresent(string packageFamilyPrefix);
}

public sealed record DetectContext(IRegistryAccess Registry, IServiceConfigAccess Services, ITaskSchedulerAccess Tasks, IAppxAccess? Appx, string UserHive);

public static class TweakEngine
{
    /// <summary>Things no preset may ever touch (DESIGN: never disable Update, Defender, the Store, Edge, WebView2, the pagefile, mitigations).</summary>
    private static readonly string[] ForbiddenFragments =
    [
        "Windows Defender\\DisableAntiSpyware", "Windows Defender\\Real-Time Protection", "\\Spynet", "TamperProtection", "Exclusions",
        "WindowsUpdate\\AU\\NoAutoUpdate", "DisableWindowsUpdateAccess", "SetDisableUXWUAccess", "PagingFiles", "FeatureSettingsOverride",
        // Security features PC Doctor never turns off, whatever a catalog says: memory integrity / VBS, SmartScreen, UAC, exploit mitigations.
        "DeviceGuard", "HypervisorEnforcedCodeIntegrity", "DisableRealtimeMonitoring", "DisableAntiVirus", "EnableSmartScreen", "SmartScreenEnabled",
        "Policies\\System\\EnableLUA", "MitigationOptions", "Windows Defender Security Center", "\\Services\\wuauserv", "\\Services\\WinDefend",
    ];

    private static readonly string[] ProtectedServices = ["wuauserv", "BITS", "WinDefend", "WdNisSvc", "Sense", "mpssvc", "UsoSvc", "WaaSMedicSvc", "TrustedInstaller"];

    private static readonly string[] ProtectedApps =
        ["Microsoft.WindowsStore", "Microsoft.DesktopAppInstaller", "Microsoft.WebView2", "Microsoft.MicrosoftEdge", "Microsoft.SecHealthUI", "Microsoft.VCLibs", "Microsoft.UI.Xaml", "Microsoft.NET",
         "Microsoft.StorePurchaseApp", "Microsoft.WindowsAppRuntime", "Microsoft.Windows.ShellExperienceHost", "Microsoft.Windows.StartMenuExperienceHost", "MicrosoftWindows.Client",
         "Microsoft.Windows.Search", "Microsoft.AAD.BrokerPlugin", "Microsoft.Windows.CloudExperienceHost", "Microsoft.LockApp", "Microsoft.AccountsControl", "windows.immersivecontrolpanel"];

    /// <summary>Validates the catalog itself. A catalog that breaks a rule is rejected entirely.</summary>
    public static IReadOnlyList<string> Violations(TweakCatalog catalog)
    {
        var v = new List<string>();
        foreach (var t in catalog.Tweaks)
        {
            foreach (var a in t.Actions)
            {
                switch (a)
                {
                    case RegistryAction r when ForbiddenFragments.Any(f => $@"{r.Key}\{r.Name}".Contains(f, StringComparison.OrdinalIgnoreCase)):
                        v.Add($"{t.Id}: forbidden registry target {r.Key}\\{r.Name}");
                        break;
                    case RegistryAction r when r.Hive is not ("HKLM" or "HKCU"):
                        v.Add($"{t.Id}: unsupported hive {r.Hive}");
                        break;
                    case ServiceAction s when ProtectedServices.Contains(s.Service, StringComparer.OrdinalIgnoreCase):
                        v.Add($"{t.Id}: protected service {s.Service}");
                        break;
                    case ServiceAction s when s.StartType is not ("Automatic" or "Manual" or "Disabled"):
                        v.Add($"{t.Id}: start type {s.StartType}");
                        break;
                    case AppxAction x when ProtectedApps.Any(p => x.PackageFamilyPrefix.StartsWith(p, StringComparison.OrdinalIgnoreCase)):
                        v.Add($"{t.Id}: protected app {x.PackageFamilyPrefix}");
                        break;
                }
            }
            if (t.Actions.Count == 0)
            {
                v.Add($"{t.Id}: no actions");
            }
        }
        foreach (var dup in catalog.Tweaks.GroupBy(t => t.Id).Where(g => g.Count() > 1))
        {
            v.Add($"duplicate id {dup.Key}");
        }
        return v;
    }

    public static bool Applies(Tweak t, OsInfo os) =>
        os.Build >= t.AppliesTo.MinBuild && os.Build <= t.AppliesTo.MaxBuild &&
        (t.AppliesTo.Editions is null || t.AppliesTo.Editions.Contains(os.Edition, StringComparer.OrdinalIgnoreCase)) &&
        (!t.AppliesTo.CopilotPlusOnly || os.CopilotPlus);

    public static TweakState Detect(Tweak t, OsInfo os, DetectContext ctx)
    {
        if (!Applies(t, os))
        {
            return TweakState.NotApplicable;
        }
        var results = t.Actions.Select(a => IsInPlace(a, ctx)).ToList();
        if (results.Any(r => r is null))
        {
            return TweakState.Unknown;
        }
        return results.All(r => r == true) ? TweakState.Applied : results.Any(r => r == true) ? TweakState.Partial : TweakState.NotApplied;
    }

    private static bool? IsInPlace(TweakAction a, DetectContext ctx)
    {
        try
        {
            return a switch
            {
                RegistryAction r => Equals(ctx.Registry.Read(r.Hive == "HKCU" ? ctx.UserHive : "HKLM", r.Key, r.Name), new RegistryData(r.Kind, r.Value)),
                ServiceAction s => ctx.Services.Read(s.Service) is { } cur ? cur.StartType == s.StartType : true, // absent service: nothing to do
                TaskAction k => ctx.Tasks.IsEnabled(k.Path) is { } en ? en == k.Enabled : true,
                AppxAction x => ctx.Appx is null ? null : !ctx.Appx.IsPresent(x.PackageFamilyPrefix),
                _ => null,
            };
        }
        catch (Exception ex) when (ex is UnauthorizedAccessException or System.Security.SecurityException or IOException)
        {
            return null;
        }
    }

    /// <summary>The planned changes for tweaks, skipping actions already in place. Never anything from a catalog with violations.</summary>
    public static IReadOnlyList<PlannedChange>? Plan(TweakCatalog catalog, IReadOnlyList<string> ids, OsInfo os, DetectContext ctx)
    {
        if (Violations(catalog).Count > 0)
        {
            return null;
        }
        var plan = new List<PlannedChange>();
        foreach (var id in ids)
        {
            if (catalog.Find(id) is not { } t || !Applies(t, os))
            {
                return null;
            }
            foreach (var a in t.Actions.Where(a => IsInPlace(a, ctx) != true))
            {
                plan.Add(a switch
                {
                    RegistryAction r => new PlannedRegistrySet(r.Hive, r.Key, r.Name, new RegistryData(r.Kind, r.Value)),
                    ServiceAction s => new PlannedServiceStart(s.Service, s.StartType, false),
                    TaskAction k => new PlannedTaskEnabled(k.Path, k.Enabled),
                    AppxAction x => new PlannedAppxRemove(x.PackageFamilyPrefix, x.StoreId),
                    _ => throw new NotSupportedException(),
                });
            }
        }
        return plan;
    }

    public static IReadOnlyList<Tweak> Preset(TweakCatalog catalog, string preset, OsInfo os) => preset switch
    {
        "recommended" => catalog.Tweaks.Where(t => t.Tier == Tier.Recommended && Applies(t, os)).ToList(),
        // Windows AI features and extra apps are picked from the checklist, item by item: one button never removes a pile of apps.
        "limited" => catalog.Tweaks.Where(t => (t.Tier == Tier.Recommended || (t.Tier == Tier.Limited && t.Category is not ("ai" or "apps"))) && Applies(t, os)).ToList(),
        // Advanced is never a preset: each Advanced item is chosen and confirmed on its own.
        _ => [],
    };
}

/// <summary>
/// Drift: Windows feature updates reset some settings. The manifest of applied tweak IDs is stored
/// with the OS version; when the version changes, applied tweaks are detected again.
/// </summary>
public sealed record AppliedManifest(string OsVersion, IReadOnlyList<string> TweakIds, DateTimeOffset AppliedUtc)
{
    public IReadOnlyList<string> Drifted(string currentOsVersion, Func<string, TweakState> detect) =>
        currentOsVersion == OsVersion ? [] : TweakIds.Where(id => detect(id) is TweakState.NotApplied or TweakState.Partial).ToList();
}
