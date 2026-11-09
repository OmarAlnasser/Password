using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using Microsoft.Win32;

namespace PcDoctor.Core.Platform;

/// <summary>Reads the start type from the registry and changes it with ChangeServiceConfig, as SCM expects.</summary>
[SupportedOSPlatform("windows")]
public sealed partial class WindowsServiceConfigAccess : IServiceConfigAccess
{
    private const uint SERVICE_NO_CHANGE = 0xFFFFFFFF;
    private const uint SC_MANAGER_CONNECT = 0x0001;
    private const uint SERVICE_CHANGE_CONFIG = 0x0002;
    private const uint SERVICE_CONFIG_DELAYED_AUTO_START_INFO = 3;

    public (string StartType, bool Delayed)? Read(string service)
    {
        using var key = Registry.LocalMachine.OpenSubKey($@"SYSTEM\CurrentControlSet\Services\{service}");
        if (key?.GetValue("Start") is not int start)
        {
            return null;
        }
        var delayed = key.GetValue("DelayedAutostart") is int d && d != 0;
        return (start switch
        {
            0 => "Boot",
            1 => "System",
            2 => "Automatic",
            3 => "Manual",
            4 => "Disabled",
            _ => start.ToString(System.Globalization.CultureInfo.InvariantCulture),
        }, delayed && start == 2);
    }

    public void Write(string service, string startType, bool delayed)
    {
        var start = startType switch
        {
            "Automatic" => 2u,
            "Manual" => 3u,
            "Disabled" => 4u,
            _ => throw new ArgumentException($"Start type {startType} cannot be set by PC Doctor."),
        };
        var scm = OpenSCManagerW(null, null, SC_MANAGER_CONNECT);
        if (scm == IntPtr.Zero)
        {
            throw new Win32Exception();
        }
        try
        {
            var svc = OpenServiceW(scm, service, SERVICE_CHANGE_CONFIG);
            if (svc == IntPtr.Zero)
            {
                throw new Win32Exception();
            }
            try
            {
                if (!ChangeServiceConfigW(svc, SERVICE_NO_CHANGE, start, SERVICE_NO_CHANGE,
                        null, null, IntPtr.Zero, null, null, null, null))
                {
                    throw new Win32Exception();
                }
                if (start == 2)
                {
                    var info = delayed ? 1 : 0;
                    if (!ChangeServiceConfig2W(svc, SERVICE_CONFIG_DELAYED_AUTO_START_INFO, ref info))
                    {
                        throw new Win32Exception();
                    }
                }
            }
            finally
            {
                CloseServiceHandle(svc);
            }
        }
        finally
        {
            CloseServiceHandle(scm);
        }
    }

    [LibraryImport("advapi32.dll", SetLastError = true, StringMarshalling = StringMarshalling.Utf16)]
    private static partial IntPtr OpenSCManagerW(string? machine, string? database, uint access);

    [LibraryImport("advapi32.dll", SetLastError = true, StringMarshalling = StringMarshalling.Utf16)]
    private static partial IntPtr OpenServiceW(IntPtr scm, string name, uint access);

    [LibraryImport("advapi32.dll", SetLastError = true, StringMarshalling = StringMarshalling.Utf16)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool ChangeServiceConfigW(IntPtr service, uint type, uint start, uint error,
        string? binaryPath, string? loadOrderGroup, IntPtr tagId, string? dependencies,
        string? account, string? password, string? displayName);

    [LibraryImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool ChangeServiceConfig2W(IntPtr service, uint infoLevel, ref int info);

    [LibraryImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool CloseServiceHandle(IntPtr handle);
}
