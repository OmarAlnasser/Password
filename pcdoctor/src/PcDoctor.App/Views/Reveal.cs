using System.Windows;
using PcDoctor.App.Controls;

namespace PcDoctor.App.Views;

/// <summary>Replays the enter animation when an element's DataContext changes (the detail pane).</summary>
public static class Reveal
{
    public static readonly DependencyProperty OnDataContextChangeProperty = DependencyProperty.RegisterAttached(
        "OnDataContextChange", typeof(bool), typeof(Reveal), new PropertyMetadata(false, OnChanged));

    public static void SetOnDataContextChange(DependencyObject d, bool value) => d.SetValue(OnDataContextChangeProperty, value);
    public static bool GetOnDataContextChange(DependencyObject d) => (bool)d.GetValue(OnDataContextChangeProperty);

    private static void OnChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is FrameworkElement fe && e.NewValue is true)
        {
            fe.DataContextChanged += (_, args) =>
            {
                if (args.NewValue is not null && fe.IsLoaded)
                {
                    Motion.Enter(fe, fromY: 10);
                }
            };
        }
    }
}
