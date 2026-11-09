using CommunityToolkit.Mvvm.ComponentModel;
using PcDoctor.Core.Findings;
using PcDoctor.Core.Journal;
using PcDoctor.Core.Localization;
using PcDoctor.Core.Reporting;

namespace PcDoctor.App.ViewModels;

/// <summary>A finding with its text resolved for the current language. <see cref="Refresh"/> re-resolves it.</summary>
public sealed partial class FindingItemViewModel(Finding finding, Text moduleName) : ObservableObject
{
    public Finding Finding { get; } = finding;
    public Severity Severity => Finding.Severity;
    public IReadOnlyList<Evidence> Evidence => Finding.Evidence;
    public bool HasFix => Finding.FixId is not null;

    public string ModuleName => Loc.Resolve(moduleName);
    public string Title => Loc.Resolve(Finding.Title);
    public string Why => Loc.Resolve(Finding.WhyItMatters);
    public string Action => Loc.Resolve(Finding.SuggestedAction);
    public string Undo => ReportExporter.UndoText(Finding.Undo, Loc.Culture);
    public string Badges =>
        $"{Loc.Get("severity." + Finding.Severity)} · {Loc.Get("confidence." + Finding.Confidence)} · {Loc.Get("source." + Finding.Source)}";

    public void Refresh() => OnPropertyChanged(string.Empty);
}

public sealed partial class CheckItemViewModel(CheckResult check, Text moduleName) : ObservableObject
{
    public CheckStatus Status => check.Status;
    public string ModuleName => Loc.Resolve(moduleName);
    public string StatusText => Loc.Get("check.status." + check.Status);
    public string Title => Loc.Resolve(check.Title);
    public string Detail => check.Detail is null ? "" : Loc.Resolve(check.Detail);

    public void Refresh() => OnPropertyChanged(string.Empty);
}

public sealed partial class JournalItemViewModel(JournalEntry entry) : ObservableObject
{
    public JournalEntry Entry { get; } = entry;
    public string When => Entry.TimestampUtc.ToLocalTime().ToString("yyyy-MM-dd HH:mm");
    public string Source => Entry.SourceId;
    public string StateText => Loc.Get("journal.state." + Entry.State);
    public bool CanUndo => Entry.State is EntryState.Applied or EntryState.UndoConflict;

    /// <summary>The exact change, for the LTR evidence column.</summary>
    public string Change => Entry.Change switch
    {
        RegistryChange r => $@"{r.Hive}\{r.Key}\{r.ValueName}: {(r.Existed ? r.OldData?.Encoded : "(absent)")} → {r.NewData?.Encoded ?? "(deleted)"}",
        ServiceChange s => $"{s.Service}: {s.OldStartType} → {s.NewStartType}",
        TaskChange t => $"{t.TaskPath}: {(t.OldEnabled ? "enabled" : "disabled")} → {(t.NewEnabled ? "enabled" : "disabled")}",
        AppxChange a => $"{a.PackageFullName} removed (reinstall: {a.WingetOrStoreId ?? "?"})",
        _ => Entry.Change.ToString(),
    };

    public void Refresh() => OnPropertyChanged(string.Empty);
}
