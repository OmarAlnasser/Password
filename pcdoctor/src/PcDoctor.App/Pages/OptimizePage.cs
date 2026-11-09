using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using System.Windows.Data;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PcDoctor.App.Services;
using PcDoctor.App.ViewModels;
using PcDoctor.App.Views;
using PcDoctor.Core.Ipc;
using PcDoctor.Core.Journal;
using PcDoctor.Core.Localization;
using PcDoctor.Core.Platform;
using PcDoctor.Tweaks;

namespace PcDoctor.App.Pages;

public sealed partial class TweakItem(Tweak tweak, TweakState state, Action<TweakItem, bool> onToggle) : ObservableObject
{
    public Tweak Tweak => tweak;
    public TweakState State { get; set; } = state;
    public string Tier => Loc.Get("tweak.tier." + tweak.Tier);
    public string Title => Loc.Get($"tweak.{tweak.Id}.title");
    public string Why => Loc.Get($"tweak.{tweak.Id}.why");
    public string Warning => tweak.HasWarning ? Loc.Get($"tweak.{tweak.Id}.warning") : "";
    public bool HasWarning => tweak.HasWarning;
    public string StateText => Loc.Get("tweak.state." + State);
    public string StateKey => State switch { TweakState.Applied => "Good", TweakState.Partial => "Warn", TweakState.NotApplicable => "Muted", _ => "Soft" };
    public bool Applicable => State != TweakState.NotApplicable;
    public bool IsManaged => tweak.LocksSetting && State == TweakState.Applied;
    public string Notes => string.Join(" · ", new[]
    {
        tweak.RequiresRestart ? Loc.Get("tweak.note.restart") : null,
        tweak.SignOut ? Loc.Get("tweak.note.signOut") : null,
        tweak.ExplorerRestart ? Loc.Get("tweak.note.explorer") : null,
        tweak.LocksSetting ? Loc.Get("tweak.note.policy") : null,
    }.Where(n => n is not null));

    [ObservableProperty] private bool _isSelected;

    partial void OnIsSelectedChanged(bool value) => onToggle(this, value);

    public void Refresh() => OnPropertyChanged(string.Empty);
}

/// <summary>M13: a tiered, reversible tweak catalog. Detect first, preview exactly, journal everything.</summary>
public sealed partial class OptimizeViewModel : PageViewModel
{
    private readonly TweakCatalog _catalog = TweakCatalog.Load();
    private bool _suppressToggle;

    public OptimizeViewModel(AppServices services) : base(services)
    {
        View = CollectionViewSource.GetDefaultView(Items);
        View.GroupDescriptions.Add(new PropertyGroupDescription(nameof(TweakItem.Tier)));
    }

    public override string Key => "optimize";
    public override string Icon => "";

    public ObservableCollection<TweakItem> Items { get; } = [];
    public ICollectionView View { get; }

    [ObservableProperty] [NotifyCanExecuteChangedFor(nameof(ApplySelectedCommand), nameof(RecommendedCommand), nameof(LimitedCommand), nameof(ClearCommand),
        nameof(ReapplyCommand))]
    private bool _isBusy;

    [ObservableProperty] private string _status = "";
    [ObservableProperty] private string _drift = "";
    [ObservableProperty] private bool _hasDrift;

    private IReadOnlyList<string> _drifted = [];

    public int SelectedCount => Items.Count(i => i.IsSelected);

    private static string ManifestPath => Path.Combine(AppModules.ProgramDataFolder, "tweaks-applied.json");

    private static OsInfo Os()
    {
        using var cv = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion");
        return new OsInfo(int.TryParse(cv?.GetValue("CurrentBuildNumber") as string, out var b) ? b : 0, cv?.GetValue("EditionID") as string ?? "", false);
    }

    private static string OsVersion()
    {
        using var cv = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion");
        return $"{cv?.GetValue("CurrentBuildNumber")}.{cv?.GetValue("UBR")} {cv?.GetValue("DisplayVersion")}";
    }

    private static DetectContext Context() => new(new WindowsRegistryAccess(), new WindowsServiceConfigAccess(), new WindowsTaskSchedulerAccess(),
        new Platform.Appx.WindowsAppxAccess(false), $@"HKU\{WindowsIdentity.GetCurrent().User!.Value}");

    public override void OnShown() => _ = Detect();

    [RelayCommand]
    private async Task Detect()
    {
        IsBusy = true;
        Status = Loc.Get("tweak.detecting");
        try
        {
            var os = Os();
            var states = await Task.Run(() => _catalog.Tweaks.Select(t => (t, TweakEngine.Detect(t, os, Context()))).ToList());
            _suppressToggle = true;
            Items.Clear();
            foreach (var (t, s) in states)
            {
                Items.Add(new TweakItem(t, s, OnToggle));
            }
            _suppressToggle = false;
            CheckDrift(states.ToDictionary(x => x.t.Id, x => x.Item2));
            Status = Loc.Format("tweak.detected", states.Count(s => s.Item2 == TweakState.Applied), states.Count(s => s.Item2 != TweakState.NotApplicable));
        }
        finally
        {
            IsBusy = false;
            OnPropertyChanged(nameof(SelectedCount));
        }
    }

    private void CheckDrift(Dictionary<string, TweakState> states)
    {
        _drifted = [];
        try
        {
            if (File.Exists(ManifestPath) && JsonSerializer.Deserialize<AppliedManifest>(File.ReadAllText(ManifestPath), TweakCatalog.Json) is { } m)
            {
                _drifted = m.Drifted(OsVersion(), id => states.GetValueOrDefault(id, TweakState.Unknown));
            }
        }
        catch (Exception ex) when (ex is JsonException or IOException or UnauthorizedAccessException)
        {
        }
        HasDrift = _drifted.Count > 0;
        Drift = HasDrift ? Loc.Format("tweak.drift", _drifted.Count) : "";
        ReapplyCommand.NotifyCanExecuteChanged();
    }

    private void OnToggle(TweakItem item, bool selected)
    {
        if (_suppressToggle)
        {
            return;
        }
        // Advanced items are confirmed one by one, with their tradeoff.
        if (selected && item.Tweak.Tier == Tier.Advanced &&
            !ConsentDialog.Ask(item.Title, item.Warning + "\n\n" + item.Why, Loc.Get("tweak.advanced.include"), danger: true))
        {
            _suppressToggle = true;
            item.IsSelected = false;
            _suppressToggle = false;
        }
        OnPropertyChanged(nameof(SelectedCount));
        ApplySelectedCommand.NotifyCanExecuteChanged();
    }

    private bool CanAct() => !IsBusy;
    private bool CanApply() => !IsBusy && Items.Any(i => i.IsSelected);
    private bool CanReapply() => !IsBusy && _drifted.Count > 0;

    [RelayCommand(CanExecute = nameof(CanAct))]
    private Task Recommended() => ApplyPreset("recommended");

    [RelayCommand(CanExecute = nameof(CanAct))]
    private Task Limited() => ApplyPreset("limited");

    private Task ApplyPreset(string preset)
    {
        var ids = TweakEngine.Preset(_catalog, preset, Os()).Select(t => t.Id).ToHashSet();
        _suppressToggle = true;
        foreach (var i in Items)
        {
            i.IsSelected = ids.Contains(i.Tweak.Id) && i.State != TweakState.Applied;
        }
        _suppressToggle = false;
        OnPropertyChanged(nameof(SelectedCount));
        return Apply(Items.Where(i => i.IsSelected).Select(i => i.Tweak.Id).ToList());
    }

    [RelayCommand(CanExecute = nameof(CanApply))]
    private Task ApplySelected() => Apply(Items.Where(i => i.IsSelected).Select(i => i.Tweak.Id).ToList());

    [RelayCommand(CanExecute = nameof(CanReapply))]
    private Task Reapply() => Apply(_drifted.ToList());

    [RelayCommand]
    private void MeasureFirst() => Services.Navigate("performance");

    private async Task Apply(IReadOnlyList<string> ids)
    {
        if (ids.Count == 0)
        {
            Status = Loc.Get("tweak.nothing");
            return;
        }
        var plan = await Task.Run(() => TweakEngine.Plan(_catalog, ids, Os(), Context()));
        if (plan is null)
        {
            Status = Loc.Get("tweak.refused");
            return;
        }
        var tweaks = ids.Select(_catalog.Find).OfType<Tweak>().ToList();
        var body = new StringBuilder()
            .AppendLine(Loc.Format("tweak.preview.intro", tweaks.Count)).AppendLine();
        foreach (var t in tweaks)
        {
            body.AppendLine("• " + Loc.Get($"tweak.{t.Id}.title"));
        }
        body.AppendLine().AppendLine(Loc.Get("fix.preview.changes"));
        foreach (var c in plan)
        {
            body.AppendLine("  ⁦" + c.Describe() + "⁩");
        }
        body.AppendLine().AppendLine(Loc.Get("fix.preview.restorePoint"));
        if (plan.OfType<PlannedAppxRemove>().Any())
        {
            body.AppendLine(Loc.Get("tweak.preview.apps"));
        }
        if (tweaks.Any(t => t.RequiresRestart))
        {
            body.AppendLine(Loc.Get("fix.preview.restart"));
        }
        if (!ConsentDialog.Ask(Loc.Get("tweak.preview.title"), body.ToString(), Loc.Get("action.applyFix.confirm")))
        {
            return;
        }
        if (!await Services.Broker.EnsureStartedAsync(CancellationToken.None))
        {
            Status = Loc.Get("status.brokerDeclined");
            return;
        }
        IsBusy = true;
        try
        {
            var r = await Services.Broker.SendAsync(new TweakApplyRequest(ids), CancellationToken.None);
            Status = r.Ok ? Loc.Get("tweak.applied") : Loc.Format("status.fixFailed", r.Error, r.ErrorDetail ?? "");
        }
        finally
        {
            IsBusy = false;
        }
        await Detect();
    }

    /// <summary>"Clear": undo every tweak batch PC Doctor applied, newest first, from the journal.</summary>
    [RelayCommand(CanExecute = nameof(CanAct))]
    private async Task Clear()
    {
        if (!ConsentDialog.Ask(Loc.Get("tweak.clear.title"), Loc.Get("tweak.clear.consent"), Loc.Get("tweak.clear.button")))
        {
            return;
        }
        if (!await Services.Broker.EnsureStartedAsync(CancellationToken.None))
        {
            Status = Loc.Get("status.brokerDeclined");
            return;
        }
        IsBusy = true;
        try
        {
            var batches = new ChangeJournal(AppModules.JournalPath).ReadCurrent()
                .Where(e => e.SourceId.StartsWith("tweaks:", StringComparison.Ordinal) && e.State is EntryState.Applied or EntryState.UndoConflict)
                .OrderByDescending(e => e.TimestampUtc).Select(e => e.BatchId).Distinct().ToList();
            int undone = 0, conflicts = 0, failed = 0;
            foreach (var b in batches)
            {
                var r = (await Services.Broker.SendAsync(new UndoRequest(UndoScope.Batch, b, false), CancellationToken.None)).PayloadAs<UndoResult>();
                undone += r?.Undone ?? 0;
                conflicts += r?.Conflicts ?? 0;
                failed += r?.Failed ?? 0;
            }
            Status = Loc.Format("status.undone", undone, conflicts, failed) + (failed > 0 ? " " + Loc.Get("tweak.clear.apps") : "");
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            Status = Loc.Get("status.journalUnreadable");
        }
        finally
        {
            IsBusy = false;
        }
        await Detect();
    }

    protected override void OnTextsChanged()
    {
        foreach (var i in Items)
        {
            i.Refresh();
        }
        View.Refresh();
    }
}
