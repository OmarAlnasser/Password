using System.Text.Json.Serialization;

namespace PcDoctor.Core.Journal;

/// <summary>
/// A change PC Doctor intends to make, shown to the user as a preview before consent. The Broker
/// turns it into a <see cref="JournalChange"/> by reading the current (old) state first.
/// </summary>
[JsonPolymorphic(TypeDiscriminatorPropertyName = "type")]
[JsonDerivedType(typeof(PlannedRegistrySet), "registrySet")]
[JsonDerivedType(typeof(PlannedRegistryDelete), "registryDelete")]
[JsonDerivedType(typeof(PlannedServiceStart), "serviceStart")]
public abstract record PlannedChange
{
    /// <summary>The exact target, for the consent preview (left-to-right, untranslated).</summary>
    public abstract string Describe();
}

/// <param name="Hive">HKLM or HKCU. HKCU means the signed-in user and is recorded as HKU\&lt;SID&gt;.</param>
public sealed record PlannedRegistrySet(string Hive, string Key, string ValueName, RegistryData Data) : PlannedChange
{
    public override string Describe() => $@"{Hive}\{Key}\{ValueName} = {Data.Encoded} ({Data.Kind})";
}

public sealed record PlannedRegistryDelete(string Hive, string Key, string ValueName) : PlannedChange
{
    public override string Describe() => $@"{Hive}\{Key}\{ValueName} (delete)";
}

/// <param name="StartType">Automatic, Manual or Disabled. Boot/System start types are never set.</param>
public sealed record PlannedServiceStart(string Service, string StartType, bool DelayedAutostart) : PlannedChange
{
    public override string Describe() =>
        $"Service {Service}: start = {StartType}{(DelayedAutostart ? " (delayed)" : "")}";
}
