using System.Globalization;
using System.Windows;
using System.Windows.Media;
using PcDoctor.App.Controls;
using PcDoctor.App.Localization;
using PcDoctor.App.Pages;
using PcDoctor.App.Services;
using PcDoctor.App.ViewModels;
using PcDoctor.App.Views;
using PcDoctor.Core.Localization;

namespace PcDoctor.App;

public partial class App : Application
{
    private ShellViewModel? _shell;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        var settings = AppSettings.Load();
        Loc.Digits = settings.Digits;
        Motion.UserReducedMotion = settings.ReduceMotion;
        ApplyLanguage(CultureInfo.GetCultureInfo(settings.Language));
        ThemeManager.Apply(settings.Theme);

        var services = new AppServices(settings);
        if (e.Args.Contains("--uninstall-prompt"))
        {
            _ = RunUninstallPrompt(services);
            return;
        }
        if (e.Args.Contains("--scheduled-scan"))
        {
            _ = RunScheduledScan(services);
            return;
        }
        _shell = new ShellViewModel(services, CreatePages(services));
        MainWindow = new MainWindow { DataContext = _shell };
        MainWindow.Show();
    }

    /// <summary>
    /// Called by the installer before files are removed: offers to put back everything still in the
    /// journal. Declining leaves the changes (and the journal in %ProgramData%) in place.
    /// </summary>
    private async Task RunUninstallPrompt(AppServices services)
    {
        ShutdownMode = ShutdownMode.OnExplicitShutdown;
        int pending;
        try
        {
            pending = new Core.Journal.ChangeJournal(AppModules.JournalPath).ReadCurrent().Count();
        }
        catch (Exception ex) when (ex is System.IO.IOException or UnauthorizedAccessException)
        {
            pending = 0;
        }
        if (pending > 0 && ConsentDialog.Ask(Loc.Get("uninstall.title"), Loc.Format("uninstall.body", pending), Loc.Get("journal.undoAll.button")))
        {
            string message;
            if (await services.Broker.EnsureStartedAsync(CancellationToken.None))
            {
                var response = await services.Broker.SendAsync(new Core.Ipc.UndoRequest(Core.Ipc.UndoScope.Everything, null, Force: false), CancellationToken.None);
                message = response.PayloadAs<Core.Journal.UndoResult>() is { } r
                    ? Loc.Format("status.undone", r.Undone, r.Conflicts, r.Failed)
                    : Loc.Format("status.fixFailed", response.Error, response.ErrorDetail ?? "");
            }
            else
            {
                message = Loc.Get("status.brokerDeclined");
            }
            ConsentDialog.Ask(Loc.Get("uninstall.title"), message, Loc.Get("uninstall.continue"));
        }
        await services.DisposeAsync();
        Shutdown();
    }

    /// <summary>Read-only Health Check from Task Scheduler. Silent unless there are new High or Critical findings.</summary>
    private async Task RunScheduledScan(AppServices services)
    {
        ShutdownMode = ShutdownMode.OnExplicitShutdown;
        var previous = History.Load().FirstOrDefault();
        await services.RunScanAsync(Core.Scanning.ScanMode.HealthCheck);
        var notify = services.Report is { } report ? Core.Reporting.ReportDiff.WorthNotifying(previous, report) : [];
        if (notify.Count == 0)
        {
            Shutdown();
            return;
        }
        var window = new QuietNotification(Loc.Format("notify.title", notify.Count), string.Join("\n", notify.Take(3).Select(f => Loc.Resolve(f.Title))));
        window.Closed += (_, _) => Shutdown();
        window.Show();
    }

    /// <summary>Every page in the navigation rail, in order.</summary>
    public static IEnumerable<PageViewModel> CreatePages(AppServices services) =>
    [
        new OverviewViewModel(services),
        new FindingsViewModel(services),
        new CrashesViewModel(services),
        new ProtectionViewModel(services),
        new StartupViewModel(services),
        new RepairsViewModel(services),
        new PerformanceViewModel(services),
        new OptimizeViewModel(services),
        new SensorsViewModel(services),
        new FilesViewModel(services),
        new HistoryViewModel(services),
        new ChangesViewModel(services),
        new SettingsViewModel(services),
    ];

    /// <summary>Switches strings, flow direction and the UI font family (Outfit or IBM Plex Sans Arabic first).</summary>
    public static void ApplyLanguage(CultureInfo culture)
    {
        LocSource.Instance.SetCulture(culture);
        if (Current is { } app)
        {
            app.Resources["Font.Ui"] = app.TryFindResource(culture.TextInfo.IsRightToLeft ? "Font.Arabic" : "Font.Latin") as FontFamily
                                       ?? app.Resources["Font.Ui"];
        }
    }

    protected override async void OnExit(ExitEventArgs e)
    {
        if (_shell is not null)
        {
            await _shell.DisposeAsync();
        }
        base.OnExit(e);
    }
}
