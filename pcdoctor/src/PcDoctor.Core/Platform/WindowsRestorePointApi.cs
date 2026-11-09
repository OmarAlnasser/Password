using System.Management;
using System.Runtime.Versioning;
using Microsoft.Win32;
using PcDoctor.Core.Journal;

namespace PcDoctor.Core.Platform;

/// <summary>System Restore through WMI root\default. Needs administrator rights (Broker only).</summary>
[SupportedOSPlatform("windows")]
public sealed class WindowsRestorePointApi : IRestorePointApi
{
    private const string SrKey = @"SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore";
    private const string FrequencyValue = "SystemRestorePointCreationFrequency";
    private const int MODIFY_SETTINGS = 12;
    private const int BEGIN_SYSTEM_CHANGE = 100;

    public bool IsProtectionEnabled(string drive)
    {
        // VERIFY: SystemRestoreConfig / Enable state per drive is not exposed in WMI. RPSessionInterval=1
        // under the SPP client key is set when protection is on for at least one drive; a failed
        // Create() still reports honestly as NotCreated, so this is a first-pass hint only.
        using var key = Registry.LocalMachine.OpenSubKey(SrKey);
        if (key?.GetValue("DisableSR") is int disabled && disabled != 0)
        {
            return false;
        }
        return key?.GetValue("RPSessionInterval") is not int interval || interval != 0;
    }

    public uint? LatestSequenceNumber()
    {
        using var searcher = new ManagementObjectSearcher(@"root\default", "SELECT SequenceNumber FROM SystemRestore");
        uint? max = null;
        foreach (var o in searcher.Get())
        {
            using (o)
            {
                var n = Convert.ToUInt32(o["SequenceNumber"], System.Globalization.CultureInfo.InvariantCulture);
                max = max is null || n > max ? n : max;
            }
        }
        return max;
    }

    public void Create(string description)
    {
        using var sr = new ManagementClass(new ManagementScope(@"\\.\root\default"), new ManagementPath("SystemRestore"), null);
        using var input = sr.GetMethodParameters("CreateRestorePoint");
        input["Description"] = description;
        input["RestorePointType"] = MODIFY_SETTINGS;
        input["EventType"] = BEGIN_SYSTEM_CHANGE;
        using var output = sr.InvokeMethod("CreateRestorePoint", input, null);
        var rc = Convert.ToUInt32(output?["ReturnValue"] ?? 0u, System.Globalization.CultureInfo.InvariantCulture);
        if (rc != 0)
        {
            throw new InvalidOperationException($"CreateRestorePoint returned 0x{rc:X8}.");
        }
    }

    public int? ReadCreationFrequency()
    {
        using var key = Registry.LocalMachine.OpenSubKey(SrKey);
        return key?.GetValue(FrequencyValue) is int v ? v : null;
    }

    public void WriteCreationFrequency(int? minutes)
    {
        using var key = Registry.LocalMachine.CreateSubKey(SrKey, writable: true);
        if (minutes is null)
        {
            key.DeleteValue(FrequencyValue, throwOnMissingValue: false);
        }
        else
        {
            key.SetValue(FrequencyValue, minutes.Value, RegistryValueKind.DWord);
        }
    }
}
