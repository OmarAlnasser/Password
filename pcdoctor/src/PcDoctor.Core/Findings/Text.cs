using System.Text.Json.Serialization;

namespace PcDoctor.Core.Findings;

/// <summary>
/// A localizable message: a resource key plus format arguments. Resolved at display time so the
/// language can change at runtime. Arguments are already formatted, culture-neutral strings
/// (paths, codes, counts); <see cref="Localization.Loc"/> handles digits for the selected culture.
/// </summary>
public sealed record Text
{
    [JsonConstructor]
    public Text(string key, IReadOnlyList<string> args)
    {
        Key = key;
        Args = args;
    }

    public Text(string key, params object[] args)
        : this(key, (IReadOnlyList<string>)args.Select(Localization.Loc.FormatArg).ToArray())
    {
    }

    public string Key { get; }
    public IReadOnlyList<string> Args { get; }

    public bool Equals(Text? other) =>
        other is not null && Key == other.Key && Args.SequenceEqual(other.Args);

    public override int GetHashCode() => HashCode.Combine(Key, Args.Count);

    public override string ToString() => Localization.Loc.Resolve(this);
}
