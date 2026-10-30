using System.Buffers.Binary;

namespace PcDoctor.Modules.Disk;

/// <summary>
/// NVMe SMART / Health Information log page (log identifier 0x02), per the NVMe base specification
/// and NVME_HEALTH_INFO_LOG in nvme.h. Temperatures are Kelvin. Data units are thousands of
/// 512-byte units. 128-bit counters are little-endian.
/// </summary>
public sealed record NvmeHealthLog(
    byte CriticalWarning,
    int CompositeTemperatureKelvin,
    int AvailableSparePercent,
    int AvailableSpareThresholdPercent,
    int PercentageUsed,
    UInt128 DataUnitsRead,
    UInt128 DataUnitsWritten,
    UInt128 PowerCycles,
    UInt128 PowerOnHours,
    UInt128 UnsafeShutdowns,
    UInt128 MediaErrors,
    UInt128 ErrorLogEntries,
    uint WarningTempMinutes,
    uint CriticalTempMinutes)
{
    public const int Size = 512;

    [Flags]
    public enum Warning : byte
    {
        SpareBelowThreshold = 0x01,
        Temperature = 0x02,
        ReliabilityDegraded = 0x04,
        ReadOnly = 0x08,
        VolatileBackupFailed = 0x10,
        PersistentMemoryReadOnly = 0x20,
    }

    public Warning Warnings => (Warning)CriticalWarning;

    public int CompositeTemperatureCelsius => CompositeTemperatureKelvin - 273;

    public UInt128 BytesWritten => DataUnitsWritten * 512_000;

    public static NvmeHealthLog Parse(ReadOnlySpan<byte> log)
    {
        if (log.Length < Size)
        {
            throw new ArgumentException($"NVMe health log must be {Size} bytes, got {log.Length}.");
        }
        return new NvmeHealthLog(
            CriticalWarning: log[0],
            CompositeTemperatureKelvin: BinaryPrimitives.ReadUInt16LittleEndian(log[1..]),
            AvailableSparePercent: log[3],
            AvailableSpareThresholdPercent: log[4],
            PercentageUsed: log[5],
            DataUnitsRead: U128(log, 32),
            DataUnitsWritten: U128(log, 48),
            PowerCycles: U128(log, 112),
            PowerOnHours: U128(log, 128),
            UnsafeShutdowns: U128(log, 144),
            MediaErrors: U128(log, 160),
            ErrorLogEntries: U128(log, 176),
            WarningTempMinutes: BinaryPrimitives.ReadUInt32LittleEndian(log[192..]),
            CriticalTempMinutes: BinaryPrimitives.ReadUInt32LittleEndian(log[196..]));
    }

    private static UInt128 U128(ReadOnlySpan<byte> log, int offset) =>
        BinaryPrimitives.ReadUInt128LittleEndian(log.Slice(offset, 16));
}

/// <summary>WCTEMP / CCTEMP from Identify Controller (bytes 266–269, Kelvin; 0 = not reported).</summary>
public sealed record NvmeThresholds(int WarningKelvin, int CriticalKelvin)
{
    public static NvmeThresholds? Parse(ReadOnlySpan<byte> identify) =>
        identify.Length < 270
            ? null
            : new NvmeThresholds(BinaryPrimitives.ReadUInt16LittleEndian(identify[266..]),
                BinaryPrimitives.ReadUInt16LittleEndian(identify[268..]));
}

/// <summary>
/// Builds the IOCTL_STORAGE_QUERY_PROPERTY input for StorageDeviceProtocolSpecificProperty and
/// extracts the payload from the STORAGE_PROTOCOL_DATA_DESCRIPTOR output. Layout follows the
/// Microsoft "Working with NVMe drives" sample. VERIFY on hardware.
/// </summary>
public static class NvmeQuery
{
    public const uint IoctlStorageQueryProperty = 0x002D1400;
    private const int StorageDeviceProtocolSpecificProperty = 50;
    private const int PropertyStandardQuery = 0;
    private const int ProtocolTypeNvme = 3;
    public const int DataTypeIdentify = 1;
    public const int DataTypeLogPage = 2;
    public const int NvmeLogPageHealthInfo = 0x02;
    public const int NvmeIdentifyCnsController = 1;
    /// <summary>offsetof(STORAGE_PROPERTY_QUERY, AdditionalParameters)</summary>
    private const int QueryHeader = 8;
    /// <summary>sizeof(STORAGE_PROTOCOL_SPECIFIC_DATA): ten 32-bit fields.</summary>
    public const int ProtocolDataSize = 40;

    public static byte[] BuildRequest(int dataType, int requestValue, int length)
    {
        var buffer = new byte[QueryHeader + ProtocolDataSize + length];
        var s = buffer.AsSpan();
        BinaryPrimitives.WriteInt32LittleEndian(s[0..], StorageDeviceProtocolSpecificProperty);
        BinaryPrimitives.WriteInt32LittleEndian(s[4..], PropertyStandardQuery);
        var p = s[QueryHeader..];
        BinaryPrimitives.WriteInt32LittleEndian(p[0..], ProtocolTypeNvme);
        BinaryPrimitives.WriteInt32LittleEndian(p[4..], dataType);
        BinaryPrimitives.WriteInt32LittleEndian(p[8..], requestValue);
        BinaryPrimitives.WriteInt32LittleEndian(p[12..], 0); // ProtocolDataRequestSubValue
        BinaryPrimitives.WriteInt32LittleEndian(p[16..], ProtocolDataSize); // ProtocolDataOffset
        BinaryPrimitives.WriteInt32LittleEndian(p[20..], length); // ProtocolDataLength
        return buffer;
    }

    /// <summary>
    /// Output is STORAGE_PROTOCOL_DATA_DESCRIPTOR { Version, Size, ProtocolSpecificData }. Version
    /// and Size must both equal its size (8 + 40); the data starts at 8 + ProtocolDataOffset.
    /// </summary>
    public static byte[] ExtractPayload(ReadOnlySpan<byte> output, int expectedLength)
    {
        const int descriptor = QueryHeader + ProtocolDataSize;
        if (output.Length < descriptor ||
            BinaryPrimitives.ReadInt32LittleEndian(output) != descriptor ||
            BinaryPrimitives.ReadInt32LittleEndian(output[4..]) != descriptor)
        {
            throw new InvalidDataException("Unexpected STORAGE_PROTOCOL_DATA_DESCRIPTOR header.");
        }
        var offset = BinaryPrimitives.ReadInt32LittleEndian(output[(QueryHeader + 16)..]);
        var length = BinaryPrimitives.ReadInt32LittleEndian(output[(QueryHeader + 20)..]);
        if (offset < ProtocolDataSize || length < expectedLength || QueryHeader + offset + expectedLength > output.Length)
        {
            throw new InvalidDataException("NVMe payload outside the returned buffer.");
        }
        return output.Slice(QueryHeader + offset, expectedLength).ToArray();
    }
}
