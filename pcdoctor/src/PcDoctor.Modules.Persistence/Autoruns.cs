using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using PcDoctor.Core.Platform;

namespace PcDoctor.Modules.Persistence;

public enum AutorunCategory
{
    RunKey,
    StartupFolder,
    Service,
    Driver,
    ScheduledTask,
    WmiSubscription,
    Winlogon,
    AppInit,
    ImageFileExecution,
    Accessibility,
    BootExecute,
    Lsa,
    PrintMonitor,
    WinsockProvider,
    ComHijack,
    OfficeAddin,
    BrowserExtension,
    PowerShellProfile,
    ScreenSaver,
}

/// <summary>
/// One place something starts from. <see cref="Location"/> is where it is registered (registry key,
/// folder, task path); <see cref="Command"/> what it runs; <see cref="Image"/> the resolved file.
/// </summary>
public sealed record AutorunEntry
{
    public required AutorunCategory Category { get; init; }
    public required string Location { get; init; }
    public required string Name { get; init; }
    public string Command { get; init; } = "";
    /// <summary>The registry value as stored, for entries that are registry values (needed to disable and restore exactly).</summary>
    public Core.Journal.RegistryData? Value { get; init; }
    public string? Image { get; init; }
    public bool Enabled { get; init; } = true;
    /// <summary>For services: Automatic / Manual / Boot / System. For tasks: hidden flag in Detail.</summary>
    public string? Detail { get; init; }
    public SignatureInfo? Signature { get; init; }
    public string? Sha256 { get; init; }
    public bool ImageUserWritable { get; init; }
    /// <summary>Script text (WMI ActiveScript consumer, PowerShell profile) for AMSI.</summary>
    public string? ScriptText { get; init; }
    /// <summary>AMSI verdict on <see cref="ScriptText"/> or the command line; null = not scanned.</summary>
    public int? AmsiResult { get; init; }
    /// <summary>VirusTotal hash-lookup counts, when the user enabled it.</summary>
    public VtVerdict? VirusTotal { get; init; }

    /// <summary>Stable ID the Broker uses to find this entry again; never a path the UI can choose.</summary>
    public string Id => MakeId(Category, Location, Name);

    public static string MakeId(AutorunCategory category, string location, string name) =>
        category + ":" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes($"{category}|{location}|{name}".ToUpperInvariant())))[..16];

    public bool IsMicrosoft => Signature?.Status == SignatureStatus.MicrosoftSigned;
}

public sealed record VtVerdict(int Malicious, int Suspicious, int Undetected, int Harmless, DateTimeOffset CheckedUtc);

public static partial class CommandLines
{
    [GeneratedRegex(@"%([^%]+)%")]
    private static partial Regex EnvVar();

    /// <summary>
    /// The executable or DLL a command line actually loads: quotes, environment variables, rundll32
    /// "file.dll,Entry", unquoted paths with spaces (the longest existing prefix ending in .exe), and
    /// \??\ or \SystemRoot\ prefixes from service ImagePath values.
    /// </summary>
    public static string? ResolveImage(string command, Func<string, bool> exists, Func<string, string?> env)
    {
        var c = Expand(command.Trim(), env);
        if (c.Length == 0)
        {
            return null;
        }
        if (c.StartsWith(@"\??\", StringComparison.Ordinal))
        {
            c = c[4..];
        }
        if (c.StartsWith(@"\SystemRoot\", StringComparison.OrdinalIgnoreCase))
        {
            c = (env("SystemRoot") ?? @"C:\Windows") + c[11..];
        }
        if (c.StartsWith(@"system32\", StringComparison.OrdinalIgnoreCase))
        {
            c = (env("SystemRoot") ?? @"C:\Windows") + @"\" + c;
        }

        string first;
        string rest;
        if (c.StartsWith('"'))
        {
            var end = c.IndexOf('"', 1);
            first = end > 0 ? c[1..end] : c[1..];
            rest = end > 0 ? c[(end + 1)..].Trim() : "";
        }
        else
        {
            var exe = c.IndexOf(".exe", StringComparison.OrdinalIgnoreCase);
            first = LongestExisting(c, exists) ?? (exe > 0 ? c[..(exe + 4)] : c.Split(' ')[0]);
            rest = c.Length > first.Length ? c[first.Length..].Trim() : "";
        }

        var name = WinPath.FileName(first);
        if (name.Equals("rundll32.exe", StringComparison.OrdinalIgnoreCase) || name.Equals("rundll32", StringComparison.OrdinalIgnoreCase))
        {
            var dll = rest.Trim('"').Split(',')[0].Trim().Trim('"');
            if (dll.Length > 0)
            {
                return dll.Contains('\\') ? dll : WinPath.Join(env("SystemRoot") ?? @"C:\Windows", "System32", dll);
            }
        }
        if (!first.Contains('\\') && !first.Contains('/'))
        {
            // Bare name ("svchost.exe -k ..."): Windows looks in System32.
            var sys = WinPath.Join(env("SystemRoot") ?? @"C:\Windows", "System32", first.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ? first : first + ".exe");
            return sys;
        }
        return first;
    }

    /// <summary>True when an unquoted path contains a space before its .exe: "C:\Program Files\A B\x.exe".</summary>
    public static bool IsUnquotedWithSpaces(string command)
    {
        var c = command.Trim();
        if (c.StartsWith('"'))
        {
            return false;
        }
        var exe = c.IndexOf(".exe", StringComparison.OrdinalIgnoreCase);
        return exe > 0 && c[..exe].Contains(' ');
    }

    public static string Expand(string s, Func<string, string?> env) =>
        EnvVar().Replace(s, m => env(m.Groups[1].Value) ?? m.Value);

    private static string? LongestExisting(string c, Func<string, bool> exists)
    {
        // Try every prefix that ends at a space or at the end, longest first.
        var cuts = new List<int> { c.Length };
        for (var i = c.Length - 1; i > 0; i--)
        {
            if (c[i] == ' ')
            {
                cuts.Add(i);
            }
        }
        foreach (var cut in cuts)
        {
            var candidate = c[..cut];
            if (exists(candidate))
            {
                return candidate;
            }
            if (!candidate.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) && exists(candidate + ".exe"))
            {
                return candidate + ".exe";
            }
        }
        return null;
    }
}
