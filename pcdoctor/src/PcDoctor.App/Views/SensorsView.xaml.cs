using System.Windows.Controls;

namespace PcDoctor.App.Views;

public partial class SensorsView : UserControl
{
    public SensorsView()
    {
        InitializeComponent();
        // Stop polling the Broker when the page is left.
        Unloaded += (_, _) => (DataContext as Pages.SensorsViewModel)?.StopCommand.Execute(null);
    }
}
