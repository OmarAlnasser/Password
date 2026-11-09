using System.Windows;
using PcDoctor.App.Controls;

namespace PcDoctor.App.Views;

/// <summary>
/// Themed confirmation for anything that changes the system: radial dialog surface, enters with a
/// 300 ms fade + rise + scale from 0.98. Cancel has focus by default, so Enter alone never consents
/// to a change unless the dialog was opened with <c>confirmIsDefault</c>.
/// </summary>
public partial class ConsentDialog : Window
{
    private ConsentDialog(string title, string body, string confirm, bool danger)
    {
        InitializeComponent();
        TitleText.Text = title;
        BodyText.Text = body;
        ConfirmButton.Content = confirm;
        if (danger)
        {
            ConfirmButton.Style = (Style)FindResource("Btn.Danger");
        }
        Loaded += (_, _) =>
        {
            Motion.Enter(Panel, fromY: 16, fromScale: 0.98);
            CancelButton.Focus();
        };
    }

    public static bool Ask(string title, string body, string confirm, bool danger = false)
    {
        var dialog = new ConsentDialog(title, body, confirm, danger)
        {
            Owner = Application.Current?.MainWindow,
        };
        return dialog.ShowDialog() == true;
    }

    private void OnConfirm(object sender, RoutedEventArgs e) => DialogResult = true;

    private void OnCancel(object sender, RoutedEventArgs e) => DialogResult = false;
}
