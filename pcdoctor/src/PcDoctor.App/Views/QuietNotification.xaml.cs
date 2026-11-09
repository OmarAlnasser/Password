using System.Diagnostics;
using System.Windows;
using System.Windows.Threading;
using PcDoctor.App.Controls;

namespace PcDoctor.App.Views;

/// <summary>The only thing a scheduled scan ever shows: new High or Critical findings. No sound, no countdown, closes by itself.</summary>
public partial class QuietNotification : Window
{
    public QuietNotification(string title, string body)
    {
        InitializeComponent();
        TitleText.Text = title;
        BodyText.Text = body;
        Loaded += (_, _) =>
        {
            var area = SystemParameters.WorkArea;
            Left = area.Right - ActualWidth;
            Top = area.Bottom - ActualHeight;
            Motion.Enter(Panel, fromY: 24);
        };
        var close = new DispatcherTimer { Interval = TimeSpan.FromMinutes(2) };
        close.Tick += (_, _) => Close();
        close.Start();
    }

    private void OnDismiss(object sender, RoutedEventArgs e) => Close();

    private void OnOpen(object sender, RoutedEventArgs e)
    {
        if (Environment.ProcessPath is { } exe)
        {
            Process.Start(new ProcessStartInfo(exe) { UseShellExecute = false });
        }
        Close();
    }
}
