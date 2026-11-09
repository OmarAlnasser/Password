using System.Collections.ObjectModel;
using System.ComponentModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PcDoctor.App.Services;
using PcDoctor.App.ViewModels;
using PcDoctor.Core.Findings;
using PcDoctor.Core.Localization;
using PcDoctor.Core.Scanning;

namespace PcDoctor.App.Pages;

public sealed class TimelineItem(TimelineEntry entry)
{
    public TimelineEntry Entry { get; } = entry;
    public Severity Severity => Entry.Severity;
    public string Tag => Entry.Tag ?? "";
    public string Day => Entry.Time.ToLocalTime().ToString("yyyy-MM-dd");
    public string Time => Entry.Time.ToLocalTime().ToString("HH:mm");
    public string Title => Loc.Resolve(Entry.Title);
    public string Detail => Entry.Detail is null ? "" : Loc.Resolve(Entry.Detail);
    public bool HasDetail => Entry.Detail is not null;
}

/// <summary>Crash timeline (M5): blue screens, freezes, power losses and hardware errors, newest first.</summary>
public sealed partial class CrashesViewModel : PageViewModel
{
    public CrashesViewModel(AppServices services) : base(services)
    {
        _filter = Filters[0];
        services.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(AppServices.Report))
            {
                Load();
            }
            else if (e.PropertyName == nameof(AppServices.IsScanning))
            {
                DeepScanCommand.NotifyCanExecuteChanged();
            }
        };
        Load();
    }

    public override string Key => "crashes";
    public override string Icon => "";

    public IReadOnlyList<Choice<string?>> Filters { get; } =
    [
        new(null, "crashes.filter.all"),
        new("bsod", "crashes.filter.bsod"),
        new("freeze", "crashes.filter.freeze"),
        new("hardware", "crashes.filter.hardware"),
        new("gpu", "crashes.filter.gpu"),
    ];

    public ObservableCollection<TimelineItem> Items { get; } = [];
    public ObservableCollection<FindingItemViewModel> Verdicts { get; } = [];

    [ObservableProperty] private Choice<string?> _filter;

    public bool HasData => Items.Count > 0;
    public bool HasReport => Services.Report is not null;
    public bool NeedsDeepScan => Services.Report?.Modules.FirstOrDefault(m => m.ModuleId == "M5")?.Checks
        .Any(c => c.Id == "M5.dumpAnalysis" && c.Status == CheckStatus.NotChecked) == true;

    partial void OnFilterChanged(Choice<string?> value) => Load();

    protected override void OnTextsChanged() => Load();

    private void Load()
    {
        Items.Clear();
        Verdicts.Clear();
        var m5 = Services.Report?.Modules.FirstOrDefault(m => m.ModuleId == "M5");
        if (m5 is not null)
        {
            foreach (var t in m5.Timeline.Where(t => Filter.Value switch
                     {
                         null => true,
                         "freeze" => t.Tag is "forced" or "power",
                         "hardware" => t.Tag is "hardware" or "disk" or "dump",
                         var tag => t.Tag == tag,
                     }))
            {
                Items.Add(new TimelineItem(t));
            }
            foreach (var f in m5.Findings.Where(f => f.Id.StartsWith("M5.culprit.", StringComparison.Ordinal) ||
                                                     f.Id.StartsWith("M5.bsod.", StringComparison.Ordinal) ||
                                                     f.Id == "M5.needDebugger"))
            {
                Verdicts.Add(new FindingItemViewModel(f, m5.ModuleName));
            }
        }
        OnPropertyChanged(nameof(HasData));
        OnPropertyChanged(nameof(HasReport));
        OnPropertyChanged(nameof(NeedsDeepScan));
    }

    [RelayCommand(CanExecute = nameof(CanScan))]
    private Task DeepScan() => Services.RunScanAsync(ScanMode.DeepScan);

    private bool CanScan() => !Services.IsScanning;

    [RelayCommand]
    private void OpenFinding(FindingItemViewModel? item)
    {
        if (item is not null)
        {
            Services.Navigate("findings:M5");
        }
    }
}
