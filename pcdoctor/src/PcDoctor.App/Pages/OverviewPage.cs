using System.Collections.ObjectModel;
using System.ComponentModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PcDoctor.App.Services;
using PcDoctor.App.ViewModels;
using PcDoctor.Core.Findings;
using PcDoctor.Core.Localization;
using PcDoctor.Core.Reporting;
using PcDoctor.Core.Scanning;

namespace PcDoctor.App.Pages;

public sealed record StatTile(string LabelKey, int Value, string BrushKey)
{
    public string Label => Loc.Get(LabelKey);
}

/// <summary>One card per module on the overview: name, counts, and its most severe finding.</summary>
public sealed class ModuleCard(ModuleResult module)
{
    private readonly ModuleResult m = module;

    public ModuleResult Module => m;
    public string Name => Loc.Resolve(m.ModuleName);
    public int FindingCount => m.Findings.Count(f => !f.HiddenByDefault);
    public int CheckCount => m.Checks.Count(c => c.Status is not (CheckStatus.NotChecked or CheckStatus.NotAvailable));
    public int NotCheckedCount => m.Checks.Count(c => c.Status is CheckStatus.NotChecked or CheckStatus.NotAvailable);
    public Severity? Worst => m.Findings.Where(f => !f.HiddenByDefault).Select(f => (Severity?)f.Severity).Max();
    public string WorstKey => Worst is { } s ? "Severity." + s : "Good";
    public string Headline => m.Findings.Where(f => !f.HiddenByDefault).OrderByDescending(f => f.Severity).FirstOrDefault() is { } f
        ? Loc.Resolve(f.Title)
        : Loc.Get("overview.module.nothing");
    public string Counts => Loc.Format("overview.module.counts", FindingCount, CheckCount, NotCheckedCount);
}

public sealed partial class OverviewViewModel : PageViewModel
{
    public OverviewViewModel(AppServices services) : base(services)
    {
        services.PropertyChanged += OnServicesChanged;
        Rebuild();
    }

    public override string Key => "overview";
    public override string Icon => "";

    public ObservableCollection<StatTile> Stats { get; } = [];
    public ObservableCollection<ModuleCard> Modules { get; } = [];
    public ObservableCollection<string> Summary { get; } = [];

    public bool HasReport => Services.Report is not null;
    public bool IsScanning => Services.IsScanning;
    public double Progress => Services.Progress;
    public string Status => Services.Status;
    public string LastScan => Services.Report is { } r
        ? Loc.Format("overview.lastScan", r.FinishedUtc.ToLocalTime().ToString("yyyy-MM-dd HH:mm"), Loc.Get("scanMode." + r.Conditions.Mode))
        : Loc.Get("overview.neverScanned");

    private void OnServicesChanged(object? sender, PropertyChangedEventArgs e)
    {
        switch (e.PropertyName)
        {
            case nameof(AppServices.Report):
                Rebuild();
                break;
            case nameof(AppServices.IsScanning):
                OnPropertyChanged(nameof(IsScanning));
                HealthCheckCommand.NotifyCanExecuteChanged();
                DeepScanCommand.NotifyCanExecuteChanged();
                CancelCommand.NotifyCanExecuteChanged();
                break;
            case nameof(AppServices.Progress):
                OnPropertyChanged(nameof(Progress));
                break;
            case nameof(AppServices.Status):
                OnPropertyChanged(nameof(Status));
                break;
        }
    }

    protected override void OnTextsChanged() => Rebuild();

    private void Rebuild()
    {
        Stats.Clear();
        Modules.Clear();
        Summary.Clear();
        var r = Services.Report;
        if (r is null)
        {
            Summary.Add(Loc.Get("dashboard.intro"));
        }
        else
        {
            var visible = r.AllFindings.Where(f => !f.HiddenByDefault).ToList();
            Stats.Add(new StatTile("overview.stat.critical", visible.Count(f => f.Severity == Severity.Critical), "Severity.Critical"));
            Stats.Add(new StatTile("overview.stat.high", visible.Count(f => f.Severity == Severity.High), "Severity.High"));
            Stats.Add(new StatTile("overview.stat.medium", visible.Count(f => f.Severity == Severity.Medium), "Severity.Medium"));
            Stats.Add(new StatTile("overview.stat.low", visible.Count(f => f.Severity is Severity.Low or Severity.Info), "Accent2"));
            Stats.Add(new StatTile("overview.stat.checked",
                r.AllChecks.Count(c => c.Status is not (CheckStatus.NotChecked or CheckStatus.NotAvailable)), "Good"));
            Stats.Add(new StatTile("overview.stat.notChecked",
                r.AllChecks.Count(c => c.Status is CheckStatus.NotChecked or CheckStatus.NotAvailable), "Muted"));
            foreach (var m in r.Modules)
            {
                Modules.Add(new ModuleCard(m));
            }
            foreach (var line in ReportSummary.Build(r))
            {
                Summary.Add(Loc.Resolve(line));
            }
        }
        OnPropertyChanged(nameof(HasReport));
        OnPropertyChanged(nameof(LastScan));
    }

    private bool CanScan() => !Services.IsScanning;

    [RelayCommand(CanExecute = nameof(CanScan))]
    private Task HealthCheck() => Services.RunScanAsync(ScanMode.HealthCheck);

    [RelayCommand(CanExecute = nameof(CanScan))]
    private Task DeepScan() => Services.RunScanAsync(ScanMode.DeepScan);

    private bool CanCancel() => Services.IsScanning;

    [RelayCommand(CanExecute = nameof(CanCancel))]
    private void Cancel() => Services.CancelScan();

    [RelayCommand]
    private void OpenModule(ModuleCard? card)
    {
        if (card is not null)
        {
            Services.Navigate("findings:" + card.Module.ModuleId);
        }
    }
}
