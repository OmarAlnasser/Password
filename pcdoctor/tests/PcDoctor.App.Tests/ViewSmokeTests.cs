using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using PcDoctor.App.Services;
using PcDoctor.App.ViewModels;
using PcDoctor.Core.Findings;
using PcDoctor.Core.Reporting;
using PcDoctor.Core.Scanning;
using PcDoctor.Modules.Crash;
using PcDoctor.Modules.Security;
using Xunit;

namespace PcDoctor.App.Tests;

/// <summary>
/// Builds every page with a real report, in every theme and both languages, at 100% and 150%
/// scale, and checks nothing throws and no text block is clipped narrower than its content.
/// </summary>
public sealed class ViewSmokeTests
{
    /// <summary>
    /// One STA thread for the whole class: WPF's Application and its resources belong to the thread
    /// that created them, so every test runs its work there.
    /// </summary>
    private static readonly System.Collections.Concurrent.BlockingCollection<(Action Work, TaskCompletionSource Done)> Queue = new();

    private static readonly Thread Sta = StartSta();

    private static Thread StartSta()
    {
        var thread = new Thread(() =>
        {
            var app = new App { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            app.InitializeComponent();
            foreach (var (work, done) in Queue.GetConsumingEnumerable())
            {
                try
                {
                    work();
                    done.SetResult();
                }
                catch (Exception ex)
                {
                    done.SetException(ex);
                }
            }
        })
        {
            IsBackground = true,
        };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        return thread;
    }

    private static void OnSta(Action action)
    {
        _ = Sta;
        var done = new TaskCompletionSource();
        Queue.Add((action, done));
        try
        {
            done.Task.GetAwaiter().GetResult();
        }
        catch (Exception ex)
        {
            throw new Xunit.Sdk.XunitException(ex.ToString());
        }
    }

    private static ScanReport SampleReport() => new()
    {
        Id = Guid.NewGuid(),
        StartedUtc = DateTimeOffset.UtcNow,
        FinishedUtc = DateTimeOffset.UtcNow,
        Conditions = new ScanConditions
        {
            AppVersion = "0.2.0", OsProductName = "Windows 11 Pro", OsBuild = "10.0.26100.1", OsDisplayVersion = "24H2",
            OsEdition = "Professional", Architecture = "X64", Uptime = TimeSpan.FromHours(3), PowerSource = PowerSource.AC,
            PowerPlan = "Balanced", Elevated = false, Mode = ScanMode.HealthCheck, UiCulture = "en-US",
        },
        Modules =
        [
            SecurityAnalyzer.Analyze(new SecuritySnapshot { OsBuild = 19045, EnableLua = 0 }, OsSupportConfig.Load(), DateTimeOffset.UtcNow),
            CrashAnalyzer.Analyze(new CrashSnapshot { DumpConfig = new DumpConfig(0, null, null, null) }),
        ],
    };

    public static IEnumerable<object[]> Matrix() =>
        from theme in new[] { ThemeChoice.Dark, ThemeChoice.Light }
        from culture in new[] { "en-US", "ar-SA" }
        from scale in new[] { 1.0, 1.5 }
        select new object[] { theme, culture, scale };

    [Theory]
    [MemberData(nameof(Matrix))]
    public void Every_page_renders(ThemeChoice theme, string culture, double scale)
    {
        OnSta(() =>
        {
            ThemeManager.Apply(theme);
            App.ApplyLanguage(CultureInfo.GetCultureInfo(culture));
            var services = new AppServices(new AppSettings()) { Report = SampleReport() };
            foreach (var page in App.CreatePages(services))
            {
                var host = new ContentControl
                {
                    Content = page,
                    FlowDirection = culture.StartsWith("ar") ? FlowDirection.RightToLeft : FlowDirection.LeftToRight,
                    LayoutTransform = new ScaleTransform(scale, scale),
                };
                var window = new Window
                {
                    Content = host,
                    Width = 1280,
                    Height = 820,
                    WindowStyle = WindowStyle.None,
                    ShowInTaskbar = false,
                    Left = -10000,
                    Top = -10000,
                    ShowActivated = false,
                };
                window.Show();
                window.UpdateLayout();
                AssertNoClippedText(host, page.Key);
                window.Close();
            }
        });
    }

    [Fact]
    public void Shell_window_opens()
    {
        OnSta(() =>
        {
            var services = new AppServices(new AppSettings());
            var window = new Views.MainWindow
            {
                DataContext = new ShellViewModel(services, App.CreatePages(services)),
                Left = -10000,
                Top = -10000,
                ShowActivated = false,
            };
            window.Show();
            window.UpdateLayout();
            window.Close();
        });
    }

    /// <summary>A non-wrapping TextBlock narrower than its text is clipped; wrapping ones may not be squeezed below one glyph.</summary>
    private static void AssertNoClippedText(DependencyObject root, string page)
    {
        foreach (var tb in Descendants(root).OfType<TextBlock>().Where(t => t.IsVisible && !string.IsNullOrEmpty(t.Text)))
        {
            if (tb.TextWrapping == TextWrapping.NoWrap && tb.TextTrimming == TextTrimming.None)
            {
                tb.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
                Assert.True(tb.ActualWidth + 1 >= tb.DesiredSize.Width,
                    $"{page}: \"{tb.Text}\" is clipped ({tb.ActualWidth:0} < {tb.DesiredSize.Width:0})");
            }
        }
    }

    private static IEnumerable<DependencyObject> Descendants(DependencyObject root)
    {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++)
        {
            var child = VisualTreeHelper.GetChild(root, i);
            yield return child;
            foreach (var d in Descendants(child))
            {
                yield return d;
            }
        }
    }
}
