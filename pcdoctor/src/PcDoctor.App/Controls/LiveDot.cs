using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;

namespace PcDoctor.App.Controls;

/// <summary>
/// The 8px status dot with a pulsing ring (2.4 s loop). Decorative: the text next to it carries
/// the meaning. Pulses only while <see cref="IsLive"/> and motion is allowed.
/// </summary>
public sealed class LiveDot : Grid
{
    private readonly Ellipse _ring = new() { Width = 8, Height = 8, Opacity = 0, IsHitTestVisible = false };
    private readonly Ellipse _dot = new() { Width = 8, Height = 8 };
    private readonly ScaleTransform _scale = new(1, 1);

    public static readonly DependencyProperty IsLiveProperty = DependencyProperty.Register(
        nameof(IsLive), typeof(bool), typeof(LiveDot), new PropertyMetadata(true, (d, _) => ((LiveDot)d).Update()));

    public static readonly DependencyProperty DotBrushProperty = DependencyProperty.Register(
        nameof(DotBrush), typeof(Brush), typeof(LiveDot), new PropertyMetadata(Brushes.MediumSeaGreen, (d, e) =>
        {
            var self = (LiveDot)d;
            self._dot.Fill = (Brush)e.NewValue;
            self._ring.Fill = (Brush)e.NewValue;
        }));

    public LiveDot()
    {
        Width = 20;
        Height = 20;
        _ring.RenderTransformOrigin = new Point(0.5, 0.5);
        _ring.RenderTransform = _scale;
        Children.Add(_ring);
        Children.Add(_dot);
        Loaded += (_, _) => Update();
        Unloaded += (_, _) => Stop();
    }

    public bool IsLive { get => (bool)GetValue(IsLiveProperty); set => SetValue(IsLiveProperty, value); }
    public Brush DotBrush { get => (Brush)GetValue(DotBrushProperty); set => SetValue(DotBrushProperty, value); }

    // Decorative: no automation peer, so screen readers skip it and read the text beside it.
    protected override System.Windows.Automation.Peers.AutomationPeer? OnCreateAutomationPeer() => null;

    private void Update()
    {
        if (!IsLoaded)
        {
            return;
        }
        if (!IsLive || Motion.Reduced)
        {
            Stop();
            return;
        }
        var d = new Duration(TimeSpan.FromMilliseconds(2400));
        var grow = new DoubleAnimation(1, 2.4, d) { RepeatBehavior = RepeatBehavior.Forever, EasingFunction = Motion.Smooth };
        var fade = new DoubleAnimation(0.5, 0, d) { RepeatBehavior = RepeatBehavior.Forever, EasingFunction = Motion.Smooth };
        _scale.BeginAnimation(ScaleTransform.ScaleXProperty, grow);
        _scale.BeginAnimation(ScaleTransform.ScaleYProperty, grow);
        _ring.BeginAnimation(OpacityProperty, fade);
    }

    private void Stop()
    {
        _scale.BeginAnimation(ScaleTransform.ScaleXProperty, null);
        _scale.BeginAnimation(ScaleTransform.ScaleYProperty, null);
        _ring.BeginAnimation(OpacityProperty, null);
        _ring.Opacity = 0;
    }
}
