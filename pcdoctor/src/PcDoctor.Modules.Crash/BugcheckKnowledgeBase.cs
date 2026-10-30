using System.Globalization;
using System.Text.Json;
using PcDoctor.Core.Localization;

namespace PcDoctor.Modules.Crash;

public sealed record BugcheckEntry(uint Code, string Name, string Kind, IReadOnlyDictionary<string, string> Cause,
    IReadOnlyDictionary<string, string> Next);

/// <summary>
/// Stop-code explanations from bugchecks.json. Registers keys "kb.&lt;code&gt;.cause" and
/// "kb.&lt;code&gt;.next" with <see cref="Loc"/> so findings stay plain <see cref="Core.Findings.Text"/>.
/// </summary>
public static class BugcheckKnowledgeBase
{
    private static readonly Lazy<IReadOnlyDictionary<uint, BugcheckEntry>> Entries = new(Load);
    private static readonly Lazy<(IReadOnlyList<DriverInfo> Drivers, IReadOnlyDictionary<string, IReadOnlyDictionary<string, string>> Texts)> DriverData = new(LoadDrivers);

    internal static IReadOnlyList<DriverInfo> DriverEntries => DriverData.Value.Drivers;

    static BugcheckKnowledgeBase()
    {
        Loc.RegisterProvider((key, culture) =>
        {
            if (key.StartsWith("driver.", StringComparison.Ordinal))
            {
                return DriverData.Value.Texts.TryGetValue(key, out var byLang)
                    ? byLang.GetValueOrDefault(culture.TwoLetterISOLanguageName) ?? byLang.GetValueOrDefault("en")
                    : null;
            }
            if (!key.StartsWith("kb.", StringComparison.Ordinal))
            {
                return null;
            }
            var parts = key.Split('.');
            if (parts.Length != 3 || ParseCode(parts[1]) is not { } code || !Entries.Value.TryGetValue(code, out var e))
            {
                return null;
            }
            var field = parts[2] switch { "cause" => e.Cause, "next" => e.Next, _ => null };
            return field is null ? null
                : field.TryGetValue(culture.TwoLetterISOLanguageName, out var v) ? v
                : field.GetValueOrDefault("en");
        });
    }

    public static IReadOnlyCollection<BugcheckEntry> All => (IReadOnlyCollection<BugcheckEntry>)Entries.Value.Values;

    public static BugcheckEntry? Find(uint code) => Entries.Value.GetValueOrDefault(code);

    public static string Format(uint code) => "0x" + code.ToString("X", CultureInfo.InvariantCulture);

    public static uint? ParseCode(string text)
    {
        text = text.Trim();
        return text.StartsWith("0x", StringComparison.OrdinalIgnoreCase)
            && uint.TryParse(text.AsSpan(2), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var v)
                ? v
                : null;
    }

    public static void EnsureRegistered()
    {
        _ = Entries.Value;
        _ = DriverData.Value;
    }

    private static (IReadOnlyList<DriverInfo>, IReadOnlyDictionary<string, IReadOnlyDictionary<string, string>>) LoadDrivers()
    {
        using var stream = typeof(BugcheckKnowledgeBase).Assembly
            .GetManifestResourceStream("PcDoctor.Modules.Crash.bugchecks.json")!;
        using var doc = JsonDocument.Parse(stream);
        var drivers = new List<DriverInfo>();
        var texts = new Dictionary<string, IReadOnlyDictionary<string, string>>();
        foreach (var e in doc.RootElement.GetProperty("drivers").EnumerateArray())
        {
            var key = e.GetProperty("key").GetString()!;
            drivers.Add(new DriverInfo(key, e.GetProperty("files").EnumerateArray().Select(f => f.GetString()!).ToList()));
            foreach (var field in new[] { "name", "why", "action" })
            {
                texts[$"driver.{key}.{field}"] = Fields(e.GetProperty(field));
            }
        }
        return (drivers, texts);
    }

    private static IReadOnlyDictionary<uint, BugcheckEntry> Load()
    {
        using var stream = typeof(BugcheckKnowledgeBase).Assembly
            .GetManifestResourceStream("PcDoctor.Modules.Crash.bugchecks.json")!;
        using var doc = JsonDocument.Parse(stream);
        var result = new Dictionary<uint, BugcheckEntry>();
        foreach (var e in doc.RootElement.GetProperty("entries").EnumerateArray())
        {
            var code = ParseCode(e.GetProperty("code").GetString()!) ?? throw new FormatException("Bad code in bugchecks.json");
            result[code] = new BugcheckEntry(code, e.GetProperty("name").GetString()!, e.GetProperty("kind").GetString()!,
                Fields(e.GetProperty("cause")), Fields(e.GetProperty("next")));
        }
        return result;
    }

    private static Dictionary<string, string> Fields(JsonElement e) =>
        e.EnumerateObject().ToDictionary(p => p.Name, p => p.Value.GetString() ?? "");
}
