using System.Globalization;
using CommunityToolkit.Mvvm.ComponentModel;
using PcDoctor.App.Controls;
using PcDoctor.App.Localization;
using PcDoctor.App.Services;
using PcDoctor.App.ViewModels;
using PcDoctor.Core.Localization;

namespace PcDoctor.App.Pages;

public sealed partial class SettingsViewModel : PageViewModel
{
    public SettingsViewModel(AppServices services) : base(services)
    {
        var s = services.Settings;
        _selectedLanguage = Languages.FirstOrDefault(l => l.Value == s.Language) ?? Languages[0];
        _selectedTheme = Themes.First(t => t.Value == s.Theme);
        _selectedDigits = DigitStyles.First(d => d.Value == s.Digits);
        _redactExports = s.RedactExports;
        _reduceMotion = s.ReduceMotion;
        _allowSymbolDownload = s.AllowSymbolDownload;
    }

    public override string Key => "settings";
    public override string Icon => "";

    public IReadOnlyList<Choice<string>> Languages { get; } = [new("en-US", "language.en"), new("ar-SA", "language.ar")];
    public IReadOnlyList<Choice<ThemeChoice>> Themes { get; } =
        [new(ThemeChoice.Dark, "theme.dark"), new(ThemeChoice.Light, "theme.light"), new(ThemeChoice.System, "theme.system")];
    public IReadOnlyList<Choice<DigitStyle>> DigitStyles { get; } =
        [new(DigitStyle.Western, "digits.western"), new(DigitStyle.ArabicIndic, "digits.arabicIndic")];

    [ObservableProperty] private Choice<string> _selectedLanguage;
    [ObservableProperty] private Choice<ThemeChoice> _selectedTheme;
    [ObservableProperty] private Choice<DigitStyle> _selectedDigits;
    [ObservableProperty] private bool _redactExports;
    [ObservableProperty] private bool _reduceMotion;
    [ObservableProperty] private bool _allowSymbolDownload;

    public string Version => typeof(SettingsViewModel).Assembly.GetName().Version?.ToString(3) ?? "0.0.0";

    partial void OnSelectedLanguageChanged(Choice<string> value)
    {
        Services.UpdateSettings(s => s with { Language = value.Value });
        App.ApplyLanguage(CultureInfo.GetCultureInfo(value.Value));
        Services.RaiseTextsChanged();
    }

    partial void OnSelectedDigitsChanged(Choice<DigitStyle> value)
    {
        Loc.Digits = value.Value;
        Services.UpdateSettings(s => s with { Digits = value.Value });
        LocSource.Instance.Refresh();
        Services.RaiseTextsChanged();
    }

    partial void OnSelectedThemeChanged(Choice<ThemeChoice> value)
    {
        ThemeManager.Apply(value.Value);
        Services.UpdateSettings(s => s with { Theme = value.Value });
        Services.RaiseTextsChanged();
    }

    partial void OnAllowSymbolDownloadChanged(bool value) => Services.UpdateSettings(s => s with { AllowSymbolDownload = value });

    partial void OnRedactExportsChanged(bool value) => Services.UpdateSettings(s => s with { RedactExports = value });

    partial void OnReduceMotionChanged(bool value)
    {
        Motion.UserReducedMotion = value;
        Services.UpdateSettings(s => s with { ReduceMotion = value });
    }
}
