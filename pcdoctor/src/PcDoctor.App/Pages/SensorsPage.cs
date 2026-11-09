using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Globalization;
using System.Windows.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PcDoctor.App.Services;
using PcDoctor.App.ViewModels;
using PcDoctor.App.Views;
using PcDoctor.Core.Ipc;
using PcDoctor.Core.Localization;
using PcDoctor.Modules.Sensors;

namespace PcDoctor.App.Pages;

public sealed partial class SensorTile(string key) : ObservableObject
{
    public string Key => key;
    [ObservableProperty] private string _name = "";
    [ObservableProperty] private string _value = "";
    [ObservableProperty] private string _max = "";
    [ObservableProperty] private double _fraction;
    [ObservableProperty] private string _brushKey = "Accent2";
}

public sealed class HardwareGroup(string name)
{
    public string Name => name;
    public ObservableCollection<SensorTile> Tiles { get; } = [];
}

/// <summary>M8 live: temperatures, loads, clocks and fans, refreshed every 2 seconds while the page is open.</summary>
public sealed partial class SensorsViewModel : PageViewModel
{
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromSeconds(2) };
    private bool _reading;

    public SensorsViewModel(AppServices services) : base(services)
    {
        _timer.Tick += async (_, _) => await Poll();
    }

    public override string Key => "sensors";
    public override string Icon => "";

    public ObservableCollection<HardwareGroup> Groups { get; } = [];

    [ObservableProperty] private bool _isLive;
    [ObservableProperty] private string _status = "";

    public bool PawnIoInstalled => OperatingSystem.IsWindows() && SensorReader.PawnIoInstalled();

    public override void OnShown() => OnPropertyChanged(nameof(PawnIoInstalled));

    [RelayCommand]
    private async Task Start()
    {
        if (!await Services.Broker.EnsureStartedAsync(CancellationToken.None))
        {
            Status = Loc.Get("status.brokerDeclined");
            return;
        }
        IsLive = true;
        await Poll();
        _timer.Start();
    }

    [RelayCommand]
    private void Stop()
    {
        _timer.Stop();
        IsLive = false;
    }

    [RelayCommand]
    private void GetPawnIo()
    {
        if (ConsentDialog.Ask(Loc.Get("sensors.pawnio.title"), Loc.Get("sensors.pawnio.consent"), Loc.Get("sensors.pawnio.open")))
        {
            Process.Start(new ProcessStartInfo("https://pawnio.eu/") { UseShellExecute = true });
        }
    }

    private async Task Poll()
    {
        if (_reading)
        {
            return;
        }
        _reading = true;
        try
        {
            var readings = await Services.Broker.ReadAsync<List<SensorReading>>(ElevatedData.Sensors, CancellationToken.None) ?? [];
            Apply(readings);
            Status = Loc.Format("sensors.updated", DateTime.Now.ToString("HH:mm:ss", CultureInfo.InvariantCulture));
        }
        catch (Exception ex) when (ex is InvalidOperationException or System.IO.IOException)
        {
            Stop();
            Status = Loc.Format("status.fixFailed", "", ex.Message);
        }
        finally
        {
            _reading = false;
        }
    }

    private static readonly string[] Interesting = ["Temperature", "Load", "Clock", "Fan", "Power"];

    private void Apply(IReadOnlyList<SensorReading> readings)
    {
        foreach (var hw in readings.Where(r => Interesting.Contains(r.Type) && r.Value is not null).GroupBy(r => r.Hardware))
        {
            var group = Groups.FirstOrDefault(g => g.Name == hw.Key);
            if (group is null)
            {
                group = new HardwareGroup(hw.Key);
                Groups.Add(group);
            }
            foreach (var r in hw.OrderBy(r => Array.IndexOf(Interesting, r.Type)).ThenBy(r => r.Name).Take(16))
            {
                var key = r.Type + "|" + r.Name;
                var tile = group.Tiles.FirstOrDefault(t => t.Key == key);
                if (tile is null)
                {
                    tile = new SensorTile(key) { Name = r.Name };
                    group.Tiles.Add(tile);
                }
                var (unit, scale) = r.Type switch
                {
                    "Temperature" => ("°C", 105.0),
                    "Load" => ("%", 100.0),
                    "Clock" => ("MHz", 6000.0),
                    "Fan" => ("RPM", 3000.0),
                    "Power" => ("W", 300.0),
                    _ => ("", 100.0),
                };
                tile.Value = $"{r.Value!.Value.ToString("0", CultureInfo.InvariantCulture)} {unit}";
                tile.Max = r.Max is { } m ? Loc.Format("sensors.max", $"{m.ToString("0", CultureInfo.InvariantCulture)} {unit}") : "";
                tile.Fraction = Math.Clamp(r.Value.Value / scale, 0, 1);
                tile.BrushKey = r.Type == "Temperature" && r.Value >= 90 ? "Severity.High" : r.Type == "Temperature" && r.Value >= 80 ? "Warn" : "Accent2";
            }
        }
    }
}
