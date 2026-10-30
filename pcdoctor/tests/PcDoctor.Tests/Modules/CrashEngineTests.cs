using System.Buffers.Binary;
using System.Text;
using PcDoctor.Core.Findings;
using PcDoctor.Modules.Crash;
using Xunit;

namespace PcDoctor.Tests.Modules;

public sealed class CrashEngineTests
{
    private static AnalyzeResult NvidiaAnalysis =>
        AnalyzeOutputParser.Parse(Fixtures.Text(Path.Combine("dumps", "analyze-nvlddmkm.txt")));

    [Fact]
    public void Analyze_output_fields_are_parsed()
    {
        var a = NvidiaAnalysis;
        Assert.Equal(0x116u, a.BugcheckCode);
        Assert.Equal("nvlddmkm.sys", a.ImageName);
        Assert.Equal("nvlddmkm", a.ModuleName);
        Assert.Equal("0x116_IMAGE_nvlddmkm.sys", a.FailureBucketId);
        Assert.Equal("System", a.ProcessName);
        Assert.Equal(3, a.Stack.Count);
        Assert.Equal("ffffa50c1e2d3010", a.Parameters[0]);
        Assert.True(a.SymbolsLoaded);
    }

    [Fact]
    public void Follow_up_commands_match_the_stop_code()
    {
        Assert.Equal("; !errrec 0x1f; !whea", AnalyzeOutputParser.FollowUps(0x124, [0, 0x1f, 0, 0]));
        Assert.Equal("; !dpcs", AnalyzeOutputParser.FollowUps(0x133, null));
        Assert.Equal("", AnalyzeOutputParser.FollowUps(0x9F, null));
    }

    internal static byte[] Minidump64(uint code, ulong p1, string[] modules)
    {
        var head = new byte[0x2000];
        "PAGEDU64"u8.CopyTo(head);
        BinaryPrimitives.WriteUInt32LittleEndian(head.AsSpan(0x34), 8);
        BinaryPrimitives.WriteUInt32LittleEndian(head.AsSpan(0x38), code);
        BinaryPrimitives.WriteUInt64LittleEndian(head.AsSpan(0x40), p1);
        var pool = Encoding.Unicode.GetBytes(string.Join("\0\0", modules));
        return [.. head, .. pool];
    }

    [Fact]
    public void Offline_header_parser_reads_code_parameters_and_module_names()
    {
        var dump = Minidump64(0x9F, 3, ["ntoskrnl.exe", "ACPI.sys", "rtwlane02.sys"]);
        var header = DumpHeaderParser.Parse(dump)!;
        Assert.True(header.Is64Bit);
        Assert.Equal(0x9Fu, header.BugcheckCode);
        Assert.Equal(3ul, header.Parameters[0]);
        Assert.Equal(8, header.Processors);
        Assert.Contains("rtwlane02.sys", DumpHeaderParser.ModuleNames(dump));
        Assert.Null(DumpHeaderParser.Parse("MDMP...."u8.ToArray().Concat(new byte[0x100]).ToArray()));
    }

    [Fact]
    public void Wer_report_utf16_with_bom_is_parsed()
    {
        var text = "Version=1\r\nEventType=LiveKernelEvent\r\nEventTime=133432123456789012\r\nSig[0].Name=Code\r\nSig[0].Value=141\r\nAppName=\r\n";
        var bytes = new byte[] { 0xFF, 0xFE }.Concat(Encoding.Unicode.GetBytes(text)).ToArray();
        var r = WerReportParser.Parse(@"C:\ProgramData\Microsoft\Windows\WER\ReportArchive\x\Report.wer", bytes)!;
        Assert.Equal("LiveKernelEvent", r.EventType);
        Assert.Equal("141", r.Signature["Code"]);
        Assert.NotNull(r.Time);
    }

    private static DumpAnalysis Dump(string name, DateTimeOffset time, AnalyzeResult? a) =>
        new($@"C:\Windows\Minidump\{name}", time, 300_000, new DumpHeader(true, 0x116, [1, 2, 3, 4], 8), a, ["nvlddmkm.sys"], null);

    [Fact]
    public void Repeated_driver_in_dumps_gives_a_probable_verdict_with_friendly_name()
    {
        var kp = Fixtures.Event("kp41-bsod");
        var t = kp.TimeCreated;
        var result = CrashAnalyzer.Analyze(new CrashSnapshot
        {
            DumpConfig = new DumpConfig(7, null, null, null),
            Events = [kp, Fixtures.Event("bugcheck1001")],
            DumpAnalyses =
            [
                Dump("102026-12345-01.dmp", t.AddMinutes(-2), NvidiaAnalysis),
                Dump("101826-11111-01.dmp", t.AddDays(-2), NvidiaAnalysis),
            ],
            DebuggerAvailable = true,
        });
        var verdict = Assert.Single(result.Findings, f => f.Id == "M5.culprit.nvlddmkm.sys");
        Assert.Equal(Confidence.Probable, verdict.Confidence);
        Assert.Equal(FindingSource.MicrosoftTool, verdict.Source);
        Assert.Equal("driver.nvidia.why", verdict.WhyItMatters.Key);
        Assert.Equal("2", verdict.Title.Args[0]);
        Assert.Contains(result.Timeline, e => e.Tag == "bsod" && e.Detail is not null);
        TextAssert.AllResolve(result);
    }

    [Fact]
    public void A_single_dump_only_gives_a_possible_verdict()
    {
        var result = CrashAnalyzer.Analyze(new CrashSnapshot
        {
            DumpAnalyses = [Dump("a.dmp", DateTimeOffset.UtcNow.AddDays(-1), NvidiaAnalysis)],
            DebuggerAvailable = true,
        });
        Assert.Equal(Confidence.Possible, Assert.Single(result.Findings, f => f.Id.StartsWith("M5.culprit.", StringComparison.Ordinal)).Confidence);
    }

    [Fact]
    public void Kernel_only_verdict_says_it_is_a_symptom()
    {
        var kernel = NvidiaAnalysis with { ImageName = "ntkrnlmp.exe", ModuleName = "nt" };
        var result = CrashAnalyzer.Analyze(new CrashSnapshot
        {
            DumpAnalyses = [Dump("a.dmp", DateTimeOffset.UtcNow.AddDays(-1), kernel), Dump("b.dmp", DateTimeOffset.UtcNow.AddDays(-2), kernel)],
            DebuggerAvailable = true,
        });
        var f = Assert.Single(result.Findings, f => f.Id.StartsWith("M5.culprit.", StringComparison.Ordinal));
        Assert.Equal("m5.culprit.core.title", f.Title.Key);
        Assert.Equal(Confidence.Possible, f.Confidence);
    }

    [Fact]
    public void Without_the_debugger_it_says_so_and_lists_names_without_a_verdict()
    {
        var result = CrashAnalyzer.Analyze(new CrashSnapshot
        {
            DumpAnalyses = [Dump("a.dmp", DateTimeOffset.UtcNow.AddDays(-1), null)],
            DebuggerAvailable = false,
        });
        Assert.DoesNotContain(result.Findings, f => f.Id.StartsWith("M5.culprit.", StringComparison.Ordinal));
        var need = Assert.Single(result.Findings, f => f.Id == "M5.needDebugger");
        Assert.Contains(need.Evidence, e => e.Label.Contains("not a verdict", StringComparison.Ordinal));
        Assert.Contains(result.Checks, c => c.Id == "M5.dumpAnalysis" && c.Detail!.Key == "m5.check.dumpAnalysis.offline");
        TextAssert.AllResolve(result);
    }

    [Fact]
    public void Health_check_marks_dump_analysis_as_needing_a_deep_scan()
    {
        var result = CrashAnalyzer.Analyze(new CrashSnapshot());
        Assert.Contains(result.Checks, c => c.Id == "M5.dumpAnalysis" && c.Status == CheckStatus.NotChecked && c.Detail!.Key == "check.needsDeepScan");
    }

    [Fact]
    public void Driver_catalog_names_are_translated()
    {
        foreach (var d in DriverCatalog.All)
        {
            foreach (var field in new[] { "name", "why", "action" })
            {
                foreach (var c in Cultures.Both)
                {
                    Assert.DoesNotContain("[[", PcDoctor.Core.Localization.Loc.Get($"driver.{d.Key}.{field}", c));
                }
            }
        }
        Assert.Equal("intel-wifi", DriverCatalog.Find("Netwtw10.sys")!.Key);
    }
}
