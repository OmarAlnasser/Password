namespace PcDoctor.Modules.Disk;

public sealed record SmartAttribute(byte Id, byte Current, byte Worst, ulong Raw);

/// <summary>
/// ATA SMART attribute table as returned in MSStorageDriver_FailurePredictData.VendorSpecific:
/// 2-byte revision, then 30 entries of 12 bytes { id, flags[2], current, worst, raw[6], reserved }.
/// </summary>
public static class SmartAttributes
{
    public const byte Reallocated = 5;
    public const byte UncorrectableReported = 187;
    public const byte Pending = 197;
    public const byte OfflineUncorrectable = 198;

    public static IReadOnlyList<SmartAttribute> Parse(ReadOnlySpan<byte> vendorSpecific)
    {
        var result = new List<SmartAttribute>();
        for (var i = 0; i < 30; i++)
        {
            var offset = 2 + i * 12;
            if (offset + 12 > vendorSpecific.Length)
            {
                break;
            }
            var entry = vendorSpecific.Slice(offset, 12);
            if (entry[0] == 0)
            {
                continue;
            }
            ulong raw = 0;
            for (var b = 0; b < 6; b++)
            {
                raw |= (ulong)entry[5 + b] << (8 * b);
            }
            result.Add(new SmartAttribute(entry[0], entry[3], entry[4], raw));
        }
        return result;
    }
}
