using PcDoctor.Core.Events;

namespace PcDoctor.Modules.Crash;

/// <summary>The providers and event IDs M5 reads, and the queries that fetch them.</summary>
public static class CrashEvents
{
    public const string KernelPower = "Microsoft-Windows-Kernel-Power";
    public const string BugCheck = "Microsoft-Windows-WER-SystemErrorReporting";
    public const string EventLog = "EventLog";
    public const string Whea = "Microsoft-Windows-WHEA-Logger";
    public const string Display = "Display";
    public const string ProcessorPower = "Microsoft-Windows-Kernel-Processor-Power";
    public const string Scm = "Service Control Manager";
    public const string Disk = "disk";
    public const string Ntfs = "Microsoft-Windows-Ntfs";
    public const string Storport = "Microsoft-Windows-StorPort";
    public const string Classpnp = "Microsoft-Windows-Classpnp"; // VERIFY: some builds log 157 under "disk".
    public const string KernelPnp = "Microsoft-Windows-Kernel-PnP";
    public const string Volmgr = "volmgr";
    public const string AppError = "Application Error";
    public const string AppHang = "Application Hang";
    public const string DotNet = ".NET Runtime";
    public const string Wer = "Windows Error Reporting";

    public static IReadOnlyList<EventQuery> Queries(TimeSpan window) =>
    [
        new EventQuery("System",
        [
            (KernelPower, [41]),
            (BugCheck, [1001]),
            (EventLog, [6008]),
            (Whea, [17, 18, 19, 47]),
            (Display, [4101]),
            (ProcessorPower, [37]),
            (Scm, [7000, 7009, 7011, 7031, 7034]),
            (Disk, [7, 11, 51, 157]),
            (Ntfs, [50, 55, 98, 140]),
            (Storport, [129, 153]),
            (Classpnp, [157]),
            (KernelPnp, [219]),
            (Volmgr, [161]),
        ], window, MaxEvents: 1000),
        new EventQuery("Application",
        [
            (AppError, [1000]),
            (AppHang, [1002]),
            (DotNet, [1026]),
            (Wer, [1001]),
        ], window, MaxEvents: 1000),
    ];

    public static bool Is(this EventRecordData e, string provider, int id) =>
        e.EventId == id && string.Equals(e.Provider, provider, StringComparison.OrdinalIgnoreCase);
}
