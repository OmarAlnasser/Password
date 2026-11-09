using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media.Animation;
using PcDoctor.Core.Localization;

namespace PcDoctor.App.Controls;

/// <summary>
/// Stat-tile numbers count up to their value (600 ms). The final value is always the bound one;
/// the animation is only the way there.
/// </summary>
public static class CountUp
{
    public static readonly DependencyProperty ValueProperty = DependencyProperty.RegisterAttached(
        "Value", typeof(int), typeof(CountUp), new PropertyMetadata(0, OnValueChanged));

    public static void SetValue(DependencyObject d, int value) => d.SetValue(ValueProperty, value);
    public static int GetValue(DependencyObject d) => (int)d.GetValue(ValueProperty);

    private static readonly DependencyProperty ShownProperty = DependencyProperty.RegisterAttached(
        "Shown", typeof(double), typeof(CountUp), new PropertyMetadata(0.0, OnShownChanged));

    private static void OnValueChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is not TextBlock tb)
        {
            return;
        }
        var to = (int)e.NewValue;
        if (Motion.Reduced)
        {
            tb.BeginAnimation(ShownProperty, null);
            tb.SetValue(ShownProperty, (double)to);
            Render(tb, to);
            return;
        }
        var from = (double)tb.GetValue(ShownProperty);
        tb.BeginAnimation(ShownProperty, new DoubleAnimation(from, to, new Duration(TimeSpan.FromMilliseconds(600)))
        {
            EasingFunction = Motion.Ease,
        });
    }

    private static void OnShownChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is TextBlock tb)
        {
            Render(tb, (int)Math.Round((double)e.NewValue));
        }
    }

    // Stat numerals stay Western digits in every language, like Khazna's.
    private static void Render(TextBlock tb, int value) => tb.Text = value.ToString(CultureInfo.InvariantCulture);
}
