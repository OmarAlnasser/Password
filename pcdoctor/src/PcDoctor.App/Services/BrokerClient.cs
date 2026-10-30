using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Security.Principal;
using PcDoctor.Core.Ipc;
using PcDoctor.Core.Scanning;

namespace PcDoctor.App.Services;

/// <summary>
/// Starts PcDoctor.Broker.exe through UAC on demand and talks to it over a per-session named pipe.
/// The pipe name is random, the Broker's pipe ACL admits only this user's SID, and the client
/// checks that the pipe server is the Broker process it started.
/// </summary>
public sealed partial class BrokerClient : IElevatedReader, IAsyncDisposable
{
    private const int ErrorCancelled = 1223;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private NamedPipeClientStream? _pipe;
    private Process? _broker;

    public bool IsConnected => _pipe is { IsConnected: true } && _broker is { HasExited: false };

    public static string BrokerPath => Path.Combine(AppContext.BaseDirectory, "PcDoctor.Broker.exe");

    /// <summary>Returns false if the Broker is missing or the user declined the UAC prompt.</summary>
    public async Task<bool> EnsureStartedAsync(CancellationToken ct)
    {
        if (IsConnected)
        {
            return true;
        }
        await DisposeAsync().ConfigureAwait(false);
        if (!File.Exists(BrokerPath))
        {
            return false;
        }
        var pipeName = "PCDoctor.Broker." + Guid.NewGuid().ToString("N");
        var sid = WindowsIdentity.GetCurrent().User!.Value;
        var psi = new ProcessStartInfo(BrokerPath)
        {
            UseShellExecute = true,
            Verb = "runas",
            Arguments = $"--pipe {pipeName} --client-sid {sid} --client-pid {Environment.ProcessId}",
        };
        try
        {
            _broker = Process.Start(psi);
        }
        catch (Win32Exception ex) when (ex.NativeErrorCode == ErrorCancelled)
        {
            return false;
        }
        if (_broker is null)
        {
            return false;
        }

        var pipe = new NamedPipeClientStream(".", pipeName, PipeDirection.InOut, PipeOptions.Asynchronous);
        try
        {
            await pipe.ConnectAsync(TimeSpan.FromSeconds(30), ct).ConfigureAwait(false);
        }
        catch (TimeoutException)
        {
            await pipe.DisposeAsync().ConfigureAwait(false);
            return false;
        }
        if (!GetNamedPipeServerProcessId(pipe.SafePipeHandle.DangerousGetHandle(), out var serverPid) || serverPid != _broker.Id)
        {
            await pipe.DisposeAsync().ConfigureAwait(false);
            return false;
        }
        _pipe = pipe;
        return true;
    }

    public async Task<BrokerResponse> SendAsync(BrokerRequest request, CancellationToken ct)
    {
        await _gate.WaitAsync(ct).ConfigureAwait(false);
        try
        {
            if (_pipe is null)
            {
                throw new InvalidOperationException("Broker is not running.");
            }
            await PipeFraming.WriteAsync<BrokerRequest>(_pipe, request, ct).ConfigureAwait(false);
            return await PipeFraming.ReadAsync<BrokerResponse>(_pipe, ct).ConfigureAwait(false)
                   ?? throw new IOException("Broker closed the connection.");
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<T?> ReadAsync<T>(ElevatedData data, CancellationToken ct)
    {
        var response = await SendAsync(new ReadElevatedRequest(data), ct).ConfigureAwait(false);
        return response.Ok ? response.PayloadAs<T>() : default;
    }

    public async ValueTask DisposeAsync()
    {
        if (_pipe is { IsConnected: true })
        {
            try
            {
                using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(2));
                await SendAsync(new ShutdownRequest(), cts.Token).ConfigureAwait(false);
            }
            catch (Exception ex) when (ex is IOException or OperationCanceledException or InvalidOperationException)
            {
                // Broker already gone.
            }
        }
        if (_pipe is not null)
        {
            await _pipe.DisposeAsync().ConfigureAwait(false);
        }
        _pipe = null;
        _broker?.Dispose();
        _broker = null;
    }

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetNamedPipeServerProcessId(IntPtr pipe, out int serverProcessId);
}
