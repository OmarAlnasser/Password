using System.Text.RegularExpressions;

namespace PcDoctor.Core.Localization;

/// <summary>
/// Phrases PC Doctor must never show: they claim more than any scan can prove. Used by the
/// acceptance test over every string and every generated report, and by report export at runtime.
/// </summary>
public static partial class HonestyGuard
{
    [GeneratedRegex(
        @"\bclean\b|\b100\s?%|\ball viruses\b|\bguaranteed\b|\b100% safe\b|\bvirus[- ]free\b|\bfully protected\b" +
        // Arabic: "clean/free of viruses", "100%", "guaranteed", "all viruses"
        @"|نظيف|خال[ٍي]? من الفيروسات|جميع الفيروسات|مضمون|١٠٠٪",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex Banned();

    public static IReadOnlyList<string> FindBannedPhrases(string text) =>
        Banned().Matches(text).Select(m => m.Value).Distinct().ToList();

    public static void ThrowIfBanned(string text, string where)
    {
        var hits = FindBannedPhrases(text);
        if (hits.Count > 0)
        {
            throw new InvalidOperationException(
                $"Honesty rule violated in {where}: {string.Join(", ", hits)}");
        }
    }
}
