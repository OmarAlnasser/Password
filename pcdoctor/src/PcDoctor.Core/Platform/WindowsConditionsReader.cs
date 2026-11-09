using System.Reflection;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Security.Principal;
using Microsoft.Win32;
using PcDoctor.Core.Scanning;

namespace PcDoctor.Core.Platform;

[SupportedOSPlatform("windows")]
public sealed partial class WindowsConditionsReader : IConditionsReader
{
    public ScanConditions Read(ScanMode mode)
    {
        using var cv = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion");
        var build = cv?.GetValue("CurrentBuildNumber") as string ?? "0";
        var ubr = cv?.GetValue("UBR") is int u ? u : 0;
        var product = cv?.GetValue("ProductName") as string ?? "Windows";
        // ProductName still says "Windows 10" on Windows 11; the build number is authoritative.
        if (int.TryParse(build, out var b) && b >= 22000)
        {
            product = product.Replace("Windows 10", "Windows 11", StringComparison.Ordinal);
        }

        return new ScanConditions
        {
            AppVersion = Assembly.GetEntryAssembly()?.GetName().Version?.ToString() ?? "0.0.0",
            OsProductName = product,
            OsBuild = $"{Environment.OSVersion.Version.Major}.{Environment.OSVersion.Version.Minor}.{build}.{ubr}",
            OsDisplayVersion = cv?.GetValue("DisplayVersion") as string ?? cv?.GetValue("ReleaseId") as string ?? "",
            OsEdition = cv?.GetValue("EditionID") as string ?? "",
            Architecture = RuntimeInformation.OSArchitecture.ToString(),
            Uptime = TimeSpan.FromMilliseconds(Environment.TickCount64),
            PowerSource = ReadPowerSource(),
            PowerPlan = ReadPowerPlan(),
            Elevated = new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator),
            Mode = mode,
            UiCulture = Localization.Loc.Culture.Name,
            MachineName = Environment.MachineName,
            UserName = Environment.UserName,
        };
    }

    private static PowerSource ReadPowerSource() =>
        GetSystemPowerStatus(out var s) ? s.ACLineStatus switch
        {
            0 => PowerSource.Battery,
            1 => PowerSource.AC,
            _ => PowerSource.Unknown,
        } : PowerSource.Unknown;

    private static string ReadPowerPlan()
    {
        if (PowerGetActiveScheme(IntPtr.Zero, out var guidPtr) != 0)
        {
            return "unknown";
        }
        try
        {
            var guid = Marshal.PtrToStructure<Guid>(guidPtr);
            uint size = 0;
            PowerReadFriendlyName(IntPtr.Zero, ref guid, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, ref size);
            var buffer = Marshal.AllocHGlobal((int)size);
            try
            {
                if (PowerReadFriendlyName(IntPtr.Zero, ref guid, IntPtr.Zero, IntPtr.Zero, buffer, ref size) == 0)
                {
                    return $"{Marshal.PtrToStringUni(buffer)} ({guid})";
                }
                return guid.ToString();
            }
            finally
            {
                Marshal.FreeHGlobal(buffer);
            }
        }
        finally
        {
            LocalFree(guidPtr);
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SystemPowerStatus
    {
        public byte ACLineStatus;
        public byte BatteryFlag;
        public byte BatteryLifePercent;
        public byte SystemStatusFlag;
        public int BatteryLifeTime;
        public int BatteryFullLifeTime;
    }

    [LibraryImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetSystemPowerStatus(out SystemPowerStatus status);

    [LibraryImport("powrprof.dll")]
    private static partial uint PowerGetActiveScheme(IntPtr root, out IntPtr activeScheme);

    [LibraryImport("powrprof.dll")]
    private static partial uint PowerReadFriendlyName(IntPtr root, ref Guid scheme, IntPtr subGroup,
        IntPtr setting, IntPtr buffer, ref uint size);

    [LibraryImport("kernel32.dll")]
    private static partial IntPtr LocalFree(IntPtr mem);
}
