using System.Diagnostics.Eventing.Reader;
using System.Runtime.Versioning;
using PcDoctor.Core.Events;

namespace PcDoctor.Core.Platform;

[SupportedOSPlatform("windows")]
public sealed class WindowsEventSource : IEventSource
{
    public IReadOnlyList<EventRecordData> Read(EventQuery query)
    {
        var result = new List<EventRecordData>();
        var q = new EventLogQuery(query.LogName, PathType.LogName, query.ToXPath()) { ReverseDirection = true };
        try
        {
            using var reader = new EventLogReader(q);
            for (var record = reader.ReadEvent(); record is not null && result.Count < query.MaxEvents; record = reader.ReadEvent())
            {
                using (record)
                {
                    try
                    {
                        result.Add(EventXmlParser.Parse(record.ToXml()));
                    }
                    catch (System.Xml.XmlException)
                    {
                        // A record with malformed XML is skipped; the module reports its count as read.
                    }
                }
            }
        }
        catch (EventLogNotFoundException)
        {
            // Channel absent on this edition: no events, reported as not available by the caller.
        }
        return result;
    }
}
