using System.Globalization;
using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using PcDoctor.Core.Findings;
using PcDoctor.Core.Localization;

namespace PcDoctor.Core.Reporting;

public sealed record ExportOptions(CultureInfo Culture, bool Redact);

/// <summary>JSON, CSV and HTML reports. HTML is self-contained and prints to PDF from any browser.</summary>
public static class ReportExporter
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
    };

    public static string ToJson(ScanReport report, ExportOptions options)
    {
        var doc = new
        {
            report.Id,
            report.StartedUtc,
            report.FinishedUtc,
            report.Conditions,
            Summary = ReportSummary.Build(report).Select(t => Loc.Resolve(t, options.Culture)),
            Modules = report.Modules.Select(m => new
            {
                m.ModuleId,
                Name = Loc.Resolve(m.ModuleName, options.Culture),
                Checks = m.Checks.Select(c => new
                {
                    c.Id,
                    c.Status,
                    c.Source,
                    Title = Loc.Resolve(c.Title, options.Culture),
                    Detail = c.Detail is null ? null : Loc.Resolve(c.Detail, options.Culture),
                }),
                Findings = m.Findings.Select(f => Resolved(f, options.Culture)),
            }),
        };
        return Finish(JsonSerializer.Serialize(doc, Json), report, options);
    }

    public static string FindingsToCsv(ScanReport report, ExportOptions options)
    {
        var sb = new StringBuilder();
        sb.AppendLine("id,module,severity,confidence,source,title,why_it_matters,suggested_action,undo,evidence");
        foreach (var f in report.AllFindings)
        {
            var r = Resolved(f, options.Culture);
            sb.AppendJoin(',', new[]
            {
                f.Id, f.Module, f.Severity.ToString(), f.Confidence.ToString(), f.Source.ToString(),
                r.Title, r.WhyItMatters, r.SuggestedAction, r.Undo,
                string.Join(" | ", f.Evidence.Select(e => $"{e.Label}: {e.Value}")),
            }.Select(Csv));
            sb.Append("\r\n");
        }
        return Finish(sb.ToString(), report, options);
    }

    public static string ToHtml(ScanReport report, ExportOptions options)
    {
        var c = options.Culture;
        string T(Text t) => H(Loc.Resolve(t, c));
        string L(string key) => H(Loc.Get(key, c));
        var rtl = c.TextInfo.IsRightToLeft;
        var sb = new StringBuilder();
        sb.Append($"<!doctype html><html lang=\"{c.TwoLetterISOLanguageName}\" dir=\"{(rtl ? "rtl" : "ltr")}\"><head><meta charset=\"utf-8\">");
        sb.Append($"<title>{L("app.title")} — {L("report.title")}</title>");
        sb.Append("<style>body{font-family:'Segoe UI','Noto Sans Arabic',sans-serif;margin:24px;color:#1b1b1b;background:#fff}" +
                  "h1{font-size:22px}h2{font-size:18px;margin-top:28px;border-bottom:1px solid #ddd}" +
                  ".f{border:1px solid #ddd;border-radius:6px;padding:10px 14px;margin:10px 0}" +
                  ".sev{font-weight:600}.Critical{color:#a4262c}.High{color:#c43e1c}.Medium{color:#8a6100}.Low,.Info{color:#3b3b3b}" +
                  "code,.ltr{direction:ltr;unicode-bidi:isolate;font-family:Consolas,monospace;font-size:12px;word-break:break-all}" +
                  "table{border-collapse:collapse}td,th{border:1px solid #ddd;padding:4px 8px;text-align:start;vertical-align:top}</style></head><body>");
        sb.Append($"<h1>{L("app.title")} — {L("report.title")}</h1><ul>");
        foreach (var line in ReportSummary.Build(report))
        {
            sb.Append($"<li>{T(line)}</li>");
        }
        sb.Append("</ul>");

        var cond = report.Conditions;
        sb.Append($"<h2>{L("report.conditions")}</h2><table>");
        void Row(string key, string value) => sb.Append($"<tr><th>{L(key)}</th><td><span class=\"ltr\">{H(value)}</span></td></tr>");
        Row("report.cond.app", cond.AppVersion);
        Row("report.cond.os", $"{cond.OsProductName} {cond.OsDisplayVersion} ({cond.OsBuild}, {cond.OsEdition}, {cond.Architecture})");
        Row("report.cond.uptime", cond.Uptime.ToString(@"d\.hh\:mm", CultureInfo.InvariantCulture));
        Row("report.cond.power", $"{cond.PowerSource} / {cond.PowerPlan}");
        Row("report.cond.mode", $"{cond.Mode}{(cond.Elevated ? " (elevated)" : "")}");
        Row("report.cond.time", $"{report.StartedUtc:u} – {report.FinishedUtc:u}");
        sb.Append("</table>");

        foreach (var m in report.Modules)
        {
            sb.Append($"<h2>{T(m.ModuleName)}</h2>");
            foreach (var f in m.Findings.OrderByDescending(f => f.Severity))
            {
                sb.Append($"<div class=\"f\"><div class=\"sev {f.Severity}\">{L("severity." + f.Severity)} · {L("confidence." + f.Confidence)} · {L("source." + f.Source)}</div>");
                sb.Append($"<strong>{T(f.Title)}</strong><p>{T(f.WhyItMatters)}</p>");
                sb.Append($"<p><em>{L("finding.suggested")}</em> {T(f.SuggestedAction)}</p>");
                sb.Append($"<p><em>{L("finding.undo")}</em> {H(UndoText(f.Undo, c))}</p>");
                if (f.Evidence.Count > 0)
                {
                    sb.Append("<table>");
                    foreach (var e in f.Evidence)
                    {
                        sb.Append($"<tr><th><span class=\"ltr\">{H(e.Label)}</span></th><td><code>{H(e.Value)}</code></td></tr>");
                    }
                    sb.Append("</table>");
                }
                sb.Append("</div>");
            }
            sb.Append($"<details><summary>{L("report.checks")}</summary><table>");
            foreach (var chk in m.Checks)
            {
                sb.Append($"<tr><td>{L("check.status." + chk.Status)}</td><td>{T(chk.Title)}</td><td>{(chk.Detail is null ? "" : T(chk.Detail))}</td></tr>");
            }
            sb.Append("</table></details>");
        }
        sb.Append("</body></html>");
        return Finish(sb.ToString(), report, options);
    }

    public static string UndoText(UndoInfo undo, CultureInfo culture) => undo.Kind switch
    {
        UndoKind.NothingChanged => Loc.Get("undo.nothingChanged", culture),
        _ => Loc.Get(undo.Kind == UndoKind.Reversible ? "undo.reversible" : "undo.notReversible", culture) +
             (undo.Explanation is null ? "" : " " + Loc.Resolve(undo.Explanation, culture)),
    };

    /// <summary>Plain text for "copy as text".</summary>
    public static string FindingToText(Finding f, CultureInfo culture)
    {
        var sb = new StringBuilder();
        sb.AppendLine($"[{Loc.Get("severity." + f.Severity, culture)} / {Loc.Get("confidence." + f.Confidence, culture)} / {Loc.Get("source." + f.Source, culture)}] {Loc.Resolve(f.Title, culture)}");
        sb.AppendLine(Loc.Resolve(f.WhyItMatters, culture));
        sb.AppendLine($"{Loc.Get("finding.suggested", culture)} {Loc.Resolve(f.SuggestedAction, culture)}");
        sb.AppendLine($"{Loc.Get("finding.undo", culture)} {UndoText(f.Undo, culture)}");
        foreach (var e in f.Evidence)
        {
            sb.AppendLine($"  {e.Label}: {e.Value}");
        }
        sb.AppendLine($"  ID: {f.Id}");
        return sb.ToString();
    }

    private sealed record ResolvedFinding(
        string Id, string Module, Severity Severity, Confidence Confidence, FindingSource Source,
        string Title, string WhyItMatters, string SuggestedAction, string Undo,
        IReadOnlyList<Evidence> Evidence, string? FixId);

    private static ResolvedFinding Resolved(Finding f, CultureInfo c) => new(
        f.Id, f.Module, f.Severity, f.Confidence, f.Source,
        Loc.Resolve(f.Title, c), Loc.Resolve(f.WhyItMatters, c), Loc.Resolve(f.SuggestedAction, c),
        UndoText(f.Undo, c), f.Evidence, f.FixId);

    private static string Finish(string output, ScanReport report, ExportOptions options) =>
        options.Redact ? Redactor.Redact(output, report.Conditions.UserName, report.Conditions.MachineName) : output;

    private static string H(string s) => WebUtility.HtmlEncode(s);

    /// <summary>RFC 4180 quoting, and a leading apostrophe on cells a spreadsheet would run as a formula.</summary>
    internal static string Csv(string s)
    {
        if (s.Length > 0 && "=+-@\t\r".Contains(s[0]))
        {
            s = "'" + s;
        }
        return "\"" + s.Replace("\"", "\"\"") + "\"";
    }
}

public static class Redactor
{
    public static string Redact(string text, string userName, string machineName)
    {
        foreach (var (value, placeholder) in new[] { (machineName, "<PC>"), (userName, "<user>") })
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                continue;
            }
            text = Regex.Replace(text, $@"(?<![\p{{L}}\p{{N}}_]){Regex.Escape(value)}(?![\p{{L}}\p{{N}}_])",
                placeholder, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        }
        return text;
    }
}
