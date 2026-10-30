namespace PcDoctor.Core.Journal;

/// <summary>Applies and reverts one kind of journal change. Implementations live where the platform API is.</summary>
public interface IChangeApplier
{
    bool CanHandle(JournalChange change);

    /// <summary>Applies the change. The change carries the old values captured by <see cref="Capture"/>.</summary>
    void Apply(JournalChange change);

    /// <summary>True if the system still holds what <see cref="Apply"/> wrote (nobody changed it since).</summary>
    bool IsStillApplied(JournalChange change);

    void Revert(JournalChange change);
}
