using System.Windows;
using System.Windows.Controls;

namespace PcDoctor.App.Controls;

/// <summary>A ContentControl that plays the page transition (fade + 16px rise, 300 ms) on every change.</summary>
public sealed class PageHost : ContentControl
{
    protected override void OnContentChanged(object oldContent, object newContent)
    {
        base.OnContentChanged(oldContent, newContent);
        if (oldContent is not null)
        {
            Motion.Enter(this);
        }
    }
}
