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
        if (e.Args.Contains("--scheduled-scan"))
        {
            _ = RunScheduledScan(services);
            return;
        }
        _shell = new ShellViewModel(services, CreatePages(services));
        MainWindow = new MainWindow { DataContext = _shell };
        MainWindow.Show();
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
