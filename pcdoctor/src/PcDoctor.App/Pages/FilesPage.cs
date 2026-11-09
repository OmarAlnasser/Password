using System.Collections.ObjectModel;
using System.IO;
using System.Text.Json;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.Win32;
using PcDoctor.App.Services;
using PcDoctor.App.ViewModels;
using PcDoctor.Core.Ipc;
using PcDoctor.Core.Localization;
using PcDoctor.Modules.Inventory;

namespace PcDoctor.App.Pages;

/// <summary>M1: account for every file on the fixed drives, scanned or skipped with a reason.</summary>
public sealed partial class FilesViewModel(AppServices services) : PageViewModel(services)
{
    private CancellationTokenSource? _cts;
    private InventoryResult? _result;

    public override string Key => "files";
    public override string Icon => "";

    public ObservableCollection<StatTile> Stats { get; } = [];
    public ObservableCollection<SkippedItem> Sample { get; } = [];

    [ObservableProperty] [NotifyCanExecuteChangedFor(nameof(RunCommand), nameof(RunElevatedCommand), nameof(CancelCommand), nameof(ExportCommand))]
    private bool _isRunning;

    [ObservableProperty] private string _status = "";
    [ObservableProperty] private string _summary = "";

    public bool HasResult => _result is not null;

    private bool CanRun() => !IsRunning;
    private bool CanCancel() => IsRunning;
    private bool CanExport() => !IsRunning && _result is not null;

    [RelayCommand(CanExecute = nameof(CanRun))]
    private async Task Run()
    {
        IsRunning = true;
        _cts = new CancellationTokenSource();
        try
        {
            var progress = new UiProgress(this);
            var csv = Path.Combine(AppSettings.Folder, "inventory");
            Show(await Task.Run(() => InventoryWalker.Run(false, progress, _cts.Token, csv)));
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
    private async Task RunElevated()
    {
        if (!await Services.Broker.EnsureStartedAsync(CancellationToken.None))
        {
            Status = Loc.Get("status.brokerDeclined");
            return;
        }
        IsRunning = true;
        _cts = new CancellationTokenSource();
        try
        {
            var final = await Services.Broker.RunJobAsync(JobKind.InventoryWithBackupPrivilege, null, s => Status = s.Message ?? "", _cts.Token);
            if (final.Result is { } json && json.Deserialize<InventoryResult>(PipeFraming.JsonOptions) is { } r)
            {
                Show(r);
            }
            else
            {
                Status = final.State == JobState.Cancelled ? Loc.Get("status.cancelled") : Loc.Format("status.fixFailed", "", final.Message ?? "");
            }
        }
        finally
        {
            IsRunning = false;
        }
    }

    [RelayCommand(CanExecute = nameof(CanCancel))]
    private void Cancel() => _cts?.Cancel();

    [RelayCommand(CanExecute = nameof(CanExport))]
    private void Export()
    {
        if (_result?.SkippedCsvPath is not { } csv || !File.Exists(csv))
        {
            return;
        }
        var dialog = new SaveFileDialog { FileName = Path.GetFileName(csv), Filter = "CSV (*.csv)|*.csv" };
        if (dialog.ShowDialog() == true)
        {
            File.Copy(csv, dialog.FileName, overwrite: true);
            Status = Loc.Format("status.exported", dialog.FileName);
        }
    }

    private void Show(InventoryResult r)
    {
        _result = r;
        Stats.Clear();
        Sample.Clear();
        Stats.Add(new StatTile("files.stat.inventoried", (int)Math.Min(int.MaxValue, r.FilesInventoried), "Accent2"));
        Stats.Add(new StatTile("files.stat.denied", (int)r.SkippedFiles.GetValueOrDefault(SkipReason.AccessDenied), "Severity.Medium"));
        Stats.Add(new StatTile("files.stat.cloud", (int)r.SkippedFiles.GetValueOrDefault(SkipReason.CloudOnly), "Accent"));
        Stats.Add(new StatTile("files.stat.links", (int)r.SkippedFiles.GetValueOrDefault(SkipReason.LinkNotFollowed), "Muted"));
        Stats.Add(new StatTile("files.stat.folders", (int)Math.Min(int.MaxValue, r.TotalSkippedDirectories), "Severity.High"));
        foreach (var s in r.SkippedSample.Take(200))
        {
            Sample.Add(s);
        }
        Summary = Loc.Format("files.summary", r.FilesInventoried, r.TotalSkippedFiles, r.SkippedFiles.GetValueOrDefault(SkipReason.AccessDenied),
            r.SkippedFiles.GetValueOrDefault(SkipReason.Locked), r.SkippedFiles.GetValueOrDefault(SkipReason.CloudOnly),
            r.SkippedFiles.GetValueOrDefault(SkipReason.PathError), r.SkippedFiles.GetValueOrDefault(SkipReason.LinkNotFollowed),
            r.TotalSkippedDirectories, r.HardLinkDuplicates);
        Status = Loc.Format("files.duration", r.Duration.ToString(@"h\:mm\:ss"), string.Join(", ", r.Volumes));
        OnPropertyChanged(nameof(HasResult));
        ExportCommand.NotifyCanExecuteChanged();
    }

    private sealed class UiProgress(FilesViewModel vm) : IJobProgress
    {
        private readonly System.Windows.Threading.Dispatcher _dispatcher = System.Windows.Application.Current.Dispatcher;

        public void Report(double? fraction, string? message) => _dispatcher.BeginInvoke(() => vm.Status = message ?? "");
    }
}
