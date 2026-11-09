using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.Text.Json;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PcDoctor.App.Services;
using PcDoctor.App.ViewModels;
using PcDoctor.App.Views;
using PcDoctor.Core.Findings;
using PcDoctor.Core.Ipc;
using PcDoctor.Core.Localization;
using PcDoctor.Modules.Integrity;

namespace PcDoctor.App.Pages;

public sealed record RepairLogItem(DateTimeOffset Time, Severity Severity, string Step, string Outcome)
{
    public string When => Time.ToLocalTime().ToString("HH:mm");
}

/// <summary>M6 repairs on demand: DISM → SFC → chkdsk, Memory Diagnostic, Defender Offline, and (expert) Driver Verifier.</summary>
public sealed partial class RepairsViewModel : PageViewModel
{
    private CancellationTokenSource? _cts;

    public RepairsViewModel(AppServices services) : base(services)
    {
        services.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(AppServices.Report))
            {
                SuggestDrivers();
            }
        };
        SuggestDrivers();
    }

    public override string Key => "repairs";
    public override string Icon => "";

    public ObservableCollection<RepairLogItem> Log { get; } = [];

    [ObservableProperty] [NotifyCanExecuteChangedFor(nameof(RecommendedCommand), nameof(DismCheckCommand), nameof(DismScanCommand), nameof(DismRestoreCommand),
        nameof(SfcCommand), nameof(ChkdskScanCommand), nameof(ChkdskScheduleCommand), nameof(MemoryDiagnosticCommand), nameof(DefenderOfflineCommand),
        nameof(VerifierEnableCommand), nameof(VerifierResetCommand), nameof(CancelCommand))]
    private bool _isRunning;

    [ObservableProperty] private double? _progress;
    [ObservableProperty] private string _status = "";
    [ObservableProperty] private string _verifierDrivers = "";

    public bool ExpertMode => Services.Settings.ExpertMode;

    private void SuggestDrivers()
    {
        // Prefill Driver Verifier with the drivers crash analysis named (never Windows' own images).
        var names = Services.Report?.Modules.FirstOrDefault(m => m.ModuleId == "M5")?.Findings
            .Where(f => f.Id.StartsWith("M5.culprit.", StringComparison.Ordinal) && f.Title.Key == "m5.culprit.title")
            .Select(f => f.Id["M5.culprit.".Length..])
            .Where(n => n.EndsWith(".sys", StringComparison.OrdinalIgnoreCase))
            .Distinct().ToList() ?? [];
        if (names.Count > 0 && string.IsNullOrWhiteSpace(VerifierDrivers))
        {
            VerifierDrivers = string.Join(" ", names);
        }
    }

    private bool CanRun() => !IsRunning;
    private bool CanCancel() => IsRunning;

    [RelayCommand(CanExecute = nameof(CanRun))]
    private async Task Recommended()
    {
        // CheckHealth → ScanHealth → (consent) RestoreHealth → SFC, one at a time.
        var scan = await Job<DismResult>(JobKind.DismScanHealth);
        if (scan is null)
        {
            return;
        }
        if (scan.State == ImageHealth.Repairable)
        {
            if (!ConsentDialog.Ask(Loc.Get("repairs.restore.title"), Loc.Get("repairs.restore.consent"), Loc.Get("repairs.restore.button")))
            {
                return;
            }
            if (await Job<DismResult>(JobKind.DismRestoreHealth) is not { State: ImageHealth.Repaired })
            {
                return;
            }
        }
        await Job<SfcResult>(JobKind.Sfc);
    }

    [RelayCommand(CanExecute = nameof(CanRun))]
    private Task DismCheck() => Job<DismResult>(JobKind.DismCheckHealth);

    [RelayCommand(CanExecute = nameof(CanRun))]
    private Task DismScan() => Job<DismResult>(JobKind.DismScanHealth);

    [RelayCommand(CanExecute = nameof(CanRun))]
    private Task DismRestore() =>
        ConsentDialog.Ask(Loc.Get("repairs.restore.title"), Loc.Get("repairs.restore.consent"), Loc.Get("repairs.restore.button"))
            ? Job<DismResult>(JobKind.DismRestoreHealth)
            : Task.CompletedTask;

    [RelayCommand(CanExecute = nameof(CanRun))]
    private Task Sfc() => Job<SfcResult>(JobKind.Sfc);

    [RelayCommand(CanExecute = nameof(CanRun))]
    private Task ChkdskScan() => Job<ChkdskResult>(JobKind.ChkdskScan);

    [RelayCommand(CanExecute = nameof(CanRun))]
    private async Task ChkdskSchedule()
    {
        if (!ConsentDialog.Ask(Loc.Get("repairs.chkdskFix.title"), Loc.Get("repairs.chkdskFix.consent"), Loc.Get("repairs.chkdskFix.button"), danger: true))
        {
            return;
        }
        if (await Job<SimpleJobResult>(JobKind.ChkdskScheduleFix) is { ExitCode: 0 })
        {
            OfferRestart();
        }
    }

    [RelayCommand(CanExecute = nameof(CanRun))]
    private void MemoryDiagnostic()
    {
        if (!ConsentDialog.Ask(Loc.Get("repairs.memory.title"), Loc.Get("repairs.memory.consent"), Loc.Get("repairs.memory.button")))
        {
            return;
        }
        try
        {
            // Microsoft's own dialog asks "restart now or at next start"; results appear in the Health Check afterwards.
            Process.Start(new ProcessStartInfo(Core.Platform.ProcessRunner.PathOf(Core.Platform.Tool.Mdsched)) { UseShellExecute = true, Verb = "runas" });
            AddLog(Severity.Info, "repairs.memory.title", Loc.Get("repairs.memory.started"));
        }
        catch (System.ComponentModel.Win32Exception)
        {
            Status = Loc.Get("status.brokerDeclined");
        }
    }

    [RelayCommand(CanExecute = nameof(CanRun))]
    private async Task DefenderOffline()
    {
        if (!ConsentDialog.Ask(Loc.Get("repairs.offline.title"), Loc.Get("repairs.offline.consent"), Loc.Get("repairs.offline.button"), danger: true))
        {
            return;
        }
        await Job<SimpleJobResult>(JobKind.DefenderOfflineScan);
    }

    private bool CanVerifier() => !IsRunning && Services.Settings.ExpertMode;

    [RelayCommand(CanExecute = nameof(CanVerifier))]
    private async Task VerifierEnable()
    {
        if (VerifierArgs.Drivers(VerifierDrivers) is not { } drivers)
        {
            Status = Loc.Get("repairs.verifier.invalid");
            return;
        }
        if (!ConsentDialog.Ask(Loc.Get("repairs.verifier.title"), Loc.Format("repairs.verifier.consent", string.Join(", ", drivers)),
                Loc.Get("repairs.verifier.button"), danger: true))
        {
            return;
        }
        if (await Job<SimpleJobResult>(JobKind.VerifierEnable, string.Join(" ", drivers)) is { ExitCode: 0 })
        {
            OfferRestart();
        }
    }

    [RelayCommand(CanExecute = nameof(CanVerifier))]
    private async Task VerifierReset()
    {
        if (await Job<SimpleJobResult>(JobKind.VerifierReset) is { ExitCode: 0 })
        {
            OfferRestart();
        }
    }

    [RelayCommand(CanExecute = nameof(CanCancel))]
    private void Cancel() => _cts?.Cancel();

    private void OfferRestart()
    {
        if (ConsentDialog.Ask(Loc.Get("repairs.restart.title"), Loc.Get("repairs.restart.body"), Loc.Get("repairs.restart.now")))
        {
            _ = Core.Platform.ProcessRunner.RunAsync(Core.Platform.Tool.Shutdown, ["/r", "/t", "30"], TimeSpan.FromSeconds(30), CancellationToken.None);
        }
    }

    private async Task<T?> Job<T>(JobKind kind, string? target = null) where T : class
    {
        if (!await Services.Broker.EnsureStartedAsync(CancellationToken.None))
        {
            Status = Loc.Get("status.brokerDeclined");
            return null;
        }
        IsRunning = true;
        _cts = new CancellationTokenSource();
        try
        {
            var final = await Services.Broker.RunJobAsync(kind, target, s =>
            {
                Progress = s.Progress;
                Status = Loc.Get("repairs.kind." + kind) + " · " +
                         (s.Progress is { } p ? (p * 100).ToString("0") + " %" : (DateTimeOffset.UtcNow - s.StartedUtc).ToString(@"m\:ss"));
            }, _cts.Token);
            var result = final.Result is { } json ? json.Deserialize<T>(PipeFraming.JsonOptions) : null;
            Describe(kind, final, result);
            return final.State == JobState.Succeeded ? result : null;
        }
        catch (Exception ex) when (ex is InvalidOperationException or System.IO.IOException)
        {
            AddLog(Severity.Medium, "repairs.kind." + kind, Loc.Format("status.fixFailed", "", ex.Message));
            return null;
        }
        finally
        {
            IsRunning = false;
            Status = "";
            Progress = null;
        }
    }

    private void Describe(JobKind kind, JobStatus final, object? result)
    {
        var step = "repairs.kind." + kind;
        if (final.State == JobState.Cancelled)
        {
            AddLog(Severity.Info, step, Loc.Get("status.cancelled"));
            return;
        }
        if (final.State == JobState.Failed)
        {
            AddLog(Severity.Medium, step, Loc.Format("status.fixFailed", "", final.Message ?? ""));
            return;
        }
        switch (result)
        {
            case DismResult d:
                AddLog(d.State switch { ImageHealth.Healthy or ImageHealth.Repaired => Severity.Info, ImageHealth.Repairable => Severity.Medium, _ => Severity.High },
                    step, Loc.Format("repairs.dism." + d.State, "0x" + d.HResult.ToString("X8")));
                break;
            case SfcResult s:
                AddLog(s.Unrepairable.Count > 0 ? Severity.High : s.Repaired.Count > 0 ? Severity.Medium : Severity.Info, step,
                    !s.LogReadable ? Loc.Format("repairs.sfc.noLog", s.ExitCode)
                    : s.Unrepairable.Count > 0 ? Loc.Format("repairs.sfc.unrepairable", s.Unrepairable.Count, string.Join(", ", s.Unrepairable.Take(5)))
                    : s.Repaired.Count > 0 ? Loc.Format("repairs.sfc.repaired", s.Repaired.Count, string.Join(", ", s.Repaired.Take(5)))
                    : Loc.Get("repairs.sfc.none"));
                break;
            case ChkdskResult c:
                AddLog(c.ExitCode == 0 ? Severity.Info : c.ExitCode == 1 ? Severity.Low : Severity.High, step, Loc.Format("repairs.chkdsk." + c.Meaning, c.Volume));
                break;
            case SimpleJobResult r:
                AddLog(r.ExitCode == 0 ? Severity.Info : Severity.Medium, step, Loc.Format(r.ExitCode == 0 ? "repairs.done" : "repairs.exit", r.ExitCode));
                break;
        }
    }

    private void AddLog(Severity severity, string stepKey, string outcome) =>
        Log.Insert(0, new RepairLogItem(DateTimeOffset.UtcNow, severity, Loc.Get(stepKey), outcome));

    protected override void OnTextsChanged()
    {
        OnPropertyChanged(nameof(ExpertMode));
        VerifierEnableCommand.NotifyCanExecuteChanged();
        VerifierResetCommand.NotifyCanExecuteChanged();
    }
}
