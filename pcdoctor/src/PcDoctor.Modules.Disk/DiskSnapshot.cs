namespace PcDoctor.Modules.Disk;

/// <summary>MSFT_PhysicalDisk (root\Microsoft\Windows\Storage). Readable without administrator rights.</summary>
public sealed record PhysicalDiskInfo(
    string DeviceId,
    string FriendlyName,
    string? SerialNumber,
    int BusType,
    int MediaType,
    int? HealthStatus,
    IReadOnlyList<int> OperationalStatus,
    long SizeBytes)
{
    public const int BusSata = 11;
    public const int BusNvme = 17;
    public const int BusUsb = 7;
    public const int BusRaid = 8;

    public bool IsNvme => BusType == BusNvme;
}

/// <summary>MSFT_StorageReliabilityCounter. Needs administrator rights. Null = not reported by this drive.</summary>
public sealed record ReliabilityCounters(
    string DeviceId,
    int? Temperature,
    int? TemperatureMax,
    int? Wear,
    long? ReadErrorsTotal,
    long? ReadErrorsUncorrected,
    long? WriteErrorsTotal,
    long? WriteErrorsUncorrected,
    long? ReadLatencyMaxMs,
    long? WriteLatencyMaxMs,
    long? PowerOnHours);

/// <summary>Raw NVMe log page 0x02 (512 bytes) and Identify Controller (4096 bytes) for one disk.</summary>
public sealed record NvmeRawData(string DeviceId, byte[] HealthLog, byte[]? IdentifyController);

/// <summary>MSStorageDriver_FailurePredictData (root\wmi). Needs administrator rights; SATA/ATA only.</summary>
public sealed record SmartRawData(string InstanceName, byte[] VendorSpecific);

public sealed record DiskSnapshot
{
    /// <summary>Null if the storage WMI namespace could not be read.</summary>
    public IReadOnlyList<PhysicalDiskInfo>? Disks { get; init; }
    /// <summary>Null = not read (Health Check without administrator rights).</summary>
    public IReadOnlyList<ReliabilityCounters>? Reliability { get; init; }
    public IReadOnlyList<NvmeRawData>? Nvme { get; init; }
    public IReadOnlyList<SmartRawData>? Smart { get; init; }
}
