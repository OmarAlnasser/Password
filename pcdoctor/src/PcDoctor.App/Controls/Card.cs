using System.Windows;
using System.Windows.Controls;

namespace PcDoctor.App.Controls;

/// <summary>
/// Khazna card: gradient surface, 1px border, radius 16. On hover (pointer only) it lifts 4px, its
/// border lights up and a soft violet glow fades in (250 ms). Template in Themes/Styles.xaml.
/// </summary>
public sealed class Card : ContentControl
{
    public static readonly DependencyProperty IsFeaturedProperty = DependencyProperty.Register(
        nameof(IsFeatured), typeof(bool), typeof(Card), new PropertyMetadata(false));

    public static readonly DependencyProperty IsInteractiveProperty = DependencyProperty.Register(
        nameof(IsInteractive), typeof(bool), typeof(Card), new PropertyMetadata(true));

    public static readonly DependencyProperty IsSelectedProperty = DependencyProperty.Register(
        nameof(IsSelected), typeof(bool), typeof(Card), new PropertyMetadata(false));

    public bool IsFeatured { get => (bool)GetValue(IsFeaturedProperty); set => SetValue(IsFeaturedProperty, value); }
    public bool IsInteractive { get => (bool)GetValue(IsInteractiveProperty); set => SetValue(IsInteractiveProperty, value); }
    public bool IsSelected { get => (bool)GetValue(IsSelectedProperty); set => SetValue(IsSelectedProperty, value); }

    protected override void OnMouseEnter(System.Windows.Input.MouseEventArgs e)
    {
        base.OnMouseEnter(e);
        if (IsInteractive)
        {
            Motion.SetHoverLiftNow(this, -4);
        }
    }

    protected override void OnMouseLeave(System.Windows.Input.MouseEventArgs e)
    {
        base.OnMouseLeave(e);
        Motion.SetHoverLiftNow(this, 0);
    }
}
