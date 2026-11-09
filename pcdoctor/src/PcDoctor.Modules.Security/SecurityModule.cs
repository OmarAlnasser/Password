using System.Globalization;
using System.Runtime.Versioning;
using Microsoft.Win32;
using PcDoctor.Core.Findings;
using PcDoctor.Core.Ipc;
using PcDoctor.Core.Platform;
using PcDoctor.Core.Scanning;

namespace PcDoctor.Modules.Security;

public sealed class SecurityModule(Func<SecuritySnapshot> collect, Func<OsSupportConfig> support) : IModule
{
    public string Id => SecurityAnalyzer.ModuleId;
    public Text Name => new("m11.name");

    public async Task<ModuleResult> RunAsync(ScanContext context)
    {
        var snapshot = await Task.Run(collect, context.CancellationToken).ConfigureAwait(false);
        if (context.Elevated is { } e)
        {
            snapshot = snapshot with
            {
                Tpm = await e.ReadAsync<TpmStatus>(ElevatedData.Tpm, context.CancellationToken).ConfigureAwait(false),
                BitLocker = await e.ReadAsync<List<BitLockerVolume>>(ElevatedData.BitLocker, context.CancellationToken).ConfigureAwait(false),
            };
        }
        return SecurityAnalyzer.Analyze(snapshot, support(), context.Now);
    }

    [SupportedOSPlatform("windows")]
    public static SecurityModule ForWindows(string configOverridePath) =>
        new(SecurityReader.Read, () => OsSupportConfig.Load(configOverridePath));
}

[SupportedOSPlatform("windows")]
public static class SecurityReader
{
    public static SecuritySnapshot Read()
    {
        using var cv = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion");
        using var policies = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System");
        using var secureBoot = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Control\SecureBoot\State");
        using var ci = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Control\CI\Policy");
        using var lsa = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Control\Lsa");
        using var ts = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Control\Terminal Server");
        using var rdpTcp = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp");

        return new SecuritySnapshot
        {
            OsBuild = int.TryParse(cv?.GetValue("CurrentBuildNumber") as string, NumberStyles.Integer, CultureInfo.InvariantCulture, out var b) ? b : 0,
            OsEdition = cv?.GetValue("EditionID") as string ?? "",
            Defender = Try(ReadDefender),
            AvProducts = Try(() => Wmi.TryQuery(@"root\SecurityCenter2", "SELECT displayName, productState FROM AntiVirusProduct")
                ?.Select(r => new AvProduct(r.Str("displayName") ?? "?", (uint)(r.Long("productState") ?? 0))).ToList()),
            Firewall = Try(() => Wmi.TryQuery(@"root\StandardCimv2", "SELECT Name, Enabled FROM MSFT_NetFirewallProfile")
                // Enabled is a GPO boolean: 1 true, 0 false, 2 not configured (Windows default: on). VERIFY store.
                ?.Select(r => new FirewallProfile(r.Str("Name") ?? "?", r.Long("Enabled") switch { 1 => true, 0 => false, _ => null })).ToList()),
            EnableLua = policies?.GetValue("EnableLUA") as int?,
            ConsentPromptBehaviorAdmin = policies?.GetValue("ConsentPromptBehaviorAdmin") as int?,
            SecureBootEnabled = secureBoot?.GetValue("UEFISecureBootEnabled") is int sb ? sb != 0 : null,
            DeviceGuard = Try(ReadDeviceGuard),
            SmartAppControlState = ci?.GetValue("VerifiedAndReputablePolicyState") as int?,
            LsaRunAsPpl = lsa?.GetValue("RunAsPPL") as int?,
            Smb1InstallState = Try(() => (int?)Wmi.TryQuery(@"root\cimv2", "SELECT InstallState FROM Win32_OptionalFeature WHERE Name='SMB1Protocol'")
                ?.FirstOrDefault()?.Long("InstallState")),
            RdpDenyConnections = ts?.GetValue("fDenyTSConnections") as int?,
            RdpNla = rdpTcp?.GetValue("UserAuthentication") as int?,
            PendingRebootReasons = PendingReboot(),
            LastUpdateInstalled = Try(ReadLastUpdate),
            LocalAdministrators = Try(ReadAdministrators),
        };
    }

    /// <summary>Administrator only (Broker). Win32_Tpm lives in root\cimv2\Security\MicrosoftTpm.</summary>
    public static TpmStatus ReadTpm()
    {
        var row = Wmi.TryQuery(@"root\cimv2\Security\MicrosoftTpm", "SELECT IsEnabled_InitialValue, IsActivated_InitialValue, SpecVersion FROM Win32_Tpm")
            ?.FirstOrDefault();
        return row is null
            ? new TpmStatus(false, null, null, null)
            : new TpmStatus(true, row.Bool("IsEnabled_InitialValue"), row.Bool("IsActivated_InitialValue"), row.Str("SpecVersion"));
    }

    /// <summary>Administrator only (Broker).</summary>
    public static List<BitLockerVolume> ReadBitLocker() =>
        (Wmi.TryQuery(@"root\cimv2\Security\MicrosoftVolumeEncryption", "SELECT DriveLetter, ProtectionStatus, ConversionStatus FROM Win32_EncryptableVolume") ?? [])
        .Where(r => r.Str("DriveLetter") is not null)
        .Select(r => new BitLockerVolume(r.Str("DriveLetter")!, (int)(r.Long("ProtectionStatus") ?? 2), (int?)r.Long("ConversionStatus")))
        .ToList();

    private static DefenderStatus? ReadDefender()
    {
        var row = Wmi.TryQuery(@"root\Microsoft\Windows\Defender",
            "SELECT AMRunningMode, AntivirusEnabled, RealTimeProtectionEnabled, IsTamperProtected, AntivirusSignatureAge FROM MSFT_MpComputerStatus")
            ?.FirstOrDefault();
        return row is null ? null : new DefenderStatus(row.Str("AMRunningMode"), row.Bool("AntivirusEnabled"),
            row.Bool("RealTimeProtectionEnabled"), row.Bool("IsTamperProtected"), (int?)row.Long("AntivirusSignatureAge"));
    }

    private static DeviceGuardStatus? ReadDeviceGuard()
    {
        var row = Wmi.TryQuery(@"root\Microsoft\Windows\DeviceGuard",
            "SELECT VirtualizationBasedSecurityStatus, SecurityServicesRunning, CodeIntegrityPolicyEnforcementStatus FROM Win32_DeviceGuard")
            ?.FirstOrDefault();
        if (row is null)
        {
            return null;
        }
        var running = row.TryGetValue("SecurityServicesRunning", out var v) && v is uint[] arr ? arr.Select(x => (int)x).ToArray() : [];
        return new DeviceGuardStatus((int?)row.Long("VirtualizationBasedSecurityStatus"), running,
            (int?)row.Long("CodeIntegrityPolicyEnforcementStatus"));
    }

    private static List<string> PendingReboot()
    {
        var reasons = new List<string>();
        void Key(string path)
        {
            using var k = Registry.LocalMachine.OpenSubKey(path);
            if (k is not null)
            {
                reasons.Add(@"HKLM\" + path);
            }
        }
        Key(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending");
        Key(@"SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired");
        using var sm = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Control\Session Manager");
        if (sm?.GetValue("PendingFileRenameOperations") is string[] { Length: > 0 })
        {
            reasons.Add(@"HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations");
        }
        return reasons;
    }

    /// <summary>Newest hotfix install date. InstalledOn is a locale-formatted string. VERIFY on non-US locales.</summary>
    private static DateTime? ReadLastUpdate() =>
        Wmi.Query(@"root\cimv2", "SELECT InstalledOn FROM Win32_QuickFixEngineering")
            .Select(r => r.Str("InstalledOn"))
            .Select(s => DateTime.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.AssumeLocal, out var d)
                ? d
                : DateTime.TryParse(s, CultureInfo.CurrentCulture, DateTimeStyles.AssumeLocal, out d) ? d : (DateTime?)null)
            .Max();

    private static List<string> ReadAdministrators() =>
        Wmi.Query(@"root\cimv2",
                "SELECT PartComponent FROM Win32_GroupUser WHERE GroupComponent=\"Win32_Group.Domain='" + Environment.MachineName + "',Name='" +
                AdministratorsGroupName() + "'\"")
            .Select(r => r.Str("PartComponent") ?? "")
            .Select(p => p[(p.IndexOf("Name=\"", StringComparison.Ordinal) + 6)..].TrimEnd('"'))
            .ToList();

    /// <summary>The Administrators group name is localized; resolve it from S-1-5-32-544.</summary>
    private static string AdministratorsGroupName() =>
        new System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
            .Translate(typeof(System.Security.Principal.NTAccount)).Value.Split('\\').Last();

    private static T? Try<T>(Func<T?> read)
    {
        try
        {
            return read();
        }
        catch (Exception ex) when (ex is System.Management.ManagementException or UnauthorizedAccessException
                                       or System.Runtime.InteropServices.COMException or TimeoutException)
        {
            return default;
        }
    }
}
