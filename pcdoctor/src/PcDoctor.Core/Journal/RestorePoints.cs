namespace PcDoctor.Core.Journal;

public interface IRestorePointApi
{
    bool IsProtectionEnabled(string drive);
    /// <summary>Highest existing restore point sequence number, or null if there are none.</summary>
    uint? LatestSequenceNumber();
    void Create(string description);
    /// <summary>SystemRestorePointCreationFrequency in minutes; null if the value is absent (default 1440).</summary>
    int? ReadCreationFrequency();
    /// <summary>Writes the value, or deletes it when <paramref name="minutes"/> is null.</summary>
    void WriteCreationFrequency(int? minutes);
}

public enum RestorePointOutcome { Created, ProtectionOff, NotCreated, Error }

public sealed record RestorePointResult(RestorePointOutcome Outcome, uint? SequenceNumber, string? Detail);

/// <summary>
/// Creates a restore point and proves it exists. Windows skips creation silently if another point
/// was made in the last 24 hours, unless SystemRestorePointCreationFrequency is 0, so the frequency is
/// set to 0 for the call and restored to its original value (or absence) afterwards.
/// </summary>
public sealed class RestorePointGuard(IRestorePointApi api)
{
    public RestorePointResult CreateVerified(string description, string systemDrive = "C:\\")
    {
        if (!api.IsProtectionEnabled(systemDrive))
        {
            return new(RestorePointOutcome.ProtectionOff, null, systemDrive);
        }
        var before = api.LatestSequenceNumber();
        var originalFrequency = api.ReadCreationFrequency();
        try
        {
            if (originalFrequency != 0)
            {
                api.WriteCreationFrequency(0);
            }
            api.Create(description);
        }
        catch (Exception ex)
        {
            return new(RestorePointOutcome.Error, null, ex.Message);
        }
        finally
        {
            if (originalFrequency != 0)
            {
                api.WriteCreationFrequency(originalFrequency);
            }
        }
        var after = api.LatestSequenceNumber();
        return after is not null && (before is null || after > before)
            ? new(RestorePointOutcome.Created, after, null)
            : new(RestorePointOutcome.NotCreated, after, "Sequence number did not increase.");
    }
}
