using PcDoctor.Core.Findings;
using PcDoctor.Core.Journal;

namespace PcDoctor.Core.Fixes;

/// <summary>A change set the Broker is allowed to apply, previewed to the user before consent.</summary>
public sealed record FixDefinition(
    string Id,
    Text Title,
    Text Explanation,
    IReadOnlyList<PlannedChange> Changes,
    bool RequiresRestart);

/// <summary>
/// The only changes the elevated Broker will make. The UI sends a fix ID, never a registry path,
/// so a process that reaches the pipe cannot turn the Broker into a general-purpose registry writer.
/// The catalog is compiled into the signed Broker binary.
/// </summary>
public static class FixCatalog
{
    private const string CrashControl = @"SYSTEM\CurrentControlSet\Control\CrashControl";

    public static IReadOnlyList<FixDefinition> All { get; } =
    [
        new FixDefinition(
            "crash.dumps.automatic",
            new Text("fix.dumpsAutomatic.title"),
            new Text("fix.dumpsAutomatic.explain"),
            [new PlannedRegistrySet("HKLM", CrashControl, "CrashDumpEnabled", new RegistryData("DWord", "7"))],
            RequiresRestart: true),
    ];

    public static FixDefinition? Find(string id) => All.FirstOrDefault(f => f.Id == id);
}
