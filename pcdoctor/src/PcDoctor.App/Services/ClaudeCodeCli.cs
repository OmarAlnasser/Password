using System.ComponentModel;
using System.Diagnostics;
using System.IO;

namespace PcDoctor.App.Services;

/// <summary>
/// Driver research through Claude Code already installed and signed in on this PC, instead of an API key.
/// PC Doctor starts it once per question in an empty folder, allows it web search and page reading only,
/// and stops it when the answer is in. Nothing is installed, and it is never started without the user's yes.
/// </summary>
public static class ClaudeCodeCli
{
    private static readonly TimeSpan Limit = TimeSpan.FromMinutes(5);

    /// <summary>Where Claude Code is on this PC, or null when it is not installed.</summary>
    public static string? Find()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var candidates = new List<string>
        {
            Path.Combine(home, ".local", "bin", "claude.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "npm", "claude.cmd"),
        };
        foreach (var dir in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            candidates.Add(Path.Combine(dir.Trim(), "claude.exe"));
            candidates.Add(Path.Combine(dir.Trim(), "claude.cmd"));
        }
        foreach (var c in candidates)
        {
            try
            {
                if (File.Exists(c))
                {
                    return c;
                }
            }
            catch (Exception ex) when (ex is ArgumentException or NotSupportedException)
            {
                // A malformed PATH entry: skip it.
            }
        }
        return null;
    }

    public static async Task<DriverAiResult> AskAsync(string exe, string prompt, CancellationToken ct)
    {
        // An empty working folder, so the assistant has no files of the user's in front of it.
        var folder = Path.Combine(Path.GetTempPath(), "PCDoctor-drivers-" + Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(folder);
            var info = new ProcessStartInfo(exe)
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                WorkingDirectory = folder,
                StandardOutputEncoding = System.Text.Encoding.UTF8,
            };
            // Fixed arguments only; the question itself goes in through standard input, never the command line.
            info.ArgumentList.Add("-p");
            info.ArgumentList.Add("--allowedTools");
            info.ArgumentList.Add("WebSearch,WebFetch");

            using var process = Process.Start(info);
            if (process is null)
            {
                return new DriverAiResult(DriverAiOutcome.Failed, "");
            }
            using var limit = CancellationTokenSource.CreateLinkedTokenSource(ct);
            limit.CancelAfter(Limit);
            try
            {
                await process.StandardInput.WriteAsync(prompt.AsMemory(), limit.Token).ConfigureAwait(false);
                process.StandardInput.Close();
                var errors = process.StandardError.ReadToEndAsync(limit.Token);
                var text = (await process.StandardOutput.ReadToEndAsync(limit.Token).ConfigureAwait(false)).Trim();
                await process.WaitForExitAsync(limit.Token).ConfigureAwait(false);
                var error = (await errors.ConfigureAwait(false)).Trim();
                if (process.ExitCode != 0 || text.Length == 0)
                {
                    var notSignedIn = (error + text).Contains("login", StringComparison.OrdinalIgnoreCase);
                    return new DriverAiResult(notSignedIn ? DriverAiOutcome.BadKey : DriverAiOutcome.Failed, error.Length > 300 ? error[..300] : error);
                }
                return new DriverAiResult(DriverAiOutcome.Answered, text);
            }
            catch (OperationCanceledException)
            {
                return new DriverAiResult(DriverAiOutcome.Failed, "");
            }
            finally
            {
                // Never leave it running behind PC Doctor.
                if (!process.HasExited)
                {
                    try
                    {
                        process.Kill(entireProcessTree: true);
                    }
                    catch (Exception ex) when (ex is InvalidOperationException or Win32Exception)
                    {
                        // Already gone.
                    }
                }
            }
        }
        catch (Exception ex) when (ex is Win32Exception or IOException or UnauthorizedAccessException or InvalidOperationException)
        {
            return new DriverAiResult(DriverAiOutcome.Failed, ex.Message);
        }
        finally
        {
            try
            {
                Directory.Delete(folder, recursive: true);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // A leftover empty temp folder is harmless.
            }
        }
    }
}
