using System.Buffers.Binary;
using PcDoctor.Core.Findings;
using PcDoctor.Modules.Disk;
using Xunit;

namespace PcDoctor.Tests.Modules;

public sealed class DiskTests
{
    internal static byte[] HealthLog(byte warning = 0, int kelvin = 310, int spare = 100, int threshold = 10, int used = 3,
        ulong mediaErrors = 0, UInt128? written = null)
    {
        var log = new byte[512];
        log[0] = warning;
        BinaryPrimitives.WriteUInt16LittleEndian(log.AsSpan(1), (ushort)kelvin);
        log[3] = (byte)spare;
        log[4] = (byte)threshold;
        log[5] = (byte)used;
        BinaryPrimitives.WriteUInt128LittleEndian(log.AsSpan(48), written ?? 20_000_000);
        BinaryPrimitives.WriteUInt128LittleEndian(log.AsSpan(128), 8_760);
        BinaryPrimitives.WriteUInt128LittleEndian(log.AsSpan(160), mediaErrors);
        return log;
    }

    [Fact]
    public void Nvme_log_parses_kelvin_and_128_bit_counters()
    {
        var huge = (UInt128.One << 70) + 5;
        var log = NvmeHealthLog.Parse(HealthLog(kelvin: 318, written: huge));
        Assert.Equal(318, log.CompositeTemperatureKelvin);
        Assert.Equal(45, log.CompositeTemperatureCelsius);
        Assert.Equal(huge, log.DataUnitsWritten);
        Assert.Equal(huge * 512_000, log.BytesWritten);
        Assert.Equal((UInt128)8_760, log.PowerOnHours);
    }

    [Fact]
    public void Nvme_request_and_response_layout_round_trips()
    {
        var request = NvmeQuery.BuildRequest(NvmeQuery.DataTypeLogPage, NvmeQuery.NvmeLogPageHealthInfo, 512);
        Assert.Equal(8 + 40 + 512, request.Length);
        Assert.Equal(50, BinaryPrimitives.ReadInt32LittleEndian(request)); // StorageDeviceProtocolSpecificProperty
        Assert.Equal(3, BinaryPrimitives.ReadInt32LittleEndian(request.AsSpan(8))); // ProtocolTypeNvme
        Assert.Equal(40, BinaryPrimitives.ReadInt32LittleEndian(request.AsSpan(8 + 16))); // ProtocolDataOffset

        // Simulate the driver: descriptor { Version=48, Size=48, protocol data }, payload at 8 + offset.
        var output = (byte[])request.Clone();
        BinaryPrimitives.WriteInt32LittleEndian(output, 48);
        BinaryPrimitives.WriteInt32LittleEndian(output.AsSpan(4), 48);
        HealthLog(used: 42).CopyTo(output, 48);

        Assert.Equal(42, NvmeHealthLog.Parse(NvmeQuery.ExtractPayload(output, 512)).PercentageUsed);
        output[0] = 0;
        Assert.Throws<InvalidDataException>(() => NvmeQuery.ExtractPayload(output, 512));
    }

    [Fact]
    public void Identify_thresholds_are_read_from_bytes_266_to_269()
    {
        var id = new byte[4096];
        BinaryPrimitives.WriteUInt16LittleEndian(id.AsSpan(266), 357);
        BinaryPrimitives.WriteUInt16LittleEndian(id.AsSpan(268), 361);
        Assert.Equal(new NvmeThresholds(357, 361), NvmeThresholds.Parse(id));
    }

    [Fact]
    public void Smart_attributes_parse_48_bit_raw_values()
    {
        var vs = new byte[512];
        void Attr(int slot, byte id, ulong raw)
        {
            var o = 2 + slot * 12;
            vs[o] = id;
            vs[o + 3] = 100;
            vs[o + 4] = 99;
            for (var b = 0; b < 6; b++)
            {
                vs[o + 5 + b] = (byte)(raw >> (8 * b));
            }
        }
        Attr(0, 9, 0x0000_1234_5678);
        Attr(1, 5, 8);
        var attrs = SmartAttributes.Parse(vs);
        Assert.Equal(0x0000_1234_5678ul, attrs.Single(a => a.Id == 9).Raw);
        Assert.Equal(8ul, attrs.Single(a => a.Id == 5).Raw);
    }

    private static readonly PhysicalDiskInfo Nvme = new("0", "Contoso NVMe 1TB", "SN1", PhysicalDiskInfo.BusNvme, 4, 0, [2], 1_000_000_000_000);

    [Fact]
    public void Healthy_drive_without_elevation_reports_what_was_not_checked()
    {
        var result = DiskAnalyzer.Analyze(new DiskSnapshot { Disks = [Nvme] });
        Assert.Empty(result.Findings);
        Assert.Contains(result.Checks, c => c.Id == "M7.health.0" && c.Status == CheckStatus.Pass);
        Assert.Contains(result.Checks, c => c.Id == "M7.reliability" && c.Status == CheckStatus.NotChecked);
        Assert.Contains(result.Checks, c => c.Id == "M7.nvme" && c.Status == CheckStatus.NotChecked);
        TextAssert.AllResolve(result);
    }

    [Fact]
    public void Nvme_critical_warning_and_media_errors_say_back_up()
    {
        var result = DiskAnalyzer.Analyze(new DiskSnapshot
        {
            Disks = [Nvme],
            Nvme = [new NvmeRawData("0", HealthLog(warning: 0x04, mediaErrors: 3, used: 85), null)],
            Reliability = [new ReliabilityCounters("0", 40, 70, 85, 0, 0, 0, 2, 12_000, 10, 8760)],
        });
        var critical = Assert.Single(result.Findings, f => f.Id == "M7.nvmeCritical.0");
        Assert.Equal(Severity.Critical, critical.Severity);
        Assert.Equal("m7.backupNow", critical.SuggestedAction.Key);
        Assert.Contains(result.Findings, f => f.Id == "M7.nvmeMedia.0");
        Assert.Contains(result.Findings, f => f.Id == "M7.nvmeWear.0");
        Assert.Contains(result.Findings, f => f.Id == "M7.uncorrected.0");
        Assert.Contains(result.Findings, f => f.Id == "M7.latency.0");
        TextAssert.AllResolve(result);
    }

    [Fact]
    public void Unhealthy_status_is_critical()
    {
        var result = DiskAnalyzer.Analyze(new DiskSnapshot { Disks = [Nvme with { HealthStatus = 2 }] });
        Assert.Equal(Severity.Critical, Assert.Single(result.Findings).Severity);
    }
}
