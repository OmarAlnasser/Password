using System.Collections.ObjectModel;
using System.Text.Json;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.Win32;
using PcDoctor.App.Services;
using PcDoctor.App.ViewModels;
using PcDoctor.App.Views;
using PcDoctor.Core.Ipc;
using PcDoctor.Core.Localization;
using PcDoctor.Modules.Malware;
using PcDoctor.Modules.Security;

namespace PcDoctor.App.Pages;

public sealed class DetectionItem(DefenderDetection d)
{
    public DefenderDetection Detection => d;
    public string Name => d.ThreatName;
    public string Severity => d.SeverityName;
    public string Paths => string.Join("\n", d.Paths.Take(5));
    public string When => d.DetectedUtc?.ToLocalTime().ToString("yyyy-MM-dd HH:mm") ?? "";
}

/// <summary>M2 on demand: Defender scans, the Safety Scanner second opinion, and Defender's quarantine.</summary>
public sealed partial class ProtectionViewModel(AppServices services) : PageViewModel(services)
{
    private CancellationTokenSource? _cts;
    private DefenderGateResult? _gate;

    public override string Key => "protection";
    public override string Icon => "";

    public ObservableCollection<DetectionItem> Detections { get; } = [];
    public ObservableCollection<QuarantineItem> Quarantine { get; } = [];

    [ObservableProperty] [NotifyCanExecuteChangedFor(nameof(QuickScanCommand), nameof(FullScanCommand), nameof(CustomScanCommand),
        nameof(SafetyScannerCommand), nameof(CancelCommand), nameof(LoadQuarantineCommand))]
    private bool _isRunning;

    [ObservableProperty] private double? _progress;
    [ObservableProperty] private string _status = "";
    [ObservableProperty] private string _resultTitle = "";
    [ObservableProperty] private string _resultBody = "";
    [ObservableProperty] private bool _hasResult;
    [ObservableProperty] private bool _resultIsBad;

    public bool DefenderAvailable => _gate?.Availability == DefenderAvailability.Available;
    public string EngineText => _gate?.Availability switch
    {
        DefenderAvailability.Available => Loc.Get("m2.engine.defender"),
        DefenderAvailability.ThirdPartyActive => Loc.Format("m2.engine.thirdParty", _gate.ActiveProduct ?? "?"),
        null => Loc.Get("protection.engine.checking"),
        _ => Loc.Get("m2.engine.none"),
    };

    public override void OnShown()
    {
        if (_gate is not null)
        {
            return;
        }
        _ = Task.Run(() =>
        {
            var s = SecurityReader.Read();
            return DefenderGate.Evaluate(s.Defender, s.AvProducts);
        }).ContinueWith(t =>
        {
            _gate = t.IsCompletedSuccessfully ? t.Result : new DefenderGateResult(DefenderAvailability.Unknown, null, null);
            OnPropertyChanged(nameof(DefenderAvailable));
            OnPropertyChanged(nameof(EngineText));
            NotifyAll();
        }, TaskScheduler.FromCurrentSynchronizationContext());
    }

    private void NotifyAll()
    {
        QuickScanCommand.NotifyCanExecuteChanged();
        FullScanCommand.NotifyCanExecuteChanged();
        CustomScanCommand.NotifyCanExecuteChanged();
    }

    private bool CanScan() => !IsRunning && DefenderAvailable;
    private bool CanRunAny() => !IsRunning;
    private bool CanCancel() => IsRunning;

    [RelayCommand(CanExecute = nameof(CanScan))]
    private Task QuickScan() => RunDefender(JobKind.DefenderQuickScan, null);

    [RelayCommand(CanExecute = nameof(CanScan))]
    private Task FullScan() => RunDefender(JobKind.DefenderFullScan, null);

    [RelayCommand(CanExecute = nameof(CanScan))]
    private Task CustomScan()
    {
        var dialog = new OpenFolderDialog { Title = Loc.Get("protection.custom.pick") };
        return dialog.ShowDialog() == true ? RunDefender(JobKind.DefenderCustomReportOnly, dialog.FolderName) : Task.CompletedTask;
    }

    [RelayCommand(CanExecute = nameof(CanRunAny))]
    private async Task SafetyScanner()
    {
        if (!ConsentDialog.Ask(Loc.Get("protection.msert.title"), Loc.Get("protection.msert.consent"), Loc.Get("protection.msert.run")))
        {
            return;
        }
        var status = await Run(JobKind.SafetyScannerQuick, null);
        if (status?.Result is { } json && json.Deserialize<SafetyScannerResult>(PipeFraming.JsonOptions) is { } r)
        {
            ShowResult(r.InfectedFiles > 0, Loc.Format(r.InfectedFiles > 0 ? "protection.msert.found" : "protection.msert.none", r.InfectedFiles),
                string.Join("\n", r.Detections));
        }
    }

    [RelayCommand(CanExecute = nameof(CanCancel))]
    private void Cancel() => _cts?.Cancel();

    private async Task RunDefender(JobKind kind, string? target)
    {
        var status = await Run(kind, target);
        if (status?.Result is not { } json || json.Deserialize<DefenderScanResult>(PipeFraming.JsonOptions) is not { } r)
        {
            return;
        }
        Detections.Clear();
        foreach (var d in r.Detections)
        {
            Detections.Add(new DetectionItem(d));
        }
        // Wording per outcome: never "clean", and a failed scan is never reported as "threat found".
        var key = r.Outcome switch
        {
            ScanOutcome.NoThreatsDetected => "protection.result.none",
            ScanOutcome.ThreatsFound => "protection.result.handled",
            ScanOutcome.ThreatsRemaining => "protection.result.remaining",
            ScanOutcome.Cancelled => "protection.result.cancelled",
            _ => "protection.result.failed",
        };
        ShowResult(r.Outcome is ScanOutcome.ThreatsRemaining or ScanOutcome.ScanFailed, Loc.Format(key, r.Detections.Count),
            Loc.Format("protection.result.detail", Loc.Get("protection.kind." + r.ScanType), r.FinishedUtc.ToLocalTime().ToString("HH:mm"),
                r.ExitCode.ToString(System.Globalization.CultureInfo.InvariantCulture)) +
            (r.SignatureUpdateOk ? "" : "\n" + Loc.Get("protection.result.signaturesFailed")));
    }

    private void ShowResult(bool bad, string title, string body)
    {
        ResultIsBad = bad;
        ResultTitle = title;
        ResultBody = body;
        HasResult = true;
    }

    private async Task<JobStatus?> Run(JobKind kind, string? target)
    {
        if (!await Services.Broker.EnsureStartedAsync(CancellationToken.None))
        {
            Status = Loc.Get("status.brokerDeclined");
            return null;
        }
        IsRunning = true;
        HasResult = false;
        Progress = null;
        _cts = new CancellationTokenSource();
        try
        {
            var final = await Services.Broker.RunJobAsync(kind, target, s =>
            {
                Progress = s.Progress;
                Status = Loc.Format("protection.running", Loc.Get("protection.kind." + kind), (DateTimeOffset.UtcNow - s.StartedUtc).ToString(@"h\:mm\:ss"));
            }, _cts.Token);
            Status = final.State == JobState.Failed ? Loc.Format("status.fixFailed", "", final.Message ?? "") : "";
            return final;
        }
        catch (Exception ex) when (ex is InvalidOperationException or System.IO.IOException)
        {
            Status = Loc.Format("status.fixFailed", "", ex.Message);
            return null;
        }
        finally
        {
            IsRunning = false;
        }
    }

    [RelayCommand(CanExecute = nameof(CanRunAny))]
    private async Task LoadQuarantine()
    {
        if (!await Services.Broker.EnsureStartedAsync(CancellationToken.None))
        {
            Status = Loc.Get("status.brokerDeclined");
            return;
        }
        var r = await Services.Broker.SendAsync(new QuarantineListRequest(), CancellationToken.None);
        Quarantine.Clear();
        foreach (var q in r.PayloadAs<List<QuarantineItem>>() ?? [])
        {
            Quarantine.Add(q);
        }
        Status = Quarantine.Count == 0 ? Loc.Get("protection.quarantine.empty") : "";
    }

    [RelayCommand]
    private async Task Restore(QuarantineItem? item)
    {
        if (item is null || !ConsentDialog.Ask(Loc.Get("protection.restore.title"),
                Loc.Format("protection.restore.consent", item.ThreatName, string.Join("\n", item.Files)), Loc.Get("protection.restore.button"), danger: true))
        {
            return;
        }
        var r = await Services.Broker.SendAsync(new QuarantineRestoreRequest(item.ThreatName, null), CancellationToken.None);
        Status = r.Ok ? Loc.Get("protection.restore.done") : Loc.Format("status.fixFailed", r.Error, r.ErrorDetail ?? "");
        await LoadQuarantine();
    }
}
