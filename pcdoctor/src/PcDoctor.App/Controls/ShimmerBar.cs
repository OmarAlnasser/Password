using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;

namespace PcDoctor.App.Controls;

/// <summary>
/// The 3px gradient progress bar. Determinate: fills to <see cref="Value"/> (0..1) over 500 ms.
/// Indeterminate: a highlight sweeps across (1.4 s loop); with reduced motion it shows a static half bar.
/// </summary>
public sealed class ShimmerBar : Grid
{
    private readonly Rectangle _track = new() { RadiusX = 1.5, RadiusY = 1.5 };
    private readonly Rectangle _fill = new() { RadiusX = 1.5, RadiusY = 1.5, HorizontalAlignment = HorizontalAlignment.Left };
    private readonly TranslateTransform _sweep = new();

    public static readonly DependencyProperty ValueProperty = DependencyProperty.Register(
        nameof(Value), typeof(double), typeof(ShimmerBar), new PropertyMetadata(0.0, (d, _) => ((ShimmerBar)d).Update()));

    public static readonly DependencyProperty IsIndeterminateProperty = DependencyProperty.Register(
        nameof(IsIndeterminate), typeof(bool), typeof(ShimmerBar), new PropertyMetadata(false, (d, _) => ((ShimmerBar)d).Update()));

    public ShimmerBar()
    {
        Height = 3;
        ClipToBounds = true;
        _track.SetResourceReference(Shape.FillProperty, "Line");
        _fill.SetResourceReference(Shape.FillProperty, "ProgressGradient");
        _fill.Width = 0;
        Children.Add(_track);
        Children.Add(_fill);
        SizeChanged += (_, _) => Update();
        Loaded += (_, _) => Update();
        IsHitTestVisible = false;
    }

    public double Value { get => (double)GetValue(ValueProperty); set => SetValue(ValueProperty, value); }
    public bool IsIndeterminate { get => (bool)GetValue(IsIndeterminateProperty); set => SetValue(IsIndeterminateProperty, value); }

    private void Update()
    {
        var w = ActualWidth;
        if (w <= 0)
        {
            return;
        }
        _sweep.BeginAnimation(TranslateTransform.XProperty, null);
        if (IsIndeterminate)
        {
            _fill.BeginAnimation(WidthProperty, null);
            _fill.Width = w * 0.35;
            if (Motion.Reduced)
            {
                _fill.RenderTransform = null;
                _fill.Width = w * 0.5;
                return;
            }
            _fill.RenderTransform = _sweep;
            _sweep.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(-w * 0.35, w, new Duration(TimeSpan.FromMilliseconds(1400)))
            {
                RepeatBehavior = RepeatBehavior.Forever,
                EasingFunction = Motion.Smooth,
            });
            return;
        }
        _fill.RenderTransform = null;
        var target = Math.Clamp(Value, 0, 1) * w;
        _fill.BeginAnimation(WidthProperty, new DoubleAnimation(target, Motion.Ms(500)) { EasingFunction = Motion.Ease });
    }
}
