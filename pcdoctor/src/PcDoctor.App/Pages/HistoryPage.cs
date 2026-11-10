using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PcDoctor.App.Services;
using PcDoctor.App.ViewModels;
using PcDoctor.Core.Localization;
using PcDoctor.Core.Reporting;

namespace PcDoctor.App.Pages;

public sealed record HistoryEntry(ScanReport Report)
{
    public string Label => $"{Report.FinishedUtc.ToLocalTime().ToString("yyyy-MM-dd HH:mm", System.Globalization.CultureInfo.InvariantCulture)} · {Loc.Get("scanMode." + Report.Conditions.Mode)} · {Report.AllFindings.Count(f => !f.HiddenByDefault)}";
}

/// <summary>Compare any two past scans: what is new, what is gone, what is still there; and schedule quiet scans.</summary>
public sealed partial class HistoryViewModel(AppServices services) : PageViewModel(services)
{
    public override string Key => "history";
    public override string Icon => "";

    public ObservableCollection<HistoryEntry> Entries { get; } = [];
    public ObservableCollection<FindingItemViewModel> New { get; } = [];
    public ObservableCollection<FindingItemViewModel> Resolved { get; } = [];
    public ObservableCollection<FindingItemViewModel> Persisting { get; } = [];

    public IReadOnlyList<Choice<ScheduleFrequency>> Frequencies { get; } =
        [new(ScheduleFrequency.Off, "history.schedule.off"), new(ScheduleFrequency.Daily, "history.schedule.daily"), new(ScheduleFrequency.Weekly, "history.schedule.weekly")];

    [ObservableProperty] private HistoryEntry? _older;
    [ObservableProperty] private HistoryEntry? _newer;
    [ObservableProperty] private string _summary = "";
    [ObservableProperty] private Choice<ScheduleFrequency>? _frequency;
    [ObservableProperty] private string _status = "";

    partial void OnOlderChanged(HistoryEntry? value) => Compare();
    partial void OnNewerChanged(HistoryEntry? value) => Compare();

    partial void OnFrequencyChanged(Choice<ScheduleFrequency>? value)
    {
        if (value is null || value.Value == Services.Settings.ScheduledScan)
        {
            return;
        }
        try
        {
            Scheduler.Apply(value.Value, TimeSpan.FromHours(12.5));
            Services.UpdateSettings(s => s with { ScheduledScan = value.Value });
            Status = Loc.Get(value.Value == ScheduleFrequency.Off ? "history.schedule.removed" : "history.schedule.saved");
        }
        catch (Exception ex) when (ex is System.Runtime.InteropServices.COMException or InvalidOperationException or UnauthorizedAccessException)
        {
            Status = Loc.Format("status.fixFailed", "", ex.Message);
        }
    }

    public override void OnShown()
    {
        Entries.Clear();
        foreach (var r in History.Load())
        {
            Entries.Add(new HistoryEntry(r));
        }
        Newer = Entries.ElementAtOrDefault(0);
        Older = Entries.ElementAtOrDefault(1);
        Frequency = Frequencies.First(f => f.Value == Services.Settings.ScheduledScan);
    }

    private void Compare()
    {
        New.Clear();
        Resolved.Clear();
        Persisting.Clear();
        if (Older is null || Newer is null || ReferenceEquals(Older, Newer))
        {
            Summary = Loc.Get(Entries.Count < 2 ? "history.needTwo" : "history.pick");
            return;
        }
        var d = ReportDiff.Compare(Older.Report, Newer.Report);
        foreach (var f in d.New)
        {
            New.Add(new FindingItemViewModel(f, new Core.Findings.Text("m" + f.Module[1..] + ".name")));
        }
        foreach (var f in d.Resolved)
        {
            Resolved.Add(new FindingItemViewModel(f, new Core.Findings.Text("m" + f.Module[1..] + ".name")));
        }
        foreach (var f in d.Persisting)
        {
            Persisting.Add(new FindingItemViewModel(f, new Core.Findings.Text("m" + f.Module[1..] + ".name")));
        }
        Summary = Loc.Format("history.summary", d.New.Count, d.Resolved.Count, d.Persisting.Count, d.CheckedBefore, d.CheckedAfter);
    }

    protected override void OnTextsChanged() => Compare();

    [RelayCommand]
    private void Open() => Services.Navigate("findings");
}
