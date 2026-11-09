using PcDoctor.Core.Fixes;
using PcDoctor.Core.Journal;

namespace PcDoctor.Core.Ipc;

/// <summary>
/// The Broker's dispatch logic, kept free of Windows APIs so it can be tested. Every request type
/// maps to one typed operation; there is no generic path.
/// </summary>
/// <summary>Optional Broker features, each one typed and fixed.</summary>
public sealed record BrokerCapabilities
{
    public JobRunner? Jobs { get; init; }
    public Func<object?>? ListQuarantine { get; init; }
    /// <summary>Restores one quarantined item named exactly as the list returned it; throws if it is not in the list.</summary>
    public Func<string, string?, object?>? RestoreQuarantine { get; init; }
    /// <summary>Re-enumerates persistence entries in the Broker and returns the changes that disable one, or null if the ID is unknown.</summary>
    public Func<string, IReadOnlyList<PlannedChange>?>? ResolveAutorunDisable { get; init; }
    /// <summary>Returns the changes for catalog tweak IDs, or null if any ID is unknown or does not apply.</summary>
    public Func<IReadOnlyList<string>, IReadOnlyList<PlannedChange>?>? ResolveTweaks { get; init; }
    /// <summary>Called after tweaks were applied successfully (records them for drift detection).</summary>
    public Action<IReadOnlyList<string>>? TweaksApplied { get; init; }
    /// <summary>Called after any undo, so records derived from the journal (the drift manifest) can be pruned.</summary>
    public Action? AfterUndo { get; init; }
}

public sealed class BrokerRequestHandler(
    ChangeExecutor executor,
    ChangeJournal journal,
    RestorePointGuard restorePoints,
    Func<ElevatedData, object?> readElevated,
    BrokerCapabilities? capabilities = null)
{
    private readonly BrokerCapabilities _caps = capabilities ?? new BrokerCapabilities();

    public bool ShutdownRequested { get; private set; }

    public BrokerResponse Handle(BrokerRequest request)
    {
        try
        {
            return request switch
            {
                PingRequest => BrokerResponse.Success(request.RequestId, "pong"),
                ApplyFixRequest r => ApplyFix(r),
                UndoRequest r => Undo(r),
                ReadJournalRequest => BrokerResponse.Success(request.RequestId, journal.ReadCurrent()),
                ReadElevatedRequest r => readElevated(r.Data) is { } data
                    ? BrokerResponse.Success(r.RequestId, data)
                    : BrokerResponse.Failure(r.RequestId, BrokerErrorCode.NotAvailable),
                ShutdownRequest => Shutdown(request),
                JobStartRequest r when _caps.Jobs is { } jobs => BrokerResponse.Success(r.RequestId, jobs.Start(r.Kind, r.Target)),
                JobStatusRequest r when _caps.Jobs is { } jobs => jobs.Status(r.JobId) is { } st
                    ? BrokerResponse.Success(r.RequestId, st)
                    : BrokerResponse.Failure(r.RequestId, BrokerErrorCode.NotAvailable),
                JobCancelRequest r when _caps.Jobs is { } jobs => BrokerResponse.Success(r.RequestId, jobs.Cancel(r.JobId)),
                QuarantineListRequest r when _caps.ListQuarantine is { } list => BrokerResponse.Success(r.RequestId, list()),
                QuarantineRestoreRequest r when _caps.RestoreQuarantine is { } restore =>
                    BrokerResponse.Success(r.RequestId, restore(r.ThreatName, r.FilePath)),
                AutorunDisableRequest r when _caps.ResolveAutorunDisable is { } resolve => resolve(r.EntryId) is { } changes
                    ? ApplyPlanned(r.RequestId, "autorun.disable:" + r.EntryId, changes)
                    : BrokerResponse.Failure(r.RequestId, BrokerErrorCode.UnknownFix, r.EntryId),
                TweakApplyRequest r when _caps.ResolveTweaks is { } tweaks => ApplyTweaks(r, tweaks),
                _ => BrokerResponse.Failure(request.RequestId, BrokerErrorCode.UnsupportedOperation),
            };
        }
        catch (Exception ex)
        {
            return BrokerResponse.Failure(request.RequestId, BrokerErrorCode.Internal, ex.GetType().Name + ": " + ex.Message);
        }
    }

    private BrokerResponse ApplyFix(ApplyFixRequest r) =>
        FixCatalog.Find(r.FixId) is { } fix
            ? ApplyPlanned(r.RequestId, fix.Id, fix.Changes)
            : BrokerResponse.Failure(r.RequestId, BrokerErrorCode.UnknownFix, r.FixId);

    /// <summary>Safety rule: no change batch without a restore point that provably exists, and every change journaled.</summary>
    private BrokerResponse ApplyPlanned(Guid requestId, string sourceId, IReadOnlyList<PlannedChange> changes)
    {
        var rp = restorePoints.CreateVerified($"PC Doctor: {sourceId}");
        if (rp.Outcome != RestorePointOutcome.Created)
        {
            return BrokerResponse.Failure(requestId, BrokerErrorCode.RestorePointFailed, rp.Outcome + (rp.Detail is null ? "" : ": " + rp.Detail)) with
            {
                Payload = BrokerResponse.Success(requestId, new ApplyFixResult(rp, null)).Payload,
            };
        }
        var batch = executor.ApplyBatch(sourceId, changes);
        var payload = BrokerResponse.Success(requestId, new ApplyFixResult(rp, batch)).Payload;
        return batch.Succeeded
            ? BrokerResponse.Success(requestId, new ApplyFixResult(rp, batch))
            : BrokerResponse.Failure(requestId, BrokerErrorCode.ChangeFailed, batch.Error) with { Payload = payload };
    }

    private BrokerResponse ApplyTweaks(TweakApplyRequest r, Func<IReadOnlyList<string>, IReadOnlyList<PlannedChange>?> resolve)
    {
        if (resolve(r.TweakIds) is not { } changes)
        {
            return BrokerResponse.Failure(r.RequestId, BrokerErrorCode.UnknownFix, string.Join(",", r.TweakIds));
        }
        if (changes.Count == 0)
        {
            // Everything is already in place: no restore point, nothing journaled.
            _caps.TweaksApplied?.Invoke(r.TweakIds);
            return BrokerResponse.Success(r.RequestId);
        }
        var response = ApplyPlanned(r.RequestId, "tweaks:" + string.Join(",", r.TweakIds), changes);
        if (response.Ok)
        {
            _caps.TweaksApplied?.Invoke(r.TweakIds);
        }
        return response;
    }

    private BrokerResponse Undo(UndoRequest r)
    {
        var result = r.Scope switch
        {
            UndoScope.Entry when r.Id is { } id => executor.UndoEntry(id, r.Force),
            UndoScope.Batch when r.Id is { } id => executor.UndoBatch(id, r.Force),
            UndoScope.Everything => executor.UndoAll(r.Force),
            _ => null,
        };
        if (result is null)
        {
            return BrokerResponse.Failure(r.RequestId, BrokerErrorCode.UnsupportedOperation, "Undo needs an ID for this scope.");
        }
        _caps.AfterUndo?.Invoke();
        return BrokerResponse.Success(r.RequestId, result);
    }

    private BrokerResponse Shutdown(BrokerRequest r)
    {
        ShutdownRequested = true;
        return BrokerResponse.Success(r.RequestId);
    }

    /// <summary>Reads one framed request, answers it, and returns false when the session should end.</summary>
    public async Task<bool> ServeOneAsync(Stream pipe, CancellationToken ct)
    {
        var frame = await PipeFraming.ReadFrameAsync(pipe, ct).ConfigureAwait(false);
        if (frame is null)
        {
            return false;
        }
        var request = PipeFraming.TryParseRequest(frame, out var id);
        var response = request is null
            ? BrokerResponse.Failure(id, BrokerErrorCode.UnsupportedOperation)
            : Handle(request);
        try
        {
            await PipeFraming.WriteAsync(pipe, response, ct).ConfigureAwait(false);
        }
        catch (InvalidDataException)
        {
            // Too large to send. The size check runs before anything is written, so the stream is still in sync.
            await PipeFraming.WriteAsync(pipe, BrokerResponse.Failure(response.RequestId, BrokerErrorCode.Internal, "Response too large."), ct).ConfigureAwait(false);
        }
        return !ShutdownRequested;
    }

    /// <summary>The Broker stays up while a job runs even if the idle timer fires.</summary>
    public bool HasRunningJobs => _caps.Jobs?.AnyRunning == true;
}
