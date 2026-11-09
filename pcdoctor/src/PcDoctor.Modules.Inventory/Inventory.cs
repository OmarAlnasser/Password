using System.Buffers.Binary;
using System.Globalization;
using System.Text;

namespace PcDoctor.Modules.Inventory;

public enum SkipReason { AccessDenied, Locked, CloudOnly, PathError, LinkNotFollowed, Other }

public sealed record SkippedItem(string Path, SkipReason Reason, bool IsDirectory);

/// <summary>
/// The "no file left unaccounted" result: every file is inventoried or listed as skipped with a
/// reason. A folder that cannot be listed is counted as a skipped folder: its files are unknown,
/// which the summary says rather than guessing a number.
/// </summary>
public sealed record InventoryResult
{
    public required IReadOnlyList<string> Volumes { get; init; }
    public long FilesInventoried { get; init; }
    public long Directories { get; init; }
    public long Bytes { get; init; }
    public long HardLinkDuplicates { get; init; }
    public IReadOnlyDictionary<SkipReason, long> SkippedFiles { get; init; } = new Dictionary<SkipReason, long>();
    public IReadOnlyDictionary<SkipReason, long> SkippedDirectories { get; init; } = new Dictionary<SkipReason, long>();
    public IReadOnlyList<SkippedItem> SkippedSample { get; init; } = [];
    public string? SkippedCsvPath { get; init; }
    public bool BackupPrivilegeUsed { get; init; }
    public TimeSpan Duration { get; init; }

    public long TotalSkippedFiles => SkippedFiles.Values.Sum();
    public long TotalSkippedDirectories => SkippedDirectories.Values.Sum();
}

/// <summary>Counts as the walk goes. Separate from the walker so the arithmetic is tested on its own.</summary>
public sealed class InventoryAccumulator(int sampleLimit = 500)
{
    private readonly Dictionary<SkipReason, long> _files = new();
    private readonly Dictionary<SkipReason, long> _dirs = new();
    private readonly List<SkippedItem> _sample = [];
    private readonly HashSet<(uint Volume, long FileId)> _seen = [];

    public long Files { get; private set; }
    public long Directories { get; private set; }
    public long Bytes { get; private set; }
    public long HardLinkDuplicates { get; private set; }
    public List<SkippedItem> AllSkipped { get; } = [];

    public const uint RecallOnDataAccess = 0x00400000;
    public const uint RecallOnOpen = 0x00040000;
    public const uint Offline = 0x00001000;
    public const uint ReparsePoint = 0x00000400;
    public const uint DirectoryAttribute = 0x00000010;

    /// <summary>Cloud placeholders are never opened: reading one downloads it.</summary>
    public static bool IsCloudOnly(uint attributes) => (attributes & (RecallOnDataAccess | RecallOnOpen | Offline)) != 0;

    public void Directory() => Directories++;

    public void File(string path, uint volume, long fileId, uint attributes, long size)
    {
        if ((attributes & ReparsePoint) != 0 && !IsCloudOnly(attributes))
        {
            Skip(path, SkipReason.LinkNotFollowed, false);
            return;
        }
        if (IsCloudOnly(attributes))
        {
            Skip(path, SkipReason.CloudOnly, false);
            return;
        }
        if (fileId != 0 && !_seen.Add((volume, fileId)))
        {
            // A hard link to a file already counted: one file, two names.
            HardLinkDuplicates++;
            return;
        }
        Files++;
        Bytes += size;
    }

    public void Skip(string path, SkipReason reason, bool isDirectory)
    {
        var map = isDirectory ? _dirs : _files;
        map[reason] = map.GetValueOrDefault(reason) + 1;
        var item = new SkippedItem(path, reason, isDirectory);
        AllSkipped.Add(item);
        if (_sample.Count < sampleLimit)
        {
            _sample.Add(item);
        }
    }

    public InventoryResult ToResult(IReadOnlyList<string> volumes, TimeSpan duration, bool backup, string? csv) => new()
    {
        Volumes = volumes,
        FilesInventoried = Files,
        Directories = Directories,
        Bytes = Bytes,
        HardLinkDuplicates = HardLinkDuplicates,
        SkippedFiles = new Dictionary<SkipReason, long>(_files),
        SkippedDirectories = new Dictionary<SkipReason, long>(_dirs),
        SkippedSample = _sample.ToList(),
        SkippedCsvPath = csv,
        BackupPrivilegeUsed = backup,
        Duration = duration,
    };

    public static string ToCsv(IEnumerable<SkippedItem> items)
    {
        var sb = new StringBuilder("path,reason,is_directory\r\n");
        foreach (var i in items)
        {
            sb.Append('"').Append(i.Path.Replace("\"", "\"\"")).Append("\",").Append(i.Reason).Append(',')
              .Append(i.IsDirectory ? "true" : "false").Append("\r\n");
        }
        return sb.ToString();
    }
}

public sealed record DirEntry(string Name, uint Attributes, long FileId, long Size);

/// <summary>
/// FILE_ID_BOTH_DIR_INFO records as returned by GetFileInformationByHandleEx(FileIdBothDirectoryInfo):
/// NextEntryOffset @0, EndOfFile @40, FileAttributes @56, FileNameLength @60, FileId @96, FileName @104.
/// </summary>
public static class DirInfoParser
{
    public static IEnumerable<DirEntry> Parse(byte[] buffer, int length)
    {
        var offset = 0;
        while (offset + 104 <= length)
        {
            var span = buffer.AsSpan(offset);
            var next = BinaryPrimitives.ReadInt32LittleEndian(span);
            var size = BinaryPrimitives.ReadInt64LittleEndian(span[40..]);
            var attrs = BinaryPrimitives.ReadUInt32LittleEndian(span[56..]);
            var nameLen = BinaryPrimitives.ReadInt32LittleEndian(span[60..]);
            var fileId = BinaryPrimitives.ReadInt64LittleEndian(span[96..]);
            if (104 + nameLen > span.Length)
            {
                yield break;
            }
            var name = Encoding.Unicode.GetString(span.Slice(104, nameLen));
            if (name is not "." and not "..")
            {
                yield return new DirEntry(name, attrs, fileId, size);
            }
            if (next == 0)
            {
                yield break;
            }
            offset += next;
        }
    }
}

public static class InventorySummary
{
    /// <summary>The final line, always the same shape (DESIGN M1).</summary>
    public static string Line(InventoryResult r) => string.Create(CultureInfo.InvariantCulture,
        $"{r.FilesInventoried} files inventoried, {r.TotalSkippedFiles} skipped (access denied {Get(r.SkippedFiles, SkipReason.AccessDenied)}, locked {Get(r.SkippedFiles, SkipReason.Locked)}, cloud-only {Get(r.SkippedFiles, SkipReason.CloudOnly)}, path errors {Get(r.SkippedFiles, SkipReason.PathError)}, links {Get(r.SkippedFiles, SkipReason.LinkNotFollowed)}); {r.TotalSkippedDirectories} folders could not be listed");

    private static long Get(IReadOnlyDictionary<SkipReason, long> d, SkipReason r) => d.GetValueOrDefault(r);
}
