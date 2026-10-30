using System.Diagnostics;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using PcDoctor.Core.Ipc;
using PcDoctor.Core.Journal;
using PcDoctor.Core.Platform;
using PcDoctor.Modules.Crash;
using PcDoctor.Modules.Disk;
using PcDoctor.Modules.Security;

namespace PcDoctor.Broker;

/// <summary>
/// Elevated helper. Usage: PcDoctor.Broker.exe --pipe &lt;name&gt; --client-sid &lt;SID&gt; --client-pid &lt;PID&gt;
/// It serves exactly one client: the PcDoctor.App process that launched it, from the same folder,
/// running as the given user. It exits when that client disconnects or exits, or after 15 idle minutes.
/// </summary>
internal static partial class Program
{
    private static readonly TimeSpan IdleTimeout = TimeSpan.FromMinutes(15);

    private static async Task<int> Main(string[] args)
    {
        var options = ParseArgs(args);
        if (options is null)
        {
            return 2;
        }
        var (pipeName, clientSid, clientPid) = options.Value;

        using var parent = TryGetProcess(clientPid);
        if (parent is null || !IsExpectedClientImage(parent))
        {
            return 3;
        }

        var journal = new ChangeJournal(JournalPath());
        var registry = new WindowsRegistryAccess();
        var executor = new ChangeExecutor(journal,
            new RegistryApplier(registry, hive => ResolveHive(hive, clientSid)),
            new ServiceApplier(new WindowsServiceConfigAccess()));
        var handler = new BrokerRequestHandler(executor, journal,
            new RestorePointGuard(new WindowsRestorePointApi()), ReadElevated);

        await using var pipe = NamedPipeServerStreamAcl.Create(pipeName, PipeDirection.InOut, 1,
            PipeTransmissionMode.Byte, PipeOptions.Asynchronous, 0, 0, PipeAcl(clientSid));

        using var cts = new CancellationTokenSource();
        _ = parent.WaitForExitAsync().ContinueWith(_ => cts.Cancel(), TaskScheduler.Default);
        using (var connectTimeout = CancellationTokenSource.CreateLinkedTokenSource(cts.Token))
        {
            connectTimeout.CancelAfter(TimeSpan.FromMinutes(1));
            await pipe.WaitForConnectionAsync(connectTimeout.Token);
        }
        if (!GetNamedPipeClientProcessId(pipe.SafePipeHandle.DangerousGetHandle(), out var connectedPid) || connectedPid != clientPid)
        {
            // Somebody else reached the pipe first (same user, other process). Refuse everything.
            return 4;
        }

        try
        {
            while (true)
            {
                using var idle = CancellationTokenSource.CreateLinkedTokenSource(cts.Token);
                idle.CancelAfter(IdleTimeout);
                if (!await handler.ServeOneAsync(pipe, idle.Token))
                {
                    break;
                }
            }
        }
        catch (OperationCanceledException)
        {
        }
        catch (IOException)
        {
            // Client went away.
        }
        return 0;
    }

    private static object? ReadElevated(ElevatedData data) => data switch
    {
        ElevatedData.StorageReliability => DiskReader.ReadReliability(),
        ElevatedData.NvmeHealth => DiskReader.ReadNvme(),
        ElevatedData.SmartData => DiskReader.ReadSmart(),
        ElevatedData.Tpm => SecurityReader.ReadTpm(),
        ElevatedData.BitLocker => SecurityReader.ReadBitLocker(),
        ElevatedData.CrashDumps => DumpReader.Read(allowSymbolDownload: false, CancellationToken.None),
        ElevatedData.CrashDumpsWithSymbols => DumpReader.Read(allowSymbolDownload: true, CancellationToken.None),
        _ => null,
    };

    /// <summary>
    /// HKCU in an elevated process can be the admin account's hive (over-the-shoulder elevation),
    /// so user-scoped changes always go to HKU\&lt;client SID&gt;.
    /// </summary>
    internal static string ResolveHive(string hive, string clientSid) =>
        hive.Equals("HKCU", StringComparison.OrdinalIgnoreCase) ? $@"HKU\{clientSid}" : hive;

    private static PipeSecurity PipeAcl(string clientSid)
    {
        var security = new PipeSecurity();
        security.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(clientSid), PipeAccessRights.ReadWrite, AccessControlType.Allow));
        security.AddAccessRule(new PipeAccessRule(WindowsIdentity.GetCurrent().User!, PipeAccessRights.FullControl, AccessControlType.Allow));
        security.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(WellKnownSidType.NetworkSid, null), PipeAccessRights.FullControl, AccessControlType.Deny));
        return security;
    }

    /// <summary>%ProgramData%\PCDoctor\journal, writable only by Administrators and SYSTEM.</summary>
    private static string JournalPath()
    {
        var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "PCDoctor", "journal");
        var info = Directory.CreateDirectory(dir);
        var acl = new DirectorySecurity();
        acl.SetAccessRuleProtection(isProtected: true, preserveInheritance: false);
        const InheritanceFlags inherit = InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit;
        acl.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null),
            FileSystemRights.FullControl, inherit, PropagationFlags.None, AccessControlType.Allow));
        acl.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null),
            FileSystemRights.FullControl, inherit, PropagationFlags.None, AccessControlType.Allow));
        acl.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(WellKnownSidType.BuiltinUsersSid, null),
            FileSystemRights.ReadAndExecute, inherit, PropagationFlags.None, AccessControlType.Allow));
        info.SetAccessControl(acl);
        return Path.Combine(dir, "journal.jsonl");
    }

    private static bool IsExpectedClientImage(Process client)
    {
        try
        {
            var expected = Path.Combine(AppContext.BaseDirectory, "PcDoctor.App.exe");
            return string.Equals(Path.GetFullPath(client.MainModule!.FileName), Path.GetFullPath(expected), StringComparison.OrdinalIgnoreCase);
        }
        catch (Exception)
        {
            return false;
        }
    }

    private static Process? TryGetProcess(int pid)
    {
        try
        {
            return Process.GetProcessById(pid);
        }
        catch (ArgumentException)
        {
            return null;
        }
    }

    private static (string Pipe, string Sid, int Pid)? ParseArgs(string[] args)
    {
        string? pipe = null, sid = null;
        int pid = 0;
        for (var i = 0; i + 1 < args.Length; i += 2)
        {
            switch (args[i])
            {
                case "--pipe": pipe = args[i + 1]; break;
                case "--client-sid": sid = args[i + 1]; break;
                case "--client-pid": _ = int.TryParse(args[i + 1], out pid); break;
            }
        }
        if (pipe is null || sid is null || pid == 0 || !pipe.StartsWith("PCDoctor.Broker.", StringComparison.Ordinal))
        {
            return null;
        }
        try
        {
            _ = new SecurityIdentifier(sid);
        }
        catch (ArgumentException)
        {
            return null;
        }
        return (pipe, sid, pid);
    }

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetNamedPipeClientProcessId(IntPtr pipe, out int clientProcessId);
}
