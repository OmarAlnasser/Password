using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using Microsoft.Win32.SafeHandles;
using PcDoctor.Core.Ipc;

namespace PcDoctor.Modules.Inventory;

/// <summary>
/// Walks every fixed NTFS/ReFS volume with an explicit stack (no recursion), never following
/// junctions or symlinks, never opening files. Directories are opened with
/// FILE_FLAG_BACKUP_SEMANTICS, which with SeBackupPrivilege (Broker, opt-in) also lists ACL-protected ones.
/// </summary>
[SupportedOSPlatform("windows")]
public static partial class InventoryWalker
{
    private const uint FILE_LIST_DIRECTORY = 0x0001;
    private const uint FILE_SHARE_ALL = 0x7;
    private const uint OPEN_EXISTING = 3;
    private const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;
    private const uint FILE_FLAG_OPEN_REPARSE_POINT = 0x00200000;
    private const int FileIdBothDirectoryInfo = 10;
    private const int FileIdBothDirectoryRestartInfo = 11;
    private const int ERROR_NO_MORE_FILES = 18;
    private const int ERROR_ACCESS_DENIED = 5;
    private const int ERROR_SHARING_VIOLATION = 32;
    private const int ERROR_LOCK_VIOLATION = 33;

    public static InventoryResult Run(bool useBackupPrivilege, IJobProgress? progress, CancellationToken ct, string? csvFolder)
    {
        var watch = Stopwatch.StartNew();
        var backup = useBackupPrivilege && Privileges.EnableBackup();
        var acc = new InventoryAccumulator();
        var volumes = DriveInfo.GetDrives()
            .Where(d => d.DriveType == DriveType.Fixed && d.IsReady && d.DriveFormat is "NTFS" or "ReFS")
            .Select(d => d.RootDirectory.FullName)
            .ToList();
        var buffer = new byte[64 * 1024];
        foreach (var root in volumes)
        {
            var serial = VolumeSerial(root);
            var stack = new Stack<string>();
            stack.Push(root);
            while (stack.Count > 0)
            {
                ct.ThrowIfCancellationRequested();
                var dir = stack.Pop();
                acc.Directory();
                if (acc.Directories % 2000 == 0)
                {
                    progress?.Report(null, $"{acc.Files:N0} files · {dir}");
                }
                using var handle = CreateFileW(LongPath(dir), FILE_LIST_DIRECTORY, FILE_SHARE_ALL, IntPtr.Zero, OPEN_EXISTING,
                    FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, IntPtr.Zero);
                if (handle.IsInvalid)
                {
                    acc.Skip(dir, Reason(Marshal.GetLastPInvokeError()), true);
                    continue;
                }
                var cls = FileIdBothDirectoryRestartInfo;
                while (true)
                {
                    if (!GetFileInformationByHandleEx(handle, cls, buffer, buffer.Length))
                    {
                        var err = Marshal.GetLastPInvokeError();
                        if (err != ERROR_NO_MORE_FILES)
                        {
                            acc.Skip(dir, Reason(err), true);
                        }
                        break;
                    }
                    cls = FileIdBothDirectoryInfo;
                    foreach (var e in DirInfoParser.Parse(buffer, buffer.Length))
                    {
                        var path = Path.Combine(dir, e.Name);
                        if ((e.Attributes & InventoryAccumulator.DirectoryAttribute) != 0)
                        {
                            if ((e.Attributes & InventoryAccumulator.ReparsePoint) != 0)
                            {
                                acc.Skip(path, SkipReason.LinkNotFollowed, true);
                            }
                            else
                            {
                                stack.Push(path);
                            }
                        }
                        else
                        {
                            acc.File(path, serial, e.FileId, e.Attributes, e.Size);
                        }
                    }
                }
            }
        }
        string? csv = null;
        if (csvFolder is not null && acc.AllSkipped.Count > 0)
        {
            Directory.CreateDirectory(csvFolder);
            csv = Path.Combine(csvFolder, $"skipped-{DateTime.UtcNow.ToString("yyyyMMdd-HHmmss", System.Globalization.CultureInfo.InvariantCulture)}.csv");
            File.WriteAllText(csv, InventoryAccumulator.ToCsv(acc.AllSkipped), new System.Text.UTF8Encoding(true));
        }
        return acc.ToResult(volumes, watch.Elapsed, backup, csv);
    }

    private static SkipReason Reason(int win32) => win32 switch
    {
        ERROR_ACCESS_DENIED => SkipReason.AccessDenied,
        ERROR_SHARING_VIOLATION or ERROR_LOCK_VIOLATION => SkipReason.Locked,
        2 or 3 or 123 or 161 or 206 => SkipReason.PathError,
        _ => SkipReason.Other,
    };

    private static string LongPath(string path) => path.StartsWith(@"\\?\", StringComparison.Ordinal) ? path : @"\\?\" + path;

    private static uint VolumeSerial(string root) =>
        GetVolumeInformationW(root, IntPtr.Zero, 0, out var serial, out _, out _, IntPtr.Zero, 0) ? serial : 0;

    [LibraryImport("kernel32.dll", SetLastError = true, StringMarshalling = StringMarshalling.Utf16)]
    private static partial SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetFileInformationByHandleEx(SafeFileHandle file, int infoClass, byte[] buffer, int size);

    [LibraryImport("kernel32.dll", SetLastError = true, StringMarshalling = StringMarshalling.Utf16)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetVolumeInformationW(string root, IntPtr name, int nameSize, out uint serial, out uint maxComponent,
        out uint flags, IntPtr fsName, int fsNameSize);
}

/// <summary>SeBackupPrivilege for the Broker's own token, only when the user opted in.</summary>
[SupportedOSPlatform("windows")]
internal static partial class Privileges
{
    // Pack = 4 matches the Windows layout (count, then the LUID right after it). With default packing the LUID
    // lands 4 bytes too late and the privilege is never actually enabled.
    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    private struct TOKEN_PRIVILEGES
    {
        public uint Count;
        public long Luid;
        public uint Attributes;
    }

    public static bool EnableBackup()
    {
        if (!OpenProcessToken(Process.GetCurrentProcess().Handle, 0x0020 | 0x0008, out var token))
        {
            return false;
        }
        try
        {
            if (!LookupPrivilegeValueW(null, "SeBackupPrivilege", out var luid))
            {
                return false;
            }
            var tp = new TOKEN_PRIVILEGES { Count = 1, Luid = luid, Attributes = 0x2 };
            return AdjustTokenPrivileges(token, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero) && Marshal.GetLastPInvokeError() == 0;
        }
        finally
        {
            CloseHandle(token);
        }
    }

    [LibraryImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);

    [LibraryImport("advapi32.dll", SetLastError = true, StringMarshalling = StringMarshalling.Utf16)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool LookupPrivilegeValueW(string? system, string name, out long luid);

    [LibraryImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool AdjustTokenPrivileges(IntPtr token, [MarshalAs(UnmanagedType.Bool)] bool disableAll, ref TOKEN_PRIVILEGES state,
        uint len, IntPtr prev, IntPtr retLen);

    [LibraryImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool CloseHandle(IntPtr handle);
}
