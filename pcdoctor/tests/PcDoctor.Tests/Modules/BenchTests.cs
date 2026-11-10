using PcDoctor.Bench;
using Xunit;

namespace PcDoctor.Tests.Modules;

public sealed class BenchTests
{
    private static List<double> Noisy(double center, double rsd, int n, int seed)
    {
        var rng = new Random(seed);
        // Box-Muller normal noise.
        return Enumerable.Range(0, n).Select(_ =>
        {
            var u1 = 1 - rng.NextDouble();
            var u2 = rng.NextDouble();
            return center * (1 + rsd * Math.Sqrt(-2 * Math.Log(u1)) * Math.Cos(2 * Math.PI * u2));
        }).ToList();
    }

    [Fact]
    public void Two_runs_with_no_change_are_almost_never_called_a_change()
    {
        // Acceptance test 10 (false-positive check). No rule is right on every random draw, so this
        // measures the rate: 1000 pairs from the same distribution at the protocol's worst allowed
        // noise (relative SD 3.5%, 5 runs) and at a typical one (2%, 8 runs).
        foreach (var (rsd, n, limit) in new[] { (0.035, 5, 0.01), (0.02, 8, 0.005) })
        {
            var falsePositives = 0;
            for (var seed = 0; seed < 1000; seed++)
            {
                var v = Statistics.Compare(Noisy(100, rsd, n, seed), Noisy(100, rsd, n, seed + 100_000), Direction.LowerIsBetter, 0.03);
                if (v.Verdict != Verdict.NoSignificantChange)
                {
                    falsePositives++;
                }
            }
            Assert.True(falsePositives / 1000.0 < limit, $"rsd {rsd}, n {n}: {falsePositives} of 1000 unchanged pairs were called a change");
        }
    }

    [Fact]
    public void Every_metric_reports_no_change_on_a_typical_unchanged_pair()
    {
        foreach (var m in MetricInfo.All)
        {
            Assert.Equal(Verdict.NoSignificantChange, Statistics.Compare(Noisy(100, 0.02, 8, 1), Noisy(100, 0.02, 8, 2), m.Direction, m.MinimumEffect).Verdict);
        }
    }

    [Fact]
    public void A_clear_large_shift_is_improved_or_regressed_by_direction()
    {
        var before = Noisy(100, 0.02, 8, 1);
        var slower = Noisy(120, 0.02, 8, 2);
        Assert.Equal(Verdict.Regressed, Statistics.Compare(before, slower, Direction.LowerIsBetter).Verdict);
        Assert.Equal(Verdict.Improved, Statistics.Compare(before, slower, Direction.HigherIsBetter).Verdict);
        var c = Statistics.Compare(before, slower, Direction.LowerIsBetter);
        Assert.True(c.CiLow > 0, "CI excludes zero");
        Assert.InRange(c.RelativeChange, 0.15, 0.25);
    }

    [Fact]
    public void Significant_but_tiny_changes_stay_no_significant_change()
    {
        // 1% shift with almost no noise: statistically clear, practically irrelevant (below the 3% floor).
        var before = Noisy(100, 0.001, 10, 3);
        var after = Noisy(101, 0.001, 10, 4);
        var c = Statistics.Compare(before, after, Direction.LowerIsBetter);
        Assert.True(c.PValue < 0.05);
        Assert.Equal(Verdict.NoSignificantChange, c.Verdict);
    }

    [Fact]
    public void Fewer_than_three_runs_is_insufficient() =>
        Assert.Equal(Verdict.InsufficientData, Statistics.Compare([1, 2], [3, 4, 5], Direction.LowerIsBetter).Verdict);

    [Fact]
    public void Mann_whitney_and_quantiles_match_known_values()
    {
        Assert.InRange(Statistics.MannWhitneyP([1, 2, 3, 4, 5], [6, 7, 8, 9, 10]), 0.005, 0.02);
        Assert.Equal(1, Statistics.MannWhitneyP([1, 1, 1], [1, 1, 1]));
        var s = Statistics.Summarize([1, 2, 3, 4, 100]);
        Assert.Equal(3, s.Median);
        Assert.Equal(2, s.Q1);
        Assert.Equal(4, s.Q3);
        Assert.InRange(Statistics.NormalCdf(1.96), 0.9749, 0.9751);
    }

    [Fact]
    public async Task Adaptive_runner_stops_early_when_stable_and_caps_at_ten()
    {
        var stable = await AdaptiveRunner.RunAsync(_ => Task.FromResult(10.0), CancellationToken.None);
        Assert.Equal(5, stable.Count);
        var i = 0;
        var noisy = await AdaptiveRunner.RunAsync(_ => Task.FromResult(i++ % 2 == 0 ? 10.0 : 20.0), CancellationToken.None);
        Assert.Equal(10, noisy.Count);
    }

    [Fact]
    public void Injected_cpu_load_is_detected_as_worse()
    {
        // Acceptance test 10: a real all-threads CPU benchmark with every core kept busy by other threads.
        for (var w = 0; w < 2; w++)
        {
            CpuWorkload.AllThreadsMs(1);
        }
        var before = Enumerable.Range(0, 6).Select(_ => CpuWorkload.AllThreadsMs(1)).ToList();
        // Normal priority: the load competes with the benchmark as an equal (roughly halving its share).
        // AboveNormal spinners starve every Normal thread on the machine on Windows, including other test
        // processes and the desktop, which hung CI. The deadline bounds the load even if the benchmark stalls.
        using var stop = new CancellationTokenSource(TimeSpan.FromSeconds(20));
        var hogs = Enumerable.Range(0, Environment.ProcessorCount).Select(_ => new Thread(() =>
        {
            var x = 0.0;
            while (!stop.IsCancellationRequested)
            {
                x += Math.Sqrt(x + 1);
            }
        }) { IsBackground = true, Priority = ThreadPriority.Normal }).ToList();
        hogs.ForEach(t => t.Start());
        List<double> after;
        try
        {
            after = Enumerable.Range(0, 6).Select(_ => CpuWorkload.AllThreadsMs(1)).ToList();
        }
        finally
        {
            stop.Cancel();
            hogs.ForEach(t => t.Join());
        }
        Assert.Equal(Verdict.Regressed, Statistics.Compare(before, after, Direction.LowerIsBetter, 0.03).Verdict);
    }

    [Fact]
    public void PresentMon_csv_gives_average_and_lows()
    {
        var rows = string.Join("\n", Enumerable.Range(0, 1000).Select(i => $"game.exe,1234,{(i == 999 ? 50.0 : 10.0):0.0}"));
        var stats = PresentMonParser.Parse("Application,ProcessID,MsBetweenPresents\n" + rows);
        Assert.Equal(1000, stats.Frames);
        Assert.InRange(stats.AverageFps, 95, 100);
        Assert.InRange(stats.Low01Fps, 20, 100);
        Assert.Throws<FormatException>(() => PresentMonParser.Parse("A,B\n1,2"));
    }

    [Fact]
    public void DiskSpd_xml_is_parsed()
    {
        var xml = """
            <Results><TimeSpan><TestTimeSeconds>10.00</TestTimeSeconds>
              <Thread><Target><ReadBytes>10485760000</ReadBytes><ReadCount>10000</ReadCount><WriteBytes>0</WriteBytes><WriteCount>0</WriteCount></Target></Thread>
              <Latency><AverageTotalMilliseconds>1.25</AverageTotalMilliseconds></Latency>
            </TimeSpan></Results>
            """;
        var r = DiskSpdParser.Parse(xml);
        Assert.InRange(r.MegabytesPerSecond, 999, 1001);
        Assert.Equal(1000, r.Iops);
        Assert.Equal(1.25, r.AverageLatencyMs);
        Assert.All(DiskSpdParser.Profiles(@"C:\Temp\x.dat"), p => Assert.Contains("-c1G", p.Args));
    }

    [Fact]
    public void Boots_compare_like_with_like_and_drop_the_first_after_an_update()
    {
        var t0 = new DateTimeOffset(2026, 11, 1, 8, 0, 0, TimeSpan.Zero);
        var boots = new List<BootSample>
        {
            new(t0, 9000, 20000, 29000, false, 0),
            new(t0.AddDays(1), 5000, 9000, 14000, false, 1),
            new(t0.AddDays(2), 30000, 50000, 80000, true, 0),
            new(t0.AddDays(3), 9100, 21000, 30100, false, 0),
        };
        var comparable = BootHistory.Comparable(boots, 0, [t0.AddDays(1.5)]);
        Assert.Equal([9000, 9100], comparable.Select(b => b.MainPathMs));
    }

    [Fact]
    public void Conditions_differences_and_warnings()
    {
        var a = new BenchConditions("10.0.26100.1", TimeSpan.FromHours(1), "AC", "Balanced", "0.2", 1, false, true);
        var b = a with { PowerSource = "Battery", Uptime = TimeSpan.FromMinutes(2) };
        Assert.Equal(["power"], b.DifferencesFrom(a));
        Assert.Equal(["battery", "justBooted"], b.Warnings());
    }

    [Fact]
    public void A_bundled_tool_with_the_wrong_hash_is_not_used()
    {
        var dir = Directory.CreateTempSubdirectory("pcdoctor-tools-").FullName;
        try
        {
            File.WriteAllText(Path.Combine(dir, "diskspd.exe"), "not the real one");
            Assert.Null(BundledTools.Resolve("diskspd.exe", dir, "X64"));
            Assert.Null(BundledTools.Resolve("evil.exe", dir, "X64"));
        }
        finally
        {
            Directory.Delete(dir, true);
        }
    }
}
