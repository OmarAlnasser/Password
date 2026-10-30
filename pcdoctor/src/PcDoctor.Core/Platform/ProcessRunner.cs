using System.Diagnostics;
using System.Text;

namespace PcDoctor.Core.Platform;

/// <summary>Microsoft tools PC Doctor may start. Resolved to System32 by full path, never through PATH.</summary>
public enum Tool { Powercfg, Pnputil, Driverquery }

public sealed record ProcessResult(int ExitCode, string StdOut, string StdErr, string CommandLine, bool TimedOut);

public static class ProcessRunner
{
    /// <summary>Every command line PC Doctor runs, for the in-app log.</summary>
    public static event Action<string>? CommandStarted;

    public static string PathOf(Tool tool)
    {
        var system32 = Environment.GetFolderPath(Environment.SpecialFolder.System);
        return Path.Combine(system32, tool switch
        {
            Tool.Powercfg => "powercfg.exe",
            Tool.Pnputil => "pnputil.exe",
            Tool.Driverquery => "driverquery.exe",
            _ => throw new ArgumentOutOfRangeException(nameof(tool)),
        });
    }

    /// <param name="outputEncoding">sfc writes UTF-16 when redirected; most tools use the OEM code page.</param>
    /// <summary>
    /// Runs a Microsoft tool that is not in System32 (the debugger). The path must be under Program
    /// Files, which only administrators can write, so a user-level process cannot plant it.
    /// </summary>
    public static Task<ProcessResult> RunProgramFilesToolAsync(string exePath, IReadOnlyList<string> args, TimeSpan? timeout,
        CancellationToken ct, IReadOnlyDictionary<string, string>? environment = null)
    {
        var full = Path.GetFullPath(exePath);
        var roots = new[]
        {
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
        }.Where(r => r.Length > 0).Select(r => Path.TrimEndingDirectorySeparator(r) + Path.DirectorySeparatorChar);
        if (!roots.Any(r => full.StartsWith(r, StringComparison.OrdinalIgnoreCase)))
        {
            throw new InvalidOperationException($"Refusing to run a tool outside Program Files: {full}");
        }
        return RunPathAsync(full, args, timeout, ct, null, environment);
    }

    public static Task<ProcessResult> RunAsync(
        Tool tool,
        IReadOnlyList<string> args,
        TimeSpan? timeout,
        CancellationToken ct,
        Encoding? outputEncoding = null) => RunPathAsync(PathOf(tool), args, timeout, ct, outputEncoding, null);

    private static async Task<ProcessResult> RunPathAsync(
        string exePath,
        IReadOnlyList<string> args,
        TimeSpan? timeout,
        CancellationToken ct,
        Encoding? outputEncoding,
        IReadOnlyDictionary<string, string>? environment)
    {
        var psi = new ProcessStartInfo(exePath)
        {
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            StandardOutputEncoding = outputEncoding,
            StandardErrorEncoding = outputEncoding,
        };
        foreach (var a in args)
        {
            psi.ArgumentList.Add(a);
        }
        foreach (var (k, v) in environment ?? new Dictionary<string, string>())
        {
            psi.Environment[k] = v;
        }
        var commandLine = $"\"{psi.FileName}\" {string.Join(' ', args.Select(a => a.Contains(' ') ? $"\"{a}\"" : a))}";
        CommandStarted?.Invoke(commandLine);

        using var process = Process.Start(psi) ?? throw new InvalidOperationException($"Could not start {exePath}.");
        var stdout = process.StandardOutput.ReadToEndAsync(ct);
        var stderr = process.StandardError.ReadToEndAsync(ct);
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        if (timeout is { } t)
        {
            cts.CancelAfter(t);
        }
        var timedOut = false;
        try
        {
            await process.WaitForExitAsync(cts.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            timedOut = true;
            process.Kill(entireProcessTree: true);
        }
        return new ProcessResult(timedOut ? -1 : process.ExitCode, await stdout.ConfigureAwait(false),
            await stderr.ConfigureAwait(false), commandLine, timedOut);
    }
}
