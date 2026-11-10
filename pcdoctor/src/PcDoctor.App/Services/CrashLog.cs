using System.Globalization;
using System.IO;

namespace PcDoctor.App.Services;

/// <summary>Unexpected errors, kept on this PC only (never uploaded) so a problem can be reported. Capped in size.</summary>
public static class CrashLog
{
    private const long MaxBytes = 512 * 1024;
    private static readonly object Gate = new();

    public static string FilePath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PCDoctor", "errors.log");

    public static void Write(Exception? ex)
    {
        if (ex is null)
        {
            return;
        }
        try
        {
            lock (Gate)
            {
                Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
                if (File.Exists(FilePath) && new FileInfo(FilePath).Length > MaxBytes)
                {
                    File.Move(FilePath, FilePath + ".old", overwrite: true);
                }
                File.AppendAllText(FilePath, $"{DateTimeOffset.UtcNow.ToString("u", CultureInfo.InvariantCulture)} {ex}{Environment.NewLine}{Environment.NewLine}");
            }
        }
        catch (Exception io) when (io is IOException or UnauthorizedAccessException)
        {
            // Logging must never be the thing that crashes.
        }
    }
}
