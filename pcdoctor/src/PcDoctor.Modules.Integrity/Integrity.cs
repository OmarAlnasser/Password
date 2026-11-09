using System.Globalization;
using System.Text.RegularExpressions;

namespace PcDoctor.Modules.Integrity;

public enum ImageHealth { Healthy, Repairable, NonRepairable, Repaired, Failed }

/// <summary>DISM result. State comes from the DISM API's DismImageHealthState, not from localized text.</summary>
public sealed record DismResult(string Operation, ImageHealth State, int HResult, string? Message);

public sealed record SfcResult(int ExitCode, IReadOnlyList<string> Repaired, IReadOnlyList<string> Unrepairable, int CorruptionLines, bool LogReadable)
{
    public bool FoundCorruption => Repaired.Count + Unrepairable.Count + CorruptionLines > 0;
}

public sealed record ChkdskResult(string Volume, int ExitCode, string Output)
{
    /// <summary>chkdsk exit codes: 0 no errors, 1 errors found and fixed, 2 cleanup without fixing, 3 could not check or errors not fixed.</summary>
    public string Meaning => ExitCode switch { 0 => "none", 1 => "fixed", 2 => "cleanup", 3 => "errors", _ => "unknown" };
}

public sealed record SimpleJobResult(int ExitCode, string Output);

public static partial class DismProgress
{
    [GeneratedRegex(@"\[[= ]*(\d{1,3}(?:[.,]\d)?)%[= ]*\]")]
    private static partial Regex Bar();

    /// <summary>Reads "[==== 62.3% ====]" from DISM console output (used when the API is unavailable).</summary>
    public static double? Parse(string line) =>
        Bar().Matches(line).LastOrDefault() is { } m &&
        double.TryParse(m.Groups[1].Value.Replace(',', '.'), NumberStyles.Float, CultureInfo.InvariantCulture, out var v)
            ? Math.Clamp(v / 100, 0, 1)
            : null;
}

/// <summary>
/// The [SR] lines SFC writes to CBS.log (always English). "Repairing corrupted file … from store" and
/// "Repaired file … by copying from backup" are repairs; "Cannot repair member file" is unrepairable.
/// </summary>
public static partial class CbsLogParser
{
    [GeneratedRegex(@"^(?<time>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}),[^\[]*\[SR\]\s*(?<msg>.+)$", RegexOptions.Multiline)]
    private static partial Regex SrLine();

    [GeneratedRegex(@"\\\??\\?(?<path>[A-Za-z]:\\[^\s""\]]+)")]
    private static partial Regex FilePath();

    [GeneratedRegex(@"file \[l:\d+\]""(?<name>[^""]+)""", RegexOptions.IgnoreCase)]
    private static partial Regex MemberName();

    public static SfcResult Parse(string cbsLog, DateTime sinceLocal, int exitCode)
    {
        var repaired = new List<string>();
        var unrepairable = new List<string>();
        var corrupt = 0;
        foreach (Match m in SrLine().Matches(cbsLog))
        {
            if (!DateTime.TryParseExact(m.Groups["time"].Value, "yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture, DateTimeStyles.None, out var t) ||
                t < sinceLocal)
            {
                continue;
            }
            var msg = m.Groups["msg"].Value;
            var file = FilePath().Match(msg) is { Success: true } p ? p.Groups["path"].Value
                : MemberName().Match(msg) is { Success: true } n ? n.Groups["name"].Value
                : msg;
            if (msg.Contains("Cannot repair member file", StringComparison.OrdinalIgnoreCase))
            {
                unrepairable.Add(file);
            }
            else if (msg.Contains("Repaired file", StringComparison.OrdinalIgnoreCase) || msg.Contains("Repairing corrupted file", StringComparison.OrdinalIgnoreCase))
            {
                repaired.Add(file);
            }
            else if (msg.Contains("Hashes for file member", StringComparison.OrdinalIgnoreCase) && msg.Contains("do not match", StringComparison.OrdinalIgnoreCase))
            {
                corrupt++;
            }
        }
        // A file repaired later in the same run is no longer unrepairable.
        unrepairable.RemoveAll(u => repaired.Contains(u, StringComparer.OrdinalIgnoreCase));
        return new SfcResult(exitCode, repaired.Distinct(StringComparer.OrdinalIgnoreCase).ToList(),
            unrepairable.Distinct(StringComparer.OrdinalIgnoreCase).ToList(), corrupt, true);
    }
}

/// <summary>Driver Verifier arguments. Only named .sys drivers, never /all, never core Windows images.</summary>
public static partial class VerifierArgs
{
    [GeneratedRegex(@"^[A-Za-z0-9_\-\.]{1,64}\.sys$")]
    private static partial Regex DriverName();

    private static readonly HashSet<string> Never = new(StringComparer.OrdinalIgnoreCase)
    {
        "ntoskrnl.sys", "hal.sys", "ci.sys", "ntfs.sys", "disk.sys", "classpnp.sys", "storport.sys", "stornvme.sys", "acpi.sys", "pci.sys", "volmgr.sys",
    };

    public static IReadOnlyList<string>? Drivers(string? target)
    {
        var names = (target ?? "").Split(' ', StringSplitOptions.RemoveEmptyEntries).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        if (names.Count is 0 or > 8 || names.Any(n => !DriverName().IsMatch(n) || Never.Contains(n)))
        {
            return null;
        }
        return names;
    }

    public static IReadOnlyList<string> Enable(IReadOnlyList<string> drivers) => ["/standard", "/driver", .. drivers];
}
