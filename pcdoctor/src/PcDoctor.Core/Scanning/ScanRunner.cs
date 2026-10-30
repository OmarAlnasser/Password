using PcDoctor.Core.Findings;
using PcDoctor.Core.Reporting;

namespace PcDoctor.Core.Scanning;

public sealed record ScanProgress(int Completed, int Total, Text CurrentModule);

/// <summary>Runs modules one by one. A module that throws is reported as not checked, never dropped.</summary>
public sealed class ScanRunner(IReadOnlyList<IModule> modules, IConditionsReader conditions, TimeProvider? clock = null)
{
    private readonly TimeProvider _clock = clock ?? TimeProvider.System;

    public async Task<ScanReport> RunAsync(
        ScanMode mode,
        IElevatedReader? elevated,
        IProgress<ScanProgress>? progress,
        CancellationToken ct)
    {
        var started = _clock.GetUtcNow();
        var ctx = new ScanContext(mode, mode == ScanMode.DeepScan ? elevated : null, _clock, ct);
        var results = new List<ModuleResult>();
        for (var i = 0; i < modules.Count; i++)
        {
            ct.ThrowIfCancellationRequested();
            var module = modules[i];
            progress?.Report(new ScanProgress(i, modules.Count, module.Name));
            try
            {
                results.Add(await module.RunAsync(ctx).ConfigureAwait(false));
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch (Exception ex)
            {
                results.Add(new ModuleResult
                {
                    ModuleId = module.Id,
                    ModuleName = module.Name,
                    Checks = [Checks.Failed(module.Id + ".module", module.Name, ex)],
                });
            }
        }
        progress?.Report(new ScanProgress(modules.Count, modules.Count, new Text("scan.done")));
        return new ScanReport
        {
            Id = Guid.NewGuid(),
            StartedUtc = started,
            FinishedUtc = _clock.GetUtcNow(),
            Conditions = conditions.Read(mode),
            Modules = results,
        };
    }
}
