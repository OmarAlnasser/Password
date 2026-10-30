using System.ComponentModel;
using System.Globalization;
using System.Windows;
using System.Windows.Data;
using System.Windows.Markup;
using PcDoctor.Core.Localization;

namespace PcDoctor.App.Localization;

/// <summary>Bindable string table. Raising "Item[]" refreshes every {loc:Loc} binding on language change.</summary>
public sealed class LocSource : INotifyPropertyChanged
{
    public static LocSource Instance { get; } = new();

    public string this[string key] => Loc.Resolve(new Core.Findings.Text(key));

    public FlowDirection FlowDirection => Loc.IsRightToLeft() ? FlowDirection.RightToLeft : FlowDirection.LeftToRight;

    public event PropertyChangedEventHandler? PropertyChanged;

    public void SetCulture(CultureInfo culture)
    {
        Loc.Culture = culture;
        CultureInfo.CurrentUICulture = culture;
        Refresh();
    }

    public void Refresh()
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs("Item[]"));
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(FlowDirection)));
    }
}

/// <summary>Usage in XAML: <c>{loc:Loc app.title}</c>.</summary>
[MarkupExtensionReturnType(typeof(BindingExpression))]
public sealed class LocExtension(string key) : MarkupExtension
{
    public string Key { get; } = key;

    public override object ProvideValue(IServiceProvider serviceProvider) =>
        new Binding($"[{Key}]") { Source = LocSource.Instance, Mode = BindingMode.OneWay }.ProvideValue(serviceProvider);
}
