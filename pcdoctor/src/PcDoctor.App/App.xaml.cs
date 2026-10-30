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
        _shell = new ShellViewModel(services, CreatePages(services));
        MainWindow = new MainWindow { DataContext = _shell };
        MainWindow.Show();
    }

    /// <summary>Every page in the navigation rail, in order.</summary>
    public static IEnumerable<PageViewModel> CreatePages(AppServices services) =>
    [
        new OverviewViewModel(services),
        new FindingsViewModel(services),
        new CrashesViewModel(services),
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
