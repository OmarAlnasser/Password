using System.Collections.ObjectModel;
using System.Globalization;
using System.IO;
using System.Text.Json;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PcDoctor.App.Services;
using PcDoctor.App.ViewModels;
using PcDoctor.Bench;
using PcDoctor.Core.Ipc;
using PcDoctor.Core.Localization;
using PcDoctor.Core.Platform;

namespace PcDoctor.App.Pages;

public sealed class ComparisonRow(MetricComparison c, IReadOnlyList<string> differences)
{
    public string Metric => Loc.Get("metric." + c.Metric.Id);
    public string Unit => c.Metric.Unit;
    public string Before => Format(c.Result.Before.Median, c.Result.Before.Iqr);
    public string After => Format(c.Result.After.Median, c.Result.After.Iqr);
    public string Change => double.IsNaN(c.Result.RelativeChange) ? "—" : (c.Result.RelativeChange * 100).ToString("+0.0;-0.0;0.0", CultureInfo.InvariantCulture) + " %";
    public string Verdict => Loc.Get("bench.verdict." + c.Result.Verdict);
    public string VerdictKey => c.Result.Verdict switch
    {
        Bench.Verdict.Improved => "Good",
        Bench.Verdict.Regressed => "ErrorBrush",
        _ => "Muted",
    };
    public string Detail => Loc.Format("bench.detail", c.Result.Before.Count, c.Result.After.Count,
        c.Result.PValue.ToString("0.000", CultureInfo.InvariantCulture), (c.Metric.MinimumEffect * 100).ToString("0", CultureInfo.InvariantCulture)) +
        (c.Metric.EnvironmentDependent ? " " + Loc.Get("bench.environment") : "") +
        (differences.Count > 0 ? " " + Loc.Format("bench.conditionsDiffer", string.Join(", ", differences.Select(d => Loc.Get("bench.diff." + d)))) : "");

    private string Format(double median, double iqr) =>
        double.IsNaN(median) ? "—" : $"{median.ToString("0.##", CultureInfo.InvariantCulture)} ± {(iqr / 2).ToString("0.##", CultureInfo.InvariantCulture)} {Unit}".Trim();
}

public sealed record LatencyRow(DriverLatency D)
{
    public string Driver => D.Driver;
    public string Dpc => $"{D.DpcMaxUs:0} / {D.DpcP99Us:0} µs";
    public string Isr => $"{D.IsrMaxUs:0} / {D.IsrP99Us:0} µs";
    public bool Over => D.OverGuidance;
}

/// <summary>M12: measure before and after a change, and say plainly when the difference is within noise.</summary>
public sealed partial class PerformanceViewModel : PageViewModel
{
    private readonly SessionStore _store = new(Path.Combine(AppSettings.Folder, "bench"));
    private CancellationTokenSource? _cts;

    public PerformanceViewModel(AppServices services) : base(services) => LoadSessions();

    public override string Key => "performance";
    public override string Icon => "";

    public ObservableCollection<BenchSession> Sessions { get; } = [];
    public ObservableCollection<ComparisonRow> Rows { get; } = [];
    public ObservableCollection<string> Warnings { get; } = [];
    public ObservableCollection<LatencyRow> Latency { get; } = [];

    [ObservableProperty] [NotifyCanExecuteChangedFor(nameof(RecordBeforeCommand), nameof(RecordAfterCommand), nameof(CancelCommand), nameof(TraceLatencyCommand))]
    private bool _isRunning;

    [ObservableProperty] private string _status = "";
    [ObservableProperty] private bool _measureCpu = true;
    [ObservableProperty] private bool _measureBackground = true;
    [ObservableProperty] private bool _measureDisk = true;
    [ObservableProperty] private bool _measureNetwork;
    [ObservableProperty] private bool _measureBoot = true;
    [ObservableProperty] private string _gameProcess = "";
    [ObservableProperty] private BenchSession? _before;
    [ObservableProperty] private BenchSession? _after;
    [ObservableProperty] private string _latencyNote = "";

    public bool DiskAvailable => Tool("diskspd.exe") is not null;
    public bool GameAvailable => Tool("PresentMon.exe") is not null;
    public bool HasComparison => Rows.Count > 0;

    private static string? Tool(string name) => BundledTools.Resolve(name, Path.Combine(AppContext.BaseDirectory, "tools"), BundledTools.Arch);

    partial void OnBeforeChanged(BenchSession? value) => Compare();
    partial void OnAfterChanged(BenchSession? value) => Compare();

    public override void OnShown() => _ = RefreshWarnings();

    private async Task RefreshWarnings()
    {
        var c = await Task.Run(Conditions);
        Warnings.Clear();
        foreach (var w in c.Warnings())
        {
            Warnings.Add(Loc.Get("bench.warn." + w));
        }
        if (!DiskAvailable)
        {
            Warnings.Add(Loc.Get("bench.warn.noDiskspd"));
        }
    }

    private BenchConditions Conditions()
    {
        var c = new WindowsConditionsReader().Read(Core.Scanning.ScanMode.HealthCheck);
        using var cbs = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending");
        using var wu = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired");
        return new BenchConditions(c.OsBuild, c.Uptime, c.PowerSource.ToString(), c.PowerPlan, c.AppVersion, WindowsBench.IdleCpuPercent(),
            cbs is not null || wu is not null, DiskAvailable);
    }

    private bool CanRun() => !IsRunning;
    private bool CanCancel() => IsRunning;

    [RelayCommand(CanExecute = nameof(CanRun))]
    private Task RecordBefore() => Record("before");

    [RelayCommand(CanExecute = nameof(CanRun))]
    private Task RecordAfter() => Record("after");

    [RelayCommand(CanExecute = nameof(CanCancel))]
    private void Cancel() => _cts?.Cancel();

    private async Task Record(string label)
    {
        IsRunning = true;
        _cts = new CancellationTokenSource();
        var ct = _cts.Token;
        try
        {
            Status = Loc.Get("bench.status.settling");
            var conditions = await Task.Run(Conditions, ct);
            var metrics = new Dictionary<string, List<double>>();
            async Task Measure(MetricInfo m, Func<CancellationToken, Task<double>> f, int warmups = 2, int min = 5, int max = 10)
            {
                var values = await AdaptiveRunner.RunAsync(f, ct, warmups, min, max,
                    onRun: (n, v) => Status = Loc.Format("bench.status.run", Loc.Get("metric." + m.Id), n, v.ToString("0.##", CultureInfo.InvariantCulture), m.Unit));
                metrics[m.Id] = values.ToList();
            }

            if (MeasureCpu)
            {
                await Measure(MetricInfo.CpuSingle, _ => Task.Run(() => CpuWorkload.SingleThreadMs(), ct));
                await Measure(MetricInfo.CpuMulti, _ => Task.Run(() => CpuWorkload.AllThreadsMs(), ct));
            }
            if (MeasureBackground)
            {
                var samples = new List<(double, double, double)>();
                for (var i = 0; i < 5; i++)
                {
                    Status = Loc.Format("bench.status.run", Loc.Get("metric.bg.commit"), i + 1, "", "");
                    samples.Add(await Task.Run(WindowsBench.BackgroundLoad, ct));
                }
                metrics[MetricInfo.CommitMb.Id] = samples.Select(s => s.Item1).ToList();
                metrics[MetricInfo.Processes.Id] = samples.Select(s => s.Item2).ToList();
                metrics[MetricInfo.DpcPercent.Id] = samples.Select(s => s.Item3).ToList();
            }
            if (MeasureDisk && Tool("diskspd.exe") is { } diskspd)
            {
                var runs = new List<Dictionary<string, double>>();
                for (var i = 0; i < 3; i++)
                {
                    Status = Loc.Format("bench.status.run", Loc.Get("metric.disk.seqRead"), i + 1, "", "");
                    runs.Add(await WindowsBench.DiskAsync(diskspd, ct));
                }
                foreach (var id in new[] { MetricInfo.DiskSeqRead.Id, MetricInfo.DiskRandRead.Id, MetricInfo.DiskRandLatency.Id })
                {
                    metrics[id] = runs.Where(r => r.ContainsKey(id)).Select(r => r[id]).ToList();
                }
            }
            if (MeasureNetwork)
            {
                if (NetworkProbe.DefaultGateway() is { } gw)
                {
                    metrics[MetricInfo.PingGateway.Id] = [(await NetworkProbe.PingAsync(gw, 50, ct)).Median];
                }
                var pub = new List<double>();
                var dns = new List<double>();
                for (var i = 0; i < 5; i++)
                {
                    Status = Loc.Format("bench.status.run", Loc.Get("metric.net.public"), i + 1, "", "");
                    pub.Add((await NetworkProbe.PingAsync("1.1.1.1", 20, ct)).Median);
                    dns.Add(await NetworkProbe.DnsMsAsync(ct));
                }
                metrics[MetricInfo.PingPublic.Id] = pub.Where(v => !double.IsNaN(v)).ToList();
                metrics[MetricInfo.DnsLookup.Id] = dns;
            }
            if (!string.IsNullOrWhiteSpace(GameProcess) && Tool("PresentMon.exe") is { } pm)
            {
                var fps = new List<double>();
                var low = new List<double>();
                for (var i = 0; i < 4; i++)
                {
                    Status = Loc.Format("bench.status.game", i + 1, GameProcess);
                    var f = await WindowsBench.FramesAsync(pm, GameProcess.Trim(), ct);
                    if (i > 0 && f.Frames > 0)
                    {
                        // The first pass is discarded (shader caches, loading).
                        fps.Add(f.AverageFps);
                        low.Add(f.Low1Fps);
                    }
                }
                metrics[MetricInfo.FpsAverage.Id] = fps;
                metrics[MetricInfo.FpsLow1.Id] = low;
            }
            if (MeasureBoot && await Services.Broker.EnsureStartedAsync(ct))
            {
                var boots = await Services.Broker.ReadAsync<List<BootSample>>(ElevatedData.BootHistory, ct) ?? [];
                var previous = Sessions.OrderByDescending(s => s.StartedUtc).FirstOrDefault()?.StartedUtc ?? DateTimeOffset.MinValue;
                // Like with like: full (cold) boots only, those since the previous session, the first after an update dropped.
                var cold = BootHistory.Comparable(boots, 0, []).Where(b => b.Time > previous).TakeLast(5).ToList();
                metrics[MetricInfo.BootMainPath.Id] = cold.Select(b => b.MainPathMs).ToList();
                metrics[MetricInfo.BootPostBoot.Id] = cold.Select(b => b.PostBootMs).ToList();
            }

            var session = new BenchSession { Id = Guid.NewGuid(), Label = label, StartedUtc = DateTimeOffset.UtcNow, Conditions = conditions, Metrics = metrics };
            _store.Save(session);
            LoadSessions();
            if (label == "before")
            {
                Before = Sessions.FirstOrDefault(s => s.Id == session.Id);
            }
            else
            {
                After = Sessions.FirstOrDefault(s => s.Id == session.Id);
            }
            Status = Loc.Get("bench.status.saved");
        }
        catch (OperationCanceledException)
        {
            Status = Loc.Get("status.cancelled");
        }
        finally
        {
            IsRunning = false;
        }
    }

    [RelayCommand(CanExecute = nameof(CanRun))]
    private async Task TraceLatency()
    {
        if (!await Services.Broker.EnsureStartedAsync(CancellationToken.None))
        {
            Status = Loc.Get("status.brokerDeclined");
            return;
        }
        IsRunning = true;
        try
        {
            var final = await Services.Broker.RunJobAsync(JobKind.LatencyTrace, null, _ => Status = Loc.Get("bench.latency.running"), CancellationToken.None);
            Latency.Clear();
            if (final.Result is { } json && json.Deserialize<LatencyTraceResult>(PipeFraming.JsonOptions) is { } r)
            {
                foreach (var d in r.Drivers)
                {
                    Latency.Add(new LatencyRow(d));
                }
                LatencyNote = r.Conflict is not null ? Loc.Get("bench.latency.busy")
                    : r.Drivers.Any(d => d.OverGuidance) ? Loc.Get("bench.latency.over") : Loc.Get("bench.latency.ok");
            }
            Status = "";
        }
        finally
        {
            IsRunning = false;
        }
    }

    private void LoadSessions()
    {
        Sessions.Clear();
        foreach (var s in _store.Load())
        {
            Sessions.Add(s);
        }
    }

    private void Compare()
    {
        Rows.Clear();
        if (Before is not null && After is not null && Before.Id != After.Id)
        {
            var differences = After.Conditions.DifferencesFrom(Before.Conditions);
            foreach (var c in SessionComparer.Compare(Before, After))
            {
                Rows.Add(new ComparisonRow(c, differences));
            }
        }
        OnPropertyChanged(nameof(HasComparison));
    }

    protected override void OnTextsChanged() => Compare();
}
