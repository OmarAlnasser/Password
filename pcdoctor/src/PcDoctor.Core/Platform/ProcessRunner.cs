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
    public static async Task<ProcessResult> RunAsync(
        Tool tool,
        IReadOnlyList<string> args,
        TimeSpan? timeout,
        CancellationToken ct,
        Encoding? outputEncoding = null)
    {
        var psi = new ProcessStartInfo(PathOf(tool))
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
        var commandLine = $"\"{psi.FileName}\" {string.Join(' ', args.Select(a => a.Contains(' ') ? $"\"{a}\"" : a))}";
        CommandStarted?.Invoke(commandLine);

        using var process = Process.Start(psi) ?? throw new InvalidOperationException($"Could not start {tool}.");
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
