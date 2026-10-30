using System.Globalization;
using System.Windows;
using PcDoctor.App.Localization;
using PcDoctor.App.Services;
using PcDoctor.App.ViewModels;
using PcDoctor.App.Views;
using PcDoctor.Core.Localization;

namespace PcDoctor.App;

public partial class App : Application
{
    private MainViewModel? _viewModel;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        var settings = AppSettings.Load();
        Loc.Digits = settings.Digits;
        LocSource.Instance.SetCulture(CultureInfo.GetCultureInfo(settings.Language));
        ThemeManager.Apply(settings.Theme);

        _viewModel = new MainViewModel(settings);
        MainWindow = new MainWindow { DataContext = _viewModel };
        MainWindow.Show();
    }

    protected override async void OnExit(ExitEventArgs e)
    {
        if (_viewModel is not null)
        {
            await _viewModel.DisposeAsync();
        }
        base.OnExit(e);
    }
}
