using System.Globalization;
using System.Runtime.Versioning;
using Microsoft.Win32;
using PcDoctor.Core.Journal;

namespace PcDoctor.Core.Platform;

[SupportedOSPlatform("windows")]
public sealed class WindowsRegistryAccess : IRegistryAccess
{
    public RegistryData? Read(string hive, string key, string valueName)
    {
        using var k = Root(hive).OpenSubKey(key, writable: false);
        if (k is null || !k.GetValueNames().Contains(valueName, StringComparer.OrdinalIgnoreCase))
        {
            return null;
        }
        var kind = k.GetValueKind(valueName);
        var value = k.GetValue(valueName, null, RegistryValueOptions.DoNotExpandEnvironmentNames);
        return Encode(kind, value);
    }

    public bool KeyExists(string hive, string key)
    {
        using var k = Root(hive).OpenSubKey(key, writable: false);
        return k is not null;
    }

    public void Write(string hive, string key, string valueName, RegistryData data)
    {
        using var k = Root(hive).CreateSubKey(key, writable: true);
        var (kind, value) = Decode(data);
        k.SetValue(valueName, value, kind);
    }

    public void DeleteValue(string hive, string key, string valueName)
    {
        using var k = Root(hive).OpenSubKey(key, writable: true);
        k?.DeleteValue(valueName, throwOnMissingValue: false);
    }

    public void DeleteKeyIfEmpty(string hive, string key)
    {
        using (var k = Root(hive).OpenSubKey(key, writable: false))
        {
            if (k is null || k.ValueCount > 0 || k.SubKeyCount > 0)
            {
                return;
            }
        }
        Root(hive).DeleteSubKey(key, throwOnMissingSubKey: false);
    }

    public static RegistryData Encode(RegistryValueKind kind, object? value) => kind switch
    {
        RegistryValueKind.DWord => new("DWord", unchecked((uint)(int)value!).ToString(CultureInfo.InvariantCulture)),
        RegistryValueKind.QWord => new("QWord", unchecked((ulong)(long)value!).ToString(CultureInfo.InvariantCulture)),
        RegistryValueKind.MultiString => new("MultiString", string.Join('\0', (string[])value!)),
        RegistryValueKind.Binary => new("Binary", Convert.ToHexString((byte[])value!).ToLowerInvariant()),
        RegistryValueKind.ExpandString => new("ExpandString", (string)value!),
        RegistryValueKind.String => new("String", (string)value!),
        _ => new(kind.ToString(), value is byte[] b ? Convert.ToHexString(b).ToLowerInvariant() : value?.ToString() ?? ""),
    };

    public static (RegistryValueKind Kind, object Value) Decode(RegistryData data) => data.Kind switch
    {
        "DWord" => (RegistryValueKind.DWord, unchecked((int)uint.Parse(data.Encoded, CultureInfo.InvariantCulture))),
        "QWord" => (RegistryValueKind.QWord, unchecked((long)ulong.Parse(data.Encoded, CultureInfo.InvariantCulture))),
        "MultiString" => (RegistryValueKind.MultiString, data.Encoded.Length == 0 ? Array.Empty<string>() : data.Encoded.Split('\0')),
        "Binary" => (RegistryValueKind.Binary, Convert.FromHexString(data.Encoded)),
        "ExpandString" => (RegistryValueKind.ExpandString, data.Encoded),
        "String" => (RegistryValueKind.String, data.Encoded),
        _ => throw new NotSupportedException($"Registry kind {data.Kind} is not supported for writing."),
    };

    private static RegistryKey Root(string hive)
    {
        if (hive.Equals("HKLM", StringComparison.OrdinalIgnoreCase))
        {
            return RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);
        }
        if (hive.StartsWith(@"HKU\", StringComparison.OrdinalIgnoreCase))
        {
            var users = RegistryKey.OpenBaseKey(RegistryHive.Users, RegistryView.Registry64);
            return users.OpenSubKey(hive[4..], writable: true)
                ?? throw new InvalidOperationException($"User hive {hive} is not loaded.");
        }
        throw new ArgumentException($"Unsupported hive {hive}; HKCU must be resolved to HKU\\<SID> first.");
    }
}
