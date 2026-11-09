using CommunityToolkit.Mvvm.ComponentModel;
using PcDoctor.App.Services;
using PcDoctor.Core.Localization;

namespace PcDoctor.App.ViewModels;

/// <summary>A page in the navigation rail.</summary>
public abstract partial class PageViewModel : ObservableObject
{
    protected PageViewModel(AppServices services)
    {
        Services = services;
        services.TextsChanged += () =>
        {
            OnTextsChanged();
            OnPropertyChanged(string.Empty);
        };
    }

    public AppServices Services { get; }

    /// <summary>Stable key used for navigation (e.g. "overview").</summary>
    public abstract string Key { get; }

    /// <summary>Segoe Fluent Icons glyph.</summary>
    public abstract string Icon { get; }

    public string Title => Loc.Get($"page.{Key}.title");
    public string Eyebrow => Loc.Get($"page.{Key}.eyebrow");
    public string Subtitle => Loc.Get($"page.{Key}.subtitle");

    /// <summary>Called when the page becomes visible.</summary>
    public virtual void OnShown()
    {
    }

    /// <summary>Called before the page is shown by a link, with the part after "key:".</summary>
    public virtual void OnNavigated(string? argument)
    {
    }

    protected virtual void OnTextsChanged()
    {
    }
}
