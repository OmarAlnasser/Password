using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace PcDoctor.App.Views;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        SourceInitialized += (_, _) => ApplyTitleBarTheme(IsDark);
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
