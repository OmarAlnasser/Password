using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using PcDoctor.App.Services;
using PcDoctor.Core.Localization;

namespace PcDoctor.App.ViewModels;

public sealed partial class ShellViewModel : ObservableObject, IAsyncDisposable
{
    public ShellViewModel(AppServices services, IEnumerable<PageViewModel> pages)
    {
        Services = services;
        Pages = new ObservableCollection<PageViewModel>(pages);
        _selectedPage = Pages[0];
        services.NavigateRequested += target =>
        {
            var parts = target.Split(':', 2);
            if (Pages.FirstOrDefault(p => p.Key == parts[0]) is { } page)
            {
                page.OnNavigated(parts.Length > 1 ? parts[1] : null);
                SelectedPage = page;
            }
        };
        services.TextsChanged += () => OnPropertyChanged(string.Empty);
    }

    public AppServices Services { get; }
    public ObservableCollection<PageViewModel> Pages { get; }

    [ObservableProperty] private PageViewModel _selectedPage;

    public string AppTitle => Loc.Get("app.title");
    public string Privacy => Loc.Get("shell.privacy");

    partial void OnSelectedPageChanged(PageViewModel value) => value.OnShown();

    public ValueTask DisposeAsync() => Services.DisposeAsync();
}
