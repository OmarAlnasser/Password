using System.Collections.Concurrent;
using System.Text.Json;

namespace PcDoctor.Core.Ipc;

/// <summary>Long-running elevated work (scans, repairs, inventory). Each kind is one fixed operation.</summary>
public enum JobKind
{
    DefenderSignatureUpdate,
    DefenderQuickScan,
    DefenderFullScan,
    /// <summary>Custom scan of <see cref="JobStartRequest.Target"/>, letting Defender remediate as usual.</summary>
    DefenderCustomScan,
    /// <summary>Custom scan of the target with -DisableRemediation: report only.</summary>
    DefenderCustomReportOnly,
    SafetyScannerQuick,
    SafetyScannerFull,
    Inventory,
    InventoryWithBackupPrivilege,
    DismCheckHealth,
    DismScanHealth,
    DismRestoreHealth,
    Sfc,
    ChkdskScan,
    /// <summary>Marks the system volume dirty so autochk repairs it at the next restart (chkdsk /f equivalent).</summary>
    ChkdskScheduleFix,
    /// <summary>Microsoft Defender Offline: restarts the PC into a scan outside Windows.</summary>
    DefenderOfflineScan,
    /// <summary>Expert: Driver Verifier standard checks on the named drivers (Target: space-separated .sys names).</summary>
    VerifierEnable,
    VerifierReset,
    MemoryDiagnostic,
    /// <summary>10-second kernel trace of DPC and ISR durations per driver.</summary>
    LatencyTrace,
}

public enum JobState { Running, Succeeded, Failed, Cancelled }

/// <summary>Progress and, when finished, the typed result as JSON.</summary>
public sealed record JobStatus(Guid JobId, JobKind Kind, JobState State, double? Progress, string? Message,
    DateTimeOffset StartedUtc, DateTimeOffset? FinishedUtc, JsonElement? Result);

/// <summary>What a running job can report back.</summary>
public interface IJobProgress
{
    void Report(double? fraction, string? message);
}

/// <summary>Runs jobs in the background inside the Broker so the pipe stays free for status and cancel requests.</summary>
public sealed class JobRunner(Func<JobKind, string?, IJobProgress, CancellationToken, Task<object?>> execute, TimeProvider? clock = null)
{
    private readonly ConcurrentDictionary<Guid, Entry> _jobs = new();
    private readonly TimeProvider _clock = clock ?? TimeProvider.System;

    private sealed class Entry(JobKind kind, DateTimeOffset started) : IJobProgress
    {
        public JobKind Kind { get; } = kind;
        public DateTimeOffset Started { get; } = started;
        public CancellationTokenSource Cts { get; } = new();
        public volatile JobState State = JobState.Running;
        public double? Progress;
        public string? Message;
        public DateTimeOffset? Finished;
        public JsonElement? Result;

        public void Report(double? fraction, string? message)
        {
            Progress = fraction is null ? null : Math.Clamp(fraction.Value, 0, 1);
            Message = message;
        }
    }

    public Guid Start(JobKind kind, string? target)
    {
        // One servicing job at a time: DISM and SFC share the TrustedInstaller lock.
        if (IsServicing(kind) && _jobs.Values.Any(j => j.State == JobState.Running && IsServicing(j.Kind)))
        {
            throw new InvalidOperationException("Another repair is already running.");
        }
        var id = Guid.NewGuid();
        var entry = new Entry(kind, _clock.GetUtcNow());
        _jobs[id] = entry;
        _ = Task.Run(async () =>
        {
            try
            {
                var result = await execute(kind, target, entry, entry.Cts.Token).ConfigureAwait(false);
                entry.Result = result is null ? null : JsonSerializer.SerializeToElement(result, result.GetType(), PipeFraming.JsonOptions);
                entry.State = JobState.Succeeded;
            }
            catch (OperationCanceledException)
            {
                entry.State = JobState.Cancelled;
            }
            catch (Exception ex)
            {
                entry.Message = ex.GetType().Name + ": " + ex.Message;
                entry.State = JobState.Failed;
            }
            finally
            {
                entry.Finished = _clock.GetUtcNow();
            }
        });
        return id;
    }

    public JobStatus? Status(Guid id) =>
        _jobs.TryGetValue(id, out var e)
            ? new JobStatus(id, e.Kind, e.State, e.Progress, e.Message, e.Started, e.Finished, e.Result)
            : null;

    public bool Cancel(Guid id)
    {
        if (!_jobs.TryGetValue(id, out var e) || e.State != JobState.Running)
        {
            return false;
        }
        e.Cts.Cancel();
        return true;
    }

    public bool AnyRunning => _jobs.Values.Any(j => j.State == JobState.Running);

    private static bool IsServicing(JobKind kind) => kind is JobKind.DismCheckHealth or JobKind.DismScanHealth or JobKind.DismRestoreHealth or JobKind.Sfc;
}
