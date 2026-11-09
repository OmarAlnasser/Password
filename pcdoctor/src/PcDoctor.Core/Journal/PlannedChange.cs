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
[JsonDerivedType(typeof(PlannedTaskEnabled), "taskEnabled")]
[JsonDerivedType(typeof(PlannedFileMove), "fileMove")]
[JsonDerivedType(typeof(PlannedAppxRemove), "appxRemove")]
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

public sealed record PlannedTaskEnabled(string TaskPath, bool Enabled) : PlannedChange
{
    public override string Describe() => $"Scheduled task {TaskPath}: {(Enabled ? "enable" : "disable")}";
}

/// <summary>Moves a file aside (a startup shortcut into PC Doctor's backup folder) instead of deleting it.</summary>
public sealed record PlannedFileMove(string From, string To) : PlannedChange
{
    public override string Describe() => $"Move {From} → {To}";
}

/// <summary>Removes an app for all users and deprovisions it. Not reversible by PC Doctor; the Store ID makes it reinstallable.</summary>
public sealed record PlannedAppxRemove(string PackageFamilyPrefix, string StoreId) : PlannedChange
{
    public override string Describe() => $"Remove and deprovision {PackageFamilyPrefix} (reinstall: winget install --id {StoreId} -s msstore)";
}
