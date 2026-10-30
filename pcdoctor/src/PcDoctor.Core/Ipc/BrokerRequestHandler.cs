using PcDoctor.Core.Fixes;
using PcDoctor.Core.Journal;

namespace PcDoctor.Core.Ipc;

/// <summary>
/// The Broker's dispatch logic, kept free of Windows APIs so it can be tested. Every request type
/// maps to one typed operation; there is no generic path.
/// </summary>
public sealed class BrokerRequestHandler(
    ChangeExecutor executor,
    ChangeJournal journal,
    RestorePointGuard restorePoints,
    Func<ElevatedData, object?> readElevated)
{
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
                _ => BrokerResponse.Failure(request.RequestId, BrokerErrorCode.UnsupportedOperation),
            };
        }
        catch (Exception ex)
        {
            return BrokerResponse.Failure(request.RequestId, BrokerErrorCode.Internal, ex.GetType().Name + ": " + ex.Message);
        }
    }

    private BrokerResponse ApplyFix(ApplyFixRequest r)
    {
        if (FixCatalog.Find(r.FixId) is not { } fix)
        {
            return BrokerResponse.Failure(r.RequestId, BrokerErrorCode.UnknownFix, r.FixId);
        }
        // Safety rule: no change batch without a restore point that provably exists.
        var rp = restorePoints.CreateVerified($"PC Doctor: {fix.Id}");
        if (rp.Outcome != RestorePointOutcome.Created)
        {
            return new BrokerResponse
            {
                RequestId = r.RequestId,
                Error = BrokerErrorCode.RestorePointFailed,
                ErrorDetail = rp.Outcome + (rp.Detail is null ? "" : ": " + rp.Detail),
                Payload = BrokerResponse.Success(r.RequestId, new ApplyFixResult(rp, null)).Payload,
            };
        }
        var batch = executor.ApplyBatch(fix.Id, fix.Changes);
        var payload = new ApplyFixResult(rp, batch);
        return batch.Succeeded
            ? BrokerResponse.Success(r.RequestId, payload)
            : BrokerResponse.Failure(r.RequestId, BrokerErrorCode.ChangeFailed, batch.Error) with
            {
                Payload = BrokerResponse.Success(r.RequestId, payload).Payload,
            };
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
        return result is null
            ? BrokerResponse.Failure(r.RequestId, BrokerErrorCode.UnsupportedOperation, "Undo needs an ID for this scope.")
            : BrokerResponse.Success(r.RequestId, result);
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
        await PipeFraming.WriteAsync(pipe, response, ct).ConfigureAwait(false);
        return !ShutdownRequested;
    }
}
