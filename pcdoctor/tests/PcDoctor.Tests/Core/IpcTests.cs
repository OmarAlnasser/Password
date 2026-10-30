using System.IO.Pipes;
using System.Text;
using System.Text.Json;
using PcDoctor.Core.Ipc;
using PcDoctor.Core.Journal;
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
        Assert.Equal(["ping", "fix.apply", "journal.undo", "journal.read", "read.elevated", "shutdown"], ops);
        // Requests carry IDs and enums, never paths, command lines or registry locations.
        foreach (var type in typeof(BrokerRequest).Assembly.GetTypes().Where(t => t.IsSubclassOf(typeof(BrokerRequest))))
        {
            Assert.All(type.GetProperties(), p =>
                Assert.DoesNotMatch("(?i)path|command|args|hive|key|exe|script", p.Name));
        }
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
