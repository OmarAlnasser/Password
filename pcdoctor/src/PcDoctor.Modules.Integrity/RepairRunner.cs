using System.Management;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Text;
using Microsoft.Win32.SafeHandles;
using PcDoctor.Core.Ipc;
using PcDoctor.Core.Platform;

namespace PcDoctor.Modules.Integrity;

/// <summary>Repairs, run by the Broker as jobs. DISM through dismapi.dll; SFC, chkdsk and friends from System32.</summary>
[SupportedOSPlatform("windows")]
public static partial class RepairRunner
{
    public static async Task<object?> Run(JobKind kind, string? target, IJobProgress progress, CancellationToken ct)
    {
        switch (kind)
        {
            case JobKind.DismCheckHealth:
                return Dism.Check(scan: false, progress, ct);
            case JobKind.DismScanHealth:
                return Dism.Check(scan: true, progress, ct);
            case JobKind.DismRestoreHealth:
                return Dism.Restore(progress, ct);
            case JobKind.Sfc:
            {
                var started = DateTime.Now.AddSeconds(-5);
                progress.Report(null, "sfc");
                // sfc writes UTF-16 when its output is redirected.
                var r = await ProcessRunner.RunAsync(Tool.Sfc, ["/scannow"], TimeSpan.FromHours(2), ct, Encoding.Unicode);
                var cbs = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "Logs", "CBS", "CBS.log");
                try
                {
                    using var stream = new FileStream(cbs, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
                    using var reader = new StreamReader(stream);
                    return CbsLogParser.Parse(await reader.ReadToEndAsync(ct), started, r.ExitCode);
                }
                catch (IOException)
                {
                    return new SfcResult(r.ExitCode, [], [], 0, false);
                }
            }
            case JobKind.ChkdskScan:
            {
                var volume = Environment.GetFolderPath(Environment.SpecialFolder.Windows)[..2];
                progress.Report(null, "chkdsk");
                var r = await ProcessRunner.RunAsync(Tool.Chkdsk, [volume, "/scan"], TimeSpan.FromHours(2), ct);
                return new ChkdskResult(volume, r.ExitCode, Tail(r.StdOut));
            }
            case JobKind.ChkdskScheduleFix:
            {
                var volume = Environment.GetFolderPath(Environment.SpecialFolder.Windows)[..2];
                var r = await ProcessRunner.RunAsync(Tool.Fsutil, ["dirty", "set", volume], TimeSpan.FromMinutes(1), ct);
                return new SimpleJobResult(r.ExitCode, Tail(r.StdOut + r.StdErr));
            }
            case JobKind.DefenderOfflineScan:
            {
                // Start-MpWDOScan is MSFT_MpWDOScan.Start(); Windows restarts into the offline scan shortly after. VERIFY.
                using var cls = new ManagementClass(new ManagementScope(@"\\.\root\Microsoft\Windows\Defender"), new ManagementPath("MSFT_MpWDOScan"), null);
                using var result = cls.InvokeMethod("Start", null, null);
                return new SimpleJobResult(Convert.ToInt32(result?["ReturnValue"] ?? 0, System.Globalization.CultureInfo.InvariantCulture), "");
            }
            case JobKind.VerifierEnable:
            {
                var drivers = VerifierArgs.Drivers(target) ?? throw new ArgumentException("Name one to eight third-party .sys drivers.");
                var r1 = await ProcessRunner.RunAsync(Tool.Verifier, VerifierArgs.Enable(drivers), TimeSpan.FromMinutes(2), ct);
                // If Windows does not start normally, Verifier switches itself off at the next boot.
                var r2 = await ProcessRunner.RunAsync(Tool.Verifier, ["/bootmode", "resetonunusualshutdown"], TimeSpan.FromMinutes(2), ct);
                if (r1.ExitCode == 0 && r2.ExitCode != 0)
                {
                    // Without the automatic switch-off a bad driver could leave Windows crashing at every start. Never leave Verifier on without it.
                    var undo = await ProcessRunner.RunAsync(Tool.Verifier, ["/reset"], TimeSpan.FromMinutes(2), CancellationToken.None);
                    return new SimpleJobResult(r2.ExitCode == 0 ? 1 : r2.ExitCode, Tail(r1.StdOut + r2.StdOut + undo.StdOut));
                }
                return new SimpleJobResult(r1.ExitCode == 0 ? r2.ExitCode : r1.ExitCode, Tail(r1.StdOut + r2.StdOut));
            }
            case JobKind.VerifierReset:
            {
                var r = await ProcessRunner.RunAsync(Tool.Verifier, ["/reset"], TimeSpan.FromMinutes(2), ct);
                return new SimpleJobResult(r.ExitCode, Tail(r.StdOut));
            }
            default:
                throw new NotSupportedException(kind.ToString());
        }
    }

    private static string Tail(string s) => s.Length > 6000 ? s[^6000..] : s;

    /// <summary>FSCTL_IS_VOLUME_DIRTY on the system volume. Needs administrator rights.</summary>
    public static bool? IsSystemVolumeDirty()
    {
        var volume = Environment.GetFolderPath(Environment.SpecialFolder.Windows)[..2];
        using var h = CreateFileW($@"\\.\{volume}", 0, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
        if (h.IsInvalid)
        {
            return null;
        }
        var buffer = new byte[4];
        return DeviceIoControl(h, 0x00090078, IntPtr.Zero, 0, buffer, 4, out _, IntPtr.Zero) ? (BitConverter.ToUInt32(buffer) & 1) != 0 : null;
    }

    [LibraryImport("kernel32.dll", SetLastError = true, StringMarshalling = StringMarshalling.Utf16)]
    private static partial SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool DeviceIoControl(SafeFileHandle h, uint code, IntPtr input, int inputSize, byte[] output, int outputSize, out int returned, IntPtr overlapped);
}

/// <summary>DISM API (dismapi.dll). The health state is an enum, not localized console text.</summary>
[SupportedOSPlatform("windows")]
internal static partial class Dism
{
    private const string OnlineImage = "DISM_{53BFAE52-B167-4E2F-A258-0A37B57FF845}";
    private static readonly object Gate = new();

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate void ProgressCallback(uint current, uint total, IntPtr userData);

    public static DismResult Check(bool scan, IJobProgress progress, CancellationToken ct) => WithSession(scan ? "ScanHealth" : "CheckHealth", (session, cancel, cb) =>
    {
        var hr = DismCheckImageHealth(session, scan, cancel, cb, IntPtr.Zero, out var state);
        return hr != 0
            ? new DismResult(scan ? "ScanHealth" : "CheckHealth", ImageHealth.Failed, hr, null)
            : new DismResult(scan ? "ScanHealth" : "CheckHealth", state switch { 0 => ImageHealth.Healthy, 1 => ImageHealth.Repairable, _ => ImageHealth.NonRepairable }, 0, null);
    }, progress, ct);

    public static DismResult Restore(IJobProgress progress, CancellationToken ct) => WithSession("RestoreHealth", (session, cancel, cb) =>
    {
        var hr = DismRestoreImageHealth(session, IntPtr.Zero, 0, false, cancel, cb, IntPtr.Zero);
        return new DismResult("RestoreHealth", hr == 0 ? ImageHealth.Repaired : ImageHealth.Failed, hr, null);
    }, progress, ct);

    private static DismResult WithSession(string op, Func<uint, IntPtr, ProgressCallback, DismResult> body, IJobProgress progress, CancellationToken ct)
    {
        lock (Gate)
        {
            var log = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "PCDoctor", "dism.log");
            var hr = DismInitialize(2, log, null);
            if (hr != 0)
            {
                return new DismResult(op, ImageHealth.Failed, hr, "DismInitialize");
            }
            try
            {
                hr = DismOpenSession(OnlineImage, null, null, out var session);
                if (hr != 0)
                {
                    return new DismResult(op, ImageHealth.Failed, hr, "DismOpenSession");
                }
                using var cancel = new ManualResetEvent(false);
                using var reg = ct.Register(() => cancel.Set());
                ProgressCallback cb = (cur, total, _) => progress.Report(total == 0 ? null : (double)cur / total, op);
                try
                {
                    var result = body(session, cancel.SafeWaitHandle.DangerousGetHandle(), cb);
                    GC.KeepAlive(cb);
                    ct.ThrowIfCancellationRequested();
                    return result;
                }
                finally
                {
                    DismCloseSession(session);
                }
            }
            finally
            {
                DismShutdown();
            }
        }
    }

    [DllImport("dismapi.dll", CharSet = CharSet.Unicode)]
    private static extern int DismInitialize(int logLevel, string? logFilePath, string? scratchDirectory);

    [DllImport("dismapi.dll", CharSet = CharSet.Unicode)]
    private static extern int DismOpenSession(string imagePath, string? windowsDirectory, string? systemDrive, out uint session);

    [DllImport("dismapi.dll")]
    private static extern int DismCheckImageHealth(uint session, [MarshalAs(UnmanagedType.Bool)] bool scanImage, IntPtr cancelEvent,
        ProgressCallback progress, IntPtr userData, out int imageHealth);

    [DllImport("dismapi.dll")]
    private static extern int DismRestoreImageHealth(uint session, IntPtr sourcePaths, uint sourcePathCount, [MarshalAs(UnmanagedType.Bool)] bool limitAccess,
        IntPtr cancelEvent, ProgressCallback progress, IntPtr userData);

    [DllImport("dismapi.dll")]
    private static extern int DismCloseSession(uint session);

    [DllImport("dismapi.dll")]
    private static extern int DismShutdown();
}
