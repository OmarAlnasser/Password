using PcDoctor.Core.Findings;
using PcDoctor.Core.Reporting;
using PcDoctor.Modules.Sensors;
using PcDoctor.Tests.Core;
using Xunit;

namespace PcDoctor.Tests.Modules;

public sealed class SensorTests
{
    [Fact]
    public void Without_the_broker_sensors_need_a_deep_scan()
    {
        var r = SensorAnalyzer.Analyze(new SensorSnapshot { PawnIoInstalled = false, Readings = null });
        Assert.Empty(r.Findings);
        Assert.Contains(r.Checks, c => c.Id == "M8.sensors" && c.Status == CheckStatus.NotChecked);
        TextAssert.AllResolve(r);
    }

    [Fact]
    public void Cpu_at_throttle_point_and_hot_gpu_are_possible_heuristics_not_verdicts()
    {
        var r = SensorAnalyzer.Analyze(new SensorSnapshot
        {
            PawnIoInstalled = true,
            Readings =
            [
                new SensorReading("Intel Core i7", "Cpu", "CPU Core #1 Distance to TjMax", "Temperature", 3, 1),
                new SensorReading("Intel Core i7", "Cpu", "CPU Package", "Temperature", 97, 99),
                new SensorReading("NVIDIA GeForce", "GpuNvidia", "GPU Hot Spot", "Temperature", 104, 106),
            ],
        });
        Assert.Equal(2, r.Findings.Count);
        Assert.All(r.Findings, f =>
        {
            Assert.Equal(Confidence.Possible, f.Confidence);
            Assert.Equal(FindingSource.Heuristic, f.Source);
            Assert.True(f.Severity <= Severity.Medium);
        });
        Assert.Equal("3", r.Findings.Single(f => f.Id == "M8.cpuTjMax").Title.Args[0]);
        TextAssert.AllResolve(r);
    }

    [Fact]
    public void Missing_cpu_temperature_without_pawnio_is_not_available_not_a_problem()
    {
        var r = SensorAnalyzer.Analyze(new SensorSnapshot
        {
            Readings = [new SensorReading("Samsung SSD", "Storage", "Temperature", "Temperature", 41, 50)],
        });
        Assert.Empty(r.Findings);
        Assert.Contains(r.Checks, c => c.Id == "M8.cpuTemp" && c.Status == CheckStatus.NotAvailable);
    }
}

public sealed class ReportDiffTests
{
    private static ScanReport With(ScanReport template, params Finding[] findings) => template with
    {
        Modules = [new ModuleResult { ModuleId = "M11", ModuleName = new Text("m11.name"), Checks = [], Findings = findings }],
    };

    private static Finding F(string id, Severity s) => new()
    {
        Id = id, Module = "M11", Severity = s, Confidence = Confidence.Confirmed, Source = FindingSource.Registry,
        Title = new Text("m11.name"), WhyItMatters = new Text("m11.name"), SuggestedAction = new Text("m11.name"), Undo = UndoInfo.NothingChanged, Evidence = [],
    };

    [Fact]
    public void Diff_splits_new_resolved_and_persisting_and_notifies_only_new_high()
    {
        var t = HonestyAndLocalizationTests.SampleReport();
        var older = With(t, F("a", Severity.High), F("b", Severity.Low));
        var newer = With(t, F("b", Severity.Low), F("c", Severity.Critical), F("d", Severity.Medium));
        var d = ReportDiff.Compare(older, newer);
        Assert.Equal(["c", "d"], d.New.Select(f => f.Id));
        Assert.Equal("a", Assert.Single(d.Resolved).Id);
        Assert.Equal("b", Assert.Single(d.Persisting).Id);
        Assert.Equal("c", Assert.Single(ReportDiff.WorthNotifying(older, newer)).Id);
        Assert.Empty(ReportDiff.WorthNotifying(newer, newer));
    }

    [Fact]
    public void Scheduled_task_runs_unelevated_on_ac_with_a_fixed_argument()
    {
        var xml = PcDoctor.Core.Reporting.ScheduleXml.Build(daily: true, TimeSpan.FromHours(12.5), @"C:\Program Files\PC Doctor\PcDoctor.App.exe");
        var doc = System.Xml.Linq.XDocument.Parse(xml);
        Assert.Contains("<RunLevel>LeastPrivilege</RunLevel>", xml);
        Assert.Contains("<DisallowStartIfOnBatteries>true</DisallowStartIfOnBatteries>", xml);
        Assert.Contains("<Arguments>--scheduled-scan</Arguments>", xml);
        Assert.NotNull(doc.Root);
    }
}
