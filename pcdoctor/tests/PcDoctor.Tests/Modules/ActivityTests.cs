using PcDoctor.Core.Findings;
using PcDoctor.Core.Reporting;
using PcDoctor.Modules.Activity;
using Xunit;

namespace PcDoctor.Tests.Modules;

public class ActivityTests
{
    private const long Gb = 1024L * 1024 * 1024;

    private static ActivitySnapshot Snapshot(long available, params ProgramActivity[] programs) =>
        new() { Programs = programs, SampleSeconds = 3, TotalMemoryBytes = 16 * Gb, AvailableMemoryBytes = available };

    [Fact]
    public void A_quiet_pc_has_no_findings()
    {
        var r = ActivityAnalyzer.Analyze(Snapshot(9 * Gb, new ProgramActivity("explorer", 1, 1.5, 200_000_000, 3000, 80), new ProgramActivity("chrome", 30, 6, 3 * Gb, 40_000, 600)));
        Assert.Empty(r.Findings);
        Assert.Contains(r.Checks, c => c.Id == "M14.cpu");
        Assert.Contains(r.Checks, c => c.Id == "M14.memory");
    }

    [Fact]
    public void A_program_keeping_the_processor_busy_is_reported_as_one_short_sample()
    {
        var f = Assert.Single(ActivityAnalyzer.Analyze(Snapshot(9 * Gb, new ProgramActivity("miner", 1, 82, 100_000_000, 500, 20))).Findings);
        Assert.Equal("M14.cpu.miner", f.Id);
        Assert.Equal(Severity.Medium, f.Severity);
        Assert.Equal(Confidence.Possible, f.Confidence);
    }

    [Fact]
    public void Low_free_memory_names_the_largest_programs()
    {
        var f = Assert.Single(ActivityAnalyzer.Analyze(Snapshot(1 * Gb, new ProgramActivity("editor", 1, 2, 3 * Gb, 2000, 50))).Findings);
        Assert.Equal("M14.memLow", f.Id);
        Assert.Contains(f.Evidence, e => e.Label == "editor");
    }

    [Fact]
    public void A_very_high_handle_count_is_a_possible_leak_but_many_small_processes_are_not()
    {
        var r = ActivityAnalyzer.Analyze(Snapshot(9 * Gb,
            new ProgramActivity("leaky", 1, 0.1, 500_000_000, 120_000, 40),
            new ProgramActivity("browser", 40, 3, 2 * Gb, 90_000, 900),
            new ProgramActivity("System", 1, 0.5, 1_000_000, 200_000, 300)));
        Assert.Equal("M14.handles.leaky", Assert.Single(r.Findings).Id);
    }

    [Fact]
    public void One_program_holding_a_quarter_of_memory_is_noted()
    {
        Assert.Contains(ActivityAnalyzer.Analyze(Snapshot(6 * Gb, new ProgramActivity("game", 1, 20, 6 * Gb, 5000, 120))).Findings, f => f.Id == "M14.memHeavy.game");
    }

    [Fact]
    public void Nothing_readable_is_reported_as_not_checked_rather_than_as_fine()
    {
        var r = ActivityAnalyzer.Analyze(null);
        Assert.Empty(r.Findings);
        Assert.All(r.Checks, c => Assert.Equal(CheckStatus.NotAvailable, c.Status));
    }

    [Fact]
    public async Task Reading_twice_does_not_keep_process_objects_alive()
    {
        var before = GC.GetTotalMemory(forceFullCollection: true);
        for (var i = 0; i < 5; i++)
        {
            var s = await ActivityReader.ReadAsync(TimeSpan.FromMilliseconds(50), CancellationToken.None);
            Assert.NotEmpty(s.Programs);
            Assert.All(s.Programs, p => Assert.InRange(p.CpuPercent, 0, 100.5 * Environment.ProcessorCount));
        }
        var after = GC.GetTotalMemory(forceFullCollection: true);
        Assert.True(after - before < 8 * 1024 * 1024, $"grew by {after - before} bytes");
    }

    [Fact]
    public void The_sign_in_task_is_delayed_least_privilege_and_runs_the_read_only_scan()
    {
        var xml = ScheduleXml.BuildAtSignIn(@"C:\Program Files\PC Doctor\PcDoctor.App.exe");
        Assert.Contains("<LogonTrigger>", xml);
        Assert.Contains("<Delay>PT2M</Delay>", xml);
        Assert.Contains("LeastPrivilege", xml);
        Assert.Contains("<Arguments>--scheduled-scan</Arguments>", xml);
        Assert.DoesNotContain("HighestAvailable", xml);
        System.Xml.Linq.XDocument.Parse(xml.TrimStart());
    }
}
