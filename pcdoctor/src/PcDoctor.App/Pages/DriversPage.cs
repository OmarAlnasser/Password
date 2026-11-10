using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Globalization;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PcDoctor.App.Services;
using PcDoctor.App.ViewModels;
using PcDoctor.App.Views;
using PcDoctor.Core.Localization;
using PcDoctor.Modules.Drivers;

namespace PcDoctor.App.Pages;

public sealed record DriverRow(AdvisedDriver Driver)
{
    public string Device => Driver.Device;
    public string Detail => Loc.Format("drivers.row.detail", Driver.Provider, Driver.Version ?? "?",
        Driver.Date?.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) ?? "?");
    public string Age => Driver.AgeYears(DateTimeOffset.UtcNow) is { } y && y >= 1 ? Loc.Format("drivers.row.age", y) : "";
    public bool HasOfficial => Driver.OfficialUrl is not null;
}

/// <summary>
/// Driver advisor. It only reads and advises: it never downloads or installs a driver. It asks once whether the user has
/// an AI key; with no key it sticks to official sources (Windows Update and the makers' own sites).
/// </summary>
public sealed partial class DriversViewModel(AppServices services) : PageViewModel(services)
{
    public override string Key => "drivers";
    public override string Icon => "";

    public ObservableCollection<DriverRow> Rows { get; } = [];

    [ObservableProperty] private bool _showQuestion;
    [ObservableProperty] private bool _aiMode;
    [ObservableProperty] private bool _hasKey;
    [ObservableProperty] private bool _isBusy;
    [ObservableProperty] private bool _isEmpty;
    [ObservableProperty] private string _status = "";
    [ObservableProperty] private string _advice = "";
    [ObservableProperty] private bool _hasAdvice;

    private bool _loaded;
    private CancellationTokenSource? _asking;

    private bool UsesClaudeCode => Services.Settings.DriverAdvice == DriverAdviceMode.ClaudeCode;

    public string ModeText => Loc.Get(UsesClaudeCode ? "drivers.mode.claudeCode" : AiMode ? "drivers.mode.ai" : "drivers.mode.official");

    public override void OnShown()
    {
        ShowQuestion = Services.Settings.DriverAdvice == DriverAdviceMode.NotAsked;
        HasKey = Services.Settings.DriverAdvice == DriverAdviceMode.Ai && Services.Settings.DriverAiKeyProtected is not null;
        AiMode = HasKey || UsesClaudeCode;
        OnPropertyChanged(nameof(ModeText));
        if (!_loaded)
        {
            _loaded = true;
            _ = Load();
        }
    }

    public override void OnHidden()
    {
        // Leaving the page stops a question in progress; nothing keeps running behind the page.
        _asking?.Cancel();
    }

    private async Task Load()
    {
        IsBusy = true;
        try
        {
            var drivers = OperatingSystem.IsWindows()
                ? await Task.Run(() => DriverAdvice.Select(DriversReader.Read().Drivers))
                : [];
            Rows.Clear();
            foreach (var d in drivers)
            {
                Rows.Add(new DriverRow(d));
            }
        }
        catch (Exception ex) when (ex is System.Management.ManagementException or System.Runtime.InteropServices.COMException or UnauthorizedAccessException or InvalidOperationException)
        {
            Status = Loc.Get("drivers.unreadable");
        }
        finally
        {
            IsBusy = false;
            IsEmpty = Rows.Count == 0;
        }
    }

    /// <summary>Called from the view with the password box content. The key is encrypted with DPAPI and never shown again.</summary>
    public void SaveKey(string key)
    {
        if (string.IsNullOrWhiteSpace(key))
        {
            Status = Loc.Get("drivers.key.empty");
            return;
        }
        Services.UpdateSettings(s => s with { DriverAdvice = DriverAdviceMode.Ai, DriverAiKeyProtected = AppSettings.ProtectKey(key) });
        ShowQuestion = false;
        AiMode = true;
        HasKey = true;
        Status = Loc.Get("drivers.key.saved");
        OnPropertyChanged(nameof(ModeText));
    }

    /// <summary>No key: use Claude Code that is already installed and signed in on this PC.</summary>
    [RelayCommand]
    private void UseClaudeCode()
    {
        if (ClaudeCodeCli.Find() is null)
        {
            Status = Loc.Get("drivers.cc.notFound");
            return;
        }
        Services.UpdateSettings(s => s with { DriverAdvice = DriverAdviceMode.ClaudeCode });
        ShowQuestion = false;
        AiMode = true;
        HasKey = false;
        Status = Loc.Get("drivers.cc.saved");
        OnPropertyChanged(nameof(ModeText));
    }

    [RelayCommand]
    private void Skip()
    {
        Services.UpdateSettings(s => s with { DriverAdvice = DriverAdviceMode.OfficialOnly });
        ShowQuestion = false;
        AiMode = false;
        HasKey = false;
        Status = Loc.Get("drivers.skip.saved");
        OnPropertyChanged(nameof(ModeText));
    }

    [RelayCommand]
    private void ChangeChoice() => ShowQuestion = true;

    [RelayCommand]
    private void RemoveKey()
    {
        _asking?.Cancel();
        Services.UpdateSettings(s => s with { DriverAdvice = DriverAdviceMode.OfficialOnly, DriverAiKeyProtected = null });
        AiMode = false;
        HasKey = false;
        Advice = "";
        HasAdvice = false;
        Status = Loc.Get("drivers.key.removed");
        OnPropertyChanged(nameof(ModeText));
    }

    [RelayCommand]
    private void OpenWindowsUpdate() => Open(DriverAdvice.WindowsUpdateOptional);

    [RelayCommand]
    private void OpenOfficial(DriverRow? row)
    {
        if (row?.Driver.OfficialUrl is { } url)
        {
            Open(url);
        }
    }

    private void Open(string address)
    {
        try
        {
            // Only fixed addresses from the built-in list reach this point: Windows Update settings or a maker's own site.
            using var p = Process.Start(new ProcessStartInfo(address) { UseShellExecute = true });
        }
        catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or InvalidOperationException)
        {
            Status = Loc.Format("status.fixFailed", "", ex.Message);
        }
    }

    [RelayCommand]
    private async Task AskAi()
    {
        if (IsBusy || Rows.Count == 0)
        {
            return;
        }
        var claudeCode = UsesClaudeCode ? ClaudeCodeCli.Find() : null;
        var key = UsesClaudeCode ? null : Services.Settings.ReadDriverAiKey();
        if (claudeCode is null && key is null)
        {
            Status = Loc.Get(UsesClaudeCode ? "drivers.cc.notFound" : "drivers.ai.badKey");
            return;
        }
        var drivers = Rows.Select(r => r.Driver).ToList();
        var windows = Environment.OSVersion.Version.ToString();
        // Show exactly what leaves this PC, and ask, before anything is sent.
        if (!ConsentDialog.Ask(Loc.Get("drivers.ai.consent.title"),
                Loc.Format(claudeCode is not null ? "drivers.cc.consent" : "drivers.ai.consent", DriverAdvice.DeviceList(drivers, windows)), Loc.Get("drivers.ai.consent.ok")))
        {
            return;
        }
        var cts = new CancellationTokenSource();
        _asking = cts;
        IsBusy = true;
        Status = Loc.Get("drivers.ai.working");
        try
        {
            var arabic = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "ar";
            var prompt = DriverAdvice.Prompt(drivers, windows, arabic);
            var result = claudeCode is not null
                ? await ClaudeCodeCli.AskAsync(claudeCode, prompt, cts.Token)
                : await DriverAi.AskAsync(key!, prompt, DriverAdvice.AllowedDomains, cts.Token);
            Advice = result.Outcome == DriverAiOutcome.Answered ? result.Text : "";
            HasAdvice = Advice.Length > 0;
            Status = result.Outcome switch
            {
                DriverAiOutcome.Answered => Loc.Get("drivers.ai.done"),
                DriverAiOutcome.BadKey => Loc.Get(claudeCode is not null ? "drivers.cc.signIn" : "drivers.ai.badKey"),
                DriverAiOutcome.Busy => Loc.Get("drivers.ai.busy"),
                DriverAiOutcome.Declined => Loc.Get("drivers.ai.declined"),
                _ => cts.IsCancellationRequested ? Loc.Get("drivers.ai.stopped") : Loc.Get("drivers.ai.failed"),
            };
        }
        finally
        {
            IsBusy = false;
            if (ReferenceEquals(_asking, cts))
            {
                _asking = null;
            }
            cts.Dispose();
        }
    }
}
