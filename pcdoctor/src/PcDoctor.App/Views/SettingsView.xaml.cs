using System.Windows.Controls;

namespace PcDoctor.App.Views;

public partial class SettingsView : UserControl
{
    public SettingsView()
    {
        InitializeComponent();
    }

    private void OnSaveVtKey(object sender, System.Windows.RoutedEventArgs e)
    {
        if (DataContext is Pages.SettingsViewModel vm)
        {
            vm.SaveVirusTotalKey(VtKey.Password);
            VtKey.Clear();
        }
    }
}
