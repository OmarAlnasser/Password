using System.Text.Json;

namespace PcDoctor.Modules.Security;

public sealed record EsuProgram(string Program, DateOnly Ends, bool Verify, string? Note);

public sealed record Win11Release(int Build, string Version, DateOnly HomePro, DateOnly EnterpriseEducation);

public sealed record OsSupportConfig(DateOnly AsOf, DateOnly Windows10EndOfSupport, IReadOnlyList<EsuProgram> Esu, string GuidanceUrl)
{
    /// <summary>Windows 11 feature updates and their end of servicing; empty when the file has none.</summary>
    public IReadOnlyList<Win11Release> Windows11 { get; init; } = [];

    /// <summary>Loads the override file if it exists and parses, otherwise the copy shipped in the binary.</summary>
    public static OsSupportConfig Load(string? overridePath = null)
    {
        if (overridePath is not null && File.Exists(overridePath))
        {
            try
            {
                return Parse(File.ReadAllText(overridePath));
            }
            catch (Exception ex) when (ex is JsonException or FormatException or KeyNotFoundException or InvalidOperationException)
            {
                // A broken override must not hide the banner; fall back to the shipped dates.
            }
        }
        using var stream = typeof(OsSupportConfig).Assembly.GetManifestResourceStream("PcDoctor.Modules.Security.os-support.json")!;
        using var reader = new StreamReader(stream);
        return Parse(reader.ReadToEnd());
    }

    public static OsSupportConfig Parse(string json)
    {
        using var doc = JsonDocument.Parse(json);
        var w10 = doc.RootElement.GetProperty("windows10");
        return new OsSupportConfig(
            DateOnly.Parse(doc.RootElement.GetProperty("asOf").GetString()!, System.Globalization.CultureInfo.InvariantCulture),
            DateOnly.Parse(w10.GetProperty("endOfSupport").GetString()!, System.Globalization.CultureInfo.InvariantCulture),
            w10.GetProperty("esu").EnumerateArray().Select(e => new EsuProgram(
                e.GetProperty("program").GetString()!,
                DateOnly.Parse(e.GetProperty("ends").GetString()!, System.Globalization.CultureInfo.InvariantCulture),
                e.TryGetProperty("verify", out var v) && v.GetBoolean(),
                e.TryGetProperty("note", out var n) ? n.GetString() : null)).ToList(),
            w10.GetProperty("guidanceUrl").GetString()!)
        {
            Windows11 = doc.RootElement.TryGetProperty("windows11", out var w11)
                ? w11.EnumerateArray().Select(r => new Win11Release(r.GetProperty("build").GetInt32(), r.GetProperty("version").GetString()!,
                    DateOnly.Parse(r.GetProperty("homePro").GetString()!, System.Globalization.CultureInfo.InvariantCulture),
                    DateOnly.Parse(r.GetProperty("enterpriseEducation").GetString()!, System.Globalization.CultureInfo.InvariantCulture))).ToList()
                : [],
        };
    }
}
