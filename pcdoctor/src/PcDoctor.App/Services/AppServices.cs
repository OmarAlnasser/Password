using System.IO;
using System.Text.Json;
using CommunityToolkit.Mvvm.ComponentModel;
using PcDoctor.Core.Findings;
using PcDoctor.Core.Localization;
using PcDoctor.Core.Platform;
using PcDoctor.Core.Reporting;
using PcDoctor.Core.Scanning;

namespace PcDoctor.App.Services;

/// <summary>State shared by every page: settings, the Broker, the latest scan and its progress.</summary>
public sealed partial class AppServices : ObservableObject, IAsyncDisposable
{
    private CancellationTokenSource? _scanCts;

    public AppServices(AppSettings settings)
    {
        Settings = settings;
    }

    public AppSettings Settings { get; private set; }
    public BrokerClient Broker { get; } = new();

    [ObservableProperty] private ScanReport? _report;
    [ObservableProperty] private bool _isScanning;
    [ObservableProperty] private double _progress;
    [ObservableProperty] private string _status = "";

    /// <summary>Raised when the language, digits or theme change, so pages re-resolve their text.</summary>
    public event Action? TextsChanged;

    public event Action<string>? NavigateRequested;

    public void RaiseTextsChanged() => TextsChanged?.Invoke();

    public void Navigate(string pageKey) => NavigateRequested?.Invoke(pageKey);

    public void UpdateSettings(Func<AppSettings, AppSettings> change)
    {
        Settings = change(Settings);
        try
        {
            Settings.Save();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            Status = Loc.Get("status.settingsUnsaved");
        }
    }

    public async Task RunScanAsync(ScanMode mode)
    {
        if (IsScanning)
        {
            return;
        }
        IsScanning = true;
        Progress = 0;
        _scanCts = new CancellationTokenSource();
        try
        {
            IElevatedReader? elevated = null;
            if (mode == ScanMode.DeepScan)
            {
                Status = Loc.Get("status.startingBroker");
                if (await Broker.EnsureStartedAsync(_scanCts.Token))
                {
                    elevated = Broker;
                }
                else
                {
                    Status = Loc.Get("status.brokerDeclined");
                    mode = ScanMode.HealthCheck;
                }
            }
            var progress = new Progress<ScanProgress>(p =>
            {
                Progress = p.Total == 0 ? 0 : (double)p.Completed / p.Total;
                Status = p.Completed < p.Total
                    ? Loc.Format("status.scanning", p.Completed + 1, p.Total, Loc.Resolve(p.CurrentModule))
                    : Loc.Get("status.done");
            });
            var runner = new ScanRunner(AppModules.Create(this), new WindowsConditionsReader());
            var report = await Task.Run(() => runner.RunAsync(mode, elevated, progress, _scanCts.Token));
            Report = report;
            History.Save(report);
            Status = Loc.Get("status.done");
        }
        catch (OperationCanceledException)
        {
            Status = Loc.Get("status.cancelled");
        }
        finally
        {
            IsScanning = false;
        }
    }

    public void CancelScan() => _scanCts?.Cancel();

    public ValueTask DisposeAsync() => Broker.DisposeAsync();
}

/// <summary>Past reports in %LOCALAPPDATA%\PCDoctor\history, newest first, at most 50.</summary>
public static class History
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new System.Text.Json.Serialization.JsonStringEnumConverter() },
    };

    public static string Folder => Path.Combine(AppSettings.Folder, "history");

    public static void Save(ScanReport report)
    {
        try
        {
            Directory.CreateDirectory(Folder);
            File.WriteAllText(Path.Combine(Folder, $"{report.StartedUtc:yyyyMMdd-HHmmss}-{report.Id:N}.json"),
                JsonSerializer.Serialize(report, Json));
            foreach (var old in Directory.GetFiles(Folder, "*.json").OrderByDescending(f => f).Skip(50))
            {
                File.Delete(old);
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // History is a convenience; a full disk must not fail the scan.
        }
    }

    public static IReadOnlyList<ScanReport> Load()
    {
        if (!Directory.Exists(Folder))
        {
            return [];
        }
        var list = new List<ScanReport>();
        foreach (var f in Directory.GetFiles(Folder, "*.json").OrderByDescending(f => f))
        {
            try
            {
                if (JsonSerializer.Deserialize<ScanReport>(File.ReadAllText(f), Json) is { } r)
                {
                    list.Add(r);
                }
            }
            catch (Exception ex) when (ex is JsonException or IOException or NotSupportedException)
            {
                // A report from an older format is skipped.
            }
        }
        return list;
    }
}
