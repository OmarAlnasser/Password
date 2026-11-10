using PcDoctor.Modules.Drivers;
using Xunit;

namespace PcDoctor.Tests.Modules;

public class DriverAdviceTests
{
    private static SignedDriver D(string device, string? provider, string? version = "1.0", int year = 2020) =>
        new(device, provider, version, new DateTime(year, 1, 1), true, "oem1.inf");

    [Fact]
    public void Windows_own_drivers_are_left_out_and_duplicates_collapse()
    {
        var rows = DriverAdvice.Select([
            D("USB Root Hub", "Microsoft"), D("Volume", "(Standard system devices)"), D("Unnamed", null),
            D("Realtek Audio", "Realtek Semiconductor Corp.", "6.0.1"), D("Realtek Audio Effects Component", "Realtek Semiconductor Corp.", "6.0.1"),
            D("NVIDIA GeForce RTX 3060", "NVIDIA", "32.0.15", 2024)]);
        Assert.Equal(["Realtek Audio", "NVIDIA GeForce RTX 3060"], rows.Select(r => r.Device));
    }

    [Fact]
    public void The_list_is_capped_and_a_missing_list_is_empty()
    {
        Assert.Empty(DriverAdvice.Select(null));
        Assert.Equal(DriverAdvice.MaxDevices, DriverAdvice.Select(Enumerable.Range(0, 200).Select(i => D("Device " + i, "Maker " + i))).Count);
    }

    [Theory]
    [InlineData("NVIDIA", "nvidia.com")]
    [InlineData("Advanced Micro Devices, Inc.", "amd.com")]
    [InlineData("AMD", "amd.com")]
    [InlineData("Intel Corporation", "intel.com")]
    [InlineData("Micro-Star International", "msi.com")]
    public void Known_makers_point_to_their_own_site(string provider, string host) =>
        Assert.Contains(host, DriverAdvice.OfficialUrl(provider));

    [Theory]
    [InlineData("Camden Devices")]
    [InlineData("Emsisoft")]
    [InlineData("Some Unknown Maker")]
    [InlineData(null)]
    public void Unknown_makers_get_no_link_rather_than_a_guess(string? provider) => Assert.Null(DriverAdvice.OfficialUrl(provider));

    [Fact]
    public void Every_link_is_https_on_an_allowed_first_party_domain()
    {
        foreach (var provider in new[] { "nvidia", "amd", "intel", "realtek", "qualcomm", "broadcom", "dell", "hewlett", "lenovo", "asus", "msi", "gigabyte", "acer", "samsung", "logitech", "razer", "corsair", "synaptics" })
        {
            var uri = new Uri(DriverAdvice.OfficialUrl(provider)!);
            Assert.Equal("https", uri.Scheme);
            Assert.Contains(DriverAdvice.AllowedDomains, d => uri.Host == d || uri.Host.EndsWith("." + d, StringComparison.Ordinal));
        }
    }

    [Fact]
    public void What_is_sent_holds_only_device_maker_version_date_and_windows_build()
    {
        var rows = DriverAdvice.Select([D("Intel(R) Wi-Fi 6 AX201", "Intel", "22.1.0", 2021)]);
        var text = DriverAdvice.DeviceList(rows, "10.0.22631.0");
        Assert.Equal("Windows: 10.0.22631.0\n- Intel(R) Wi-Fi 6 AX201 | maker: Intel | installed version: 22.1.0 | driver date: 2021-01-01\n", text.ReplaceLineEndings("\n"));
        Assert.DoesNotContain(Environment.MachineName, text, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("oem1.inf", text);
    }

    [Fact]
    public void The_request_tells_the_ai_to_use_official_sites_and_not_to_guess()
    {
        var prompt = DriverAdvice.Prompt(DriverAdvice.Select([D("Card", "NVIDIA")]), "10.0", arabic: true);
        Assert.Contains("never suggest third-party driver download sites", prompt);
        Assert.Contains("instead of guessing", prompt);
        Assert.Contains("Arabic", prompt);
    }

    [Fact]
    public void Age_is_unknown_for_placeholder_dates()
    {
        var now = new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero);
        Assert.Equal(6, new AdvisedDriver("a", "b", "1", new DateTime(2019, 6, 1), null).AgeYears(now));
        Assert.Null(new AdvisedDriver("a", "b", "1", new DateTime(2006, 6, 21), null).AgeYears(now));
        Assert.Null(new AdvisedDriver("a", "b", "1", null, null).AgeYears(now));
    }
}
