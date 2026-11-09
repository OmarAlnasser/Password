using System.Globalization;
using System.Management;
using System.Runtime.Versioning;

namespace PcDoctor.Core.Platform;

/// <summary>Small helpers over System.Management. Every query names its namespace explicitly.</summary>
[SupportedOSPlatform("windows")]
public static class Wmi
{
    public static List<Dictionary<string, object?>> Query(string scope, string wql, TimeSpan? timeout = null)
    {
        var options = new System.Management.EnumerationOptions { Timeout = timeout ?? TimeSpan.FromSeconds(30), ReturnImmediately = true, Rewindable = false };
        using var searcher = new ManagementObjectSearcher(new ManagementScope(scope), new ObjectQuery(wql), options);
        var rows = new List<Dictionary<string, object?>>();
        foreach (var obj in searcher.Get())
        {
            using (obj)
            {
                var row = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
                foreach (var p in obj.Properties)
                {
                    row[p.Name] = p.Value;
                }
                rows.Add(row);
            }
        }
        return rows;
    }

    /// <summary>Same as <see cref="Query"/> but an invalid namespace/class (feature absent on this PC) yields null.</summary>
    public static List<Dictionary<string, object?>>? TryQuery(string scope, string wql)
    {
        try
        {
            return Query(scope, wql);
        }
        catch (ManagementException ex) when (ex.ErrorCode is ManagementStatus.InvalidNamespace or ManagementStatus.InvalidClass or ManagementStatus.NotFound)
        {
            return null;
        }
    }

    public static string? Str(this Dictionary<string, object?> row, string name) =>
        row.TryGetValue(name, out var v) && v is not null ? Convert.ToString(v, CultureInfo.InvariantCulture) : null;

    public static long? Long(this Dictionary<string, object?> row, string name) =>
        row.TryGetValue(name, out var v) && v is not null && !(v is string s && s.Length == 0)
            ? Convert.ToInt64(v, CultureInfo.InvariantCulture)
            : null;

    public static bool? Bool(this Dictionary<string, object?> row, string name) =>
        row.TryGetValue(name, out var v) && v is bool b ? b : null;

    public static DateTime? CimDate(this Dictionary<string, object?> row, string name) =>
        row.Str(name) is { Length: > 0 } s ? SafeDmtf(s) : null;

    private static DateTime? SafeDmtf(string s)
    {
        try
        {
            return ManagementDateTimeConverter.ToDateTime(s);
        }
        catch (ArgumentOutOfRangeException)
        {
            return null;
        }
    }
}
