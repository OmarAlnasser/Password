using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using PcDoctor.App.ViewModels;

namespace PcDoctor.App.Views;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        SourceInitialized += (_, _) => ApplyTitleBarTheme(IsDark);
        PreviewKeyDown += OnShortcut;
    }

    /// <summary>Ctrl+1…9 opens the nth page; Ctrl+F focuses the search box on the current page.</summary>
    private void OnShortcut(object sender, KeyEventArgs e)
    {
        if (Keyboard.Modifiers != ModifierKeys.Control || DataContext is not ShellViewModel shell)
        {
            return;
        }
        var key = e.Key is >= Key.D1 and <= Key.D9 ? e.Key - Key.D1 : e.Key is >= Key.NumPad1 and <= Key.NumPad9 ? e.Key - Key.NumPad1 : -1;
        if (key >= 0 && key < shell.Pages.Count)
        {
            shell.SelectedPage = shell.Pages[key];
            e.Handled = true;
        }
        else if (e.Key == Key.F && FindSearchBox(this) is { } box)
        {
            box.Focus();
            box.SelectAll();
            e.Handled = true;
        }
    }

    private static System.Windows.Controls.TextBox? FindSearchBox(DependencyObject root)
    {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++)
        {
            var child = VisualTreeHelper.GetChild(root, i);
            if (child is System.Windows.Controls.TextBox { IsVisible: true, Tag: "search" } box)
            {
                return box;
            }
            if (FindSearchBox(child) is { } found)
            {
                return found;
            }
        }
        return null;
    }

    /// <summary>True while the dark theme is active; the shell asks DWM for a matching title bar.</summary>
    public static bool IsDark { get; set; } = true;

    public void ApplyTitleBarTheme(bool dark)
    {
        var hwnd = new WindowInteropHelper(this).Handle;
        if (hwnd == IntPtr.Zero)
        {
            return;
        }
        var value = dark ? 1 : 0;
        // DWMWA_USE_IMMERSIVE_DARK_MODE: 20 on Windows 10 20H1+ and 11. Ignored where unsupported.
        _ = DwmSetWindowAttribute(hwnd, 20, ref value, sizeof(int));
    }

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
}
