using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Data;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.Win32;
using PcDoctor.App.Localization;
using PcDoctor.App.Services;
using PcDoctor.Core.Findings;
using PcDoctor.Core.Fixes;
using PcDoctor.Core.Ipc;
using PcDoctor.Core.Journal;
using PcDoctor.Core.Localization;
using PcDoctor.Core.Platform;
using PcDoctor.Core.Reporting;
using PcDoctor.Core.Scanning;

namespace PcDoctor.App.ViewModels;

public sealed record Choice<T>(T Value, string LabelKey)
{
    public string Label => LocSource.Instance[LabelKey];
}

public sealed partial class MainViewModel : ObservableObject, IAsyncDisposable
{
    private readonly BrokerClient _broker = new();
    private AppSettings _settings;
    private CancellationTokenSource? _scanCts;
    private ScanReport? _report;

    public MainViewModel(AppSettings settings)
    {
        _settings = settings;
        FindingsView = CollectionViewSource.GetDefaultView(Findings);
        FindingsView.GroupDescriptions.Add(new PropertyGroupDescription(nameof(FindingItemViewModel.ModuleName)));
        FindingsView.SortDescriptions.Add(new SortDescription(nameof(FindingItemViewModel.Severity), ListSortDirection.Descending));
        FindingsView.Filter = o => o is FindingItemViewModel f && Matches(f);
        ChecksView = CollectionViewSource.GetDefaultView(Checks);
        ChecksView.GroupDescriptions.Add(new PropertyGroupDescription(nameof(CheckItemViewModel.ModuleName)));

        _severityFilter = SeverityFilters[0];
        _selectedLanguage = Languages.FirstOrDefault(l => l.Value == settings.Language) ?? Languages[0];
        _selectedTheme = Themes.First(t => t.Value == settings.Theme);
        _selectedDigits = DigitStyles.First(d => d.Value == settings.Digits);
        _redactExports = settings.RedactExports;
        SummaryLines.Add(Loc.Get("dashboard.intro"));
        LoadJournal();
    }

    public ObservableCollection<FindingItemViewModel> Findings { get; } = [];
    public ICollectionView FindingsView { get; }
    public ObservableCollection<CheckItemViewModel> Checks { get; } = [];
    public ICollectionView ChecksView { get; }
    public ObservableCollection<string> SummaryLines { get; } = [];
    public ObservableCollection<JournalItemViewModel> Journal { get; } = [];

    public IReadOnlyList<Choice<Severity?>> SeverityFilters { get; } =
    [
        new(null, "filter.all"),
        new(Severity.Critical, "severity.Critical"),
        new(Severity.High, "severity.High"),
        new(Severity.Medium, "severity.Medium"),
        new(Severity.Low, "severity.Low"),
        new(Severity.Info, "severity.Info"),
    ];

    public IReadOnlyList<Choice<string>> Languages { get; } = [new("en-US", "language.en"), new("ar-SA", "language.ar")];
    public IReadOnlyList<Choice<ThemeChoice>> Themes { get; } =
        [new(ThemeChoice.System, "theme.system"), new(ThemeChoice.Light, "theme.light"), new(ThemeChoice.Dark, "theme.dark")];
    public IReadOnlyList<Choice<DigitStyle>> DigitStyles { get; } =
        [new(DigitStyle.Western, "digits.western"), new(DigitStyle.ArabicIndic, "digits.arabicIndic")];

    [ObservableProperty] [NotifyCanExecuteChangedFor(nameof(HealthCheckCommand), nameof(DeepScanCommand), nameof(CancelScanCommand))]
    private bool _isBusy;

    [ObservableProperty] private string _status = "";
    [ObservableProperty] private FindingItemViewModel? _selectedFinding;
    [ObservableProperty] private Choice<Severity?> _severityFilter = null!;
    [ObservableProperty] private string _searchText = "";
    [ObservableProperty] private bool _showHidden;
    [ObservableProperty] private Choice<string> _selectedLanguage;
    [ObservableProperty] private Choice<ThemeChoice> _selectedTheme;
    [ObservableProperty] private Choice<DigitStyle> _selectedDigits;
    [ObservableProperty] private bool _redactExports;

    public bool HasReport => _report is not null;

    partial void OnSeverityFilterChanged(Choice<Severity?> value) => FindingsView.Refresh();
    partial void OnSearchTextChanged(string value) => FindingsView.Refresh();
    partial void OnShowHiddenChanged(bool value) => FindingsView.Refresh();

    partial void OnSelectedLanguageChanged(Choice<string> value)
    {
        LocSource.Instance.SetCulture(CultureInfo.GetCultureInfo(value.Value));
        SaveSettings();
        RefreshTexts();
    }

    partial void OnSelectedDigitsChanged(Choice<DigitStyle> value)
    {
        Loc.Digits = value.Value;
        LocSource.Instance.Refresh();
        SaveSettings();
        RefreshTexts();
    }

    partial void OnSelectedThemeChanged(Choice<ThemeChoice> value)
    {
        ThemeManager.Apply(value.Value);
        SaveSettings();
    }

    partial void OnRedactExportsChanged(bool value) => SaveSettings();

    private bool Matches(FindingItemViewModel f)
    {
        if (f.Finding.HiddenByDefault && !ShowHidden)
        {
            return false;
        }
        if (SeverityFilter?.Value is { } sev && f.Severity != sev)
        {
            return false;
        }
        return string.IsNullOrWhiteSpace(SearchText) ||
               f.Title.Contains(SearchText, StringComparison.CurrentCultureIgnoreCase) ||
               f.Finding.Id.Contains(SearchText, StringComparison.OrdinalIgnoreCase) ||
               f.Evidence.Any(e => e.Value.Contains(SearchText, StringComparison.OrdinalIgnoreCase));
    }

    private bool CanScan() => !IsBusy;

    [RelayCommand(CanExecute = nameof(CanScan))]
    private Task HealthCheck() => RunScan(ScanMode.HealthCheck);

    [RelayCommand(CanExecute = nameof(CanScan))]
    private Task DeepScan() => RunScan(ScanMode.DeepScan);

    [RelayCommand(CanExecute = nameof(IsBusy))]
    private void CancelScan() => _scanCts?.Cancel();

    private async Task RunScan(ScanMode mode)
    {
        IsBusy = true;
        _scanCts = new CancellationTokenSource();
        try
        {
            IElevatedReader? elevated = null;
            if (mode == ScanMode.DeepScan)
            {
                Status = Loc.Get("status.startingBroker");
                if (!await _broker.EnsureStartedAsync(_scanCts.Token))
                {
                    Status = Loc.Get("status.brokerDeclined");
                    mode = ScanMode.HealthCheck;
                }
                else
                {
                    elevated = _broker;
                }
            }
            var progress = new Progress<ScanProgress>(p => Status = Loc.Format("status.scanning", p.Completed + 1, p.Total, Loc.Resolve(p.CurrentModule)));
            var runner = new ScanRunner(AppModules.Create(), new WindowsConditionsReader());
            _report = await Task.Run(() => runner.RunAsync(mode, elevated, progress, _scanCts.Token));
            ShowReport(_report);
            Status = Loc.Get("status.done");
        }
        catch (OperationCanceledException)
        {
            Status = Loc.Get("status.cancelled");
        }
        finally
        {
            IsBusy = false;
            OnPropertyChanged(nameof(HasReport));
            ExportCommand.NotifyCanExecuteChanged();
        }
    }

    private void ShowReport(ScanReport report)
    {
        Findings.Clear();
        Checks.Clear();
        foreach (var m in report.Modules)
        {
            foreach (var f in m.Findings)
            {
                Findings.Add(new FindingItemViewModel(f, m.ModuleName));
            }
            foreach (var c in m.Checks)
            {
                Checks.Add(new CheckItemViewModel(c, m.ModuleName));
            }
        }
        RefreshSummary();
        SelectedFinding = FindingsView.Cast<FindingItemViewModel>().FirstOrDefault();
    }

    private void RefreshSummary()
    {
        SummaryLines.Clear();
        if (_report is null)
        {
            SummaryLines.Add(Loc.Get("dashboard.intro"));
            return;
        }
        foreach (var line in ReportSummary.Build(_report))
        {
            SummaryLines.Add(Loc.Resolve(line));
        }
    }

    private void RefreshTexts()
    {
        foreach (var f in Findings)
        {
            f.Refresh();
        }
        foreach (var c in Checks)
        {
            c.Refresh();
        }
        foreach (var j in Journal)
        {
            j.Refresh();
        }
        RefreshSummary();
        FindingsView.Refresh();
        ChecksView.Refresh();
    }

    [RelayCommand]
    private void CopyFinding(FindingItemViewModel? item)
    {
        if ((item ?? SelectedFinding) is { } f)
        {
            Clipboard.SetText(ReportExporter.FindingToText(f.Finding, Loc.Culture));
        }
    }

    [RelayCommand(CanExecute = nameof(HasReport))]
    private void Export()
    {
        if (_report is null)
        {
            return;
        }
        var dialog = new SaveFileDialog
        {
            FileName = $"pcdoctor-{_report.StartedUtc:yyyyMMdd-HHmm}",
            Filter = "HTML (*.html)|*.html|JSON (*.json)|*.json|CSV (*.csv)|*.csv",
        };
        if (dialog.ShowDialog() != true)
        {
            return;
        }
        var options = new ExportOptions(Loc.Culture, RedactExports);
        var text = Path.GetExtension(dialog.FileName).ToLowerInvariant() switch
        {
            ".json" => ReportExporter.ToJson(_report, options),
            ".csv" => ReportExporter.FindingsToCsv(_report, options),
            _ => ReportExporter.ToHtml(_report, options),
        };
        // UTF-8 with BOM so Excel opens Arabic CSV correctly.
        File.WriteAllText(dialog.FileName, text, new UTF8Encoding(encoderShouldEmitUTF8Identifier: true));
        Status = Loc.Format("status.exported", dialog.FileName);
    }

    [RelayCommand]
    private async Task ApplyFix(FindingItemViewModel? item)
    {
        if (item?.Finding.FixId is not { } fixId || FixCatalog.Find(fixId) is not { } fix)
        {
            return;
        }
        // Consent with the exact changes, the restore point and the restart, before anything happens.
        var preview = new StringBuilder()
            .AppendLine(Loc.Resolve(fix.Explanation)).AppendLine()
            .AppendLine(Loc.Get("fix.preview.changes"));
        foreach (var c in fix.Changes)
        {
            preview.AppendLine("  ⁦" + c.Describe() + "⁩");
        }
        preview.AppendLine().AppendLine(Loc.Get("fix.preview.restorePoint"));
        if (fix.RequiresRestart)
        {
            preview.AppendLine(Loc.Get("fix.preview.restart"));
        }
        var options = Loc.IsRightToLeft() ? MessageBoxOptions.RtlReading | MessageBoxOptions.RightAlign : MessageBoxOptions.None;
        if (MessageBox.Show(preview.ToString(), Loc.Resolve(fix.Title), MessageBoxButton.OKCancel, MessageBoxImage.Question,
                MessageBoxResult.Cancel, options) != MessageBoxResult.OK)
        {
            return;
        }
        if (!await _broker.EnsureStartedAsync(CancellationToken.None))
        {
            Status = Loc.Get("status.brokerDeclined");
            return;
        }
        var response = await _broker.SendAsync(new ApplyFixRequest(fixId), CancellationToken.None);
        Status = response.Ok ? Loc.Get("status.fixApplied") : Loc.Format("status.fixFailed", response.Error, response.ErrorDetail ?? "");
        LoadJournal();
    }

    [RelayCommand]
    private void LoadJournal()
    {
        Journal.Clear();
        try
        {
            foreach (var e in new ChangeJournal(AppModules.JournalPath).ReadCurrent().Reverse())
            {
                Journal.Add(new JournalItemViewModel(e));
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            Status = Loc.Get("status.journalUnreadable");
        }
    }

    [RelayCommand]
    private Task UndoEntry(JournalItemViewModel? item) =>
        item is null ? Task.CompletedTask : Undo(new UndoRequest(UndoScope.Entry, item.Entry.Id, Force: false));

    [RelayCommand]
    private Task UndoBatch(JournalItemViewModel? item) =>
        item is null ? Task.CompletedTask : Undo(new UndoRequest(UndoScope.Batch, item.Entry.BatchId, Force: false));

    [RelayCommand]
    private Task UndoEverything()
    {
        var options = Loc.IsRightToLeft() ? MessageBoxOptions.RtlReading | MessageBoxOptions.RightAlign : MessageBoxOptions.None;
        return MessageBox.Show(Loc.Get("journal.undoAll.confirm"), Loc.Get("journal.undoAll"), MessageBoxButton.OKCancel,
                   MessageBoxImage.Question, MessageBoxResult.Cancel, options) == MessageBoxResult.OK
            ? Undo(new UndoRequest(UndoScope.Everything, null, Force: false))
            : Task.CompletedTask;
    }

    private async Task Undo(UndoRequest request)
    {
        if (!await _broker.EnsureStartedAsync(CancellationToken.None))
        {
            Status = Loc.Get("status.brokerDeclined");
            return;
        }
        var response = await _broker.SendAsync(request, CancellationToken.None);
        var result = response.PayloadAs<UndoResult>();
        Status = result is null
            ? Loc.Format("status.fixFailed", response.Error, response.ErrorDetail ?? "")
            : Loc.Format("status.undone", result.Undone, result.Conflicts, result.Failed);
        LoadJournal();
    }

    private void SaveSettings()
    {
        _settings = _settings with
        {
            Language = SelectedLanguage.Value,
            Theme = SelectedTheme.Value,
            Digits = SelectedDigits.Value,
            RedactExports = RedactExports,
        };
        try
        {
            _settings.Save();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            Status = Loc.Get("status.settingsUnsaved");
        }
    }

    public ValueTask DisposeAsync() => _broker.DisposeAsync();
}
