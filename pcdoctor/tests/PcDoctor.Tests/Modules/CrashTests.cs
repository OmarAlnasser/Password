using PcDoctor.Core.Findings;
using PcDoctor.Modules.Crash;
using Xunit;

namespace PcDoctor.Tests.Modules;

public sealed class CrashTests
{
    private static CrashSnapshot Snapshot(params string[] events) => new()
    {
        DumpConfig = new DumpConfig(7, @"C:\Windows\Minidump", @"C:\Windows\MEMORY.DMP", 1),
        HasPagefile = true,
        Events = events.Select(Fixtures.Event).ToList(),
    };

    [Fact]
    public void Kernel_power_41_bugcheck_code_is_decimal()
    {
        var kp = Fixtures.Event("kp41-bsod");
        Assert.Equal("159", kp.Get("BugcheckCode"));
        var incident = Assert.Single(CrashAnalyzer.BuildIncidents([kp]));
        Assert.Equal(CrashKind.BlueScreen, incident.Kind);
        Assert.Equal(0x9Fu, incident.BugcheckCode);
        Assert.Equal("0x9F", BugcheckKnowledgeBase.Format(incident.BugcheckCode!.Value));
    }

    [Fact]
    public void Kernel_power_41_is_classified_by_power_button_timestamp()
    {
        var incidents = CrashAnalyzer.BuildIncidents([Fixtures.Event("kp41-forced"), Fixtures.Event("kp41-power")]);
        Assert.Equal([CrashKind.ForcedOff, CrashKind.PowerLossOrHang], incidents.Select(i => i.Kind));
    }

    [Fact]
    public void BugCheck_1001_merges_with_kernel_power_41_and_supplies_dump_path()
    {
        var incidents = CrashAnalyzer.BuildIncidents([Fixtures.Event("kp41-bsod"), Fixtures.Event("bugcheck1001")]);
        var incident = Assert.Single(incidents);
        Assert.Equal(@"C:\Windows\Minidump\102026-12345-01.dmp", incident.DumpPath);
        Assert.Equal(4, incident.Parameters.Count);
        Assert.Equal("0x0000000000000003", incident.Parameters[0]);
    }

    [Fact]
    public void Forced_off_lists_the_display_reset_just_before()
    {
        var result = CrashAnalyzer.Analyze(Snapshot("kp41-forced", "tdr-before-forced"));
        var f = Assert.Single(result.Findings, x => x.Id == "M5.forcedOff");
        Assert.Equal("m5.forcedOff.action.related", f.SuggestedAction.Key);
        Assert.Contains(f.Evidence, e => e.Value.StartsWith("Display 4101", StringComparison.Ordinal));
    }

    [Fact]
    public void Blue_screen_finding_names_code_and_explains_it_without_claiming_certainty()
    {
        var result = CrashAnalyzer.Analyze(Snapshot("kp41-bsod", "bugcheck1001"));
        var f = Assert.Single(result.Findings, x => x.Id.StartsWith("M5.bsod", StringComparison.Ordinal));
        Assert.Equal("M5.bsod.0x9F", f.Id);
        Assert.NotEqual(Confidence.Confirmed, f.Confidence);
        Assert.Equal("kb.0x9F.cause", f.WhyItMatters.Key);
        Assert.Contains("DRIVER_POWER_STATE_FAILURE", f.Title.Args);
        TextAssert.AllResolve(result);
    }

    [Fact]
    public void Dumps_disabled_offers_the_catalog_fix()
    {
        var result = CrashAnalyzer.Analyze(new CrashSnapshot { DumpConfig = new DumpConfig(0, null, null, null) });
        var f = Assert.Single(result.Findings, x => x.Id == "M5.dumpsDisabled");
        Assert.Equal("crash.dumps.automatic", f.FixId);
        Assert.Equal(UndoKind.Reversible, f.Undo.Kind);
    }

    [Fact]
    public void Missing_data_is_reported_not_hidden()
    {
        var result = CrashAnalyzer.Analyze(new CrashSnapshot());
        Assert.Contains(result.Checks, c => c.Id == "M5.dumpConfig" && c.Status == CheckStatus.NotAvailable);
        Assert.Contains(result.Checks, c => c.Id == "M5.dumps" && c.Status == CheckStatus.NotAvailable);
        Assert.Contains(result.Checks, c => c.Id == "M5.stability" && c.Status == CheckStatus.NotAvailable);
        Assert.Contains(result.Checks, c => c.Id == "M5.dumpAnalysis" && c.Status == CheckStatus.NotChecked);
        Assert.Empty(result.Findings);
    }

    [Fact]
    public void WudfRd_219_at_boot_is_suppressed_and_counted()
    {
        var result = CrashAnalyzer.Analyze(Snapshot("wudfrd219"));
        Assert.Empty(result.Findings);
        Assert.Contains(result.Checks, c => c.Id == "M5.suppressed");
    }

    [Fact]
    public void Whea_pcie_errors_are_grouped_by_device()
    {
        var result = CrashAnalyzer.Analyze(Snapshot("whea17", "whea18"));
        Assert.Contains(result.Findings, f => f.Id == @"M5.wheaPcie.PCI\VEN_8086&DEV_A33C");
        Assert.Contains(result.Findings, f => f.Id == "M5.wheaFatal" && f.Severity == Severity.High);
    }

    [Fact]
    public void All_fixtures_together_resolve_in_both_languages()
    {
        var names = Directory.GetFiles(Path.Combine(Fixtures.Dir, "events")).Select(Path.GetFileNameWithoutExtension).ToArray();
        var result = CrashAnalyzer.Analyze(Snapshot(names!) with
        {
            Dumps = [new DumpFileInfo(@"C:\Windows\Minidump\a.dmp", 1, DateTimeOffset.UnixEpoch, DumpKind.Minidump)],
            Stability = new StabilityInfo(6.4, DateTimeOffset.UnixEpoch),
        });
        Assert.Contains(result.Findings, f => f.Id == "M5.dumpFailed");
        Assert.Contains(result.Findings, f => f.Id == "M5.app.contoso.exe");
        Assert.Contains(result.Findings, f => f.Id == "M5.serviceCrash.Contoso Updater");
        Assert.Contains(result.Findings, f => f.Id.StartsWith("M5.storage.Microsoft-Windows-Ntfs.55", StringComparison.Ordinal));
        TextAssert.AllResolve(result);
    }

    [Fact]
    public void Knowledge_base_has_both_languages_and_the_required_codes()
    {
        BugcheckKnowledgeBase.EnsureRegistered();
        uint[] required = [0x124, 0x133, 0x116, 0x117, 0x9F, 0xA, 0xD1, 0x1E, 0x7E, 0x3B, 0x50, 0x1A, 0x139, 0x154, 0xEF, 0xC4];
        foreach (var code in required)
        {
            Assert.NotNull(BugcheckKnowledgeBase.Find(code));
        }
        foreach (var e in BugcheckKnowledgeBase.All)
        {
            foreach (var lang in new[] { "en", "ar" })
            {
                Assert.False(string.IsNullOrWhiteSpace(e.Cause.GetValueOrDefault(lang)), $"{e.Name} cause/{lang}");
                Assert.False(string.IsNullOrWhiteSpace(e.Next.GetValueOrDefault(lang)), $"{e.Name} next/{lang}");
            }
        }
    }

    [Fact]
    public void Tdr_advice_never_suggests_editing_tdr_delay()
    {
        BugcheckKnowledgeBase.EnsureRegistered();
        foreach (var code in new uint[] { 0x116, 0x117 })
        {
            var text = PcDoctor.Core.Localization.Loc.Get($"kb.{BugcheckKnowledgeBase.Format(code)}.next", Cultures.En);
            Assert.DoesNotContain("TdrDelay", text);
            Assert.Contains("Do not edit", text);
        }
    }
}
