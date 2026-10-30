using System.Windows;
using Microsoft.Win32;

namespace PcDoctor.App.Services;

/// <summary>Swaps the first merged dictionary between Light, Dark and HighContrast.</summary>
public static class ThemeManager
{
    public static void Apply(ThemeChoice choice)
    {
        var name = SystemParameters.HighContrast ? "HighContrast"
            : choice switch
            {
                ThemeChoice.Light => "Light",
                ThemeChoice.Dark => "Dark",
                _ => SystemUsesLightTheme() ? "Light" : "Dark",
            };
        var dict = new ResourceDictionary { Source = new Uri($"pack://application:,,,/PcDoctor.App;component/Themes/{name}.xaml") };
        var merged = Application.Current.Resources.MergedDictionaries;
        if (merged.Count > 0)
        {
            merged[0] = dict;
        }
        else
        {
            merged.Add(dict);
        }
        Views.MainWindow.IsDark = name == "Dark";
        if (Application.Current.MainWindow is Views.MainWindow window)
        {
            window.ApplyTitleBarTheme(Views.MainWindow.IsDark);
        }
    }

    private static bool SystemUsesLightTheme()
    {
        using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        return key?.GetValue("AppsUseLightTheme") is not int v || v != 0;
    }
}
