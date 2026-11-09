namespace PcDoctor.Core.Platform;

/// <summary>
/// Windows path handling that behaves the same on any OS, for the pure analyzers and parsers that the
/// tests run on Linux (where Path.Combine uses '/' and Path.GetFileName ignores '\').
/// </summary>
public static class WinPath
{
    public static string Join(params string[] parts) =>
        string.Join('\\', parts.Where(p => p.Length > 0).Select((p, i) => i == 0 ? p.TrimEnd('\\', '/') : p.Trim('\\', '/')));

    public static string FileName(string path)
    {
        var i = path.LastIndexOfAny(['\\', '/']);
        return i >= 0 ? path[(i + 1)..] : path;
    }
}
