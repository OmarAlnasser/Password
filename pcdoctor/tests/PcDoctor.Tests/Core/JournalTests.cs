using PcDoctor.Core.Journal;
using Xunit;

namespace PcDoctor.Tests.Core;

public sealed class JournalTests : IDisposable
{
    private readonly string _dir = Directory.CreateTempSubdirectory("pcdoctor-journal-").FullName;
    private readonly FakeRegistry _registry = new();
    private readonly FakeServices _services = new();

    public void Dispose() => Directory.Delete(_dir, recursive: true);

    private (ChangeExecutor Executor, ChangeJournal Journal) Create()
    {
        var journal = new ChangeJournal(Path.Combine(_dir, "journal.jsonl"));
        var executor = new ChangeExecutor(journal,
            new RegistryApplier(_registry, h => h == "HKCU" ? @"HKU\S-1-5-21-1-2-3-1001" : h),
            new ServiceApplier(_services));
        return (executor, journal);
    }

    private static readonly PlannedChange[] Batch =
    [
        new PlannedRegistrySet("HKLM", @"SYSTEM\CurrentControlSet\Control\CrashControl", "CrashDumpEnabled", new RegistryData("DWord", "7")),
        new PlannedRegistrySet("HKCU", @"Software\Contoso\New\Key", "Created", new RegistryData("String", "x")),
        new PlannedRegistryDelete("HKLM", @"SOFTWARE\Contoso", "Remove"),
        new PlannedServiceStart("SysMain", "Manual", false),
    ];

    private void Seed()
    {
        _registry.Write("HKLM", @"SYSTEM\CurrentControlSet\Control\CrashControl", "CrashDumpEnabled", new RegistryData("DWord", "0"));
        _registry.Write("HKLM", @"SOFTWARE\Contoso", "Remove", new RegistryData("MultiString", "a\0b"));
        _services.Services["SysMain"] = ("Automatic", true);
    }

    [Fact]
    public void Apply_then_undo_all_restores_exact_state()
    {
        Seed();
        var before = _registry.Export();
        var servicesBefore = _services.Services["SysMain"];
        var (executor, journal) = Create();

        var result = executor.ApplyBatch("test.batch", Batch);

        Assert.True(result.Succeeded, result.Error);
        Assert.Equal(4, result.Entries.Count);
        Assert.All(journal.ReadCurrent(), e => Assert.Equal(EntryState.Applied, e.State));
        Assert.Equal("7", _registry.Read("HKLM", @"SYSTEM\CurrentControlSet\Control\CrashControl", "CrashDumpEnabled")!.Encoded);
        // HKCU is recorded as the client's own hive, never the Broker's.
        Assert.NotNull(_registry.Read(@"HKU\S-1-5-21-1-2-3-1001", @"Software\Contoso\New\Key", "Created"));

        var undo = executor.UndoAll();

        Assert.Equal(4, undo.Undone);
        Assert.Equal(before, _registry.Export());
        Assert.Equal(servicesBefore, _services.Services["SysMain"]);
        Assert.All(journal.ReadCurrent(), e => Assert.Equal(EntryState.Undone, e.State));
    }

    [Fact]
    public void Journal_records_kind_old_and_new_data()
    {
        Seed();
        var (executor, journal) = Create();
        executor.ApplyBatch("test.batch", Batch);

        var reg = journal.ReadCurrent().Select(e => e.Change).OfType<RegistryChange>().First();
        Assert.Equal("HKLM", reg.Hive);
        Assert.True(reg.Existed);
        Assert.Equal(new RegistryData("DWord", "0"), reg.OldData);
        Assert.Equal(new RegistryData("DWord", "7"), reg.NewData);
        var created = journal.ReadCurrent().Select(e => e.Change).OfType<RegistryChange>().Single(c => c.ValueName == "Created");
        Assert.False(created.KeyExisted);
        var svc = journal.ReadCurrent().Select(e => e.Change).OfType<ServiceChange>().Single();
        Assert.Equal(("Automatic", true), (svc.OldStartType, svc.OldDelayedAutostart));
    }

    [Fact]
    public void Undo_does_not_clobber_values_changed_since()
    {
        Seed();
        var (executor, _) = Create();
        executor.ApplyBatch("test.batch", Batch);
        _registry.Write("HKLM", @"SYSTEM\CurrentControlSet\Control\CrashControl", "CrashDumpEnabled", new RegistryData("DWord", "3"));

        var undo = executor.UndoAll();

        Assert.Equal(1, undo.Conflicts);
        Assert.Equal("3", _registry.Read("HKLM", @"SYSTEM\CurrentControlSet\Control\CrashControl", "CrashDumpEnabled")!.Encoded);

        var forced = executor.UndoAll(force: true);
        Assert.Equal(1, forced.Undone);
        Assert.Equal("0", _registry.Read("HKLM", @"SYSTEM\CurrentControlSet\Control\CrashControl", "CrashDumpEnabled")!.Encoded);
    }

    [Fact]
    public void Failure_mid_batch_rolls_back_and_keeps_write_ahead_record()
    {
        Seed();
        var before = _registry.Export();
        _services.FailOn = "SysMain";
        var (executor, journal) = Create();

        var result = executor.ApplyBatch("test.batch", Batch);

        Assert.False(result.Succeeded);
        Assert.Equal(before, _registry.Export());
        var states = journal.ReadCurrent().Select(e => e.State).ToList();
        Assert.Contains(EntryState.Failed, states);
        Assert.DoesNotContain(EntryState.Applied, states);
    }

    [Fact]
    public void Unsupported_change_kind_is_refused_before_anything_changes()
    {
        Seed();
        var before = _registry.Export();
        var journal = new ChangeJournal(Path.Combine(_dir, "j2.jsonl"));
        var executor = new ChangeExecutor(journal, new RegistryApplier(_registry, h => h), services: null);

        var result = executor.ApplyBatch("test", Batch);

        Assert.False(result.Succeeded);
        Assert.Equal(before, _registry.Export());
        Assert.Empty(journal.ReadCurrent());
    }

    [Fact]
    public void Service_start_types_boot_and_system_are_never_set()
    {
        _services.Services["disk"] = ("Boot", false);
        var applier = new ServiceApplier(_services);
        Assert.Throws<ArgumentException>(() => applier.Capture(new PlannedServiceStart("disk", "Boot", false)));
    }

    [Fact]
    public void Torn_last_line_is_ignored()
    {
        Seed();
        var (executor, journal) = Create();
        executor.ApplyBatch("test.batch", Batch);
        File.AppendAllText(journal.FilePath, "{\"id\":\"trunc");

        Assert.Equal(4, journal.ReadCurrent().Count);
    }
}

public sealed class RestorePointTests
{
    [Fact]
    public void Frequency_is_zeroed_for_creation_and_restored_to_absent()
    {
        var api = new FakeRestorePoints { Frequency = null };
        api.Points.Add(41);

        var result = new RestorePointGuard(api).CreateVerified("test");

        Assert.Equal(RestorePointOutcome.Created, result.Outcome);
        Assert.Equal(42u, result.SequenceNumber);
        Assert.Equal([0], api.FrequencyDuringCreate);
        Assert.Null(api.Frequency);
    }

    [Fact]
    public void Existing_frequency_is_put_back()
    {
        var api = new FakeRestorePoints { Frequency = 1440 };
        new RestorePointGuard(api).CreateVerified("test");
        Assert.Equal(1440, api.Frequency);
    }

    [Fact]
    public void Silent_skip_is_reported_as_not_created()
    {
        var api = new FakeRestorePoints { SilentlySkip = true };
        api.Points.Add(7);
        Assert.Equal(RestorePointOutcome.NotCreated, new RestorePointGuard(api).CreateVerified("test").Outcome);
    }

    [Fact]
    public void Protection_off_is_reported_without_trying()
    {
        var api = new FakeRestorePoints { ProtectionOn = false };
        Assert.Equal(RestorePointOutcome.ProtectionOff, new RestorePointGuard(api).CreateVerified("test").Outcome);
        Assert.Empty(api.FrequencyDuringCreate);
    }
}
