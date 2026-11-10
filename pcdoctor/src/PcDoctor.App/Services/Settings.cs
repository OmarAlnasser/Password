using System.IO;
using System.Text.Json;
using PcDoctor.Core.Localization;

namespace PcDoctor.App.Services;

public enum ThemeChoice { System, Light, Dark }

/// <summary>How the driver advisor works. It asks once; "official only" never contacts any AI service.</summary>
public enum DriverAdviceMode { NotAsked, OfficialOnly, Ai, ClaudeCode }

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

    /// <summary>Hash lookups on VirusTotal with the user's own key. Off by default; nothing is ever uploaded.</summary>
    public bool VirusTotalEnabled { get; init; }

    public ScheduleFrequency ScheduledScan { get; init; } = ScheduleFrequency.Off;

    /// <summary>Shows expert tools such as Driver Verifier.</summary>
    public bool ExpertMode { get; init; }

    /// <summary>The user's VirusTotal key, encrypted with DPAPI for this Windows user (never stored in clear).</summary>
    public string? VirusTotalKeyProtected { get; init; }

    /// <summary>Driver advisor: official sources only unless the user gave their own AI key.</summary>
    public DriverAdviceMode DriverAdvice { get; init; } = DriverAdviceMode.NotAsked;

    /// <summary>The user's own AI key for driver research, encrypted with DPAPI for this Windows user (never stored in clear).</summary>
    public string? DriverAiKeyProtected { get; init; }

    public string? ReadVirusTotalKey() => Unprotect(VirusTotalKeyProtected);

    public string? ReadDriverAiKey() => Unprotect(DriverAiKeyProtected);

    private static string? Unprotect(string? value)
    {
        if (string.IsNullOrEmpty(value))
        {
            return null;
        }
        try
        {
            var bytes = System.Security.Cryptography.ProtectedData.Unprotect(Convert.FromBase64String(value), null,
                System.Security.Cryptography.DataProtectionScope.CurrentUser);
            return System.Text.Encoding.UTF8.GetString(bytes);
        }
        catch (Exception ex) when (ex is System.Security.Cryptography.CryptographicException or FormatException)
        {
            return null;
        }
    }

    public static string ProtectKey(string key) => Convert.ToBase64String(System.Security.Cryptography.ProtectedData.Protect(
        System.Text.Encoding.UTF8.GetBytes(key.Trim()), null, System.Security.Cryptography.DataProtectionScope.CurrentUser));

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
        // Written to a temp file and swapped in, so a crash or power cut cannot leave a half-written settings file.
        // A failure to save (disk full, folder locked) must never take the app down: the setting still applies this session.
        try
        {
            Directory.CreateDirectory(Folder);
            var tmp = FilePath + ".tmp";
            File.WriteAllText(tmp, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
            File.Move(tmp, FilePath, overwrite: true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
        }
    }
}
