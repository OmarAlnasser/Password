namespace PcDoctor.Core.Journal;

public sealed record BatchResult(Guid BatchId, bool Succeeded, IReadOnlyList<JournalEntry> Entries, string? Error);

public sealed record UndoResult(int Undone, int Conflicts, int Failed, IReadOnlyList<JournalEntry> Entries);

/// <summary>
/// Applies planned changes with a write-ahead journal and reverts them. Never applies a change kind
/// it cannot also undo: every planned change is captured before the first one is applied.
/// </summary>
public sealed class ChangeExecutor(
    ChangeJournal journal,
    RegistryApplier? registry,
    ServiceApplier? services,
    TimeProvider? clock = null)
{
    private readonly TimeProvider _clock = clock ?? TimeProvider.System;

    private IEnumerable<IChangeApplier> Appliers =>
        new IChangeApplier?[] { registry, services }.OfType<IChangeApplier>();

    public BatchResult ApplyBatch(string sourceId, IReadOnlyList<PlannedChange> planned)
    {
        var batchId = Guid.NewGuid();
        var captured = new List<JournalChange>();
        try
        {
            foreach (var p in planned)
            {
                captured.Add(p switch
                {
                    PlannedRegistrySet or PlannedRegistryDelete when registry is not null => registry.Capture(p),
                    PlannedServiceStart s when services is not null => services.Capture(s),
                    _ => throw new NotSupportedException($"No reversible applier for {p.GetType().Name}."),
                });
            }
        }
        catch (Exception ex)
        {
            return new BatchResult(batchId, false, [], ex.Message);
        }

        var done = new List<JournalEntry>();
        foreach (var change in captured)
        {
            var entry = new JournalEntry
            {
                Id = Guid.NewGuid(),
                BatchId = batchId,
                SourceId = sourceId,
                TimestampUtc = _clock.GetUtcNow(),
                State = EntryState.Planned,
                Change = change,
            };
            journal.Append(entry);
            try
            {
                ApplierFor(change).Apply(change);
            }
            catch (Exception ex)
            {
                journal.Append(entry with { State = EntryState.Failed, TimestampUtc = _clock.GetUtcNow(), Note = ex.Message });
                // Leave the system as it was before the batch.
                Undo(done, force: false);
                return new BatchResult(batchId, false, done, ex.Message);
            }
            var applied = entry with { State = EntryState.Applied, TimestampUtc = _clock.GetUtcNow() };
            journal.Append(applied);
            done.Add(applied);
        }
        return new BatchResult(batchId, true, done, null);
    }

    public UndoResult UndoEntry(Guid entryId, bool force = false) =>
        Undo(journal.ReadCurrent().Where(e => e.Id == entryId).ToList(), force);

    public UndoResult UndoBatch(Guid batchId, bool force = false) =>
        Undo(journal.ReadCurrent().Where(e => e.BatchId == batchId).ToList(), force);

    /// <summary>"Undo everything PC Doctor ever did", newest first.</summary>
    public UndoResult UndoAll(bool force = false) => Undo(journal.ReadCurrent().ToList(), force);

    private UndoResult Undo(IReadOnlyList<JournalEntry> entries, bool force)
    {
        int undone = 0, conflicts = 0, failed = 0;
        var results = new List<JournalEntry>();
        foreach (var entry in entries.Where(e => e.State is EntryState.Applied or EntryState.UndoConflict).Reverse())
        {
            var applier = ApplierFor(entry.Change);
            JournalEntry next;
            if (!force && !applier.IsStillApplied(entry.Change))
            {
                // Someone (Windows Update, the user, another tool) changed it since. Do not clobber.
                next = entry with { State = EntryState.UndoConflict, TimestampUtc = _clock.GetUtcNow() };
                conflicts++;
            }
            else
            {
                try
                {
                    applier.Revert(entry.Change);
                    next = entry with { State = EntryState.Undone, TimestampUtc = _clock.GetUtcNow(), Note = null };
                    undone++;
                }
                catch (Exception ex)
                {
                    next = entry with { TimestampUtc = _clock.GetUtcNow(), Note = ex.Message };
                    failed++;
                }
            }
            journal.Append(next);
            results.Add(next);
        }
        return new UndoResult(undone, conflicts, failed, results);
    }

    private IChangeApplier ApplierFor(JournalChange change) =>
        Appliers.FirstOrDefault(a => a.CanHandle(change))
        ?? throw new NotSupportedException($"No applier for {change.GetType().Name}.");
}
