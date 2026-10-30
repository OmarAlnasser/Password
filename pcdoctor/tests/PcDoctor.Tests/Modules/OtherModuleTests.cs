using PcDoctor.Core.Findings;
using PcDoctor.Modules.Battery;
using PcDoctor.Modules.Drivers;
using PcDoctor.Modules.Security;
using Xunit;

namespace PcDoctor.Tests.Modules;

public sealed class DriversTests
{
    private static readonly DateTimeOffset Now = new(2026, 10, 30, 0, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Codes_45_and_22_are_hidden_by_default()
    {
        var result = DriversAnalyzer.Analyze(new DriversSnapshot
        {
            ProblemDevices =
            [
                new ProblemDevice("USB headset", @"USB\VID_1234", 45, "AudioEndpoint"),
                new ProblemDevice("Bluetooth", @"BTH\1", 22, "Bluetooth"),
                new ProblemDevice("Contoso GPU", @"PCI\VEN_10DE", 43, "Display"),
            ],
        }, Now);
        Assert.Equal(2, result.Findings.Count(f => f.HiddenByDefault));
        var visible = Assert.Single(result.Findings, f => !f.HiddenByDefault);
        Assert.Equal(Severity.Medium, visible.Severity);
        Assert.Equal("m9.code.43", visible.WhyItMatters.Key);
        TextAssert.AllResolve(result);
    }

    [Fact]
    public void WinRing0_is_reported_with_owning_folder()
    {
        var result = DriversAnalyzer.Analyze(new DriversSnapshot
        {
            SystemDrivers =
            [
                new SystemDriver("WinRing0_1_2_0", @"C:\Program Files\FanTool\WinRing0x64.sys", "Running", "Manual"),
                new SystemDriver("disk", @"C:\Windows\system32\drivers\disk.sys", "Running", "Boot"),
            ],
        }, Now);
        var f = Assert.Single(result.Findings);
        Assert.Equal(Severity.High, f.Severity);
        Assert.Contains(@"C:\Program Files\FanTool", f.Title.Args);
    }

    [Fact]
    public void Old_inbox_drivers_are_not_flagged_and_old_third_party_ones_are_grouped()
    {
        var result = DriversAnalyzer.Analyze(new DriversSnapshot
        {
            Drivers =
            [
                new SignedDriver("Generic volume", "Microsoft", "10.0", new DateTime(2006, 6, 21), true, "volume.inf"),
                new SignedDriver("Old card reader", "Contoso", "1.0", new DateTime(2012, 1, 1), true, "oem12.inf"),
                new SignedDriver("Old card reader #2", "Contoso", "1.0", new DateTime(2012, 1, 1), true, "oem12.inf"),
                new SignedDriver("Hacked", "Unknown", "0.1", new DateTime(2024, 1, 1), false, "oem99.inf"),
            ],
        }, Now);
        var old = Assert.Single(result.Findings, f => f.Id == "M9.old");
        Assert.Single(old.Evidence);
        Assert.Equal(FindingSource.Heuristic, old.Source);
        Assert.Single(result.Findings, f => f.Id == "M9.unsigned");
        TextAssert.AllResolve(result);
    }
}

public sealed class BatteryTests
{
    [Fact]
    public void Battery_report_xml_is_parsed()
    {
        var b = Assert.Single(BatteryReportParser.Parse(Fixtures.Text("batteryreport.xml")));
        Assert.Equal(56000, b.DesignCapacityMwh);
        Assert.Equal(40320, b.FullChargeCapacityMwh);
        Assert.Equal(412, b.CycleCount);
        Assert.Equal(72.0, Math.Round(b.HealthPercent, 1));
    }

    [Fact]
    public void Worn_battery_is_low_and_heuristic_wording_is_used()
    {
        var result = BatteryAnalyzer.Analyze(BatteryReportParser.Parse(Fixtures.Text("batteryreport.xml")));
        var f = Assert.Single(result.Findings);
        Assert.Equal(Severity.Low, f.Severity);
        Assert.Equal(Confidence.Probable, f.Confidence);
        TextAssert.AllResolve(result);
    }

    [Fact]
    public void Desktop_without_battery_is_not_available_not_hidden()
    {
        var result = BatteryAnalyzer.Analyze([]);
        Assert.Contains(result.Checks, c => c.Status == CheckStatus.NotAvailable);
        Assert.Empty(result.Findings);
    }
}

public sealed class SecurityTests
{
    private static readonly DateTimeOffset Now = new(2026, 10, 30, 0, 0, 0, TimeSpan.Zero);
    private static readonly OsSupportConfig Support = OsSupportConfig.Load();

    private static SecuritySnapshot Healthy11 => new()
    {
        OsBuild = 26100,
        Defender = new DefenderStatus("Normal", true, true, true, 0),
        AvProducts = [new AvProduct("Windows Defender", 0x61100)],
        Firewall = [new FirewallProfile("Domain", true), new FirewallProfile("Private", true), new FirewallProfile("Public", true)],
        EnableLua = 1,
        ConsentPromptBehaviorAdmin = 5,
        SecureBootEnabled = true,
        DeviceGuard = new DeviceGuardStatus(2, [2], 1),
        SmartAppControlState = 0,
        LsaRunAsPpl = 2,
        Smb1InstallState = 2,
        RdpDenyConnections = 1,
        LastUpdateInstalled = new DateTime(2026, 10, 14),
        LocalAdministrators = ["owner"],
    };

    [Fact]
    public void Healthy_windows_11_has_no_findings_and_lists_deep_scan_items()
    {
        var result = SecurityAnalyzer.Analyze(Healthy11, Support, Now);
        Assert.Empty(result.Findings);
        Assert.Contains(result.Checks, c => c.Id == "M11.tpm" && c.Status == CheckStatus.NotChecked);
        Assert.Contains(result.Checks, c => c.Id == "M11.bitlocker" && c.Status == CheckStatus.NotChecked);
        TextAssert.AllResolve(result);
    }

    [Fact]
    public void Third_party_av_means_no_defender_result_is_shown()
    {
        var s = Healthy11 with
        {
            Defender = new DefenderStatus("Passive Mode", false, false, true, 30),
            AvProducts = [new AvProduct("Windows Defender", 0x60100), new AvProduct("Contoso Antivirus", 0x41000)],
        };
        var result = SecurityAnalyzer.Analyze(s, Support, Now);
        var av = Assert.Single(result.Checks, c => c.Id == "M11.av");
        Assert.Equal(CheckStatus.Info, av.Status);
        Assert.Equal("m11.av.thirdParty", av.Detail!.Key);
        Assert.Contains("Contoso Antivirus", av.Detail.Args);
        // No real-time, tamper or signature verdicts from a Defender that is not the active AV.
        Assert.DoesNotContain(result.Checks, c => c.Id is "M11.rtp" or "M11.tamper" or "M11.signatures");
        Assert.DoesNotContain(result.Findings, f => f.Source == FindingSource.Defender);
    }

    [Fact]
    public void No_active_antivirus_is_critical()
    {
        var s = Healthy11 with
        {
            Defender = new DefenderStatus("Not running", false, false, false, null),
            AvProducts = [new AvProduct("Windows Defender", 0x60100)],
        };
        var f = Assert.Single(SecurityAnalyzer.Analyze(s, Support, Now).Findings);
        Assert.Equal(Severity.Critical, f.Severity);
    }

    [Fact]
    public void Windows_10_gets_the_support_banner_with_configured_dates()
    {
        var result = SecurityAnalyzer.Analyze(Healthy11 with { OsBuild = 19045 }, Support, Now);
        var f = Assert.Single(result.Findings, x => x.Id == "M11.win10");
        Assert.Equal(Severity.High, f.Severity);
        Assert.Contains(f.Evidence, e => e.Value.Contains("(unverified)", StringComparison.Ordinal));
        Assert.Equal("2025-10-14", f.Title.Args[0]);
        TextAssert.AllResolve(result);
    }

    [Fact]
    public void Esu_dates_come_from_the_override_file_when_present()
    {
        var path = Path.GetTempFileName();
        File.WriteAllText(path, """{"asOf":"2027-01-01","windows10":{"endOfSupport":"2025-10-14","esu":[{"program":"X","ends":"2030-01-01"}],"guidanceUrl":"https://example.test"}}""");
        try
        {
            Assert.Equal(new DateOnly(2030, 1, 1), OsSupportConfig.Load(path).Esu.Single().Ends);
            File.WriteAllText(path, "{ broken");
            Assert.True(OsSupportConfig.Load(path).Esu.Count >= 1);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void Weak_settings_produce_categorized_findings()
    {
        var s = Healthy11 with
        {
            Firewall = [new FirewallProfile("Public", false)],
            EnableLua = 0,
            Smb1InstallState = 1,
            RdpDenyConnections = 0,
            RdpNla = 0,
            PendingRebootReasons = [@"HKLM\...\RebootRequired"],
            LastUpdateInstalled = new DateTime(2026, 5, 1),
        };
        var result = SecurityAnalyzer.Analyze(s, Support, Now);
        Assert.Equal(Severity.High, result.Findings.Single(f => f.Id == "M11.firewall").Severity);
        Assert.Equal(Severity.High, result.Findings.Single(f => f.Id == "M11.uac").Severity);
        Assert.Contains(result.Findings, f => f.Id == "M11.smb1");
        Assert.Contains(result.Findings, f => f.Id == "M11.rdp");
        Assert.Contains(result.Findings, f => f.Id == "M11.reboot");
        Assert.Contains(result.Findings, f => f.Id == "M11.lastUpdate");
        TextAssert.AllResolve(result);
    }
}
