using PcDoctor.Core.Journal;

namespace PcDoctor.Core.Platform;

/// <summary>Registry operations the journal needs. Hives: "HKLM" or "HKU\&lt;SID&gt;".</summary>
public interface IRegistryAccess
{
    RegistryData? Read(string hive, string key, string valueName);
    bool KeyExists(string hive, string key);
    void Write(string hive, string key, string valueName, RegistryData data);
    void DeleteValue(string hive, string key, string valueName);
    /// <summary>Deletes the key only if it has no values and no subkeys.</summary>
    void DeleteKeyIfEmpty(string hive, string key);
}

public interface IServiceConfigAccess
{
    /// <summary>Null if the service does not exist.</summary>
    (string StartType, bool Delayed)? Read(string service);
    void Write(string service, string startType, bool delayed);
}
