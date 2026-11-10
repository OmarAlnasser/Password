using System.Globalization;
using System.Text;

namespace PcDoctor.Modules.Drivers;

/// <summary>One driver worth showing: a hardware maker's driver, not one of the hundreds that ship inside Windows.</summary>
public sealed record AdvisedDriver(string Device, string Provider, string? Version, DateTime? Date, string? OfficialUrl)
{
    public int? AgeYears(DateTimeOffset now) => Date is { } d && d.Year > 2006 ? (int)((now.UtcDateTime - d).TotalDays / 365.25) : null;
}

/// <summary>
/// Picks the drivers to show and where the official download is. Pure: nothing here touches the network,
/// and nothing here installs anything. The official page is always the maker's own site or Windows Update.
/// </summary>
public static class DriverAdvice
{
    public const int MaxDevices = 40;
    public const string WindowsUpdateOptional = "ms-settings:windowsupdate-optionalupdates";

    /// <summary>Maker name fragment → the maker's own support page. Only first-party sites are listed.</summary>
    private static readonly (string Fragment, string Url)[] Official =
    [
        ("nvidia", "https://www.nvidia.com/drivers"),
        ("advanced micro devices", "https://www.amd.com/support"),
        ("amd", "https://www.amd.com/support"),
        ("intel", "https://www.intel.com/content/www/us/en/download-center/home.html"),
        ("realtek", "https://www.realtek.com/Download/Index"),
        ("qualcomm", "https://www.qualcomm.com/support"),
        ("mediatek", "https://www.mediatek.com/products"),
        ("broadcom", "https://www.broadcom.com/support/download-search"),
        ("dell", "https://www.dell.com/support/home"),
        ("hewlett", "https://support.hp.com/drivers"),
        ("hp inc", "https://support.hp.com/drivers"),
        ("lenovo", "https://pcsupport.lenovo.com"),
        ("asus", "https://www.asus.com/support/download-center"),
        ("micro-star", "https://www.msi.com/support/download"),
        ("msi", "https://www.msi.com/support/download"),
        ("gigabyte", "https://www.gigabyte.com/Support"),
        ("acer", "https://www.acer.com/support"),
        ("samsung", "https://www.samsung.com/support"),
        ("logitech", "https://support.logi.com"),
        ("razer", "https://mysupport.razer.com"),
        ("corsair", "https://www.corsair.com/downloads"),
        ("synaptics", "https://www.synaptics.com/products/touchpad-family"),
        ("elan", "https://www.emc.com.tw/eng/support.asp"),
        ("killer", "https://www.intel.com/content/www/us/en/download-center/home.html"),
    ];

    /// <summary>Sites the AI research may read. Maker sites and Microsoft only; no driver-download aggregators.</summary>
    public static readonly IReadOnlyList<string> AllowedDomains =
    [
        "microsoft.com", "nvidia.com", "amd.com", "intel.com", "realtek.com", "qualcomm.com", "mediatek.com", "broadcom.com",
        "dell.com", "hp.com", "lenovo.com", "asus.com", "msi.com", "gigabyte.com", "acer.com", "samsung.com", "logi.com",
        "razer.com", "corsair.com", "synaptics.com",
    ];

    public static string? OfficialUrl(string? provider)
    {
        if (string.IsNullOrWhiteSpace(provider))
        {
            return null;
        }
        foreach (var (fragment, url) in Official)
        {
            // Short names must match a whole word, so "amd" does not match "Camden" and "msi" does not match "Emsisoft".
            var hit = fragment.Length <= 4
                ? provider.Split([' ', ',', '.', '(', ')', '-'], StringSplitOptions.RemoveEmptyEntries).Any(w => w.Equals(fragment, StringComparison.OrdinalIgnoreCase))
                : provider.Contains(fragment, StringComparison.OrdinalIgnoreCase);
            if (hit)
            {
                return url;
            }
        }
        return null;
    }

    /// <summary>Hardware makers' drivers, one row per maker and version (the newest device name kept), oldest first.</summary>
    public static IReadOnlyList<AdvisedDriver> Select(IEnumerable<SignedDriver>? drivers) =>
        (drivers ?? [])
        .Where(d => !string.IsNullOrWhiteSpace(d.Provider) && !d.Provider!.Contains("Microsoft", StringComparison.OrdinalIgnoreCase)
                    && !d.Provider.StartsWith('(') && !string.IsNullOrWhiteSpace(d.DeviceName) && d.DeviceName != "?")
        .GroupBy(d => (Provider: d.Provider!.Trim().ToUpperInvariant(), d.Version))
        .Select(g => g.OrderBy(d => d.DeviceName.Length).First())
        .OrderBy(d => d.Date ?? DateTime.MaxValue)
        .Take(MaxDevices)
        .Select(d => new AdvisedDriver(d.DeviceName.Trim(), d.Provider!.Trim(), d.Version, d.Date, OfficialUrl(d.Provider)))
        .ToList();

    /// <summary>
    /// Exactly what is sent in AI mode, and nothing else: device names, maker, version, date and the Windows build.
    /// No user name, PC name, serial number, file path or address. The same text is shown to the user before sending.
    /// </summary>
    public static string DeviceList(IEnumerable<AdvisedDriver> drivers, string windowsVersion)
    {
        var sb = new StringBuilder();
        sb.Append("Windows: ").AppendLine(windowsVersion);
        foreach (var d in drivers)
        {
            sb.Append("- ").Append(d.Device).Append(" | maker: ").Append(d.Provider)
                .Append(" | installed version: ").Append(d.Version ?? "unknown")
                .Append(" | driver date: ").AppendLine(d.Date?.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) ?? "unknown");
        }
        return sb.ToString();
    }

    public static string Prompt(IEnumerable<AdvisedDriver> drivers, string windowsVersion, bool arabic) =>
        "You are helping the owner of a Windows PC decide which device drivers are worth updating.\n" +
        "Below is the list of hardware drivers installed on the PC.\n\n" + DeviceList(drivers, windowsVersion) + "\n" +
        "Search only the hardware makers' own websites and Microsoft. For each device where you can confirm it on an official page, say: " +
        "the newest official driver version and its release date, whether it is newer than the installed one, and the official page address. " +
        "Rules: never suggest third-party driver download sites or driver-updater programs. If you cannot confirm a newer version on an official page, " +
        "say so plainly instead of guessing. A driver that works and has no newer official release should be left alone. " +
        "For laptops and brand-name PCs, say that the PC maker's own support page is the safer source. " +
        "Do not claim any update is certain to help. Keep it short: one short paragraph per device, the most useful updates first, then one line listing devices that need nothing. " +
        "Plain text only, no tables.\n" +
        (arabic ? "Write the answer in Arabic. Keep version numbers and web addresses in Latin characters." : "Write the answer in English.");
}
