using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Windows.Data;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PcDoctor.App.Services;
using PcDoctor.App.ViewModels;
using PcDoctor.App.Views;
using PcDoctor.Core.Ipc;
using PcDoctor.Core.Localization;
using PcDoctor.Core.Platform;
using PcDoctor.Modules.Persistence;

namespace PcDoctor.App.Pages;

public sealed class AutorunItem(AutorunEntry e)
{
    public AutorunEntry Entry => e;
    public string Category => Loc.Get("m3.cat." + e.Category);
    public string Name => e.Name;
    public string Image => e.Image ?? e.Command;
    public string Publisher => SignatureVerifier.DisplayPublisher(e.Signature?.Publisher);
    public string SignatureText => Loc.Get("m3.sig." + (e.Signature?.Status.ToString() ?? "None"));
    public string SignatureKey => e.Signature?.Status switch
    {
        SignatureStatus.MicrosoftSigned or SignatureStatus.Signed => "Good",
        SignatureStatus.Invalid => "Severity.High",
        SignatureStatus.Unsigned => "Severity.Medium",
        _ => "Muted",
    };
    public bool CanDisable => DisablePlanner.CanDisable(e);
    public bool IsDisabled => !e.Enabled;
}

/// <summary>M3 as a browsable list, like Autoruns: Microsoft-signed entries hidden by default; disable, never delete.</summary>
public sealed partial class StartupViewModel : PageViewModel
{
    public StartupViewModel(AppServices services) : base(services)
    {
        View = CollectionViewSource.GetDefaultView(Items);
        View.GroupDescriptions.Add(new PropertyGroupDescription(nameof(AutorunItem.Category)));
        View.Filter = o => o is AutorunItem i && (!HideMicrosoft || !i.Entry.IsMicrosoft) &&
                           (string.IsNullOrWhiteSpace(Search) || i.Name.Contains(Search, StringComparison.OrdinalIgnoreCase) ||
                            i.Image.Contains(Search, StringComparison.OrdinalIgnoreCase) || i.Publisher.Contains(Search, StringComparison.OrdinalIgnoreCase));
    }

    public override string Key => "startup";
    public override string Icon => "";

    public ObservableCollection<AutorunItem> Items { get; } = [];
    public ICollectionView View { get; }

    [ObservableProperty] private bool _hideMicrosoft = true;
    [ObservableProperty] private string _search = "";
    [ObservableProperty] private bool _isLoading;
    [ObservableProperty] private string _status = "";

    partial void OnHideMicrosoftChanged(bool value) => View.Refresh();
    partial void OnSearchChanged(string value) => View.Refresh();

    public override void OnShown()
    {
        if (Items.Count == 0 && !IsLoading)
        {
            _ = Load();
        }
    }

    protected override void OnTextsChanged() => View.Refresh();

    [RelayCommand]
    private async Task Load()
    {
        IsLoading = true;
        Status = Loc.Get("startup.loading");
        try
        {
            var snapshot = await Task.Run(() => PersistenceReader.Read());
            Items.Clear();
            foreach (var e in snapshot.Entries.OrderBy(e => e.Category).ThenBy(e => e.Name))
            {
                Items.Add(new AutorunItem(e));
            }
            Status = Loc.Format("startup.counts", snapshot.Entries.Count, snapshot.Entries.Count(e => e.IsMicrosoft), snapshot.Unread.Count);
        }
        finally
        {
            IsLoading = false;
        }
    }

    [RelayCommand]
    private async Task Disable(AutorunItem? item)
    {
        if (item is null || !item.CanDisable)
        {
            return;
        }
        var plan = DisablePlanner.Plan(item.Entry, @"%ProgramData%\PCDoctor\DisabledAutoruns") ?? [];
        var body = Loc.Format("startup.disable.consent", item.Name) + "\n\n" + Loc.Get("fix.preview.changes") + "\n" +
                   string.Join("\n", plan.Select(c => "  ⁦" + c.Describe() + "⁩")) + "\n\n" + Loc.Get("fix.preview.restorePoint");
        if (!ConsentDialog.Ask(Loc.Get("startup.disable.title"), body, Loc.Get("startup.disable.button")))
        {
            return;
        }
        if (!await Services.Broker.EnsureStartedAsync(CancellationToken.None))
        {
            Status = Loc.Get("status.brokerDeclined");
            return;
        }
        var r = await Services.Broker.SendAsync(new AutorunDisableRequest(item.Entry.Id), CancellationToken.None);
        Status = r.Ok ? Loc.Get("status.fixApplied") : Loc.Format("status.fixFailed", r.Error, r.ErrorDetail ?? "");
        await Load();
    }
}
