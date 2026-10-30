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
        return new ServiceChange(planned.Service, current.StartType, current.Delayed,
            planned.StartType, planned.DelayedAutostart);
    }

    public bool CanHandle(JournalChange change) => change is ServiceChange;

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
