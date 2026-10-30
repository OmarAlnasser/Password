using System.Text.Json.Serialization;

namespace PcDoctor.Core.Journal;

/// <summary>Registry value data as recorded in the journal. Kind is the RegistryValueKind name.</summary>
/// <remarks>
/// Encoding: String/ExpandString as-is, DWord/QWord as decimal, MultiString as values joined with
/// U+0000, Binary as lowercase hex.
/// </remarks>
public sealed record RegistryData(string Kind, string Encoded);

/// <summary>One atomic system change with everything needed to put it back exactly.</summary>
[JsonPolymorphic(TypeDiscriminatorPropertyName = "type")]
[JsonDerivedType(typeof(RegistryChange), "registry")]
[JsonDerivedType(typeof(ServiceChange), "service")]
[JsonDerivedType(typeof(TaskChange), "task")]
[JsonDerivedType(typeof(AppxChange), "appx")]
public abstract record JournalChange;

/// <param name="Hive">HKLM or HKU\&lt;SID&gt;. HKCU is resolved to the signed-in user's SID before
/// recording, because the elevated Broker's HKCU can belong to a different (admin) account.</param>
/// <param name="KeyExisted">False when applying the change created the key; undo removes it if empty.</param>
public sealed record RegistryChange(
    string Hive,
    string Key,
    string ValueName,
    bool Existed,
    bool KeyExisted,
    RegistryData? OldData,
    RegistryData? NewData) : JournalChange;

public sealed record ServiceChange(
    string Service,
    string OldStartType,
    bool OldDelayedAutostart,
    string NewStartType,
    bool NewDelayedAutostart) : JournalChange;

public sealed record TaskChange(string TaskPath, bool OldEnabled, bool NewEnabled) : JournalChange;

/// <summary>An app removal. Not automatically reversible; the reinstall ID is what makes it recoverable.</summary>
public sealed record AppxChange(
    string PackageFullName,
    bool WasProvisioned,
    string? WingetOrStoreId) : JournalChange;

public enum EntryState { Planned, Applied, Failed, Undone, UndoConflict }

public sealed record JournalEntry
{
    public required Guid Id { get; init; }
    public required Guid BatchId { get; init; }
    /// <summary>The catalog fix or tweak this change belongs to.</summary>
    public required string SourceId { get; init; }
    public required DateTimeOffset TimestampUtc { get; init; }
    public required EntryState State { get; init; }
    public required JournalChange Change { get; init; }
    public string? Note { get; init; }
}
