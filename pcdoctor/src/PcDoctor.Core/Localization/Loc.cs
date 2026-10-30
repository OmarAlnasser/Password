using System.Globalization;
using System.Resources;
using System.Text;
using PcDoctor.Core.Findings;

namespace PcDoctor.Core.Localization;

public enum DigitStyle { Western, ArabicIndic }

/// <summary>
/// The single string table for UI, findings and reports (Resources/Strings.resx and Strings.ar.resx).
/// A missing key renders as [[key]] so it is visible in the UI and caught by the parity test.
/// </summary>
public static class Loc
{
    private static readonly ResourceManager Resources =
        new("PcDoctor.Core.Resources.Strings", typeof(Loc).Assembly);

    public static IReadOnlyList<CultureInfo> SupportedCultures { get; } =
        [CultureInfo.GetCultureInfo("en-US"), CultureInfo.GetCultureInfo("ar-SA")];

    public static CultureInfo Culture { get; set; } = CultureInfo.GetCultureInfo("en-US");

    public static DigitStyle Digits { get; set; } = DigitStyle.Western;

    public static bool IsRightToLeft(CultureInfo? culture = null) =>
        (culture ?? Culture).TextInfo.IsRightToLeft;

    private static readonly List<Func<string, CultureInfo, string?>> Providers = [];

    /// <summary>
    /// Adds a string source outside the .resx table, such as the bug check knowledge base, which
    /// keeps per-language fields in JSON.
    /// </summary>
    public static void RegisterProvider(Func<string, CultureInfo, string?> provider)
    {
        lock (Providers)
        {
            Providers.Add(provider);
        }
    }

    public static string Get(string key, CultureInfo? culture = null) =>
        TryGet(key, culture ?? Culture, out var value) ? value : $"[[{key}]]";

    public static bool TryGet(string key, CultureInfo culture, out string value)
    {
        value = Resources.GetString(key, culture) ?? "";
        if (value.Length > 0)
        {
            return true;
        }
        lock (Providers)
        {
            foreach (var p in Providers)
            {
                if (p(key, culture) is { Length: > 0 } v)
                {
                    value = v;
                    return true;
                }
            }
        }
        return false;
    }

    public static string Resolve(Text text, CultureInfo? culture = null)
    {
        culture ??= Culture;
        var template = Get(text.Key, culture);
        var args = text.Args.Select(a => (object)a).ToArray();
        string result;
        try
        {
            result = args.Length == 0 ? template : string.Format(culture, template, args);
        }
        catch (FormatException)
        {
            result = template;
        }
        return ApplyDigits(result, culture);
    }

    public static string Format(string key, params object[] args) => Resolve(new Text(key, args));

    /// <summary>Formats an argument for <see cref="Text"/> without culture-specific grouping or digits.</summary>
    public static string FormatArg(object value) => value switch
    {
        null => "",
        string s => s,
        DateTimeOffset d => d.ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture),
        DateTime d => d.ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture),
        DateOnly d => d.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
        double v => v.ToString("0.#", CultureInfo.InvariantCulture),
        float v => v.ToString("0.#", CultureInfo.InvariantCulture),
        decimal v => v.ToString("0.#", CultureInfo.InvariantCulture),
        IFormattable f => f.ToString(null, CultureInfo.InvariantCulture),
        _ => value.ToString() ?? "",
    };

    /// <summary>
    /// Converts Western digits to Arabic-Indic for Arabic prose when the user asks for it.
    /// Evidence (paths, hashes, event IDs) never goes through here.
    /// </summary>
    public static string ApplyDigits(string s, CultureInfo culture)
    {
        if (Digits != DigitStyle.ArabicIndic || !culture.TextInfo.IsRightToLeft)
        {
            return s;
        }
        var sb = new StringBuilder(s.Length);
        foreach (var c in s)
        {
            sb.Append(c is >= '0' and <= '9' ? (char)('٠' + (c - '0')) : c);
        }
        return sb.ToString();
    }
}
