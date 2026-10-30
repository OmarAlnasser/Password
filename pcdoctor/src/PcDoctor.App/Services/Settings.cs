using System.IO;
using System.Text.Json;
using PcDoctor.Core.Localization;

namespace PcDoctor.App.Services;

public enum ThemeChoice { System, Light, Dark }

/// <summary>Per-user settings in %LOCALAPPDATA%\PCDoctor\settings.json. PC Doctor sends no telemetry; there is no switch to turn it on.</summary>
public sealed record AppSettings
{
    public string Language { get; init; } = "en-US";
    public DigitStyle Digits { get; init; } = DigitStyle.Western;
    /// <summary>Dark is the identity, as in Khazna; new installs start dark.</summary>
    public ThemeChoice Theme { get; init; } = ThemeChoice.Dark;
    public bool ReduceMotion { get; init; }
    public bool RedactExports { get; init; }

    /// <summary>Lets the debugger download public symbols from msdl.microsoft.com (off until the user turns it on).</summary>
    public bool AllowSymbolDownload { get; init; }

    public static string Folder => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PCDoctor");
    private static string FilePath => Path.Combine(Folder, "settings.json");

    public static AppSettings Load()
    {
        try
        {
            return File.Exists(FilePath)
                ? JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(FilePath)) ?? new AppSettings()
                : new AppSettings();
        }
        catch (Exception ex) when (ex is IOException or JsonException or UnauthorizedAccessException)
        {
            return new AppSettings();
        }
    }

    public void Save()
    {
        Directory.CreateDirectory(Folder);
        File.WriteAllText(FilePath, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
    }
}
