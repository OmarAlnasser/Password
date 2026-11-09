using System.Buffers.Binary;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace PcDoctor.Modules.Crash;

/// <summary>Stop code and parameters read straight from a kernel dump header (no debugger needed).</summary>
public sealed record DumpHeader(bool Is64Bit, uint BugcheckCode, IReadOnlyList<ulong> Parameters, int Processors);

/// <summary>What `cdb -z dump -c "!analyze -v"` reported.</summary>
public sealed record AnalyzeResult(
    uint? BugcheckCode,
    IReadOnlyList<string> Parameters,
    string? ModuleName,
    string? ImageName,
    string? FailureBucketId,
    string? ProcessName,
    string? ProbablyCausedBy,
    IReadOnlyList<string> Stack,
    bool SymbolsLoaded,
    string RawOutput);

/// <summary>One dump file, analysed with the debugger when it is installed and always with the header parser.</summary>
public sealed record DumpAnalysis(
    string Path,
    DateTimeOffset LastWriteUtc,
    long SizeBytes,
    DumpHeader? Header,
    AnalyzeResult? Analyze,
    IReadOnlyList<string> ModuleNames,
    string? Error);

/// <summary>
/// Kernel dump header (DUMP_HEADER64 "PAGEDU64" / DUMP_HEADER32 "PAGEDUMP"). BugCheckCode sits at
/// 0x38 with 64-bit parameters from 0x40 (64-bit), or at 0x20 with 32-bit parameters from 0x24.
/// VERIFY against a real minidump; the debugger path is used whenever cdb is installed.
/// </summary>
public static partial class DumpHeaderParser
{
    public static DumpHeader? Parse(ReadOnlySpan<byte> head)
    {
        if (head.Length < 0x60 || !head[..4].SequenceEqual("PAGE"u8))
        {
            return null;
        }
        if (head[4..8].SequenceEqual("DU64"u8))
        {
            return new DumpHeader(true,
                BinaryPrimitives.ReadUInt32LittleEndian(head[0x38..]),
                [
                    BinaryPrimitives.ReadUInt64LittleEndian(head[0x40..]),
                    BinaryPrimitives.ReadUInt64LittleEndian(head[0x48..]),
                    BinaryPrimitives.ReadUInt64LittleEndian(head[0x50..]),
                    BinaryPrimitives.ReadUInt64LittleEndian(head[0x58..]),
                ],
                (int)BinaryPrimitives.ReadUInt32LittleEndian(head[0x34..]));
        }
        if (head[4..8].SequenceEqual("DUMP"u8))
        {
            return new DumpHeader(false,
                BinaryPrimitives.ReadUInt32LittleEndian(head[0x20..]),
                [
                    BinaryPrimitives.ReadUInt32LittleEndian(head[0x24..]),
                    BinaryPrimitives.ReadUInt32LittleEndian(head[0x28..]),
                    BinaryPrimitives.ReadUInt32LittleEndian(head[0x2C..]),
                    BinaryPrimitives.ReadUInt32LittleEndian(head[0x30..]),
                ],
                (int)BinaryPrimitives.ReadUInt32LittleEndian(head[0x1C..]));
        }
        return null;
    }

    [GeneratedRegex(@"[A-Za-z0-9_\-\.]{2,60}\.(?:sys|dll|exe)", RegexOptions.IgnoreCase)]
    private static partial Regex ModuleFile();

    /// <summary>
    /// Driver and module file names stored as UTF-16 strings in a minidump (its loaded-module
    /// string pool). Only names: without the debugger PC Doctor cannot tell which one crashed.
    /// </summary>
    public static IReadOnlyList<string> ModuleNames(ReadOnlySpan<byte> dump, int max = 400)
    {
        var text = Encoding.Unicode.GetString(dump.Length % 2 == 0 ? dump : dump[..^1]);
        return ModuleFile().Matches(text)
            .Select(m => m.Value.ToLowerInvariant())
            .Distinct()
            .Take(max)
            .ToList();
    }
}

/// <summary>Parses `!analyze -v` text. Field names are stable across WinDbg versions; the rest is ignored.</summary>
public static partial class AnalyzeOutputParser
{
    [GeneratedRegex(@"^(BUGCHECK_CODE|BUGCHECK_P1|BUGCHECK_P2|BUGCHECK_P3|BUGCHECK_P4|MODULE_NAME|IMAGE_NAME|FAILURE_BUCKET_ID|PROCESS_NAME)\s*:\s*(.+?)\s*$",
        RegexOptions.Multiline)]
    private static partial Regex Field();

    [GeneratedRegex(@"^Probably caused by\s*:\s*(.+?)\s*$", RegexOptions.Multiline)]
    private static partial Regex ProbablyCausedBy();

    public static AnalyzeResult Parse(string output)
    {
        var fields = new Dictionary<string, string>();
        foreach (Match m in Field().Matches(output))
        {
            fields.TryAdd(m.Groups[1].Value, m.Groups[2].Value);
        }
        uint? code = fields.TryGetValue("BUGCHECK_CODE", out var c) &&
                     uint.TryParse(c.Replace("0x", "", StringComparison.OrdinalIgnoreCase).Replace("`", "", StringComparison.Ordinal),
                         NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var v)
            ? v
            : null;
        var parameters = new[] { "BUGCHECK_P1", "BUGCHECK_P2", "BUGCHECK_P3", "BUGCHECK_P4" }
            .Select(k => fields.GetValueOrDefault(k, "")).ToList();

        var stack = new List<string>();
        var lines = output.Split('\n');
        var start = Array.FindIndex(lines, l => l.TrimEnd().Equals("STACK_TEXT:", StringComparison.Ordinal));
        if (start >= 0)
        {
            for (var i = start + 1; i < lines.Length && !string.IsNullOrWhiteSpace(lines[i]) && stack.Count < 40; i++)
            {
                stack.Add(lines[i].TrimEnd());
            }
        }
        var noSymbols = output.Contains("Symbols can not be loaded", StringComparison.OrdinalIgnoreCase) ||
                        output.Contains("*** ERROR: Symbol file could not be found", StringComparison.OrdinalIgnoreCase) ||
                        output.Contains("WRONG_SYMBOLS", StringComparison.Ordinal);

        return new AnalyzeResult(code, parameters, fields.GetValueOrDefault("MODULE_NAME"), fields.GetValueOrDefault("IMAGE_NAME"),
            fields.GetValueOrDefault("FAILURE_BUCKET_ID"), fields.GetValueOrDefault("PROCESS_NAME"),
            ProbablyCausedBy().Match(output) is { Success: true } p ? p.Groups[1].Value : null,
            stack, !noSymbols, output);
    }

    /// <summary>Extra debugger commands per stop code (DESIGN: 0x124 → !errrec P2 and !whea; 0x133 → !dpcs).</summary>
    public static string FollowUps(uint? code, IReadOnlyList<ulong>? parameters) => code switch
    {
        0x124 when parameters is { Count: > 1 } => $"; !errrec 0x{parameters[1]:x}; !whea",
        0x124 => "; !whea",
        0x133 => "; !dpcs",
        _ => "",
    };
}

/// <summary>A Windows Error Reporting Report.wer file (UTF-16 with BOM, or UTF-8), key=value lines.</summary>
public sealed record WerReport(string Path, string EventType, string? AppName, string? AppPath, DateTimeOffset? Time,
    IReadOnlyDictionary<string, string> Signature);

public static class WerReportParser
{
    public static WerReport? Parse(string path, byte[] bytes)
    {
        string text;
        if (bytes.Length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE)
        {
            text = Encoding.Unicode.GetString(bytes, 2, bytes.Length - 2);
        }
        else if (bytes.Length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF)
        {
            text = Encoding.UTF8.GetString(bytes, 3, bytes.Length - 3);
        }
        else
        {
            // No BOM: UTF-16 if every other byte is zero in the first line, else UTF-8.
            text = bytes.Length > 4 && bytes[1] == 0 && bytes[3] == 0 ? Encoding.Unicode.GetString(bytes) : Encoding.UTF8.GetString(bytes);
        }
        var values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var line in text.Split('\n'))
        {
            var eq = line.IndexOf('=');
            if (eq > 0)
            {
                values.TryAdd(line[..eq].Trim(), line[(eq + 1)..].Trim());
            }
        }
        if (!values.TryGetValue("EventType", out var eventType))
        {
            return null;
        }
        var signature = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        for (var i = 0; i < 16; i++)
        {
            if (values.TryGetValue($"Sig[{i}].Name", out var n) && values.TryGetValue($"Sig[{i}].Value", out var v))
            {
                signature.TryAdd(n, v);
            }
        }
        DateTimeOffset? time = values.TryGetValue("EventTime", out var t) && long.TryParse(t, out var ft) && ft > 0
            ? DateTimeOffset.FromFileTime(ft).ToUniversalTime()
            : null;
        return new WerReport(path, eventType,
            values.GetValueOrDefault("AppName") ?? signature.GetValueOrDefault("Application Name"),
            values.GetValueOrDefault("AppPath"), time, signature);
    }
}
