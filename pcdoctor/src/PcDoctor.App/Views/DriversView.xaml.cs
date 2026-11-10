using System.Windows.Controls;

namespace PcDoctor.App.Views;

public partial class DriversView : UserControl
{
    public DriversView()
    {
        InitializeComponent();
    }

    private void OnSaveKey(object sender, System.Windows.RoutedEventArgs e)
    {
        if (DataContext is Pages.DriversViewModel vm)
        {
            vm.SaveKey(AiKey.Password);
            AiKey.Clear();
        }
    }
}
