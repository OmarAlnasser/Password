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
                    catch (Exception ex) when (ex is System.Xml.XmlException or FormatException or OverflowException or EventLogException)
                    {
                        // A record with malformed XML is skipped; the module reports its count as read.
                    }
                }
            }
        }
        catch (Exception ex) when (ex is EventLogException or UnauthorizedAccessException)
        {
            // Channel absent on this edition, access denied, or the log is damaged: the caller gets what was
            // read so far and reports the rest as not available. One bad log must not fail a whole module.
        }
        return result;
    }
}
