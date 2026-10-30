using System.Globalization;
using System.Text.RegularExpressions;
using System.Xml.Linq;
using PcDoctor.Core.Findings;
using PcDoctor.Core.Localization;
using PcDoctor.Core.Reporting;
using PcDoctor.Core.Scanning;
using PcDoctor.Modules.Crash;
using PcDoctor.Modules.Disk;
using PcDoctor.Modules.Security;
using Xunit;

namespace PcDoctor.Tests.Core;

public sealed class HonestyAndLocalizationTests
{
    private static string ResourcesDir => Path.Combine(Fixtures.SourceRoot, "src", "PcDoctor.Core", "Resources");

    private static Dictionary<string, string> ReadResx(string file) =>
        XDocument.Load(Path.Combine(ResourcesDir, file)).Root!.Elements("data")
            .ToDictionary(d => d.Attribute("name")!.Value, d => d.Element("value")!.Value);

    [Fact]
    public void Guard_catches_the_claims_we_never_make()
    {
        foreach (var s in new[] { "Your PC is clean", "100% safe", "All viruses removed", "Guaranteed healthy", "جهازك نظيف" })
        {
            Assert.NotEmpty(HonestyGuard.FindBannedPhrases(s));
        }
        Assert.Empty(HonestyGuard.FindBannedPhrases("DISM /Cleanup-Image found no component store corruption"));
    }

    [Fact]
    public void No_ui_string_in_either_language_makes_a_banned_claim()
    {
        foreach (var file in new[] { "Strings.resx", "Strings.ar.resx" })
        {
            foreach (var (key, value) in ReadResx(file))
            {
                Assert.True(HonestyGuard.FindBannedPhrases(value).Count == 0, $"{file}:{key}: {value}");
            }
        }
        var kb = File.ReadAllText(Path.Combine(Fixtures.SourceRoot, "src", "PcDoctor.Modules.Crash", "bugchecks.json"));
        Assert.Empty(HonestyGuard.FindBannedPhrases(kb));
    }

    [Fact]
    public void English_and_arabic_have_the_same_keys_and_placeholders()
    {
        var en = ReadResx("Strings.resx");
        var ar = ReadResx("Strings.ar.resx");
        Assert.Equal(en.Keys.Order(), ar.Keys.Order());
        var placeholder = new Regex(@"\{\d+\}");
        foreach (var key in en.Keys)
        {
            Assert.False(string.IsNullOrWhiteSpace(ar[key]), $"Empty Arabic string: {key}");
            Assert.Equal(placeholder.Matches(en[key]).Select(m => m.Value).Distinct().Order(),
                placeholder.Matches(ar[key]).Select(m => m.Value).Distinct().Order());
        }
    }

    [Fact]
    public void Arabic_strings_are_actually_translated()
    {
        var en = ReadResx("Strings.resx");
        var ar = ReadResx("Strings.ar.resx");
        // Proper names and technical labels may be identical; prose may not.
        var same = en.Keys.Where(k => en[k] == ar[k] && en[k].Count(char.IsWhiteSpace) >= 2).ToList();
        Assert.True(same.Count == 0, "Untranslated: " + string.Join(", ", same));
    }

    [Fact]
    public void Every_literal_key_in_source_and_xaml_exists()
    {
        var keys = ReadResx("Strings.resx").Keys.ToHashSet();
        var patterns = new[]
        {
            new Regex("""new Text\("([a-z0-9.]+[a-z0-9])"[,)]"""),
            new Regex("""Loc\.(?:Get|Format)\("([a-z0-9.]+[a-z0-9])"[,)]"""),
            new Regex("""\{loc:Loc ([A-Za-z0-9.]+)\}"""),
            new Regex("""new\((?:[^,()]+), "([a-z]+\.[a-zA-Z0-9.]+)"\)"""),
        };
        var missing = new List<string>();
        foreach (var file in Directory.EnumerateFiles(Path.Combine(Fixtures.SourceRoot, "src"), "*.*", SearchOption.AllDirectories)
                     .Where(f => (f.EndsWith(".cs") || f.EndsWith(".xaml")) && !f.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}")))
        {
            var text = File.ReadAllText(file);
            foreach (var p in patterns)
            {
                foreach (Match m in p.Matches(text))
                {
                    var key = m.Groups[1].Value;
                    if (!keys.Contains(key) && !key.StartsWith("kb.", StringComparison.Ordinal))
                    {
                        missing.Add($"{Path.GetFileName(file)}: {key}");
                    }
                }
            }
        }
        Assert.True(missing.Count == 0, "Missing keys: " + string.Join(", ", missing.Distinct()));
    }

    internal static ScanReport SampleReport(ScanMode mode = ScanMode.HealthCheck)
    {
        var crash = CrashAnalyzer.Analyze(new CrashSnapshot
        {
            DumpConfig = new DumpConfig(0, null, null, null),
            Events = Directory.GetFiles(Path.Combine(Fixtures.Dir, "events")).Select(f => Fixtures.Event(Path.GetFileNameWithoutExtension(f))).ToList(),
        });
        var disk = DiskAnalyzer.Analyze(new DiskSnapshot
        {
            Disks = [new PhysicalDiskInfo("0", "Contoso SSD", "SN", PhysicalDiskInfo.BusNvme, 4, 1, [2], 1)],
        });
        var security = SecurityAnalyzer.Analyze(new SecuritySnapshot { OsBuild = 19045, EnableLua = 0 }, OsSupportConfig.Load(),
            new DateTimeOffset(2026, 10, 30, 0, 0, 0, TimeSpan.Zero));
        return new ScanReport
        {
            Id = Guid.NewGuid(),
            StartedUtc = new DateTimeOffset(2026, 10, 30, 8, 0, 0, TimeSpan.Zero),
            FinishedUtc = new DateTimeOffset(2026, 10, 30, 8, 1, 0, TimeSpan.Zero),
            Conditions = new ScanConditions
            {
                AppVersion = "0.1.0", OsProductName = "Windows 10 Pro", OsBuild = "10.0.19045.6456", OsDisplayVersion = "22H2",
                OsEdition = "Professional", Architecture = "X64", Uptime = TimeSpan.FromHours(30), PowerSource = PowerSource.AC,
                PowerPlan = "Balanced", Elevated = false, Mode = mode, UiCulture = "en-US",
                MachineName = "DESKTOP-OMAR1", UserName = "omar",
            },
            Modules = [security, crash, disk],
        };
    }

    [Theory]
    [InlineData("en-US")]
    [InlineData("ar-SA")]
    public void Generated_reports_contain_no_banned_phrase_and_always_carry_the_disclaimer(string culture)
    {
        var c = CultureInfo.GetCultureInfo(culture);
        var report = SampleReport();
        var options = new ExportOptions(c, Redact: false);
        foreach (var output in new[] { ReportExporter.ToHtml(report, options), ReportExporter.ToJson(report, options), ReportExporter.FindingsToCsv(report, options) })
        {
            Assert.Empty(HonestyGuard.FindBannedPhrases(output));
            Assert.DoesNotContain("[[", output);
        }
        Assert.Contains(Loc.Get("summary.disclaimer", c), ReportExporter.ToHtml(report, options));
    }

    [Fact]
    public void Summary_with_zero_findings_still_says_what_was_and_was_not_checked()
    {
        var report = SampleReport() with { Modules = [new ModuleResult { ModuleId = "X", ModuleName = new Text("m7.name"), Checks = [new CheckResult("a", new Text("m7.check.nvme"), CheckStatus.NotChecked)] }] };
        var lines = ReportSummary.Build(report).Select(t => t.Key).ToList();
        Assert.Equal(["summary.checked", "summary.notChecked", "summary.noActionableFindings", "summary.healthCheckScope", "summary.disclaimer"], lines);
    }

    [Fact]
    public void Arabic_html_is_rtl_and_evidence_is_isolated_ltr()
    {
        var html = ReportExporter.ToHtml(SampleReport(), new ExportOptions(Cultures.Ar, false));
        Assert.Contains("dir=\"rtl\"", html);
        Assert.Contains("direction:ltr", html);
        Assert.Contains("<code>", html);
    }

    [Fact]
    public void Redaction_removes_user_and_pc_names()
    {
        var report = SampleReport();
        var json = ReportExporter.ToJson(report, new ExportOptions(Cultures.En, Redact: true));
        Assert.DoesNotContain("DESKTOP-OMAR1", json);
        Assert.DoesNotContain("\"omar\"", json);
        Assert.Contains("<PC>", json);
    }

    [Theory]
    [InlineData("=HYPERLINK(\"x\")", "\"'=HYPERLINK(\"\"x\"\")\"")]
    [InlineData("plain", "\"plain\"")]
    [InlineData("-1+2", "\"'-1+2\"")]
    public void Csv_cells_are_quoted_and_formula_safe(string input, string expected) =>
        Assert.Equal(expected, ReportExporter.Csv(input));

    [Fact]
    public void Arabic_indic_digits_apply_to_prose_only_when_chosen()
    {
        var text = new Text("summary.checked", 12, 3);
        try
        {
            Loc.Digits = DigitStyle.ArabicIndic;
            Assert.Contains("١٢", Loc.Resolve(text, Cultures.Ar));
            Assert.Contains("12", Loc.Resolve(text, Cultures.En));
        }
        finally
        {
            Loc.Digits = DigitStyle.Western;
        }
        Assert.Contains("12", Loc.Resolve(text, Cultures.Ar));
    }
}

public sealed class StaticSafetyTests
{
    private static IEnumerable<string> SourceFiles() =>
        Directory.EnumerateFiles(Path.Combine(Fixtures.SourceRoot, "src"), "*.*", SearchOption.AllDirectories)
            .Where(f => !f.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}") &&
                        !f.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}"));

    [Fact]
    public void No_encoded_powershell_iex_or_downloaded_scripts()
    {
        var banned = new Regex(@"(?i)-EncodedCommand|\biex\b|Invoke-Expression|DownloadString|powershell(\.exe)?""");
        foreach (var file in SourceFiles().Where(f => f.EndsWith(".cs")))
        {
            Assert.False(banned.IsMatch(File.ReadAllText(file)), file);
        }
    }

    [Fact]
    public void WinRing0_is_never_shipped()
    {
        Assert.DoesNotContain(SourceFiles(), f => Path.GetFileName(f).StartsWith("WinRing0", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void Ui_never_runs_elevated_and_broker_always_does()
    {
        var app = File.ReadAllText(Path.Combine(Fixtures.SourceRoot, "src", "PcDoctor.App", "app.manifest"));
        var broker = File.ReadAllText(Path.Combine(Fixtures.SourceRoot, "src", "PcDoctor.Broker", "app.manifest"));
        Assert.Contains("level=\"asInvoker\"", app);
        Assert.Contains("longPathAware", app);
        Assert.Contains("level=\"requireAdministrator\"", broker);
    }

    [Fact]
    public void Fix_catalog_never_touches_forbidden_areas()
    {
        var forbidden = new Regex(@"(?i)Windows Defender|WinDefend|wuauserv|BITS|PagingFiles|FeatureSettingsOverride|TdrDelay|Exclusions|TamperProtection");
        foreach (var fix in PcDoctor.Core.Fixes.FixCatalog.All)
        {
            foreach (var change in fix.Changes)
            {
                Assert.False(forbidden.IsMatch(change.Describe()), $"{fix.Id}: {change.Describe()}");
            }
        }
    }
}
