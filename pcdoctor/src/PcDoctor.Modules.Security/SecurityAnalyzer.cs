using System.Globalization;
using PcDoctor.Core.Findings;
using PcDoctor.Core.Scanning;

namespace PcDoctor.Modules.Security;

/// <summary>
/// M11 security posture: categorized pass / warn / fail, each with why it matters. No single score.
/// </summary>
public sealed class SecurityAnalyzer
{
    public const string ModuleId = "M11";
    private readonly List<CheckResult> _checks = [];
    private readonly List<Finding> _findings = [];

    public static ModuleResult Analyze(SecuritySnapshot s, OsSupportConfig support, DateTimeOffset now)
    {
        var a = new SecurityAnalyzer();
        a.OsSupport(s, support, now);
        a.Antivirus(s);
        a.Firewall(s);
        a.Uac(s);
        a.Platform(s);
        a.Network(s);
        a.Updates(s, now);
        a.Accounts(s);
        a._checks.Add(Checks.NotBuiltYet("M11.winget", new Text("m11.check.winget"), "P7"));
        return new ModuleResult { ModuleId = ModuleId, ModuleName = new Text("m11.name"), Checks = a._checks, Findings = a._findings };
    }

    private void Add(string id, string key, CheckStatus status, FindingSource source, Text? detail = null,
        Severity? severity = null, IReadOnlyList<Evidence>? evidence = null, Confidence confidence = Confidence.Confirmed,
        params object[] titleArgs)
    {
        _checks.Add(new CheckResult(id, new Text(key + ".check"), status, detail, source));
        if (status is CheckStatus.Warn or CheckStatus.Fail && severity is { } sev)
        {
            _findings.Add(new Finding
            {
                Id = id,
                Module = ModuleId,
                Severity = sev,
                Confidence = confidence,
                Source = source,
                Title = new Text(key + ".title", titleArgs),
                WhyItMatters = new Text(key + ".why"),
                Evidence = evidence ?? [],
                SuggestedAction = new Text(key + ".action"),
                Undo = UndoInfo.NothingChanged,
            });
        }
    }

    private static Evidence Reg(string path, object? value) =>
        new(path, value is null ? "(absent)" : Convert.ToString(value, CultureInfo.InvariantCulture)!, EvidenceKind.RegistryValue);

    private void OsSupport(SecuritySnapshot s, OsSupportConfig support, DateTimeOffset now)
    {
        if (s.OsBuild is > 0 and < 22000)
        {
            var today = DateOnly.FromDateTime(now.UtcDateTime);
            var active = support.Esu.Where(e => e.Ends >= today).ToList();
            Add("M11.win10", "m11.win10", CheckStatus.Fail, FindingSource.Registry,
                new Text("m11.win10.detail", support.Windows10EndOfSupport), Severity.High,
                support.Esu.Select(e => new Evidence(e.Program,
                        $"ends {e.Ends:yyyy-MM-dd}{(e.Verify ? " (unverified)" : "")}{(e.Note is null ? "" : " — " + e.Note)}"))
                    .Append(new Evidence("Dates as of", support.AsOf.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)))
                    .Append(new Evidence("Guidance", support.GuidanceUrl))
                    .ToList(),
                titleArgs: [support.Windows10EndOfSupport, active.Count]);
        }
        else if (s.OsBuild >= 22000)
        {
            _checks.Add(new CheckResult("M11.win10", new Text("m11.win10.check"), CheckStatus.Pass,
                new Text("m11.win11.detail", s.OsBuild), FindingSource.Registry));
        }
    }

    private void Antivirus(SecuritySnapshot s)
    {
        var d = s.Defender;
        var thirdParty = s.AvProducts?.Where(p => !p.IsDefender && p.IsEnabled == true).ToList() ?? [];
        if (d is null && s.AvProducts is null)
        {
            _checks.Add(Checks.NotAvailable("M11.av", new Text("m11.av.check")));
            return;
        }

        var defenderActive = d is { AntivirusEnabled: true } &&
                             string.Equals(d.AMRunningMode, "Normal", StringComparison.OrdinalIgnoreCase);
        if (!defenderActive)
        {
            if (thirdParty.Count > 0)
            {
                // Never fake a Defender result: say who the active AV is.
                _checks.Add(new CheckResult("M11.av", new Text("m11.av.check"), CheckStatus.Info,
                    new Text("m11.av.thirdParty", string.Join(", ", thirdParty.Select(p => p.DisplayName)), d?.AMRunningMode ?? "?"),
                    FindingSource.Wmi));
            }
            else
            {
                Add("M11.av", "m11.noAv", CheckStatus.Fail, FindingSource.Wmi, null, Severity.Critical,
                    [new Evidence("AMRunningMode", d?.AMRunningMode ?? "?"),
                     new Evidence("AntivirusEnabled", d?.AntivirusEnabled?.ToString() ?? "?"),
                     new Evidence("SecurityCenter2 products", string.Join(", ", s.AvProducts?.Select(p => $"{p.DisplayName} (0x{p.ProductState:X})") ?? []))],
                    Confidence.Probable);
            }
            return;
        }

        _checks.Add(new CheckResult("M11.av", new Text("m11.av.check"), CheckStatus.Pass, new Text("m11.av.defender"), FindingSource.Defender));
        var evidence = new List<Evidence>
        {
            new("AMRunningMode", d!.AMRunningMode ?? "?"),
            new("RealTimeProtectionEnabled", d.RealTimeProtectionEnabled?.ToString() ?? "?"),
            new("IsTamperProtected", d.IsTamperProtected?.ToString() ?? "?"),
            new("Signature age (days)", d.SignatureAgeDays?.ToString(CultureInfo.InvariantCulture) ?? "?"),
        };
        Add("M11.rtp", "m11.rtp", d.RealTimeProtectionEnabled == false ? CheckStatus.Fail : CheckStatus.Pass,
            FindingSource.Defender, null, Severity.High, evidence);
        Add("M11.tamper", "m11.tamper", d.IsTamperProtected == false ? CheckStatus.Warn : CheckStatus.Pass,
            FindingSource.Defender, null, Severity.Medium, evidence);
        Add("M11.signatures", "m11.signatures", d.SignatureAgeDays is > 3 ? CheckStatus.Warn : CheckStatus.Pass,
            FindingSource.Defender, null, Severity.Low, evidence, titleArgs: [d.SignatureAgeDays ?? 0]);
    }

    private void Firewall(SecuritySnapshot s)
    {
        if (s.Firewall is null)
        {
            _checks.Add(Checks.NotAvailable("M11.firewall", new Text("m11.firewall.check")));
            return;
        }
        var off = s.Firewall.Where(p => p.Enabled == false).ToList();
        Add("M11.firewall", "m11.firewall", off.Count == 0 ? CheckStatus.Pass : CheckStatus.Fail, FindingSource.Wmi,
            new Text("m11.firewall.detail", string.Join(", ", s.Firewall.Select(p => $"{p.Name}={(p.Enabled is null ? "default" : p.Enabled.Value ? "on" : "off")}"))),
            off.Any(p => p.Name.Equals("Public", StringComparison.OrdinalIgnoreCase)) ? Severity.High : Severity.Medium,
            off.Select(p => new Evidence($"MSFT_NetFirewallProfile[{p.Name}].Enabled", "False")).ToList(),
            titleArgs: [string.Join(", ", off.Select(p => p.Name))]);
    }

    private void Uac(SecuritySnapshot s)
    {
        const string key = @"HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System";
        var evidence = new[] { Reg(key + @"\EnableLUA", s.EnableLua), Reg(key + @"\ConsentPromptBehaviorAdmin", s.ConsentPromptBehaviorAdmin) };
        Add("M11.uac", "m11.uac", s.EnableLua == 0 ? CheckStatus.Fail : CheckStatus.Pass, FindingSource.Registry, null, Severity.High, evidence);
        if (s.EnableLua != 0)
        {
            Add("M11.uacPrompt", "m11.uacPrompt", s.ConsentPromptBehaviorAdmin == 0 ? CheckStatus.Warn : CheckStatus.Pass,
                FindingSource.Registry, null, Severity.Medium, evidence);
        }
    }

    private void Platform(SecuritySnapshot s)
    {
        if (s.SecureBootEnabled is null)
        {
            _checks.Add(Checks.NotAvailable("M11.secureBoot", new Text("m11.secureBoot.check"), new Text("m11.secureBoot.legacy")));
        }
        else
        {
            Add("M11.secureBoot", "m11.secureBoot", s.SecureBootEnabled.Value ? CheckStatus.Pass : CheckStatus.Warn,
                FindingSource.Registry, null, Severity.Medium,
                [Reg(@"HKLM\SYSTEM\CurrentControlSet\Control\SecureBoot\State\UEFISecureBootEnabled", s.SecureBootEnabled.Value ? 1 : 0)]);
        }

        if (s.Tpm is null)
        {
            _checks.Add(Checks.NeedsDeepScan("M11.tpm", new Text("m11.tpm.check")));
        }
        else
        {
            var ok = s.Tpm.Present && s.Tpm.Enabled != false && s.Tpm.Activated != false;
            Add("M11.tpm", "m11.tpm", ok ? CheckStatus.Pass : CheckStatus.Warn, FindingSource.Wmi,
                new Text("m11.tpm.detail", s.Tpm.SpecVersion ?? "?"), Severity.Low,
                [new Evidence("Win32_Tpm", $"present={s.Tpm.Present} enabled={s.Tpm.Enabled} activated={s.Tpm.Activated} spec={s.Tpm.SpecVersion}")]);
        }

        if (s.BitLocker is null)
        {
            _checks.Add(Checks.NeedsDeepScan("M11.bitlocker", new Text("m11.bitlocker.check")));
        }
        else
        {
            var system = s.BitLocker.FirstOrDefault(v => v.DriveLetter.StartsWith("C", StringComparison.OrdinalIgnoreCase));
            // Win32_EncryptableVolume.ProtectionStatus: 0 off, 1 on, 2 unknown (locked).
            Add("M11.bitlocker", "m11.bitlocker", system is { ProtectionStatus: 1 } ? CheckStatus.Pass : CheckStatus.Warn,
                FindingSource.Wmi, null, Severity.Low,
                s.BitLocker.Select(v => new Evidence($"{v.DriveLetter} ProtectionStatus", v.ProtectionStatus.ToString(CultureInfo.InvariantCulture))).ToList());
        }

        if (s.DeviceGuard is null)
        {
            _checks.Add(Checks.NotAvailable("M11.vbs", new Text("m11.vbs.check")));
        }
        else
        {
            var dg = s.DeviceGuard;
            var hvci = dg.SecurityServicesRunning.Contains(2);
            _checks.Add(new CheckResult("M11.vbs", new Text("m11.vbs.check"), dg.VbsStatus == 2 ? CheckStatus.Pass : CheckStatus.Info,
                new Text("m11.vbs.detail", dg.VbsStatus ?? -1), FindingSource.Wmi));
            Add("M11.hvci", "m11.hvci", hvci ? CheckStatus.Pass : CheckStatus.Warn, FindingSource.Wmi, null, Severity.Low,
                [new Evidence("Win32_DeviceGuard.SecurityServicesRunning", string.Join(", ", dg.SecurityServicesRunning)),
                 new Evidence("VirtualizationBasedSecurityStatus", dg.VbsStatus?.ToString(CultureInfo.InvariantCulture) ?? "?")]);
        }

        if (s.OsBuild >= 22621)
        {
            // Smart App Control: once turned off it cannot be turned back on without a reset/reinstall.
            _checks.Add(new CheckResult("M11.sac", new Text("m11.sac.check"),
                s.SmartAppControlState switch { 1 => CheckStatus.Pass, _ => CheckStatus.Info },
                new Text(s.SmartAppControlState switch { 1 => "m11.sac.on", 2 => "m11.sac.eval", 0 => "m11.sac.off", _ => "check.notAvailable" }),
                FindingSource.Registry));
        }

        Add("M11.lsa", "m11.lsa", s.LsaRunAsPpl is 1 or 2 ? CheckStatus.Pass : CheckStatus.Warn, FindingSource.Registry, null, Severity.Low,
            [Reg(@"HKLM\SYSTEM\CurrentControlSet\Control\Lsa\RunAsPPL", s.LsaRunAsPpl)]);
    }

    private void Network(SecuritySnapshot s)
    {
        if (s.Smb1InstallState is null)
        {
            _checks.Add(Checks.NotAvailable("M11.smb1", new Text("m11.smb1.check")));
        }
        else
        {
            Add("M11.smb1", "m11.smb1", s.Smb1InstallState == 1 ? CheckStatus.Fail : CheckStatus.Pass, FindingSource.Wmi, null,
                Severity.Medium, [new Evidence("Win32_OptionalFeature[SMB1Protocol].InstallState", s.Smb1InstallState.Value.ToString(CultureInfo.InvariantCulture))]);
        }

        const string ts = @"HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server";
        var evidence = new[] { Reg(ts + @"\fDenyTSConnections", s.RdpDenyConnections), Reg(ts + @"\WinStations\RDP-Tcp\UserAuthentication", s.RdpNla) };
        if (s.RdpDenyConnections == 0)
        {
            Add("M11.rdp", "m11.rdp", s.RdpNla == 0 ? CheckStatus.Fail : CheckStatus.Info, FindingSource.Registry,
                new Text(s.RdpNla == 0 ? "m11.rdp.noNla" : "m11.rdp.nla"), Severity.Medium, evidence);
        }
        else
        {
            _checks.Add(new CheckResult("M11.rdp", new Text("m11.rdp.check"), CheckStatus.Pass, new Text("m11.rdp.off"), FindingSource.Registry));
        }
    }

    private void Updates(SecuritySnapshot s, DateTimeOffset now)
    {
        Add("M11.reboot", "m11.reboot", s.PendingRebootReasons.Count > 0 ? CheckStatus.Warn : CheckStatus.Pass, FindingSource.Registry,
            null, Severity.Low, s.PendingRebootReasons.Select(r => new Evidence("Pending", r, EvidenceKind.RegistryValue)).ToList());

        if (s.LastUpdateInstalled is not { } last)
        {
            _checks.Add(Checks.NotAvailable("M11.lastUpdate", new Text("m11.lastUpdate.check")));
            return;
        }
        var days = (int)(now - new DateTimeOffset(DateTime.SpecifyKind(last, DateTimeKind.Utc))).TotalDays;
        Add("M11.lastUpdate", "m11.lastUpdate", days > 60 ? CheckStatus.Warn : CheckStatus.Pass, FindingSource.Wmi,
            new Text("m11.lastUpdate.detail", last.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)), Severity.Medium,
            [new Evidence("Win32_QuickFixEngineering newest InstalledOn", last.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture))],
            Confidence.Probable, titleArgs: [days]);
    }

    private void Accounts(SecuritySnapshot s)
    {
        if (s.LocalAdministrators is null)
        {
            _checks.Add(Checks.NotAvailable("M11.admins", new Text("m11.admins.check")));
            return;
        }
        _checks.Add(new CheckResult("M11.admins", new Text("m11.admins.check"), CheckStatus.Info,
            new Text("m11.admins.detail", s.LocalAdministrators.Count, string.Join(", ", s.LocalAdministrators)), FindingSource.Wmi));
    }
}
