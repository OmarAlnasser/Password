namespace PcDoctor.Modules.Security;

/// <summary>MSFT_MpComputerStatus (root\Microsoft\Windows\Defender).</summary>
public sealed record DefenderStatus(
    string? AMRunningMode,
    bool? AntivirusEnabled,
    bool? RealTimeProtectionEnabled,
    bool? IsTamperProtected,
    int? SignatureAgeDays);

/// <summary>root\SecurityCenter2:AntiVirusProduct. Absent on Windows Server.</summary>
public sealed record AvProduct(string DisplayName, uint ProductState)
{
    /// <summary>
    /// productState is undocumented. The widely used reading: bits 12–15 = 1 means on, bits 4–7 = 0
    /// means definitions up to date. VERIFY; findings built on it are Probable at most.
    /// </summary>
    public bool? IsEnabled => ((ProductState >> 12) & 0xF) switch { 1 => true, 0 => false, _ => null };

    public bool IsDefender => DisplayName.Contains("Defender", StringComparison.OrdinalIgnoreCase);
}

public sealed record FirewallProfile(string Name, bool? Enabled);

public sealed record DeviceGuardStatus(int? VbsStatus, IReadOnlyList<int> SecurityServicesRunning, int? CodeIntegrityPolicyEnforcementStatus);

public sealed record TpmStatus(bool Present, bool? Enabled, bool? Activated, string? SpecVersion);

public sealed record BitLockerVolume(string DriveLetter, int ProtectionStatus, int? ConversionStatus);

public sealed record SecuritySnapshot
{
    public int OsBuild { get; init; }
    public string OsEdition { get; init; } = "";
    public DefenderStatus? Defender { get; init; }
    /// <summary>Null when SecurityCenter2 is not available.</summary>
    public IReadOnlyList<AvProduct>? AvProducts { get; init; }
    public IReadOnlyList<FirewallProfile>? Firewall { get; init; }
    public int? EnableLua { get; init; }
    public int? ConsentPromptBehaviorAdmin { get; init; }
    /// <summary>Null = no UEFI Secure Boot state key (legacy BIOS or unknown).</summary>
    public bool? SecureBootEnabled { get; init; }
    public DeviceGuardStatus? DeviceGuard { get; init; }
    /// <summary>CI\Policy VerifiedAndReputablePolicyState: 0 off, 1 on, 2 evaluation.</summary>
    public int? SmartAppControlState { get; init; }
    public int? LsaRunAsPpl { get; init; }
    /// <summary>Win32_OptionalFeature SMB1Protocol InstallState: 1 enabled, 2 disabled, 3 absent.</summary>
    public int? Smb1InstallState { get; init; }
    public int? RdpDenyConnections { get; init; }
    public int? RdpNla { get; init; }
    public IReadOnlyList<string> PendingRebootReasons { get; init; } = [];
    public DateTime? LastUpdateInstalled { get; init; }
    public IReadOnlyList<string>? LocalAdministrators { get; init; }
    /// <summary>Null = not read (needs Deep Scan).</summary>
    public TpmStatus? Tpm { get; init; }
    public IReadOnlyList<BitLockerVolume>? BitLocker { get; init; }
}
