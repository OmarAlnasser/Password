using System.Collections.ObjectModel;
using System.IO;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PcDoctor.App.Services;
using PcDoctor.App.ViewModels;
using PcDoctor.App.Views;
using PcDoctor.Core.Ipc;
using PcDoctor.Core.Journal;
using PcDoctor.Core.Localization;

namespace PcDoctor.App.Pages;

/// <summary>The change journal: every change PC Doctor made, with undo per entry, per batch, or everything.</summary>
public sealed partial class ChangesViewModel(AppServices services) : PageViewModel(services)
{
    public override string Key => "changes";
    public override string Icon => "";

    public ObservableCollection<JournalItemViewModel> Entries { get; } = [];

    [ObservableProperty] private string _status = "";

    public bool IsEmpty => Entries.Count == 0;

    public override void OnShown() => Load();

    [RelayCommand]
    private void Load()
    {
        Entries.Clear();
        try
        {
            foreach (var e in new ChangeJournal(AppModules.JournalPath).ReadCurrent().Reverse())
            {
                Entries.Add(new JournalItemViewModel(e));
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            Status = Loc.Get("status.journalUnreadable");
        }
        OnPropertyChanged(nameof(IsEmpty));
    }

    protected override void OnTextsChanged()
    {
        foreach (var e in Entries)
        {
            e.Refresh();
        }
    }

    [RelayCommand]
    private Task UndoEntry(JournalItemViewModel? item) =>
        item is null ? Task.CompletedTask : Undo(new UndoRequest(UndoScope.Entry, item.Entry.Id, Force: false));

    [RelayCommand]
    private Task UndoBatch(JournalItemViewModel? item) =>
        item is null ? Task.CompletedTask : Undo(new UndoRequest(UndoScope.Batch, item.Entry.BatchId, Force: false));

    [RelayCommand]
    private Task UndoEverything() =>
        ConsentDialog.Ask(Loc.Get("journal.undoAll"), Loc.Get("journal.undoAll.confirm"), Loc.Get("journal.undoAll.button"))
            ? Undo(new UndoRequest(UndoScope.Everything, null, Force: false))
            : Task.CompletedTask;

    private async Task Undo(UndoRequest request)
    {
        if (!await Services.Broker.EnsureStartedAsync(CancellationToken.None))
        {
            Status = Loc.Get("status.brokerDeclined");
            return;
        }
        var response = await Services.Broker.SendAsync(request, CancellationToken.None);
        var result = response.PayloadAs<UndoResult>();
        Status = result is null
            ? Loc.Format("status.fixFailed", response.Error, response.ErrorDetail ?? "")
            : Loc.Format("status.undone", result.Undone, result.Conflicts, result.Failed);
        Load();
    }
}
