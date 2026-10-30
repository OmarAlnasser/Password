using System.Text.Json;
using System.Text.Json.Serialization;
using PcDoctor.Core.Journal;

namespace PcDoctor.Core.Ipc;

/// <summary>
/// The complete list of things the elevated Broker can be asked to do. There is deliberately no
/// "run command" or "write registry path" request: changes go through <see cref="Fixes.FixCatalog"/> IDs.
/// An unknown "op" fails deserialization and is answered with <see cref="BrokerErrorCode.UnsupportedOperation"/>.
/// </summary>
[JsonPolymorphic(TypeDiscriminatorPropertyName = "op")]
[JsonDerivedType(typeof(PingRequest), "ping")]
[JsonDerivedType(typeof(ApplyFixRequest), "fix.apply")]
[JsonDerivedType(typeof(UndoRequest), "journal.undo")]
[JsonDerivedType(typeof(ReadJournalRequest), "journal.read")]
[JsonDerivedType(typeof(ReadElevatedRequest), "read.elevated")]
[JsonDerivedType(typeof(ShutdownRequest), "shutdown")]
public abstract record BrokerRequest
{
    public Guid RequestId { get; init; } = Guid.NewGuid();
}

public sealed record PingRequest : BrokerRequest;

public sealed record ApplyFixRequest(string FixId) : BrokerRequest;

public enum UndoScope { Entry, Batch, Everything }

public sealed record UndoRequest(UndoScope Scope, Guid? Id, bool Force) : BrokerRequest;

public sealed record ReadJournalRequest : BrokerRequest;

/// <summary>Read-only data that needs administrator rights (Deep Scan).</summary>
public enum ElevatedData
{
    StorageReliability,
    NvmeHealth,
    SmartData,
    Tpm,
    BitLocker,
}

public sealed record ReadElevatedRequest(ElevatedData Data) : BrokerRequest;

public sealed record ShutdownRequest : BrokerRequest;

public enum BrokerErrorCode
{
    None,
    UnsupportedOperation,
    UnknownFix,
    RestorePointFailed,
    ChangeFailed,
    NotAvailable,
    Internal,
}

public sealed record BrokerResponse
{
    public required Guid RequestId { get; init; }
    public BrokerErrorCode Error { get; init; }
    public string? ErrorDetail { get; init; }
    /// <summary>Typed payload as JSON (a <see cref="BatchResult"/>, journal entries, or a module snapshot).</summary>
    public JsonElement? Payload { get; init; }

    public bool Ok => Error == BrokerErrorCode.None;

    public T? PayloadAs<T>() => Payload is { } p ? p.Deserialize<T>(PipeFraming.JsonOptions) : default;

    public static BrokerResponse Success(Guid id, object? payload = null) => new()
    {
        RequestId = id,
        Payload = payload is null ? null : JsonSerializer.SerializeToElement(payload, payload.GetType(), PipeFraming.JsonOptions),
    };

    public static BrokerResponse Failure(Guid id, BrokerErrorCode code, string? detail = null) =>
        new() { RequestId = id, Error = code, ErrorDetail = detail };
}

/// <summary>Result of <see cref="ApplyFixRequest"/>.</summary>
public sealed record ApplyFixResult(RestorePointResult RestorePoint, BatchResult? Batch);
