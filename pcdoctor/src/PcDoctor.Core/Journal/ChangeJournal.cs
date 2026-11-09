using System.Text.Json;

namespace PcDoctor.Core.Journal;

/// <summary>
/// Append-only JSON-lines journal. Each state transition is a new line; the latest line for an
/// entry ID wins. Entries are written as Planned before the change is made (write-ahead), so a
/// crash in the middle of a batch still leaves the old values on disk.
/// </summary>
/// <remarks>
/// The Broker keeps it under %ProgramData%\PCDoctor\journal with an ACL that lets only
/// Administrators and SYSTEM write, so code running as the user cannot forge undo data.
/// </remarks>
public sealed class ChangeJournal
{
    public static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = false,
    };

    private readonly string _path;
    private readonly object _gate = new();

    public ChangeJournal(string path)
    {
        _path = path;
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
    }

    public string FilePath => _path;

    public void Append(JournalEntry entry)
    {
        var line = JsonSerializer.Serialize(entry, JsonOptions) + "\n";
        lock (_gate)
        {
            using var stream = new FileStream(_path, FileMode.Append, FileAccess.Write, FileShare.Read);
            var bytes = System.Text.Encoding.UTF8.GetBytes(line);
            stream.Write(bytes);
            stream.Flush(flushToDisk: true);
        }
    }

    /// <summary>The current state of every entry, oldest first.</summary>
    public IReadOnlyList<JournalEntry> ReadCurrent()
    {
        if (!File.Exists(_path))
        {
            return [];
        }
        var latest = new Dictionary<Guid, JournalEntry>();
        var order = new List<Guid>();
        string[] lines;
        lock (_gate)
        {
            using var stream = new FileStream(_path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            using var reader = new StreamReader(stream);
            lines = reader.ReadToEnd().Split('\n', StringSplitOptions.RemoveEmptyEntries);
        }
        foreach (var line in lines)
        {
            JournalEntry? entry;
            try
            {
                entry = JsonSerializer.Deserialize<JournalEntry>(line, JsonOptions);
            }
            catch (JsonException)
            {
                // A torn last line after a power cut: the entry before it is still authoritative.
                continue;
            }
            if (entry is null)
            {
                continue;
            }
            if (!latest.ContainsKey(entry.Id))
            {
                order.Add(entry.Id);
            }
            latest[entry.Id] = entry;
        }
        return order.Select(id => latest[id]).ToList();
    }
}
