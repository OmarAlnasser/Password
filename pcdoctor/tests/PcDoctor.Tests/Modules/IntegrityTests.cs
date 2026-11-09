using PcDoctor.Core.Findings;
using PcDoctor.Modules.Integrity;
using Xunit;

namespace PcDoctor.Tests.Modules;

public sealed class IntegrityTests
{
    private const string Cbs = """
        2026-11-09 09:00:01, Info                  CSI    00000001 [SR] Verifying 100 components
        2026-11-09 10:00:02, Info                  CSI    00000002 [SR] Beginning Verify and Repair transaction
        2026-11-09 10:01:10, Info                  CSI    00000003 [SR] Cannot repair member file [l:24]"amd64_microsoft-windows-x.dll" of Microsoft-Windows-X
        2026-11-09 10:01:11, Info                  CSI    00000004 [SR] Repairing corrupted file \??\C:\Windows\System32\drivers\etc\protocol from store
        2026-11-09 10:01:12, Info                  CSI    00000005 [SR] Cannot repair member file [l:10]"evil.dll" of Microsoft-Windows-Y
        2026-11-09 10:01:13, Info                  CSI    00000006 [SR] Repaired file \??\C:\Windows\System32\utilman.exe by copying from backup
        2026-11-09 10:01:14, Info                  CSI    00000007 [SR] Hashes for file member [l:10]"sethc.exe" do not match
        """;

    [Fact]
    public void Cbs_log_separates_repaired_from_unrepairable_since_the_run_started()
    {
        var r = CbsLogParser.Parse(Cbs, new DateTime(2026, 11, 9, 10, 0, 0), 0);
        Assert.Equal([@"C:\Windows\System32\drivers\etc\protocol", @"C:\Windows\System32\utilman.exe"], r.Repaired);
        Assert.Equal(["amd64_microsoft-windows-x.dll", "evil.dll"], r.Unrepairable);
        Assert.Equal(1, r.CorruptionLines);
        Assert.True(r.FoundCorruption);
        Assert.Empty(CbsLogParser.Parse(Cbs, new DateTime(2026, 11, 9, 11, 0, 0), 0).Repaired);
    }

    [Theory]
    [InlineData("[==========================62.3%=====                      ]", 0.623)]
    [InlineData("[===                         7,0%                           ]", 0.07)]
    [InlineData("The operation completed successfully.", null)]
    public void Dism_progress_bar_is_read(string line, double? expected) => Assert.Equal(expected, DismProgress.Parse(line));

    [Theory]
    [InlineData("nvlddmkm.sys", true)]
    [InlineData("nvlddmkm.sys rtwlane02.sys", true)]
    [InlineData("/all", false)]
    [InlineData("ntfs.sys", false)]
    [InlineData("x.sys; del c:", false)]
    [InlineData("", false)]
    [InlineData("a.sys b.sys c.sys d.sys e.sys f.sys g.sys h.sys i.sys", false)]
    public void Driver_verifier_only_takes_named_third_party_drivers(string input, bool ok)
    {
        var drivers = VerifierArgs.Drivers(input);
        Assert.Equal(ok, drivers is not null);
        if (drivers is not null)
        {
            Assert.DoesNotContain("/all", VerifierArgs.Enable(drivers));
            Assert.Equal("/standard", VerifierArgs.Enable(drivers)[0]);
        }
    }

    [Fact]
    public void Chkdsk_exit_codes_have_meanings() =>
        Assert.Equal(["none", "fixed", "cleanup", "errors", "unknown"], new[] { 0, 1, 2, 3, 9 }.Select(c => new ChkdskResult("C:", c, "").Meaning));

    [Fact]
    public void Memory_errors_and_dirty_volume_are_findings_and_health_check_says_what_needs_admin()
    {
        var e = PcDoctor.Core.Events.EventXmlParser.Parse(
            """<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event"><System><Provider Name="Microsoft-Windows-MemoryDiagnostics-Results"/><EventID>1202</EventID><TimeCreated SystemTime="2026-11-01T08:00:00Z"/><Channel>System</Channel></System></Event>""");
        var result = IntegrityAnalyzer.Analyze(new IntegritySnapshot { SystemVolumeDirty = true, Events = [e] });
        Assert.Equal(Severity.High, result.Findings.Single(f => f.Id == "M6.memoryErrors").Severity);
        Assert.Contains(result.Findings, f => f.Id == "M6.dirty");
        TextAssert.AllResolve(result);

        var basic = IntegrityAnalyzer.Analyze(new IntegritySnapshot());
        Assert.Contains(basic.Checks, c => c.Id == "M6.dirty" && c.Status == CheckStatus.NotChecked);
        Assert.Contains(basic.Checks, c => c.Id == "M6.memory" && c.Status == CheckStatus.NotAvailable);
    }
}
