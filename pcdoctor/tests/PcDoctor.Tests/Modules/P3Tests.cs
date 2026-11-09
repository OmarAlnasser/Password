using System.Buffers.Binary;
using System.Text;
using System.Text.RegularExpressions;
using PcDoctor.Core.Findings;
using PcDoctor.Core.Journal;
using PcDoctor.Core.Platform;
using PcDoctor.Modules.Inventory;
using PcDoctor.Modules.Malware;
using PcDoctor.Modules.Network;
using PcDoctor.Modules.Persistence;
using PcDoctor.Modules.Security;
using Xunit;

namespace PcDoctor.Tests.Modules;

public sealed class CommandLineTests
{
    private static readonly HashSet<string> Files = new(StringComparer.OrdinalIgnoreCase)
    {
        @"C:\Program Files\Contoso App\updater.exe",
        @"C:\Windows\System32\rundll32.exe",
    };

    private static string? Env(string n) => n switch { "SystemRoot" => @"C:\Windows", "ProgramFiles" => @"C:\Program Files", _ => null };

    [Theory]
    [InlineData("\"C:\\Program Files\\Contoso App\\updater.exe\" --silent", @"C:\Program Files\Contoso App\updater.exe")]
    [InlineData("C:\\Program Files\\Contoso App\\updater.exe --silent", @"C:\Program Files\Contoso App\updater.exe")]
    [InlineData("%ProgramFiles%\\Contoso App\\updater.exe", @"C:\Program Files\Contoso App\updater.exe")]
    [InlineData("rundll32.exe C:\\Users\\me\\AppData\\x.dll,Start", @"C:\Users\me\AppData\x.dll")]
    [InlineData("\\SystemRoot\\System32\\drivers\\acpi.sys", @"C:\Windows\System32\drivers\acpi.sys")]
    [InlineData("\\??\\C:\\Windows\\system32\\drivers\\x.sys", @"C:\Windows\system32\drivers\x.sys")]
    [InlineData("svchost.exe -k netsvcs", @"C:\Windows\System32\svchost.exe")]
    public void Resolves_the_loaded_image(string command, string expected) =>
        Assert.Equal(expected, CommandLines.ResolveImage(command, Files.Contains, Env));

    [Theory]
    [InlineData("C:\\Program Files\\A B\\svc.exe", true)]
    [InlineData("\"C:\\Program Files\\A B\\svc.exe\"", false)]
    [InlineData("C:\\Windows\\svc.exe -k x y", false)]
    public void Unquoted_paths_with_spaces(string command, bool expected) => Assert.Equal(expected, CommandLines.IsUnquotedWithSpaces(command));
}

public sealed class PersistenceTests
{
    private static AutorunEntry Entry(AutorunCategory cat, SignatureStatus? sig, string name = "Contoso", string command = @"C:\x\contoso.exe") => new()
    {
        Category = cat,
        Location = cat == AutorunCategory.RunKey ? @"HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" : @"\Contoso\Task",
        Name = name,
        Command = command,
        Image = command,
        Value = cat == AutorunCategory.RunKey ? new RegistryData("String", command) : null,
        Signature = sig is null ? null : new SignatureInfo(sig.Value, sig == SignatureStatus.MicrosoftSigned ? "Microsoft Corporation | O=Microsoft Corporation" : null, false,
            sig == SignatureStatus.Invalid ? "CERT_E_EXPIRED" : null),
    };

    [Fact]
    public void Signature_tiers_map_to_severities_and_microsoft_or_signed_give_no_finding()
    {
        var result = PersistenceAnalyzer.Analyze(new PersistenceSnapshot
        {
            Entries =
            [
                Entry(AutorunCategory.RunKey, SignatureStatus.MicrosoftSigned, "OneDrive"),
                Entry(AutorunCategory.RunKey, SignatureStatus.Signed, "Steam"),
                Entry(AutorunCategory.RunKey, SignatureStatus.Invalid, "Expired"),
                Entry(AutorunCategory.RunKey, SignatureStatus.Unsigned, "Tool"),
            ],
        });
        Assert.DoesNotContain(result.Findings, f => f.Title.Args.Contains("OneDrive") || f.Title.Args.Contains("Steam"));
        Assert.Equal(Severity.High, result.Findings.Single(f => f.Title.Args.Contains("Expired")).Severity);
        var unsigned = result.Findings.Single(f => f.Title.Args.Contains("Tool"));
        Assert.Equal(Severity.Medium, unsigned.Severity);
        Assert.Equal("m3.unsigned.why", unsigned.WhyItMatters.Key);
        Assert.StartsWith("autorun:", unsigned.FixId);
        Assert.Equal(UndoKind.Reversible, unsigned.Undo.Kind);
        TextAssert.AllResolve(result);
    }

    [Fact]
    public void Ifeo_accessibility_wmi_and_amsi_are_reported_but_never_offered_for_automatic_change_except_disable_where_safe()
    {
        var result = PersistenceAnalyzer.Analyze(new PersistenceSnapshot
        {
            Entries =
            [
                Entry(AutorunCategory.ImageFileExecution, null, "notepad.exe", @"C:\evil.exe") with { Detail = "debugger" },
                Entry(AutorunCategory.Accessibility, SignatureStatus.Unsigned, "sethc.exe", ""),
                Entry(AutorunCategory.WmiSubscription, null, "Updater", "powershell -nop -w hidden"),
                Entry(AutorunCategory.WmiSubscription, null, "SCM Event Log Consumer", ""),
                Entry(AutorunCategory.RunKey, SignatureStatus.Signed, "Script", "wscript evil.vbs") with { AmsiResult = 32768 },
            ],
        });
        Assert.Equal(Severity.High, result.Findings.Single(f => f.Id.StartsWith("M3.ifeo", StringComparison.Ordinal)).Severity);
        Assert.Equal(Severity.Critical, result.Findings.Single(f => f.Id.StartsWith("M3.accessibility", StringComparison.Ordinal)).Severity);
        Assert.Single(result.Findings, f => f.Id.StartsWith("M3.wmi", StringComparison.Ordinal));
        var amsi = result.Findings.Single(f => f.Id.StartsWith("M3.amsi", StringComparison.Ordinal));
        Assert.Equal(FindingSource.Defender, amsi.Source);
        Assert.All(result.Findings.Where(f => !f.Id.StartsWith("M3.amsi", StringComparison.Ordinal)), f => Assert.Null(f.FixId));
        TextAssert.AllResolve(result);
    }

    [Fact]
    public void Disable_plan_moves_run_values_to_backup_and_never_deletes_without_a_copy()
    {
        var e = Entry(AutorunCategory.RunKey, SignatureStatus.Unsigned);
        var plan = DisablePlanner.Plan(e, @"C:\ProgramData\PCDoctor\DisabledAutoruns")!;
        Assert.Equal(3, plan.Count);
        Assert.Contains(plan, c => c is PlannedRegistrySet s && s.Key.StartsWith(DisablePlanner.BackupKey, StringComparison.Ordinal) && s.ValueName == "Contoso");
        Assert.IsType<PlannedRegistryDelete>(plan[^1]);
        Assert.Equal([new PlannedTaskEnabled(@"\Contoso\Task", false)], DisablePlanner.Plan(Entry(AutorunCategory.ScheduledTask, SignatureStatus.Unsigned), "x"));
        Assert.Null(DisablePlanner.Plan(Entry(AutorunCategory.Driver, SignatureStatus.Unsigned), "x"));
        Assert.Null(DisablePlanner.Plan(Entry(AutorunCategory.WmiSubscription, null), "x"));
    }

    [Fact]
    public void Entry_ids_are_stable_and_do_not_contain_the_path()
    {
        var e = Entry(AutorunCategory.RunKey, null);
        Assert.Equal(e.Id, e with { Command = "changed" } is var c ? c.Id : "");
        Assert.DoesNotContain("HKLM", e.Id);
        Assert.Equal(("HKU\\S-1-5-21-1", @"Software\Run"), DisablePlanner.SplitHive(@"HKU\S-1-5-21-1\Software\Run"));
    }

    [Fact]
    public void Unreadable_locations_are_listed_as_not_checked()
    {
        var result = PersistenceAnalyzer.Analyze(new PersistenceSnapshot
        {
            Unread = new Dictionary<AutorunCategory, string> { [AutorunCategory.WmiSubscription] = "check.needsDeepScan" },
        });
        Assert.Contains(result.Checks, c => c.Id == "M3.WmiSubscription" && c.Status == CheckStatus.NotChecked);
        Assert.Contains(result.Checks, c => c.Id == "M3.vt" && c.Status == CheckStatus.NotChecked);
    }
}

public sealed class DefenderTests
{
    [Fact]
    public void Third_party_av_means_no_defender_scan()
    {
        var gate = DefenderGate.Evaluate(new DefenderStatus("Passive Mode", false, false, true, 1),
            [new AvProduct("Windows Defender", 0x60100), new AvProduct("Contoso AV", 0x41000)]);
        Assert.Equal(DefenderAvailability.ThirdPartyActive, gate.Availability);
        Assert.Equal("Contoso AV", gate.ActiveProduct);
        var result = MalwareAnalyzer.Analyze(new MalwareSnapshot { Gate = gate, Detections = [] }, DateTimeOffset.UtcNow);
        Assert.Empty(result.Findings);
        Assert.Equal("m2.engine.thirdParty", Assert.Single(result.Checks).Detail!.Key);
    }

    private static DefenderDetection Detection(int status, bool? ok) =>
        new(2147519003, "Virus:DOS/EICAR_Test_File", 5, [@"file:_C:\Users\me\Downloads\eicar.com"], status, ok, DateTimeOffset.UtcNow);

    [Fact]
    public void Exit_code_2_from_scan_errors_is_scan_failed_not_threat_found()
    {
        Assert.Equal(ScanOutcome.ScanFailed, ScanOutcomeInterpreter.Decide(2, false, []));
        Assert.Equal(ScanOutcome.NoThreatsDetected, ScanOutcomeInterpreter.Decide(0, false, []));
        Assert.Equal(ScanOutcome.ThreatsFound, ScanOutcomeInterpreter.Decide(0, false, [Detection(2, true)]));
        Assert.Equal(ScanOutcome.ThreatsRemaining, ScanOutcomeInterpreter.Decide(2, false, [Detection(1, false)]));
        Assert.Equal(ScanOutcome.Cancelled, ScanOutcomeInterpreter.Decide(0, true, [Detection(2, true)]));
    }

    [Fact]
    public void Eicar_detection_is_reported_from_defender_with_its_path()
    {
        var result = MalwareAnalyzer.Analyze(new MalwareSnapshot
        {
            Gate = new DefenderGateResult(DefenderAvailability.Available, "Microsoft Defender Antivirus", "Normal"),
            Detections = [Detection(2, true)],
            PuaProtection = 0,
        }, DateTimeOffset.UtcNow);
        var f = Assert.Single(result.Findings, f => f.Id.StartsWith("M2.detection", StringComparison.Ordinal));
        Assert.Equal(FindingSource.Defender, f.Source);
        Assert.Contains(f.Evidence, e => e.Value == @"C:\Users\me\Downloads\eicar.com");
        Assert.Equal("defender.pua.enable", Assert.Single(result.Findings, f => f.Id == "M2.pua").FixId);
        TextAssert.AllResolve(result);
    }

    [Fact]
    public void Quarantine_list_is_parsed()
    {
        var output = "The following items are quarantined:\r\n\r\nThreatName = Virus:DOS/EICAR_Test_File\r\n      file:C:\\Users\\me\\Downloads\\eicar.com quarantined at 10/30/2026 9:00:00 AM (UTC)\r\n" +
                     "ThreatName = PUA:Win32/Contoso\r\n      file:C:\\Temp\\setup.exe quarantined at 10/30/2026 9:05:00 AM (UTC)\r\n";
        var items = QuarantineParser.Parse(output);
        Assert.Equal(2, items.Count);
        Assert.Equal("Virus:DOS/EICAR_Test_File", items[0].ThreatName);
        Assert.StartsWith(@"C:\Users\me\Downloads\eicar.com", items[0].Files[0]);
    }

    [Fact]
    public void Safety_scanner_log_is_parsed()
    {
        var log = "---- older run ----\nMicrosoft Safety Scanner v1.0\nThreat Detected: Trojan:Win32/Old\n" +
                  "Microsoft Safety Scanner v1.415\nStarted On Fri Oct 30 2026\nThreat Detected: Trojan:Win32/Contoso!ml, not removed.\nResults Summary:\nInfected files: 1\n";
        var r = MsertLogParser.Parse(log);
        Assert.Equal(1, r.InfectedFiles);
        Assert.Equal(["Trojan:Win32/Contoso!ml, not removed."], r.Detections);
        Assert.True(r.Completed);
    }

    [Fact]
    public void MpCmdRun_from_the_highest_platform_version()
    {
        var platform = @"C:\ProgramData\Microsoft\Windows Defender\Platform";
        var dirs = new[] { platform + @"\4.18.24090.11-0", platform + @"\4.18.25070.5-0", platform + @"\junk" };
        var path = DefenderLocator.Find(@"C:\ProgramData", @"C:\Program Files", p => p.EndsWith("MpCmdRun.exe") && !p.Contains("junk"), _ => dirs);
        Assert.Equal(platform + @"\4.18.25070.5-0\MpCmdRun.exe", path);
    }
}

public sealed class VirusTotalTests
{
    private sealed class FakeClock(DateTimeOffset start) : TimeProvider
    {
        public DateTimeOffset Now = start;
        public override DateTimeOffset GetUtcNow() => Now;
    }

    [Fact]
    public void Limiter_never_allows_more_than_4_a_minute_or_500_a_day()
    {
        var clock = new FakeClock(new DateTimeOffset(2026, 11, 9, 12, 0, 0, TimeSpan.Zero));
        var limiter = new VtRateLimiter(clock);
        var sent = new List<DateTimeOffset>();
        for (var i = 0; i < 600; i++)
        {
            var delay = limiter.Delay();
            if (delay is null)
            {
                break;
            }
            clock.Now += delay.Value;
            limiter.Record();
            sent.Add(clock.Now);
        }
        Assert.Equal(VtRateLimiter.PerDay, sent.Count(t => t.Date == sent[0].Date));
        for (var i = 0; i + 4 < sent.Count; i++)
        {
            Assert.True(sent[i + 4] - sent[i] >= TimeSpan.FromMinutes(1), $"5 requests within a minute at {i}");
        }
    }

    [Fact]
    public void Verdict_counts_are_read_from_last_analysis_stats()
    {
        var v = VirusTotalClient.Parse("""{"data":{"attributes":{"last_analysis_stats":{"malicious":2,"suspicious":1,"undetected":60,"harmless":0}}}}""", DateTimeOffset.UnixEpoch);
        Assert.Equal((2, 1, 60), (v.Malicious, v.Suspicious, v.Undetected));
    }

    [Fact]
    public void No_upload_code_exists_anywhere()
    {
        foreach (var file in Directory.EnumerateFiles(Path.Combine(Fixtures.SourceRoot, "src"), "*.cs", SearchOption.AllDirectories)
                     .Where(f => !f.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}")))
        {
            var text = File.ReadAllText(file);
            Assert.DoesNotMatch(new Regex(@"(?i)HttpMethod\.(Post|Put)|PostAsync|PutAsync|MultipartFormDataContent|/files/upload_url|api/v3/files""\s*,"), text);
        }
    }
}

public sealed class NetworkTests
{
    [Fact]
    public void Hosts_redirect_of_update_domains_is_high_and_ad_blocking_is_not()
    {
        var hosts = HostsParser.Parse("# comment\n127.0.0.1 localhost\n0.0.0.0 ads.example.test\n10.1.2.3 update.microsoft.com  # x\n");
        var result = NetworkAnalyzer.Analyze(new NetworkSnapshot { HostsPath = @"C:\Windows\System32\drivers\etc\hosts", Hosts = hosts }, DateTimeOffset.UtcNow);
        var f = Assert.Single(result.Findings);
        Assert.Equal("M4.hostsSensitive", f.Id);
        Assert.Equal(Severity.High, f.Severity);
        Assert.Contains(f.Evidence, e => e.Label.EndsWith(":4", StringComparison.Ordinal));
        TextAssert.AllResolve(result);
    }

    [Fact]
    public void WinHttp_proxy_blob_is_parsed()
    {
        var proxy = Encoding.ASCII.GetBytes("proxy.contoso.test:8080");
        var blob = new byte[16 + proxy.Length + 4];
        BinaryPrimitives.WriteUInt32LittleEndian(blob.AsSpan(0), 0x18);
        BinaryPrimitives.WriteUInt32LittleEndian(blob.AsSpan(8), 0x3);
        BinaryPrimitives.WriteInt32LittleEndian(blob.AsSpan(12), proxy.Length);
        proxy.CopyTo(blob, 16);
        Assert.Equal("proxy.contoso.test:8080", WinHttpSettingsParser.ParseProxy(blob));
        BinaryPrimitives.WriteUInt32LittleEndian(blob.AsSpan(8), 0x1);
        Assert.Null(WinHttpSettingsParser.ParseProxy(blob));
    }

    [Fact]
    public void Known_and_private_resolvers_are_not_findings()
    {
        var result = NetworkAnalyzer.Analyze(new NetworkSnapshot
        {
            Dns = [new DnsAdapter("Wi-Fi", ["1.1.1.1", "192.168.1.1"], []), new DnsAdapter("Ethernet", ["203.0.113.66"], ["192.168.0.1"])],
        }, DateTimeOffset.UtcNow);
        Assert.Contains("203.0.113.66", Assert.Single(result.Findings).Title.Args[0]);
    }

    [Fact]
    public void Recent_self_signed_roots_are_flagged_as_review()
    {
        var now = DateTimeOffset.UtcNow;
        var result = NetworkAnalyzer.Analyze(new NetworkSnapshot
        {
            Roots =
            [
                new RootCert("LocalMachine", "CN=Old Root", "CN=Old Root", "AA", now.AddYears(-10), now.AddYears(-3)),
                new RootCert("LocalMachine", "CN=Fresh Proxy CA", "CN=Fresh Proxy CA", "BB", now.AddDays(-2), now.AddDays(-2)),
            ],
        }, now);
        var f = Assert.Single(result.Findings);
        Assert.Equal(Confidence.Possible, f.Confidence);
        Assert.Contains("Fresh Proxy CA", f.Title.Args);
    }
}

public sealed class InventoryTests
{
    [Fact]
    public void Inventoried_plus_skipped_accounts_for_every_entry()
    {
        var acc = new InventoryAccumulator();
        acc.File(@"C:\a.txt", 1, 10, 0x20, 100);
        acc.File(@"C:\b.txt", 1, 11, 0x20, 50);
        acc.File(@"C:\b-hardlink.txt", 1, 11, 0x20, 50);
        acc.File(@"C:\OneDrive\cloud.docx", 1, 12, 0x20 | InventoryAccumulator.RecallOnDataAccess, 9000);
        acc.File(@"C:\link", 1, 13, InventoryAccumulator.ReparsePoint, 0);
        acc.Skip(@"C:\System Volume Information", SkipReason.AccessDenied, true);
        var r = acc.ToResult([@"C:\"], TimeSpan.FromSeconds(1), false, null);

        Assert.Equal(2, r.FilesInventoried);
        Assert.Equal(1, r.HardLinkDuplicates);
        Assert.Equal(1, r.SkippedFiles[SkipReason.CloudOnly]);
        Assert.Equal(1, r.SkippedFiles[SkipReason.LinkNotFollowed]);
        Assert.Equal(1, r.TotalSkippedDirectories);
        Assert.Equal(5, r.FilesInventoried + r.TotalSkippedFiles + r.HardLinkDuplicates);
        Assert.Equal(150, r.Bytes);
        Assert.Equal("2 files inventoried, 2 skipped (access denied 0, locked 0, cloud-only 1, path errors 0, links 1); 1 folders could not be listed",
            InventorySummary.Line(r));
    }

    [Fact]
    public void Cloud_placeholders_are_recognised_by_attribute()
    {
        Assert.True(InventoryAccumulator.IsCloudOnly(InventoryAccumulator.RecallOnOpen));
        Assert.True(InventoryAccumulator.IsCloudOnly(InventoryAccumulator.Offline));
        Assert.False(InventoryAccumulator.IsCloudOnly(0x20));
    }

    [Fact]
    public void Directory_records_are_parsed_and_dot_entries_skipped()
    {
        static byte[] Record(string name, uint attrs, long id, long size, bool last)
        {
            var nameBytes = Encoding.Unicode.GetBytes(name);
            var len = (104 + nameBytes.Length + 7) & ~7;
            var b = new byte[len];
            BinaryPrimitives.WriteInt32LittleEndian(b.AsSpan(0), last ? 0 : len);
            BinaryPrimitives.WriteInt64LittleEndian(b.AsSpan(40), size);
            BinaryPrimitives.WriteUInt32LittleEndian(b.AsSpan(56), attrs);
            BinaryPrimitives.WriteInt32LittleEndian(b.AsSpan(60), nameBytes.Length);
            BinaryPrimitives.WriteInt64LittleEndian(b.AsSpan(96), id);
            nameBytes.CopyTo(b, 104);
            return b;
        }
        byte[] buffer = [.. Record(".", 0x10, 1, 0, false), .. Record("long name — مستند.txt", 0x20, 42, 1234, true)];
        var e = Assert.Single(DirInfoParser.Parse(buffer, buffer.Length));
        Assert.Equal(("long name — مستند.txt", 42L, 1234L), (e.Name, e.FileId, e.Size));
    }

    [Fact]
    public void Skipped_csv_quotes_paths()
    {
        var csv = InventoryAccumulator.ToCsv([new SkippedItem("C:\\a \"b\".txt", SkipReason.Locked, false)]);
        Assert.Contains("\"C:\\a \"\"b\"\".txt\",Locked,false", csv);
    }
}
