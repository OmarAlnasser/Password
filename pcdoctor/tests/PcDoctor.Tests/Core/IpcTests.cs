using System.IO.Pipes;
using System.Text;
using System.Text.Json;
using PcDoctor.Core.Ipc;
using PcDoctor.Core.Journal;
using PcDoctor.Core.Platform;
using Xunit;

namespace PcDoctor.Tests.Core;

public sealed class IpcTests : IDisposable
{
    private readonly string _dir = Directory.CreateTempSubdirectory("pcdoctor-ipc-").FullName;
    private readonly FakeRegistry _registry = new();
    private readonly FakeRestorePoints _restorePoints = new();

    public void Dispose() => Directory.Delete(_dir, recursive: true);

    private BrokerRequestHandler Handler(out ChangeJournal journal)
    {
        journal = new ChangeJournal(Path.Combine(_dir, "journal.jsonl"));
        var executor = new ChangeExecutor(journal, new RegistryApplier(_registry, h => h), null);
        return new BrokerRequestHandler(executor, journal, new RestorePointGuard(_restorePoints),
            d => d == ElevatedData.Tpm ? new { Present = true } : null);
    }

    [Fact]
    public async Task Frames_round_trip()
    {
        using var stream = new MemoryStream();
        await PipeFraming.WriteAsync<BrokerRequest>(stream, new ApplyFixRequest("crash.dumps.automatic"), CancellationToken.None);
        stream.Position = 0;

        var frame = await PipeFraming.ReadFrameAsync(stream, CancellationToken.None);
        var request = PipeFraming.TryParseRequest(frame!, out _);

        Assert.Equal("crash.dumps.automatic", Assert.IsType<ApplyFixRequest>(request).FixId);
        Assert.Null(await PipeFraming.ReadFrameAsync(stream, CancellationToken.None));
    }

    [Theory]
    [InlineData("{\"op\":\"run\",\"command\":\"cmd /c whoami\"}")]
    [InlineData("{\"op\":\"registry.write\",\"hive\":\"HKLM\"}")]
    [InlineData("{\"command\":\"x\"}")]
    [InlineData("not json")]
    public async Task Anything_but_a_known_typed_request_is_refused(string json)
    {
        var handler = Handler(out _);
        using var stream = new MemoryStream();
        var body = Encoding.UTF8.GetBytes(json);
        stream.Write(BitConverter.GetBytes(body.Length));
        stream.Write(body);
        stream.Position = 0;
        var output = new MemoryStream();

        await handler.ServeOneAsync(new DuplexStream(stream, output), CancellationToken.None);
        output.Position = 0;
        var response = await PipeFraming.ReadAsync<BrokerResponse>(output, CancellationToken.None);

        Assert.Equal(BrokerErrorCode.UnsupportedOperation, response!.Error);
        Assert.Empty(_registry.Keys);
    }

    [Fact]
    public async Task Oversized_frame_is_rejected()
    {
        using var stream = new MemoryStream(BitConverter.GetBytes(PipeFraming.MaxMessageBytes + 1));
        await Assert.ThrowsAsync<InvalidDataException>(() => PipeFraming.ReadFrameAsync(stream, CancellationToken.None));
    }

    [Fact]
    public void Protocol_has_no_generic_command_or_path_operation()
    {
        var ops = typeof(BrokerRequest).GetCustomAttributes(typeof(System.Text.Json.Serialization.JsonDerivedTypeAttribute), false)
            .Cast<System.Text.Json.Serialization.JsonDerivedTypeAttribute>()
            .Select(a => (string)a.TypeDiscriminator!)
            .ToList();
        Assert.Equal(
        [
            "ping", "fix.apply", "journal.undo", "journal.read", "read.elevated", "shutdown",
            "job.start", "job.status", "job.cancel", "defender.quarantine.list", "defender.quarantine.restore",
            "autorun.disable", "tweak.apply",
        ], ops);
        // Requests carry IDs and enums, never command lines or registry locations. The two exceptions
        // carry a file path that only ever reaches Defender: a custom scan target (read-only for PC
        // Doctor), and a quarantined item that the Broker re-checks against Defender's own list.
        var allowed = new HashSet<string> { "JobStartRequest.Target", "QuarantineRestoreRequest.FilePath" };
        foreach (var type in typeof(BrokerRequest).Assembly.GetTypes().Where(t => t.IsSubclassOf(typeof(BrokerRequest))))
        {
            Assert.All(type.GetProperties().Where(p => !allowed.Contains($"{type.Name}.{p.Name}")), p =>
                Assert.DoesNotMatch("(?i)path|command|args|hive|key|exe|script|target", p.Name));
        }
    }

    [Fact]
    public async Task Jobs_run_in_the_background_and_report_their_result()
    {
        var gate = new TaskCompletionSource();
        var jobs = new JobRunner(async (kind, target, progress, ct) =>
        {
            progress.Report(0.5, "half");
            await gate.Task.WaitAsync(ct);
            return new { Kind = kind.ToString(), Target = target };
        });
        var journal = new ChangeJournal(Path.Combine(_dir, "j.jsonl"));
        var handler = new BrokerRequestHandler(new ChangeExecutor(journal, [], null), journal, new RestorePointGuard(_restorePoints),
            _ => null, new BrokerCapabilities { Jobs = jobs });

        var start = handler.Handle(new JobStartRequest(JobKind.DefenderCustomReportOnly, @"C:\Users\me\Downloads"));
        var id = start.PayloadAs<Guid>();
        var running = handler.Handle(new JobStatusRequest(id)).PayloadAs<JobStatus>()!;
        Assert.Equal(JobState.Running, running.State);
        Assert.True(handler.HasRunningJobs);

        gate.SetResult();
        JobStatus? done = null;
        for (var i = 0; i < 100 && done?.State != JobState.Succeeded; i++)
        {
            await Task.Delay(20);
            done = handler.Handle(new JobStatusRequest(id)).PayloadAs<JobStatus>();
        }
        Assert.Equal(JobState.Succeeded, done!.State);
        Assert.Equal("DefenderCustomReportOnly", done.Result!.Value.GetProperty("kind").GetString());
    }

    [Fact]
    public void Cancelled_job_reports_cancelled_and_servicing_jobs_do_not_overlap()
    {
        var jobs = new JobRunner(async (_, _, _, ct) =>
        {
            await Task.Delay(Timeout.Infinite, ct);
            return null;
        });
        var id = jobs.Start(JobKind.DismScanHealth, null);
        Assert.Throws<InvalidOperationException>(() => jobs.Start(JobKind.Sfc, null));
        Assert.True(jobs.Cancel(id));
        SpinWait.SpinUntil(() => jobs.Status(id)!.State != JobState.Running, 2000);
        Assert.Equal(JobState.Cancelled, jobs.Status(id)!.State);
    }

    [Fact]
    public void Autorun_disable_goes_through_restore_point_and_journal_and_refuses_unknown_ids()
    {
        _registry.Write("HKLM", @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run", "Contoso", new RegistryData("String", "c:\\x.exe"));
        var journal = new ChangeJournal(Path.Combine(_dir, "a.jsonl"));
        var handler = new BrokerRequestHandler(new ChangeExecutor(journal, new RegistryApplier(_registry, h => h), null), journal,
            new RestorePointGuard(_restorePoints), _ => null, new BrokerCapabilities
            {
                ResolveAutorunDisable = id => id == "run:contoso"
                    ?
                    [
                        new PlannedRegistrySet("HKLM", @"SOFTWARE\PCDoctor\DisabledAutoruns\Run", "Contoso", new RegistryData("String", "c:\\x.exe")),
                        new PlannedRegistryDelete("HKLM", @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run", "Contoso"),
                    ]
                    : null,
            });

        Assert.Equal(BrokerErrorCode.UnknownFix, handler.Handle(new AutorunDisableRequest("HKLM\\SOFTWARE\\anything")).Error);
        var ok = handler.Handle(new AutorunDisableRequest("run:contoso"));

        Assert.True(ok.Ok, ok.ErrorDetail);
        Assert.Null(_registry.Read("HKLM", @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run", "Contoso"));
        Assert.Equal(2, journal.ReadCurrent().Count);
    }

    [Fact]
    public void Unknown_fix_is_refused()
    {
        var response = Handler(out _).Handle(new ApplyFixRequest("registry.anything"));
        Assert.Equal(BrokerErrorCode.UnknownFix, response.Error);
    }

    [Fact]
    public void Fix_is_not_applied_without_a_verified_restore_point()
    {
        _restorePoints.SilentlySkip = true;
        _registry.Write("HKLM", @"SYSTEM\CurrentControlSet\Control\CrashControl", "CrashDumpEnabled", new RegistryData("DWord", "0"));

        var response = Handler(out var journal).Handle(new ApplyFixRequest("crash.dumps.automatic"));

        Assert.Equal(BrokerErrorCode.RestorePointFailed, response.Error);
        Assert.Equal("0", _registry.Read("HKLM", @"SYSTEM\CurrentControlSet\Control\CrashControl", "CrashDumpEnabled")!.Encoded);
        Assert.Empty(journal.ReadCurrent());
    }

    [Fact]
    public void Fix_applies_with_restore_point_and_journal_and_undoes()
    {
        _registry.Write("HKLM", @"SYSTEM\CurrentControlSet\Control\CrashControl", "CrashDumpEnabled", new RegistryData("DWord", "0"));
        var handler = Handler(out var journal);

        var response = handler.Handle(new ApplyFixRequest("crash.dumps.automatic"));

        Assert.True(response.Ok, response.ErrorDetail);
        var payload = response.PayloadAs<ApplyFixResult>()!;
        Assert.Equal(RestorePointOutcome.Created, payload.RestorePoint.Outcome);
        Assert.Equal("7", _registry.Read("HKLM", @"SYSTEM\CurrentControlSet\Control\CrashControl", "CrashDumpEnabled")!.Encoded);
        Assert.Single(journal.ReadCurrent());

        var undo = handler.Handle(new UndoRequest(UndoScope.Batch, payload.Batch!.BatchId, false)).PayloadAs<UndoResult>()!;
        Assert.Equal(1, undo.Undone);
        Assert.Equal("0", _registry.Read("HKLM", @"SYSTEM\CurrentControlSet\Control\CrashControl", "CrashDumpEnabled")!.Encoded);
    }

    [Fact]
    public async Task Request_and_response_cross_a_real_named_pipe()
    {
        var handler = Handler(out _);
        var name = "PCDoctor.Test." + Guid.NewGuid().ToString("N");
        await using var server = new NamedPipeServerStream(name, PipeDirection.InOut, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous);
        await using var client = new NamedPipeClientStream(".", name, PipeDirection.InOut, PipeOptions.Asynchronous);
        var accept = server.WaitForConnectionAsync();
        await client.ConnectAsync(5000);
        await accept;

        var serve = handler.ServeOneAsync(server, CancellationToken.None);
        await PipeFraming.WriteAsync<BrokerRequest>(client, new ReadElevatedRequest(ElevatedData.Tpm), CancellationToken.None);
        var response = await PipeFraming.ReadAsync<BrokerResponse>(client, CancellationToken.None);
        await serve;

        Assert.True(response!.Ok);
        Assert.True(response.Payload!.Value.GetProperty("present").GetBoolean());
    }

    /// <summary>Reads from one stream and writes to another.</summary>
    private sealed class DuplexStream(Stream input, Stream output) : Stream
    {
        public override bool CanRead => true;
        public override bool CanSeek => false;
        public override bool CanWrite => true;
        public override long Length => throw new NotSupportedException();
        public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }
        public override void Flush() => output.Flush();
        public override int Read(byte[] buffer, int offset, int count) => input.Read(buffer, offset, count);
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => output.Write(buffer, offset, count);
    }
}
