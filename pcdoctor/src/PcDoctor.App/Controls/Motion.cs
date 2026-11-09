using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace PcDoctor.App.Controls;

/// <summary>Khazna's single motion curve, cubic-bezier(.2,.8,.2,1) (docs/DESIGN.md section 7).</summary>
public sealed class KhaznaEase : EasingFunctionBase
{
    public KhaznaEase() => EasingMode = EasingMode.EaseIn;

    protected override double EaseInCore(double t) => CubicBezier(0.2, 0.8, 0.2, 1.0, t);

    protected override Freezable CreateInstanceCore() => new KhaznaEase();

    /// <summary>y for a given x on the curve, by Newton's method with a bisection fallback.</summary>
    internal static double CubicBezier(double x1, double y1, double x2, double y2, double x)
    {
        static double Bez(double a1, double a2, double t) => ((1 - 3 * a2 + 3 * a1) * t + (3 * a2 - 6 * a1)) * t * t + 3 * a1 * t;
        static double Slope(double a1, double a2, double t) => 3 * (1 - 3 * a2 + 3 * a1) * t * t + 2 * (3 * a2 - 6 * a1) * t + 3 * a1;
        if (x <= 0) return 0;
        if (x >= 1) return 1;
        var t = x;
        for (var i = 0; i < 8; i++)
        {
            var slope = Slope(x1, x2, t);
            if (Math.Abs(slope) < 1e-6) break;
            var err = Bez(x1, x2, t) - x;
            if (Math.Abs(err) < 1e-6) return Bez(y1, y2, t);
            t -= err / slope;
        }
        double lo = 0, hi = 1;
        t = x;
        for (var i = 0; i < 30; i++)
        {
            var v = Bez(x1, x2, t);
            if (Math.Abs(v - x) < 1e-6) break;
            if (v < x) lo = t; else hi = t;
            t = (lo + hi) / 2;
        }
        return Bez(y1, y2, t);
    }
}

/// <summary>
/// Motion helpers. Everything here turns into an instant state change when reduced motion is on:
/// Windows "Animation effects" off, or the in-app setting.
/// </summary>
public static class Motion
{
    public static readonly IEasingFunction Ease = Freeze(new KhaznaEase());
    public static readonly IEasingFunction Smooth = Freeze(new CubicEase { EasingMode = EasingMode.EaseInOut });

    /// <summary>The in-app "Reduce motion" setting.</summary>
    public static bool UserReducedMotion { get; set; }

    public static bool Reduced => UserReducedMotion || !SystemParameters.ClientAreaAnimation;

    public static Duration Ms(double ms) => Reduced ? new Duration(TimeSpan.Zero) : new Duration(TimeSpan.FromMilliseconds(ms));

    private static IEasingFunction Freeze(EasingFunctionBase e)
    {
        e.Freeze();
        return e;
    }

    // ---- Appear: fade + 20px rise, 700 ms, staggered 70 ms for the first 8 items ----

    public static readonly DependencyProperty AppearProperty = DependencyProperty.RegisterAttached(
        "Appear", typeof(bool), typeof(Motion), new PropertyMetadata(false, OnAppearChanged));

    public static void SetAppear(DependencyObject d, bool value) => d.SetValue(AppearProperty, value);
    public static bool GetAppear(DependencyObject d) => (bool)d.GetValue(AppearProperty);

    /// <summary>Explicit stagger slot; -1 takes the item index inside an ItemsControl.</summary>
    public static readonly DependencyProperty IndexProperty = DependencyProperty.RegisterAttached(
        "Index", typeof(int), typeof(Motion), new PropertyMetadata(-1));

    public static void SetIndex(DependencyObject d, int value) => d.SetValue(IndexProperty, value);
    public static int GetIndex(DependencyObject d) => (int)d.GetValue(IndexProperty);

    private static readonly DependencyProperty AppearedProperty = DependencyProperty.RegisterAttached(
        "Appeared", typeof(bool), typeof(Motion), new PropertyMetadata(false));

    private static void OnAppearChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is FrameworkElement fe && e.NewValue is true)
        {
            fe.Loaded += (_, _) => PlayAppear(fe);
        }
    }

    private static void PlayAppear(FrameworkElement fe)
    {
        // Only on first appearance of this element; re-entering a page re-creates its items anyway.
        if ((bool)fe.GetValue(AppearedProperty))
        {
            return;
        }
        fe.SetValue(AppearedProperty, true);
        if (Reduced)
        {
            return;
        }
        var index = GetIndex(fe);
        if (index < 0)
        {
            var owner = ItemsControl.ItemsControlFromItemContainer(fe);
            index = owner?.ItemContainerGenerator.IndexFromContainer(fe) ?? 0;
        }
        var delay = TimeSpan.FromMilliseconds(Math.Min(Math.Max(index, 0), 8) * 70);
        var shift = new TranslateTransform(0, 20);
        fe.RenderTransform = shift;
        fe.Opacity = 0;
        var fade = new DoubleAnimation(0, 1, new Duration(TimeSpan.FromMilliseconds(700))) { BeginTime = delay, EasingFunction = Ease };
        var rise = new DoubleAnimation(20, 0, new Duration(TimeSpan.FromMilliseconds(700))) { BeginTime = delay, EasingFunction = Ease };
        // Clear the hold afterwards so later layout and hover transforms start from a clean state.
        fade.Completed += (_, _) =>
        {
            fe.BeginAnimation(UIElement.OpacityProperty, null);
            fe.Opacity = 1;
        };
        fe.BeginAnimation(UIElement.OpacityProperty, fade);
        shift.BeginAnimation(TranslateTransform.YProperty, rise);
    }

    // ---- Hover lift: translateY to -Lift over 250 ms (pointer only) ----

    public static readonly DependencyProperty HoverLiftProperty = DependencyProperty.RegisterAttached(
        "HoverLift", typeof(double), typeof(Motion), new PropertyMetadata(0.0, OnHoverLiftChanged));

    public static void SetHoverLift(DependencyObject d, double value) => d.SetValue(HoverLiftProperty, value);
    public static double GetHoverLift(DependencyObject d) => (double)d.GetValue(HoverLiftProperty);

    private static void OnHoverLiftChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is not FrameworkElement fe || (double)e.NewValue == 0)
        {
            return;
        }
        fe.MouseEnter += (_, _) => Lift(fe, -GetHoverLift(fe));
        fe.MouseLeave += (_, _) => Lift(fe, 0);
    }

    /// <summary>Animates the element's vertical offset (used by <see cref="Card"/>).</summary>
    public static void SetHoverLiftNow(FrameworkElement fe, double to) => Lift(fe, to);

    private static void Lift(FrameworkElement fe, double to)
    {
        if (fe.RenderTransform is not TranslateTransform t || t.IsFrozen)
        {
            t = new TranslateTransform();
            fe.RenderTransform = t;
        }
        t.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(to, Ms(250)) { EasingFunction = Ease });
    }

    /// <summary>Fades and slides content in (pages, dialogs): 300 ms, opacity 0 → 1, y +16 → 0.</summary>
    public static void Enter(FrameworkElement fe, double fromY = 16, double fromScale = 1)
    {
        if (Reduced)
        {
            fe.Opacity = 1;
            return;
        }
        var group = new TransformGroup();
        var scale = new ScaleTransform(fromScale, fromScale);
        var shift = new TranslateTransform(0, fromY);
        group.Children.Add(scale);
        group.Children.Add(shift);
        fe.RenderTransformOrigin = new Point(0.5, 0.5);
        fe.RenderTransform = group;
        var d = new Duration(TimeSpan.FromMilliseconds(300));
        fe.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(0, 1, d) { EasingFunction = Ease });
        shift.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(fromY, 0, d) { EasingFunction = Ease });
        if (fromScale != 1)
        {
            scale.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(fromScale, 1, d) { EasingFunction = Ease });
            scale.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(fromScale, 1, d) { EasingFunction = Ease });
        }
    }
}
