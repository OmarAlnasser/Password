using System.Buffers.Binary;
using System.Net;
using System.Runtime.Versioning;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using Microsoft.Win32;
using PcDoctor.Core.Findings;
using PcDoctor.Core.Scanning;

namespace PcDoctor.Modules.Network;

public sealed record HostsEntry(int Line, string Address, string Host);

public sealed record ProxySettings(bool UserProxyEnabled, string? UserProxy, string? AutoConfigUrl, string? WinHttpProxy);

public sealed record DnsAdapter(string Name, IReadOnlyList<string> StaticServers, IReadOnlyList<string> DhcpServers);

public sealed record RootCert(string Store, string Subject, string Issuer, string Thumbprint, DateTimeOffset NotBefore, DateTimeOffset? AddedUtc);

public sealed record NetworkSnapshot
{
    public string? HostsPath { get; init; }
    public IReadOnlyList<HostsEntry>? Hosts { get; init; }
    public bool HostsPathChanged { get; init; }
    public ProxySettings? Proxy { get; init; }
    public IReadOnlyList<DnsAdapter>? Dns { get; init; }
    public IReadOnlyList<RootCert>? Roots { get; init; }
}

public static class HostsParser
{
    public static IReadOnlyList<HostsEntry> Parse(string text)
    {
        var list = new List<HostsEntry>();
        var lines = text.Split('\n');
        for (var i = 0; i < lines.Length; i++)
        {
            var line = lines[i];
            var hash = line.IndexOf('#');
            if (hash >= 0)
            {
                line = line[..hash];
            }
            var parts = line.Split([' ', '\t'], StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length < 2)
            {
                continue;
            }
            foreach (var host in parts.Skip(1))
            {
                list.Add(new HostsEntry(i + 1, parts[0], host.ToLowerInvariant()));
            }
        }
        return list;
    }

    /// <summary>Loopback and blocking entries (0.0.0.0, 127.0.0.1, ::1) for localhost are the stock file.</summary>
    public static bool IsLocalhost(HostsEntry e) =>
        e.Host is "localhost" or "localhost.localdomain" or "local" or "broadcasthost" or "ip6-localhost" or "ip6-loopback";

    public static bool IsBlocking(HostsEntry e) => e.Address is "0.0.0.0" or "127.0.0.1" or "::1" or "::";
}

/// <summary>
/// WinHTTP proxy from HKLM\...\Internet Settings\Connections\WinHttpSettings (read instead of the
/// localized "netsh winhttp show proxy" output): DWORD version, DWORD counter, DWORD flags, then
/// length-prefixed ANSI proxy and bypass strings. Flags 0x2 = proxy set. VERIFY on 24H2.
/// </summary>
public static class WinHttpSettingsParser
{
    public static string? ParseProxy(byte[] data)
    {
        if (data.Length < 16)
        {
            return null;
        }
        var flags = BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(8));
        var len = BinaryPrimitives.ReadInt32LittleEndian(data.AsSpan(12));
        if ((flags & 0x2) == 0 || len <= 0 || 16 + len > data.Length)
        {
            return null;
        }
        return Encoding.ASCII.GetString(data, 16, len);
    }
}

/// <summary>M4 network and trust indicators. Everything here is "review", because VPNs, AV and companies set these legitimately.</summary>
public static class NetworkAnalyzer
{
    public const string ModuleId = "M4";

    /// <summary>Domains that malware redirects to stop updates, antivirus or to phish.</summary>
    private static readonly string[] Sensitive =
    [
        "microsoft.com", "windowsupdate.com", "update.microsoft.com", "windows.com", "live.com", "office.com", "msftconnecttest.com",
        "defender", "virustotal.com", "malwarebytes.com", "kaspersky", "eset.com", "avast.com", "avg.com", "norton", "bitdefender", "mcafee",
        "sophos", "trendmicro", "paypal.com", "bank", "google.com", "apple.com", "amazon.com",
    ];

    /// <summary>Well-known public resolvers: a static setting to one of these is a choice, not a finding.</summary>
    private static readonly HashSet<string> KnownResolvers = new(StringComparer.OrdinalIgnoreCase)
    {
        "1.1.1.1", "1.0.0.1", "1.1.1.2", "1.0.0.2", "1.1.1.3", "1.0.0.3", "8.8.8.8", "8.8.4.4", "9.9.9.9", "149.112.112.112", "9.9.9.11",
        "208.67.222.222", "208.67.220.220", "94.140.14.14", "94.140.15.15", "76.76.2.0", "76.76.10.0", "45.90.28.0", "45.90.30.0",
        "2606:4700:4700::1111", "2606:4700:4700::1001", "2001:4860:4860::8888", "2001:4860:4860::8844", "2620:fe::fe", "2620:fe::9",
    };

    public static ModuleResult Analyze(NetworkSnapshot s, DateTimeOffset now)
    {
        var checks = new List<CheckResult>();
        var findings = new List<Finding>();

        // hosts
        if (s.Hosts is null)
        {
            checks.Add(Checks.NotAvailable("M4.hosts", new Text("m4.check.hosts")));
        }
        else
        {
            var custom = s.Hosts.Where(e => !HostsParser.IsLocalhost(e)).ToList();
            var redirects = custom.Where(e => Sensitive.Any(d => e.Host.Contains(d, StringComparison.OrdinalIgnoreCase))).ToList();
            checks.Add(new CheckResult("M4.hosts", new Text("m4.check.hosts"), redirects.Count > 0 ? CheckStatus.Warn : CheckStatus.Info,
                new Text("m4.hosts.detail", custom.Count), FindingSource.Registry));
            if (redirects.Count > 0)
            {
                findings.Add(Make("M4.hostsSensitive", Severity.High, Confidence.Possible,
                    new Text("m4.hostsSensitive.title", redirects.Count), "m4.hostsSensitive",
                    redirects.Take(20).Select(e => new Evidence($"{s.HostsPath}:{e.Line}", $"{e.Address} {e.Host}")).ToList()));
            }
            else if (custom.Count(e => !HostsParser.IsBlocking(e)) > 0)
            {
                var other = custom.Where(e => !HostsParser.IsBlocking(e)).ToList();
                findings.Add(Make("M4.hostsCustom", Severity.Info, Confidence.Confirmed, new Text("m4.hostsCustom.title", other.Count), "m4.hostsCustom",
                    other.Take(20).Select(e => new Evidence($"{s.HostsPath}:{e.Line}", $"{e.Address} {e.Host}")).ToList()));
            }
        }
        if (s.HostsPathChanged)
        {
            findings.Add(Make("M4.hostsPath", Severity.High, Confidence.Probable, new Text("m4.hostsPath.title"), "m4.hostsPath",
                [new Evidence(@"HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\DataBasePath", s.HostsPath ?? "?", EvidenceKind.RegistryValue)]));
        }

        // proxy
        if (s.Proxy is null)
        {
            checks.Add(Checks.NotAvailable("M4.proxy", new Text("m4.check.proxy")));
        }
        else
        {
            var p = s.Proxy;
            var any = p.UserProxyEnabled && !string.IsNullOrEmpty(p.UserProxy) || !string.IsNullOrEmpty(p.AutoConfigUrl) || !string.IsNullOrEmpty(p.WinHttpProxy);
            checks.Add(new CheckResult("M4.proxy", new Text("m4.check.proxy"), any ? CheckStatus.Warn : CheckStatus.Pass,
                new Text(any ? "m4.proxy.set" : "m4.proxy.none"), FindingSource.Registry));
            if (any)
            {
                findings.Add(Make("M4.proxy", Severity.Medium, Confidence.Possible, new Text("m4.proxySet.title"), "m4.proxySet",
                [
                    new Evidence(@"HKCU\...\Internet Settings ProxyEnable / ProxyServer", $"{p.UserProxyEnabled} / {p.UserProxy}", EvidenceKind.RegistryValue),
                    new Evidence(@"HKCU\...\Internet Settings AutoConfigURL", p.AutoConfigUrl ?? "(none)", EvidenceKind.RegistryValue),
                    new Evidence("WinHTTP proxy", p.WinHttpProxy ?? "(direct)", EvidenceKind.RegistryValue),
                ]));
            }
        }

        // DNS
        if (s.Dns is null)
        {
            checks.Add(Checks.NotAvailable("M4.dns", new Text("m4.check.dns")));
        }
        else
        {
            var unknown = s.Dns.SelectMany(a => a.StaticServers.Where(srv => !KnownResolvers.Contains(srv) && !IsPrivate(srv)).Select(srv => (a.Name, srv))).ToList();
            checks.Add(new CheckResult("M4.dns", new Text("m4.check.dns"), unknown.Count > 0 ? CheckStatus.Warn : CheckStatus.Info,
                new Text("m4.dns.detail", s.Dns.Count(a => a.StaticServers.Count > 0)), FindingSource.Registry));
            if (unknown.Count > 0)
            {
                findings.Add(Make("M4.dns", Severity.Medium, Confidence.Possible, new Text("m4.dns.title", string.Join(", ", unknown.Select(u => u.srv).Distinct())), "m4.dns",
                    unknown.Select(u => new Evidence(u.Name, u.srv)).ToList()));
            }
        }

        // Root certificates: self-signed roots added in the last 90 days.
        if (s.Roots is null)
        {
            checks.Add(Checks.NotAvailable("M4.roots", new Text("m4.check.roots")));
        }
        else
        {
            var recent = s.Roots.Where(r => r.Subject == r.Issuer && (r.AddedUtc is { } a && now - a <= TimeSpan.FromDays(90) || r.Store == "CurrentUser")).ToList();
            checks.Add(new CheckResult("M4.roots", new Text("m4.check.roots"), CheckStatus.Info, new Text("m4.roots.detail", s.Roots.Count, recent.Count),
                FindingSource.Registry));
            foreach (var r in recent)
            {
                findings.Add(Make($"M4.root.{r.Thumbprint}", Severity.Low, Confidence.Possible, new Text("m4.root.title", ShortName(r.Subject)), "m4.root",
                [
                    new Evidence("Store", r.Store),
                    new Evidence("Subject", r.Subject),
                    new Evidence("Thumbprint", r.Thumbprint),
                    new Evidence("Added", r.AddedUtc?.ToString("yyyy-MM-dd") ?? "?"),
                ]));
            }
        }
        return new ModuleResult { ModuleId = ModuleId, ModuleName = new Text("m4.name"), Checks = checks, Findings = findings };
    }

    public static bool IsPrivate(string address)
    {
        if (!IPAddress.TryParse(address, out var ip))
        {
            return false;
        }
        if (IPAddress.IsLoopback(ip) || ip.IsIPv6LinkLocal || ip.IsIPv6SiteLocal || ip.IsIPv6UniqueLocal)
        {
            return true;
        }
        var b = ip.GetAddressBytes();
        return b.Length == 4 && (b[0] == 10 || b[0] == 172 && b[1] is >= 16 and <= 31 || b[0] == 192 && b[1] == 168 || b[0] == 100 && b[1] is >= 64 and <= 127);
    }

    private static string ShortName(string subject) =>
        subject.Split(", ").FirstOrDefault(p => p.StartsWith("CN=", StringComparison.Ordinal))?[3..] ?? subject;

    private static Finding Make(string id, Severity severity, Confidence confidence, Text title, string key, IReadOnlyList<Evidence> evidence) => new()
    {
        Id = id,
        Module = ModuleId,
        Severity = severity,
        Confidence = confidence,
        Source = FindingSource.Registry,
        Title = title,
        WhyItMatters = new Text(key + ".why"),
        Evidence = evidence,
        SuggestedAction = new Text(key + ".action"),
        Undo = UndoInfo.NothingChanged,
    };
}

public sealed class NetworkModule(Func<NetworkSnapshot> collect) : IModule
{
    public string Id => NetworkAnalyzer.ModuleId;
    public Text Name => new("m4.name");

    public Task<ModuleResult> RunAsync(ScanContext context) =>
        Task.Run(() => NetworkAnalyzer.Analyze(collect(), context.Now), context.CancellationToken);

    [SupportedOSPlatform("windows")]
    public static NetworkModule ForWindows() => new(NetworkReader.Read);
}

[SupportedOSPlatform("windows")]
public static partial class NetworkReader
{
    public static NetworkSnapshot Read()
    {
        using var tcpip = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Services\Tcpip\Parameters");
        var defaultDb = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "drivers", "etc");
        var db = tcpip?.GetValue("DataBasePath") is string p ? Environment.ExpandEnvironmentVariables(p) : defaultDb;
        var hostsPath = Path.Combine(db, "hosts");
        IReadOnlyList<HostsEntry>? hosts = null;
        try
        {
            hosts = File.Exists(hostsPath) ? HostsParser.Parse(File.ReadAllText(hostsPath)) : [];
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
        }

        using var inet = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Internet Settings");
        using var conns = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Connections");
        var proxy = new ProxySettings(inet?.GetValue("ProxyEnable") is int en && en != 0, inet?.GetValue("ProxyServer") as string,
            inet?.GetValue("AutoConfigURL") as string, conns?.GetValue("WinHttpSettings") is byte[] w ? WinHttpSettingsParser.ParseProxy(w) : null);

        var dns = new List<DnsAdapter>();
        using (var ifs = tcpip?.OpenSubKey("Interfaces"))
        {
            var names = System.Net.NetworkInformation.NetworkInterface.GetAllNetworkInterfaces().ToDictionary(n => n.Id, n => n.Name, StringComparer.OrdinalIgnoreCase);
            foreach (var guid in ifs?.GetSubKeyNames() ?? [])
            {
                using var k = ifs!.OpenSubKey(guid);
                static string[] Split(object? v) => (v as string ?? "").Split([',', ' '], StringSplitOptions.RemoveEmptyEntries);
                var stat = Split(k?.GetValue("NameServer"));
                var dhcp = Split(k?.GetValue("DhcpNameServer"));
                if (stat.Length + dhcp.Length > 0)
                {
                    dns.Add(new DnsAdapter(names.GetValueOrDefault(guid, guid), stat, dhcp));
                }
            }
        }

        var roots = new List<RootCert>();
        foreach (var location in new[] { StoreLocation.LocalMachine, StoreLocation.CurrentUser })
        {
            using var store = new X509Store(StoreName.Root, location);
            store.Open(OpenFlags.ReadOnly | OpenFlags.OpenExistingOnly);
            var regRoot = location == StoreLocation.LocalMachine ? Registry.LocalMachine : Registry.CurrentUser;
            foreach (var c in store.Certificates)
            {
                using var key = regRoot.OpenSubKey($@"SOFTWARE\Microsoft\SystemCertificates\ROOT\Certificates\{c.Thumbprint}");
                roots.Add(new RootCert(location.ToString(), c.Subject, c.Issuer, c.Thumbprint, c.NotBefore.ToUniversalTime(),
                    key is null ? null : LastWrite(key)));
                c.Dispose();
            }
        }
        return new NetworkSnapshot
        {
            HostsPath = hostsPath,
            Hosts = hosts,
            HostsPathChanged = !string.Equals(Path.GetFullPath(db).TrimEnd('\\'), Path.GetFullPath(defaultDb).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase),
            Proxy = proxy,
            Dns = dns,
            Roots = roots,
        };
    }

    /// <summary>When the certificate's registry key was last written: the closest record of when it was added.</summary>
    private static DateTimeOffset? LastWrite(RegistryKey key)
    {
        if (RegQueryInfoKeyW(key.Handle, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero,
                IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, out var ft) != 0)
        {
            return null;
        }
        return DateTimeOffset.FromFileTime(ft).ToUniversalTime();
    }

    [System.Runtime.InteropServices.LibraryImport("advapi32.dll")]
    private static partial int RegQueryInfoKeyW(Microsoft.Win32.SafeHandles.SafeRegistryHandle key, IntPtr cls, IntPtr clsLen, IntPtr reserved,
        IntPtr subKeys, IntPtr maxSubKeyLen, IntPtr maxClassLen, IntPtr values, IntPtr maxValueNameLen, IntPtr maxValueLen,
        IntPtr securityDescriptor, out long lastWriteTime);
}
