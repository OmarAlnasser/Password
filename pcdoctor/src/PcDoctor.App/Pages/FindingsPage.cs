using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Data;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.Win32;
using PcDoctor.App.Services;
using PcDoctor.App.ViewModels;
using PcDoctor.App.Views;
using PcDoctor.Core.Findings;
using PcDoctor.Core.Fixes;
using PcDoctor.Core.Ipc;
using PcDoctor.Core.Localization;
using PcDoctor.Core.Reporting;

namespace PcDoctor.App.Pages;

public sealed record Choice<T>(T Value, string LabelKey)
{
    public string Label => Loc.Get(LabelKey);
}

public sealed partial class FindingsViewModel : PageViewModel
{
    public FindingsViewModel(AppServices services) : base(services)
    {
        FindingsView = CollectionViewSource.GetDefaultView(Findings);
        FindingsView.GroupDescriptions.Add(new PropertyGroupDescription(nameof(FindingItemViewModel.ModuleName)));
        FindingsView.SortDescriptions.Add(new SortDescription(nameof(FindingItemViewModel.Severity), ListSortDirection.Descending));
        FindingsView.Filter = o => o is FindingItemViewModel f && Matches(f);
        ChecksView = CollectionViewSource.GetDefaultView(Checks);
        ChecksView.GroupDescriptions.Add(new PropertyGroupDescription(nameof(CheckItemViewModel.ModuleName)));
        _severityFilter = SeverityFilters[0];
        _moduleFilter = ModuleFilters[0];
        services.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(AppServices.Report))
            {
                Load();
            }
        };
        Load();
    }

    public override string Key => "findings";
    public override string Icon => "";

    public ObservableCollection<FindingItemViewModel> Findings { get; } = [];
    public ICollectionView FindingsView { get; }
    public ObservableCollection<CheckItemViewModel> Checks { get; } = [];
    public ICollectionView ChecksView { get; }

    public IReadOnlyList<Choice<Severity?>> SeverityFilters { get; } =
    [
        new(null, "filter.all"),
        new(Severity.Critical, "severity.Critical"),
        new(Severity.High, "severity.High"),
        new(Severity.Medium, "severity.Medium"),
        new(Severity.Low, "severity.Low"),
        new(Severity.Info, "severity.Info"),
    ];

    public ObservableCollection<Choice<string?>> ModuleFilters { get; } = [new(null, "filter.allAreas")];

    [ObservableProperty] private FindingItemViewModel? _selectedFinding;
    [ObservableProperty] private Choice<Severity?> _severityFilter;
    [ObservableProperty] private Choice<string?> _moduleFilter;
    [ObservableProperty] private string _searchText = "";
    [ObservableProperty] private bool _showHidden;
    [ObservableProperty] private bool _showChecks;
    [ObservableProperty] private string _status = "";

    public bool HasReport => Services.Report is not null;
    public bool IsEmpty => HasReport && !FindingsView.Cast<object>().Any();

    partial void OnSeverityFilterChanged(Choice<Severity?> value) => RefreshView();
    partial void OnModuleFilterChanged(Choice<string?> value) => RefreshView();
    partial void OnSearchTextChanged(string value) => RefreshView();
    partial void OnShowHiddenChanged(bool value) => RefreshView();

    public override void OnNavigated(string? argument)
    {
        if (argument is not null && ModuleFilters.FirstOrDefault(m => m.Value == argument) is { } m)
        {
            ModuleFilter = m;
        }
    }

    private void RefreshView()
    {
        FindingsView.Refresh();
        OnPropertyChanged(nameof(IsEmpty));
        if (SelectedFinding is null || !Matches(SelectedFinding))
        {
            SelectedFinding = FindingsView.Cast<FindingItemViewModel>().FirstOrDefault();
        }
    }

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
        if (ModuleFilter?.Value is { } module && f.Finding.Module != module)
        {
            return false;
        }
        return string.IsNullOrWhiteSpace(SearchText) ||
               f.Title.Contains(SearchText, StringComparison.CurrentCultureIgnoreCase) ||
               f.Finding.Id.Contains(SearchText, StringComparison.OrdinalIgnoreCase) ||
               f.Evidence.Any(e => e.Value.Contains(SearchText, StringComparison.OrdinalIgnoreCase));
    }

    private void Load()
    {
        Findings.Clear();
        Checks.Clear();
        var keep = ModuleFilter?.Value;
        while (ModuleFilters.Count > 1)
        {
            ModuleFilters.RemoveAt(1);
        }
        if (Services.Report is { } report)
        {
            foreach (var m in report.Modules)
            {
                ModuleFilters.Add(new Choice<string?>(m.ModuleId, m.ModuleName.Key));
                foreach (var f in m.Findings)
                {
                    Findings.Add(new FindingItemViewModel(f, m.ModuleName));
                }
                foreach (var c in m.Checks)
                {
                    Checks.Add(new CheckItemViewModel(c, m.ModuleName));
                }
            }
        }
        ModuleFilter = ModuleFilters.FirstOrDefault(m => m.Value == keep) ?? ModuleFilters[0];
        OnPropertyChanged(nameof(HasReport));
        RefreshView();
        ExportCommand.NotifyCanExecuteChanged();
    }

    protected override void OnTextsChanged()
    {
        foreach (var f in Findings)
        {
            f.Refresh();
        }
        foreach (var c in Checks)
        {
            c.Refresh();
        }
        FindingsView.Refresh();
        ChecksView.Refresh();
    }

    [RelayCommand]
    private void SetSeverity(Choice<Severity?>? choice)
    {
        if (choice is not null)
        {
            SeverityFilter = choice;
        }
    }

    [RelayCommand]
    private void Copy(FindingItemViewModel? item)
    {
        if ((item ?? SelectedFinding) is { } f)
        {
            Clipboard.SetText(ReportExporter.FindingToText(f.Finding, Loc.Culture));
            Status = Loc.Get("status.copied");
        }
    }

    [RelayCommand(CanExecute = nameof(HasReport))]
    private void Export()
    {
        if (Services.Report is not { } report)
        {
            return;
        }
        var dialog = new SaveFileDialog
        {
            FileName = $"pcdoctor-{report.StartedUtc:yyyyMMdd-HHmm}",
            Filter = "HTML (*.html)|*.html|JSON (*.json)|*.json|CSV (*.csv)|*.csv",
        };
        if (dialog.ShowDialog() != true)
        {
            return;
        }
        var options = new ExportOptions(Loc.Culture, Services.Settings.RedactExports);
        var text = Path.GetExtension(dialog.FileName).ToLowerInvariant() switch
        {
            ".json" => ReportExporter.ToJson(report, options),
            ".csv" => ReportExporter.FindingsToCsv(report, options),
            _ => ReportExporter.ToHtml(report, options),
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
        if (!ConsentDialog.Ask(Loc.Resolve(fix.Title), preview.ToString(), Loc.Get("action.applyFix.confirm")))
        {
            return;
        }
        if (!await Services.Broker.EnsureStartedAsync(CancellationToken.None))
        {
            Status = Loc.Get("status.brokerDeclined");
            return;
        }
        var response = await Services.Broker.SendAsync(new ApplyFixRequest(fixId), CancellationToken.None);
        Status = response.Ok ? Loc.Get("status.fixApplied") : Loc.Format("status.fixFailed", response.Error, response.ErrorDetail ?? "");
    }
}
