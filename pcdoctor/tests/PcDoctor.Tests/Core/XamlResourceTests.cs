using System.Text.RegularExpressions;
using System.Xml.Linq;
using Xunit;

namespace PcDoctor.Tests.Core;

/// <summary>
/// Static checks on the WPF XAML that run on any OS: a missing resource key would only fail at run
/// time on Windows, so it is caught here instead.
/// </summary>
public sealed class XamlResourceTests
{
    private static string AppDir => Path.Combine(Fixtures.SourceRoot, "src", "PcDoctor.App");

    private static readonly XNamespace X = "http://schemas.microsoft.com/winfx/2006/xaml";

    private static HashSet<string> Keys(string file) =>
        XDocument.Load(file).Descendants().Select(e => e.Attribute(X + "Key")?.Value).OfType<string>().ToHashSet();

    [Fact]
    public void All_themes_define_the_same_tokens()
    {
        var dark = Keys(Path.Combine(AppDir, "Themes", "Dark.xaml"));
        foreach (var other in new[] { "Light.xaml", "HighContrast.xaml" })
        {
            var keys = Keys(Path.Combine(AppDir, "Themes", other));
            Assert.True(dark.SetEquals(keys),
                $"{other}: missing {string.Join(", ", dark.Except(keys))}; extra {string.Join(", ", keys.Except(dark))}");
        }
    }

    [Fact]
    public void Every_resource_reference_in_xaml_resolves()
    {
        var global = Keys(Path.Combine(AppDir, "Themes", "Dark.xaml"));
        global.UnionWith(Keys(Path.Combine(AppDir, "Themes", "Styles.xaml")));
        var reference = new Regex(@"\{(?:Dynamic|Static)Resource (?!\{)([A-Za-z0-9_.]+)\}");
        var missing = new List<string>();
        foreach (var file in Directory.EnumerateFiles(AppDir, "*.xaml", SearchOption.AllDirectories)
                     .Where(f => !f.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}")))
        {
            var local = Keys(file);
            foreach (Match m in reference.Matches(File.ReadAllText(file)))
            {
                var key = m.Groups[1].Value;
                if (!global.Contains(key) && !local.Contains(key))
                {
                    missing.Add($"{Path.GetFileName(file)}: {key}");
                }
            }
        }
        Assert.True(missing.Count == 0, "Unresolved: " + string.Join(", ", missing.Distinct()));
    }

    [Fact]
    public void Styles_never_hard_code_colours()
    {
        // Colours live in the theme dictionaries only, so Light, Dark and High contrast stay complete.
        var hex = new Regex("\"#[0-9A-Fa-f]{6,8}\"");
        foreach (var file in Directory.EnumerateFiles(AppDir, "*.xaml", SearchOption.AllDirectories)
                     .Where(f => !f.Contains("Themes" + Path.DirectorySeparatorChar + "Dark") &&
                                 !f.Contains("Themes" + Path.DirectorySeparatorChar + "Light") &&
                                 !f.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}")))
        {
            Assert.False(hex.IsMatch(File.ReadAllText(file)), Path.GetFileName(file));
        }
    }
}
