using PcDoctor.Core.Platform;

namespace PcDoctor.Core.Journal;

public sealed class RegistryApplier(IRegistryAccess registry, Func<string, string> resolveHive) : IChangeApplier
{
    /// <summary>Reads the current state and returns the full change record.</summary>
    public RegistryChange Capture(PlannedChange planned)
    {
        switch (planned)
        {
            case PlannedRegistrySet set:
            {
                var hive = resolveHive(set.Hive);
                var old = registry.Read(hive, set.Key, set.ValueName);
                return new RegistryChange(hive, set.Key, set.ValueName, old is not null,
                    registry.KeyExists(hive, set.Key), old, set.Data);
            }
            case PlannedRegistryDelete del:
            {
                var hive = resolveHive(del.Hive);
                var old = registry.Read(hive, del.Key, del.ValueName);
                return new RegistryChange(hive, del.Key, del.ValueName, old is not null,
                    registry.KeyExists(hive, del.Key), old, null);
            }
            default:
                throw new ArgumentException($"Not a registry change: {planned.GetType().Name}");
        }
    }

    public bool CanHandle(JournalChange change) => change is RegistryChange;

    public JournalChange? TryCapture(PlannedChange planned) =>
        planned is PlannedRegistrySet or PlannedRegistryDelete ? Capture(planned) : null;

    public void Apply(JournalChange change)
    {
        var c = (RegistryChange)change;
        if (c.NewData is null)
        {
            if (c.Existed)
            {
                registry.DeleteValue(c.Hive, c.Key, c.ValueName);
            }
        }
        else
        {
            registry.Write(c.Hive, c.Key, c.ValueName, c.NewData);
        }
    }

    public bool IsStillApplied(JournalChange change)
    {
        var c = (RegistryChange)change;
        return Equals(registry.Read(c.Hive, c.Key, c.ValueName), c.NewData);
    }

    public void Revert(JournalChange change)
    {
        var c = (RegistryChange)change;
        if (c.Existed && c.OldData is not null)
        {
            registry.Write(c.Hive, c.Key, c.ValueName, c.OldData);
            return;
        }
        if (registry.Read(c.Hive, c.Key, c.ValueName) is not null)
        {
            registry.DeleteValue(c.Hive, c.Key, c.ValueName);
        }
        if (!c.KeyExisted)
        {
            registry.DeleteKeyIfEmpty(c.Hive, c.Key);
        }
    }
}

public sealed class ServiceApplier(IServiceConfigAccess services) : IChangeApplier
{
    private static readonly string[] Allowed = ["Automatic", "Manual", "Disabled"];

    public ServiceChange Capture(PlannedServiceStart planned)
    {
        if (!Allowed.Contains(planned.StartType))
        {
            throw new ArgumentException($"Start type {planned.StartType} is not allowed.");
        }
        var current = services.Read(planned.Service)
            ?? throw new InvalidOperationException($"Service {planned.Service} does not exist.");
        // Undo writes the old start type back. Boot and System (drivers) are never written, so a change
        // from one of them could not be undone: refuse it before anything is touched.
        if (!Allowed.Contains(current.StartType))
        {
            throw new InvalidOperationException($"Service {planned.Service} starts as {current.StartType}; PC Doctor does not change it.");
        }
        return new ServiceChange(planned.Service, current.StartType, current.Delayed,
            planned.StartType, planned.DelayedAutostart);
    }

    public bool CanHandle(JournalChange change) => change is ServiceChange;

    public JournalChange? TryCapture(PlannedChange planned) => planned is PlannedServiceStart s ? Capture(s) : null;

    public void Apply(JournalChange change)
    {
        var c = (ServiceChange)change;
        services.Write(c.Service, c.NewStartType, c.NewDelayedAutostart);
    }

    public bool IsStillApplied(JournalChange change)
    {
        var c = (ServiceChange)change;
        return services.Read(c.Service) == (c.NewStartType, c.NewDelayedAutostart);
    }

    public void Revert(JournalChange change)
    {
        var c = (ServiceChange)change;
        services.Write(c.Service, c.OldStartType, c.OldDelayedAutostart);
    }
}

public sealed class TaskApplier(ITaskSchedulerAccess tasks) : IChangeApplier
{
    public bool CanHandle(JournalChange change) => change is TaskChange;

    public JournalChange? TryCapture(PlannedChange planned)
    {
        if (planned is not PlannedTaskEnabled t)
        {
            return null;
        }
        var current = tasks.IsEnabled(t.TaskPath) ?? throw new InvalidOperationException($"Task {t.TaskPath} does not exist.");
        return new TaskChange(t.TaskPath, current, t.Enabled);
    }

    public void Apply(JournalChange change)
    {
        var c = (TaskChange)change;
        tasks.SetEnabled(c.TaskPath, c.NewEnabled);
    }

    public bool IsStillApplied(JournalChange change)
    {
        var c = (TaskChange)change;
        return tasks.IsEnabled(c.TaskPath) == c.NewEnabled;
    }

    public void Revert(JournalChange change)
    {
        var c = (TaskChange)change;
        tasks.SetEnabled(c.TaskPath, c.OldEnabled);
    }
}

/// <summary>Moves files aside and back. Never overwrites: an occupied destination fails the change.</summary>
public sealed class FileMoveApplier : IChangeApplier
{
    public bool CanHandle(JournalChange change) => change is FileMoveChange;

    public JournalChange? TryCapture(PlannedChange planned)
    {
        if (planned is not PlannedFileMove m)
        {
            return null;
        }
        if (!File.Exists(m.From))
        {
            throw new FileNotFoundException("Nothing to move.", m.From);
        }
        return new FileMoveChange(m.From, m.To);
    }

    public void Apply(JournalChange change)
    {
        var c = (FileMoveChange)change;
        Directory.CreateDirectory(Path.GetDirectoryName(c.To)!);
        File.Move(c.From, c.To, overwrite: false);
    }

    public bool IsStillApplied(JournalChange change)
    {
        var c = (FileMoveChange)change;
        return File.Exists(c.To) && !File.Exists(c.From);
    }

    public void Revert(JournalChange change)
    {
        var c = (FileMoveChange)change;
        File.Move(c.To, c.From, overwrite: false);
    }
}
