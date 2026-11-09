using System.Globalization;
using System.Xml.Linq;

namespace PcDoctor.Core.Events;

/// <summary>
/// An event log record reduced to what analyzers need. Data is read by Name from the event XML,
/// never by position in EventRecord.Properties. Unnamed Data elements get the keys "#0", "#1", …
/// </summary>
public sealed record EventRecordData(
    string LogName,
    string Provider,
    int EventId,
    DateTimeOffset TimeCreated,
    IReadOnlyDictionary<string, string> Data,
    string Xml)
{
    public string? Get(string name) => Data.TryGetValue(name, out var v) ? v : null;

    /// <summary>Named value, falling back to the position for events that log unnamed Data.</summary>
    public string? Get(string name, int position) => Get(name) ?? Get("#" + position);

    public long? GetLong(string name)
    {
        var s = Get(name);
        if (s is null)
        {
            return null;
        }
        s = s.Trim();
        return s.StartsWith("0x", StringComparison.OrdinalIgnoreCase)
            ? long.TryParse(s[2..], NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var hex) ? hex : null
            : long.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out var dec) ? dec : null;
    }
}

public static class EventXmlParser
{
    public static EventRecordData Parse(string xml)
    {
        var doc = XDocument.Parse(xml);
        var root = doc.Root ?? throw new FormatException("Empty event XML.");
        XElement? Child(XElement? e, string name) => e?.Elements().FirstOrDefault(x => x.Name.LocalName == name);

        var system = Child(root, "System") ?? throw new FormatException("Event XML has no System element.");
        var provider = Child(system, "Provider");
        var providerName = provider?.Attribute("Name")?.Value
            ?? provider?.Attribute("EventSourceName")?.Value
            ?? "";
        var eventIdText = Child(system, "EventID")?.Value ?? "0";
        var timeText = Child(system, "TimeCreated")?.Attribute("SystemTime")?.Value;
        var time = timeText is null
            ? DateTimeOffset.MinValue
            : DateTimeOffset.Parse(timeText, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal);
        var channel = Child(system, "Channel")?.Value ?? "";

        var data = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var eventData = Child(root, "EventData");
        if (eventData is not null)
        {
            var index = 0;
            foreach (var d in eventData.Elements().Where(e => e.Name.LocalName == "Data"))
            {
                var name = d.Attribute("Name")?.Value;
                data[string.IsNullOrEmpty(name) ? "#" + index : name] = d.Value;
                index++;
            }
        }
        // Manifest events that use UserData: flatten the leaf elements by local name.
        var userData = Child(root, "UserData");
        if (userData is not null)
        {
            foreach (var leaf in userData.Descendants().Where(e => !e.HasElements))
            {
                data.TryAdd(leaf.Name.LocalName, leaf.Value);
            }
        }

        return new EventRecordData(channel, providerName,
            int.Parse(eventIdText, CultureInfo.InvariantCulture), time, data, xml);
    }
}

/// <summary>One query: a log and the provider/event-ID pairs to fetch.</summary>
public sealed record EventQuery(string LogName, IReadOnlyList<(string Provider, int[] Ids)> Selectors, TimeSpan Window, int MaxEvents = 500)
{
    /// <summary>Structured XPath. Provider names are fixed strings from PC Doctor, never user input.</summary>
    public string ToXPath()
    {
        var ms = (long)Window.TotalMilliseconds;
        var parts = Selectors.Select(s =>
            $"(Provider[@Name='{s.Provider}'] and ({string.Join(" or ", s.Ids.Select(i => $"EventID={i}"))}))");
        return $"*[System[({string.Join(" or ", parts)}) and TimeCreated[timediff(@SystemTime) <= {ms}]]]";
    }
}

public interface IEventSource
{
    IReadOnlyList<EventRecordData> Read(EventQuery query);
}
