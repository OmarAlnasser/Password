using System.ComponentModel;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using Microsoft.Win32.SafeHandles;
using PcDoctor.Core.Findings;
using PcDoctor.Core.Ipc;
using PcDoctor.Core.Platform;
using PcDoctor.Core.Scanning;

namespace PcDoctor.Modules.Disk;

public sealed class DiskModule(Func<IReadOnlyList<PhysicalDiskInfo>?> readDisks) : IModule
{
    public string Id => DiskAnalyzer.ModuleId;
    public Text Name => new("m7.name");

    public async Task<ModuleResult> RunAsync(ScanContext context)
    {
        var disks = await Task.Run(readDisks, context.CancellationToken).ConfigureAwait(false);
        var snapshot = new DiskSnapshot { Disks = disks };
        if (context.Elevated is { } e)
        {
            var ct = context.CancellationToken;
            snapshot = snapshot with
            {
                Reliability = await e.ReadAsync<List<ReliabilityCounters>>(ElevatedData.StorageReliability, ct).ConfigureAwait(false),
                Nvme = await e.ReadAsync<List<NvmeRawData>>(ElevatedData.NvmeHealth, ct).ConfigureAwait(false),
                Smart = await e.ReadAsync<List<SmartRawData>>(ElevatedData.SmartData, ct).ConfigureAwait(false),
            };
        }
        return DiskAnalyzer.Analyze(snapshot);
    }

    [SupportedOSPlatform("windows")]
    public static DiskModule ForWindows() => new(DiskReader.ReadDisks);
}

[SupportedOSPlatform("windows")]
public static partial class DiskReader
{
    private const string Storage = @"root\Microsoft\Windows\Storage";

    public static IReadOnlyList<PhysicalDiskInfo>? ReadDisks()
    {
        var rows = Wmi.TryQuery(Storage,
            "SELECT DeviceId, FriendlyName, SerialNumber, BusType, MediaType, HealthStatus, OperationalStatus, Size FROM MSFT_PhysicalDisk");
        return rows?.Select(r => new PhysicalDiskInfo(
            r.Str("DeviceId") ?? "?",
            r.Str("FriendlyName") ?? "?",
            r.Str("SerialNumber")?.Trim(),
            (int)(r.Long("BusType") ?? 0),
            (int)(r.Long("MediaType") ?? 0),
            (int?)r.Long("HealthStatus"),
            r.TryGetValue("OperationalStatus", out var os) && os is ushort[] arr ? arr.Select(x => (int)x).ToArray() : [],
            r.Long("Size") ?? 0)).ToList();
    }

    /// <summary>Administrator only (Broker). VERIFY: DeviceId on the counter matches MSFT_PhysicalDisk.DeviceId.</summary>
    public static List<ReliabilityCounters> ReadReliability()
    {
        var rows = Wmi.TryQuery(Storage,
            "SELECT DeviceId, Temperature, TemperatureMax, Wear, ReadErrorsTotal, ReadErrorsUncorrected, WriteErrorsTotal, " +
            "WriteErrorsUncorrected, ReadLatencyMax, WriteLatencyMax, PowerOnHours FROM MSFT_StorageReliabilityCounter") ?? [];
        return rows.Select(r => new ReliabilityCounters(
            r.Str("DeviceId") ?? "?",
            (int?)r.Long("Temperature"),
            (int?)r.Long("TemperatureMax"),
            (int?)r.Long("Wear"),
            r.Long("ReadErrorsTotal"),
            r.Long("ReadErrorsUncorrected"),
            r.Long("WriteErrorsTotal"),
            r.Long("WriteErrorsUncorrected"),
            r.Long("ReadLatencyMax"),
            r.Long("WriteLatencyMax"),
            r.Long("PowerOnHours"))).ToList();
    }

    /// <summary>Administrator only (Broker): NVMe log page 0x02 and Identify Controller per NVMe disk.</summary>
    public static List<NvmeRawData> ReadNvme()
    {
        var result = new List<NvmeRawData>();
        foreach (var d in ReadDisks() ?? [])
        {
            if (!d.IsNvme || !int.TryParse(d.DeviceId, NumberStyles.Integer, CultureInfo.InvariantCulture, out var n))
            {
                continue;
            }
            using var handle = CreateFileW($@"\\.\PhysicalDrive{n}", GENERIC_READ | GENERIC_WRITE,
                FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
            if (handle.IsInvalid)
            {
                continue;
            }
            var log = Query(handle, NvmeQuery.DataTypeLogPage, NvmeQuery.NvmeLogPageHealthInfo, NvmeHealthLog.Size);
            byte[]? identify = null;
            try
            {
                identify = Query(handle, NvmeQuery.DataTypeIdentify, NvmeQuery.NvmeIdentifyCnsController, 4096);
            }
            catch (Win32Exception)
            {
                // Thresholds are optional; the temperature check is skipped without them.
            }
            result.Add(new NvmeRawData(d.DeviceId, log, identify));
        }
        return result;
    }

    /// <summary>Administrator only (Broker). VERIFY: InstanceName ↔ disk mapping is by PNP device path.</summary>
    public static List<SmartRawData> ReadSmart() =>
        (Wmi.TryQuery(@"root\wmi", "SELECT InstanceName, VendorSpecific FROM MSStorageDriver_FailurePredictData") ?? [])
        .Where(r => r.TryGetValue("VendorSpecific", out var v) && v is byte[])
        .Select(r => new SmartRawData(r.Str("InstanceName") ?? "?", (byte[])r["VendorSpecific"]!))
        .ToList();

    private static byte[] Query(SafeFileHandle handle, int dataType, int value, int length)
    {
        var input = NvmeQuery.BuildRequest(dataType, value, length);
        var output = new byte[input.Length];
        if (!DeviceIoControl(handle, NvmeQuery.IoctlStorageQueryProperty, input, input.Length, output, output.Length, out _, IntPtr.Zero))
        {
            throw new Win32Exception();
        }
        return NvmeQuery.ExtractPayload(output, length);
    }

    private const uint GENERIC_READ = 0x80000000;
    private const uint GENERIC_WRITE = 0x40000000;
    private const uint FILE_SHARE_READ = 1;
    private const uint FILE_SHARE_WRITE = 2;
    private const uint OPEN_EXISTING = 3;

    [LibraryImport("kernel32.dll", SetLastError = true, StringMarshalling = StringMarshalling.Utf16)]
    private static partial SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security,
        uint disposition, uint flags, IntPtr template);

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool DeviceIoControl(SafeFileHandle device, uint code, byte[] input, int inputSize,
        byte[] output, int outputSize, out int returned, IntPtr overlapped);
}
