using System.Globalization;
using PcDoctor.Core.Journal;
using PcDoctor.Core.Localization;
using PcDoctor.Core.Platform;
using PcDoctor.Tweaks;
using Xunit;

namespace PcDoctor.Tests.Modules;

public sealed class TweakTests : IDisposable
{
    private readonly string _dir = Directory.CreateTempSubdirectory("pcdoctor-tweaks-").FullName;
    private static readonly TweakCatalog Catalog = TweakCatalog.Load();
    private static readonly OsInfo Win11Pro = new(26100, "Professional", false);
    private const string UserHive = @"HKU\S-1-5-21-1-2-3-1001";

    public void Dispose() => Directory.Delete(_dir, recursive: true);

    private sealed class NoTasks : ITaskSchedulerAccess
    {
        public bool? IsEnabled(string taskPath) => null;
        public void SetEnabled(string taskPath, bool enabled) => throw new InvalidOperationException();
    }

    private sealed class FakeAppx(params string[] present) : IAppxAccess
    {
        public bool IsPresent(string prefix) => present.Any(p => string.Equals(p.Split('_')[0], prefix, StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void Shipped_catalog_passes_its_safety_validation()
    {
        Assert.Empty(TweakEngine.Violations(Catalog));
        Assert.True(Catalog.Tweaks.Count >= 25);
    }

    [Fact]
    public void Validation_rejects_forbidden_targets()
    {
        var bad = new TweakCatalog(1,
        [
            new Tweak { Id = "x1", Category = "x", Tier = Tier.Recommended, Actions = [new ServiceAction("wuauserv", "Disabled")] },
            new Tweak { Id = "x2", Category = "x", Tier = Tier.Recommended, Actions = [new RegistryAction("HKLM", @"SOFTWARE\Policies\Microsoft\Windows Defender", "DisableAntiSpyware", "DWord", "1")] },
            new Tweak { Id = "x3", Category = "x", Tier = Tier.Recommended, Actions = [new AppxAction("Microsoft.WindowsStore", "x")] },
            new Tweak { Id = "x4", Category = "x", Tier = Tier.Recommended, Actions = [new RegistryAction("HKLM", @"SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management", "PagingFiles", "MultiString", "")] },
            new Tweak { Id = "x5", Category = "x", Tier = Tier.Recommended, Actions = [new AppxAction("Microsoft.MicrosoftEdge.Stable", "x")] },
        ]);
        Assert.Equal(5, TweakEngine.Violations(bad).Count);
        Assert.Null(TweakEngine.Plan(bad, ["x1"], Win11Pro, Context(new FakeRegistry(), new FakeServices())));
    }

    [Fact]
    public void Security_features_can_never_be_turned_off_by_a_catalog()
    {
        var bad = new TweakCatalog(1,
        [
            new Tweak { Id = "s1", Category = "x", Tier = Tier.Advanced, Actions = [new RegistryAction("HKLM", @"SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity", "Enabled", "DWord", "0")] },
            new Tweak { Id = "s2", Category = "x", Tier = Tier.Advanced, Actions = [new RegistryAction("HKLM", @"SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System", "EnableLUA", "DWord", "0")] },
            new Tweak { Id = "s3", Category = "x", Tier = Tier.Advanced, Actions = [new RegistryAction("HKLM", @"SOFTWARE\Policies\Microsoft\Windows\System", "EnableSmartScreen", "DWord", "0")] },
            new Tweak { Id = "s4", Category = "x", Tier = Tier.Advanced, Actions = [new RegistryAction("HKLM", @"SYSTEM\CurrentControlSet\Services\WinDefend", "Start", "DWord", "4")] },
            new Tweak { Id = "s5", Category = "x", Tier = Tier.Advanced, Actions = [new AppxAction("MicrosoftWindows.Client.CBS", "x")] },
        ]);
        Assert.Equal(5, TweakEngine.Violations(bad).Count);
        Assert.DoesNotContain(Catalog.Tweaks, t => t.Id.Contains("memoryIntegrity", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void Windows_ai_and_extra_apps_are_never_applied_by_a_preset_button()
    {
        var ai = Catalog.Tweaks.Where(t => t.Category == "ai").ToList();
        Assert.True(ai.Count >= 9);
        Assert.Contains(ai, t => t.Id == "ai.recallOff");
        Assert.Contains(ai, t => t.Id == "ai.copilotApp");
        var limited = TweakEngine.Preset(Catalog, "limited", Win11Pro);
        Assert.DoesNotContain(limited, t => t.Category == "ai");
        Assert.DoesNotContain(limited, t => t.Category == "apps" && t.Tier != Tier.Recommended);
        // Every app removal names one exact package and a Store ID to put it back.
        foreach (var x in Catalog.Tweaks.SelectMany(t => t.Actions).OfType<AppxAction>())
        {
            Assert.False(string.IsNullOrWhiteSpace(x.StoreId));
            Assert.DoesNotContain("*", x.PackageFamilyPrefix);
        }
        Assert.Equal(Catalog.Tweaks.SelectMany(t => t.Actions).OfType<AppxAction>().Count(),
            Catalog.Tweaks.SelectMany(t => t.Actions).OfType<AppxAction>().Select(x => x.PackageFamilyPrefix).Distinct(StringComparer.OrdinalIgnoreCase).Count());
    }

    /// <summary>The rule "tell first, then ask": no page may send a change to the Broker without a consent dialog just before it.</summary>
    [Fact]
    public void Every_change_request_in_the_app_is_preceded_by_a_consent_dialog()
    {
        string[] changes = ["new TweakApplyRequest(", "new ApplyFixRequest(", "new AutorunDisableRequest(", "new QuarantineRestoreRequest(", "Scheduler.Apply(", "new UndoRequest(",
            "JobKind.Sfc)", "JobKind.DismRestoreHealth)", "JobKind.VerifierReset)", "JobKind.VerifierEnable", "JobKind.ChkdskFix", "JobKind.DefenderOffline", "JobKind.LatencyTrace"];
        var checkedSites = 0;
        foreach (var file in Directory.EnumerateFiles(Path.Combine(Fixtures.SourceRoot, "src", "PcDoctor.App"), "*.cs", SearchOption.AllDirectories)
                     .Where(f => !f.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}") && !f.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}")))
        {
            var lines = File.ReadAllLines(file);
            for (var i = 0; i < lines.Length; i++)
            {
                if (!changes.Any(c => lines[i].Contains(c, StringComparison.Ordinal)))
                {
                    continue;
                }
                checkedSites++;
                var before = string.Join("\n", lines[Math.Max(0, i - 45)..(i + 1)]);
                Assert.True(before.Contains("ConsentDialog.Ask(", StringComparison.Ordinal) || before.Contains("AskSfc()", StringComparison.Ordinal),
                    $"{Path.GetFileName(file)}:{i + 1} changes the PC without asking first");
            }
        }
        Assert.True(checkedSites >= 8);
    }

    [Fact]
    public void Presets_never_include_advanced_items_or_protected_components()
    {
        foreach (var preset in new[] { "recommended", "limited" })
        {
            var tweaks = TweakEngine.Preset(Catalog, preset, Win11Pro);
            Assert.NotEmpty(tweaks);
            Assert.DoesNotContain(tweaks, t => t.Tier == Tier.Advanced);
            foreach (var a in tweaks.SelectMany(t => t.Actions))
            {
                Assert.False(a is AppxAction { PackageFamilyPrefix: var p } && (p.Contains("Store") || p.Contains("Edge") || p.Contains("WebView") || p.Contains("AppInstaller")));
                Assert.False(a is ServiceAction { Service: "wuauserv" or "WinDefend" or "BITS" });
            }
        }
        Assert.Empty(TweakEngine.Preset(Catalog, "advanced", Win11Pro));
    }

    [Fact]
    public void Telemetry_level_depends_on_edition_and_widgets_on_build()
    {
        var pro = TweakEngine.Preset(Catalog, "recommended", Win11Pro).Select(t => t.Id).ToList();
        var ent = TweakEngine.Preset(Catalog, "recommended", Win11Pro with { Edition = "Enterprise" }).Select(t => t.Id).ToList();
        var win10 = TweakEngine.Preset(Catalog, "recommended", new OsInfo(19045, "Professional", false)).Select(t => t.Id).ToList();
        Assert.Contains("telemetry.minimum", pro);
        Assert.DoesNotContain("telemetry.minimumEnterprise", pro);
        Assert.Contains("telemetry.minimumEnterprise", ent);
        Assert.Contains("widgets.off", pro);
        Assert.Contains("feeds.off", win10);
        Assert.DoesNotContain("taskbar.endTask", win10);
    }

    private static DetectContext Context(FakeRegistry r, FakeServices s, IAppxAccess? appx = null) =>
        new(r, s, new NoTasks(), appx ?? new FakeAppx(), UserHive);

    [Fact]
    public void Detection_reports_applied_partial_and_not_applied()
    {
        var reg = new FakeRegistry();
        var t = Catalog.Find("ads.tips")!;
        Assert.Equal(TweakState.NotApplied, TweakEngine.Detect(t, Win11Pro, Context(reg, new FakeServices())));
        reg.Write(UserHive, @"Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager", "SoftLandingEnabled", new RegistryData("DWord", "0"));
        Assert.Equal(TweakState.Partial, TweakEngine.Detect(t, Win11Pro, Context(reg, new FakeServices())));
        reg.Write(UserHive, @"Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager", "SubscribedContent-338389Enabled", new RegistryData("DWord", "0"));
        Assert.Equal(TweakState.Applied, TweakEngine.Detect(t, Win11Pro, Context(reg, new FakeServices())));
        Assert.Equal(TweakState.NotApplicable, TweakEngine.Detect(Catalog.Find("feeds.off")!, Win11Pro, Context(reg, new FakeServices())));
        Assert.Equal(TweakState.Applied, TweakEngine.Detect(Catalog.Find("apps.bingNews")!, Win11Pro, Context(reg, new FakeServices(), new FakeAppx("Microsoft.BingWeather_8wekyb3d8bbwe"))));
    }

    [Fact]
    public void Recommended_applied_through_the_journal_undoes_to_an_identical_registry_and_services()
    {
        // Acceptance test 8 (registry and services; app removal is reported, not auto-reversed).
        var reg = new FakeRegistry();
        reg.Write(UserHive, @"Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced", "HideFileExt", new RegistryData("DWord", "1"));
        reg.Write("HKLM", @"SOFTWARE\Policies\Microsoft\Edge", "NewTabPageContentEnabled", new RegistryData("DWord", "1"));
        var services = new FakeServices();
        services.Services["SysMain"] = ("Automatic", false);
        var before = reg.Export();

        var ids = TweakEngine.Preset(Catalog, "limited", Win11Pro).Where(t => t.Actions.All(a => a is RegistryAction)).Select(t => t.Id).ToList();
        ids.Add("service.sysMain");
        var plan = TweakEngine.Plan(Catalog, ids, Win11Pro, Context(reg, services))!;
        var journal = new ChangeJournal(Path.Combine(_dir, "j.jsonl"));
        var executor = new ChangeExecutor(journal, [new RegistryApplier(reg, h => h == "HKCU" ? UserHive : h), new ServiceApplier(services)]);

        var batch = executor.ApplyBatch("tweaks:" + string.Join(",", ids), plan);

        Assert.True(batch.Succeeded, batch.Error);
        Assert.Equal(plan.Count, journal.ReadCurrent().Count);
        Assert.All(ids, id => Assert.Equal(TweakState.Applied, TweakEngine.Detect(Catalog.Find(id)!, Win11Pro, Context(reg, services))));
        Assert.Empty(TweakEngine.Plan(Catalog, ids, Win11Pro, Context(reg, services))!);

        executor.UndoAll();
        Assert.Equal(before, reg.Export());
        Assert.Equal(("Automatic", false), services.Services["SysMain"]);
    }

    [Fact]
    public void A_setting_reset_by_a_feature_update_is_detected_as_drift()
    {
        // Acceptance test 9.
        var reg = new FakeRegistry();
        var plan = TweakEngine.Plan(Catalog, ["explorer.fileExtensions"], Win11Pro, Context(reg, new FakeServices()))!;
        new ChangeExecutor(new ChangeJournal(Path.Combine(_dir, "d.jsonl")), [new RegistryApplier(reg, h => h == "HKCU" ? UserHive : h)])
            .ApplyBatch("tweaks:explorer.fileExtensions", plan);
        var manifest = new AppliedManifest("26100.2000 24H2", ["explorer.fileExtensions"], DateTimeOffset.UtcNow);
        TweakState Detect(string id) => TweakEngine.Detect(Catalog.Find(id)!, Win11Pro, Context(reg, new FakeServices()));

        Assert.Empty(manifest.Drifted("26100.2000 24H2", Detect));
        Assert.Empty(manifest.Drifted("26200.100 25H2", Detect));

        reg.Write(UserHive, @"Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced", "HideFileExt", new RegistryData("DWord", "1"));
        Assert.Equal(["explorer.fileExtensions"], manifest.Drifted("26200.100 25H2", Detect));
    }

    [Fact]
    public void Every_tweak_has_title_why_and_warning_texts_in_both_languages()
    {
        foreach (var t in Catalog.Tweaks)
        {
            foreach (var c in new[] { CultureInfo.GetCultureInfo("en-US"), CultureInfo.GetCultureInfo("ar-SA") })
            {
                Assert.DoesNotContain("[[", Loc.Get($"tweak.{t.Id}.title", c));
                Assert.DoesNotContain("[[", Loc.Get($"tweak.{t.Id}.why", c));
                if (t.HasWarning)
                {
                    Assert.DoesNotContain("[[", Loc.Get($"tweak.{t.Id}.warning", c));
                }
            }
        }
    }

    [Fact]
    public void App_removal_plans_record_a_store_id_for_reinstall()
    {
        var plan = TweakEngine.Plan(Catalog, ["apps.clipchamp"], Win11Pro, Context(new FakeRegistry(), new FakeServices(), new FakeAppx("Clipchamp.Clipchamp_yxz26nhyzhsrt")))!;
        var remove = Assert.IsType<PlannedAppxRemove>(Assert.Single(plan));
        Assert.Contains("winget install --id 9P1J8S7CCWWT -s msstore", remove.Describe());
    }
}
