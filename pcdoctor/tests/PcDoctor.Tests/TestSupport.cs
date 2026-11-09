using System.Globalization;
using PcDoctor.Core.Events;
using PcDoctor.Core.Findings;
using PcDoctor.Core.Journal;
using PcDoctor.Core.Localization;
using PcDoctor.Core.Platform;
using Xunit;

namespace PcDoctor.Tests;

internal static class Fixtures
{
    public static string Dir => Path.Combine(AppContext.BaseDirectory, "Fixtures");

    public static EventRecordData Event(string name) =>
        EventXmlParser.Parse(File.ReadAllText(Path.Combine(Dir, "events", name + ".xml")));

    public static string Text(string name) => File.ReadAllText(Path.Combine(Dir, name));

    /// <summary>The repository's pcdoctor/ folder, found by walking up from the test binary.</summary>
    public static string SourceRoot
    {
        get
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            while (dir is not null && !File.Exists(Path.Combine(dir.FullName, "PcDoctor.sln")))
            {
                dir = dir.Parent;
            }
            return dir?.FullName ?? throw new InvalidOperationException("PcDoctor.sln not found above the test output.");
        }
    }
}

internal static class Cultures
{
    public static readonly CultureInfo En = CultureInfo.GetCultureInfo("en-US");
    public static readonly CultureInfo Ar = CultureInfo.GetCultureInfo("ar-SA");
    public static IEnumerable<CultureInfo> Both => [En, Ar];
}

internal static class TextAssert
{
    /// <summary>Every text in the result resolves in both languages, with no missing key and no banned phrase.</summary>
    public static void AllResolve(ModuleResult result)
    {
        foreach (var c in Cultures.Both)
        {
            var texts = new List<Text> { result.ModuleName };
            texts.AddRange(result.Checks.Select(x => x.Title));
            texts.AddRange(result.Checks.Where(x => x.Detail is not null).Select(x => x.Detail!));
            foreach (var f in result.Findings)
            {
                texts.AddRange([f.Title, f.WhyItMatters, f.SuggestedAction]);
                if (f.Undo.Explanation is { } u)
                {
                    texts.Add(u);
                }
            }
            foreach (var t in texts)
            {
                var s = Loc.Resolve(t, c);
                Assert.False(s.Contains("[[", StringComparison.Ordinal), $"Missing key {t.Key} ({c.Name})");
                Assert.DoesNotContain("{0}", s);
            }
        }
    }
}

internal sealed class FakeRegistry : IRegistryAccess
{
    public readonly Dictionary<string, Dictionary<string, RegistryData>> Keys = new(StringComparer.OrdinalIgnoreCase);

    private static string K(string hive, string key) => hive + "\\" + key;

    public RegistryData? Read(string hive, string key, string valueName) =>
        Keys.TryGetValue(K(hive, key), out var values) && values.TryGetValue(valueName, out var v) ? v : null;

    public bool KeyExists(string hive, string key) => Keys.ContainsKey(K(hive, key));

    public void Write(string hive, string key, string valueName, RegistryData data)
    {
        if (!Keys.TryGetValue(K(hive, key), out var values))
        {
            Keys[K(hive, key)] = values = new Dictionary<string, RegistryData>(StringComparer.OrdinalIgnoreCase);
        }
        values[valueName] = data;
    }

    public void DeleteValue(string hive, string key, string valueName)
    {
        if (Keys.TryGetValue(K(hive, key), out var values))
        {
            values.Remove(valueName);
        }
    }

    public void DeleteKeyIfEmpty(string hive, string key)
    {
        if (Keys.TryGetValue(K(hive, key), out var values) && values.Count == 0)
        {
            Keys.Remove(K(hive, key));
        }
    }

    /// <summary>A stable text dump, for byte-identical before/after comparisons.</summary>
    public string Export() => string.Join("\n", Keys.OrderBy(k => k.Key, StringComparer.Ordinal)
        .SelectMany(k => new[] { $"[{k.Key}]" }.Concat(k.Value.OrderBy(v => v.Key, StringComparer.Ordinal)
            .Select(v => $"{v.Key}={v.Value.Kind}:{v.Value.Encoded}"))));
}

internal sealed class FakeServices : IServiceConfigAccess
{
    public readonly Dictionary<string, (string StartType, bool Delayed)> Services = new(StringComparer.OrdinalIgnoreCase);
    public string? FailOn { get; set; }

    public (string StartType, bool Delayed)? Read(string service) =>
        Services.TryGetValue(service, out var s) ? s : null;

    public void Write(string service, string startType, bool delayed)
    {
        if (service == FailOn)
        {
            throw new InvalidOperationException("Access is denied.");
        }
        Services[service] = (startType, delayed);
    }
}

internal sealed class FakeRestorePoints : IRestorePointApi
{
    public bool ProtectionOn { get; set; } = true;
    public bool SilentlySkip { get; set; }
    public int? Frequency { get; set; }
    public List<uint> Points { get; } = [];
    public List<int?> FrequencyDuringCreate { get; } = [];

    public bool IsProtectionEnabled(string drive) => ProtectionOn;
    public uint? LatestSequenceNumber() => Points.Count == 0 ? null : Points.Max();

    public void Create(string description)
    {
        FrequencyDuringCreate.Add(Frequency);
        // Windows skips creation inside the 24 h window unless the frequency is 0.
        if (!SilentlySkip && Frequency == 0)
        {
            Points.Add((LatestSequenceNumber() ?? 0) + 1);
        }
    }

    public int? ReadCreationFrequency() => Frequency;
    public void WriteCreationFrequency(int? minutes) => Frequency = minutes;
}
