using System.Text.RegularExpressions;

namespace PcDoctor.Modules.Persistence;

/// <summary>
/// "Living off the land": malware often does not drop its own program. It makes a Microsoft-signed tool
/// (PowerShell, mshta, regsvr32, rundll32, certutil...) start at boot with arguments that download or
/// decode and run something. The file is signed by Microsoft, so a signature check alone sees nothing.
/// This looks at the command line instead. It is a heuristic: each reason is named in the finding, and
/// some legitimate software matches too, so the finding never says the entry is malware.
/// </summary>
public static partial class SuspiciousCommand
{
    /// <param name="Strong">True when the pattern has almost no legitimate use in a startup entry.</param>
    public sealed record Reason(string Code, bool Strong);

    private static readonly string[] Interpreters =
    [
        "powershell", "pwsh", "cmd", "wscript", "cscript", "mshta", "rundll32", "regsvr32", "msiexec", "bitsadmin", "certutil",
        "wmic", "forfiles", "conhost", "curl", "installutil", "msbuild", "regasm", "regsvcs", "odbcconf", "cmstp", "hh", "pcalua",
    ];

    private static readonly string[] UserWritableFragments =
        [@"\appdata\", @"\temp\", @"\users\public\", @"\programdata\", @"\downloads\", @"%temp%", @"%appdata%", @"%localappdata%", @"%public%", @"\$recycle.bin\"];

    [GeneratedRegex(@"(?:^|\s)[-/]e(?:c|nc|ncodedcommand)?\s+[A-Za-z0-9+/=]{24,}", RegexOptions.IgnoreCase)]
    private static partial Regex EncodedPowerShell();

    [GeneratedRegex(@"(?:^|\s)[-/]w(?:in|indowstyle)?\s+(?:h|hid|hidden|1)\b", RegexOptions.IgnoreCase)]
    private static partial Regex HiddenWindow();

    [GeneratedRegex(@"\b(?:iex|invoke-expression)\b|\[scriptblock\]::create", RegexOptions.IgnoreCase)]
    private static partial Regex RunsText();

    [GeneratedRegex(@"downloadstring|downloadfile|downloaddata|invoke-webrequest|invoke-restmethod|\b(?:iwr|irm)\b|net\.webclient|start-bitstransfer|\bcurl(?:\.exe)?\s|\bwget\s", RegexOptions.IgnoreCase)]
    private static partial Regex Downloads();

    [GeneratedRegex(@"https?://|ftp://|\\\\\d{1,3}(?:\.\d{1,3}){3}\\", RegexOptions.IgnoreCase)]
    private static partial Regex RemoteAddress();

    [GeneratedRegex(@"[A-Za-z0-9+/]{200,}={0,2}")]
    private static partial Regex LongBase64();

    /// <summary>Why this command line looks like abuse of a built-in tool; empty when nothing stands out.</summary>
    public static IReadOnlyList<Reason> Reasons(string? command)
    {
        if (string.IsNullOrWhiteSpace(command))
        {
            return [];
        }
        var c = command.Trim();
        var lower = c.ToLowerInvariant();
        if (!Interpreters.Any(i => Mentions(lower, i)))
        {
            return [];
        }
        var reasons = new List<Reason>();
        var powershell = Mentions(lower, "powershell") || Mentions(lower, "pwsh");
        if (powershell && EncodedPowerShell().IsMatch(c) || lower.Contains("frombase64string", StringComparison.Ordinal) || LongBase64().IsMatch(c))
        {
            reasons.Add(new Reason("encoded", true));
        }
        if (powershell && HiddenWindow().IsMatch(c))
        {
            reasons.Add(new Reason("hidden", false));
        }
        if (powershell && RunsText().IsMatch(c))
        {
            reasons.Add(new Reason("runsText", false));
        }
        if (powershell && lower.Contains("bypass", StringComparison.Ordinal))
        {
            reasons.Add(new Reason("policyBypass", false));
        }
        if (Downloads().IsMatch(c) || Mentions(lower, "bitsadmin") && lower.Contains("/transfer", StringComparison.Ordinal) ||
            Mentions(lower, "certutil") && lower.Contains("urlcache", StringComparison.Ordinal))
        {
            reasons.Add(new Reason("download", true));
        }
        if (Mentions(lower, "certutil") && (lower.Contains("-decode", StringComparison.Ordinal) || lower.Contains("/decode", StringComparison.Ordinal)))
        {
            reasons.Add(new Reason("decode", true));
        }
        if (Mentions(lower, "mshta") && (RemoteAddress().IsMatch(c) || lower.Contains("javascript:", StringComparison.Ordinal) || lower.Contains("vbscript:", StringComparison.Ordinal)))
        {
            reasons.Add(new Reason("mshtaScript", true));
        }
        if (Mentions(lower, "regsvr32") && (lower.Contains("scrobj", StringComparison.Ordinal) || lower.Contains("/i:http", StringComparison.Ordinal)))
        {
            reasons.Add(new Reason("regsvr32Script", true));
        }
        if (Mentions(lower, "rundll32") && (lower.Contains("javascript:", StringComparison.Ordinal) || lower.Contains("mshtml,runhtmlapplication", StringComparison.Ordinal)))
        {
            reasons.Add(new Reason("rundll32Script", true));
        }
        if (Mentions(lower, "msiexec") && RemoteAddress().IsMatch(c))
        {
            reasons.Add(new Reason("remoteInstall", true));
        }
        if ((Mentions(lower, "wscript") || Mentions(lower, "cscript") || Mentions(lower, "rundll32") || Mentions(lower, "regsvr32") || Mentions(lower, "mshta")) &&
            UserWritableFragments.Any(f => lower.Contains(f, StringComparison.Ordinal)))
        {
            reasons.Add(new Reason("userFolder", false));
        }
        if (reasons.Count > 0 && !reasons.Any(r => r.Code is "download" or "mshtaScript" or "remoteInstall") && RemoteAddress().IsMatch(c))
        {
            reasons.Add(new Reason("remoteAddress", false));
        }
        return reasons;
    }

    /// <summary>The tool name as a whole word: "cmd" must not match "cmdkey" or a folder called "mycmd".</summary>
    private static bool Mentions(string lower, string tool)
    {
        for (var i = lower.IndexOf(tool, StringComparison.Ordinal); i >= 0; i = lower.IndexOf(tool, i + 1, StringComparison.Ordinal))
        {
            var before = i == 0 ? ' ' : lower[i - 1];
            var end = i + tool.Length;
            var after = end >= lower.Length ? ' ' : lower[end];
            if (!char.IsLetterOrDigit(before) && before != '_' && (after is ' ' or '"' or '\'' or '\t' || lower.AsSpan(end).StartsWith(".exe", StringComparison.Ordinal)))
            {
                return true;
            }
        }
        return false;
    }
}
