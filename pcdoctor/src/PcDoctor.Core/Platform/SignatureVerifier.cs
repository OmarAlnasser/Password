using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using Microsoft.Win32.SafeHandles;

namespace PcDoctor.Core.Platform;

public enum SignatureStatus { MicrosoftSigned, Signed, Invalid, Unsigned, NotFound, Error }

/// <param name="ViaCatalog">True when the file is signed through a Windows catalog rather than an embedded signature.</param>
/// <param name="Detail">For Invalid/Error: the WinVerifyTrust result (e.g. CERT_E_EXPIRED).</param>
public sealed record SignatureInfo(SignatureStatus Status, string? Publisher, bool ViaCatalog, string? Detail);

/// <summary>
/// Authenticode verification the way Microsoft's code-signing sample does it: WinVerifyTrust on the
/// embedded signature, and if there is none, a catalog lookup by SHA-256 (then SHA-1) hash with
/// WTD_CHOICE_CATALOG. Revocation is not checked (no network); the state handle is always closed.
/// X509Certificate is only used to read the publisher name after WinVerifyTrust succeeded.
/// </summary>
[SupportedOSPlatform("windows")]
public static class SignatureVerifier
{
    private static readonly Guid GenericVerifyV2 = new("00AAC56B-CD44-11d0-8CC2-00C04FC295EE");
    private const uint TRUST_E_NOSIGNATURE = 0x800B0100;
    private const uint TRUST_E_SUBJECT_FORM_UNKNOWN = 0x800B0003;
    private const uint TRUST_E_PROVIDER_UNKNOWN = 0x800B0001;

    public static SignatureInfo Verify(string path)
    {
        if (!File.Exists(path))
        {
            return new SignatureInfo(SignatureStatus.NotFound, null, false, null);
        }
        try
        {
            var embedded = VerifyEmbedded(path);
            if (embedded == 0)
            {
                return Signed(path, viaCatalog: false);
            }
            if (embedded is not (TRUST_E_NOSIGNATURE or TRUST_E_SUBJECT_FORM_UNKNOWN or TRUST_E_PROVIDER_UNKNOWN))
            {
                return new SignatureInfo(SignatureStatus.Invalid, PublisherOf(path), false, Describe(embedded));
            }
            var (catalogResult, catalogPath) = VerifyCatalog(path);
            if (catalogPath is null)
            {
                return new SignatureInfo(SignatureStatus.Unsigned, null, false, null);
            }
            return catalogResult == 0
                ? Signed(catalogPath, viaCatalog: true)
                : new SignatureInfo(SignatureStatus.Invalid, PublisherOf(catalogPath), true, Describe(catalogResult));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or CryptographicException)
        {
            return new SignatureInfo(SignatureStatus.Error, null, false, ex.GetType().Name);
        }
    }

    public static string Sha256(string path)
    {
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        return Convert.ToHexString(SHA256.HashData(stream));
    }

    private static SignatureInfo Signed(string signedFile, bool viaCatalog)
    {
        var publisher = PublisherOf(signedFile);
        var microsoft = publisher is not null && (publisher.Contains("O=Microsoft Corporation", StringComparison.Ordinal) ||
                                                  publisher.Contains("O=Microsoft Windows", StringComparison.Ordinal));
        return new SignatureInfo(microsoft ? SignatureStatus.MicrosoftSigned : SignatureStatus.Signed, ShortName(publisher), viaCatalog, null);
    }

    private static string? PublisherOf(string signedFile)
    {
        try
        {
#pragma warning disable SYSLIB0057 // Reading the signer subject only; trust was decided by WinVerifyTrust.
            using var cert = X509Certificate.CreateFromSignedFile(signedFile);
#pragma warning restore SYSLIB0057
            return cert.Subject;
        }
        catch (CryptographicException)
        {
            return null;
        }
    }

    /// <summary>"CN=NVIDIA Corporation, O=NVIDIA Corporation, ..." → keeps O= (or CN=) and the full subject for Microsoft checks.</summary>
    private static string? ShortName(string? subject)
    {
        if (subject is null)
        {
            return null;
        }
        foreach (var part in subject.Split(", "))
        {
            if (part.StartsWith("O=", StringComparison.Ordinal))
            {
                return part[2..].Trim('"') + " | " + subject;
            }
        }
        return subject;
    }

    public static string DisplayPublisher(string? publisher) => publisher?.Split(" | ")[0] ?? "";

    private static string Describe(uint hr) => hr switch
    {
        0x800B0101 => "CERT_E_EXPIRED",
        0x800B010C => "CERT_E_REVOKED",
        0x80096010 => "TRUST_E_BAD_DIGEST",
        0x800B0111 => "TRUST_E_EXPLICIT_DISTRUST",
        0x800B0109 => "CERT_E_UNTRUSTEDROOT",
        0x800B010A => "CERT_E_CHAINING",
        0x80096019 => "TRUST_E_BASIC_CONSTRAINTS",
        0x800B0004 => "TRUST_E_SUBJECT_NOT_TRUSTED",
        _ => "0x" + hr.ToString("X8"),
    };

    private static uint VerifyEmbedded(string path)
    {
        var fileInfo = new WINTRUST_FILE_INFO
        {
            cbStruct = (uint)Marshal.SizeOf<WINTRUST_FILE_INFO>(),
            pcwszFilePath = path,
        };
        var pFile = Marshal.AllocHGlobal(Marshal.SizeOf<WINTRUST_FILE_INFO>());
        try
        {
            Marshal.StructureToPtr(fileInfo, pFile, false);
            return Run(1 /* WTD_CHOICE_FILE */, pFile);
        }
        finally
        {
            Marshal.DestroyStructure<WINTRUST_FILE_INFO>(pFile);
            Marshal.FreeHGlobal(pFile);
        }
    }

    private static (uint Result, string? CatalogPath) VerifyCatalog(string path)
    {
        foreach (var algorithm in new[] { "SHA256", "SHA1" })
        {
            if (!CryptCATAdminAcquireContext2(out var admin, IntPtr.Zero, algorithm, IntPtr.Zero, 0))
            {
                continue;
            }
            try
            {
                using var file = File.OpenHandle(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                uint size = 0;
                CryptCATAdminCalcHashFromFileHandle2(admin, file, ref size, null, 0);
                if (size == 0)
                {
                    continue;
                }
                var hash = new byte[size];
                if (!CryptCATAdminCalcHashFromFileHandle2(admin, file, ref size, hash, 0))
                {
                    continue;
                }
                var prev = IntPtr.Zero;
                var catInfo = CryptCATAdminEnumCatalogFromHash(admin, hash, size, 0, ref prev);
                if (catInfo == IntPtr.Zero)
                {
                    continue;
                }
                try
                {
                    var info = new CATALOG_INFO { cbStruct = (uint)Marshal.SizeOf<CATALOG_INFO>() };
                    if (!CryptCATCatalogInfoFromContext(catInfo, ref info, 0))
                    {
                        continue;
                    }
                    var catalog = new WINTRUST_CATALOG_INFO
                    {
                        cbStruct = (uint)Marshal.SizeOf<WINTRUST_CATALOG_INFO>(),
                        pcwszCatalogFilePath = info.wszCatalogFile,
                        pcwszMemberTag = Convert.ToHexString(hash),
                        pcwszMemberFilePath = path,
                        hCatAdmin = admin,
                    };
                    var hashPtr = Marshal.AllocHGlobal(hash.Length);
                    var pCat = Marshal.AllocHGlobal(Marshal.SizeOf<WINTRUST_CATALOG_INFO>());
                    try
                    {
                        Marshal.Copy(hash, 0, hashPtr, hash.Length);
                        catalog.pbCalculatedFileHash = hashPtr;
                        catalog.cbCalculatedFileHash = size;
                        Marshal.StructureToPtr(catalog, pCat, false);
                        return (Run(2 /* WTD_CHOICE_CATALOG */, pCat), info.wszCatalogFile);
                    }
                    finally
                    {
                        Marshal.DestroyStructure<WINTRUST_CATALOG_INFO>(pCat);
                        Marshal.FreeHGlobal(pCat);
                        Marshal.FreeHGlobal(hashPtr);
                    }
                }
                finally
                {
                    CryptCATAdminReleaseCatalogContext(admin, catInfo, 0);
                }
            }
            finally
            {
                CryptCATAdminReleaseContext(admin, 0);
            }
        }
        return (TRUST_E_NOSIGNATURE, null);
    }

    private static uint Run(uint unionChoice, IntPtr union)
    {
        var data = new WINTRUST_DATA
        {
            cbStruct = (uint)Marshal.SizeOf<WINTRUST_DATA>(),
            dwUIChoice = 2,              // WTD_UI_NONE
            fdwRevocationChecks = 0,     // WTD_REVOKE_NONE
            dwUnionChoice = unionChoice,
            pUnion = union,
            dwStateAction = 1,           // WTD_STATEACTION_VERIFY
            dwProvFlags = 0x1000 | 0x10, // WTD_CACHE_ONLY_URL_RETRIEVAL | WTD_REVOCATION_CHECK_NONE
        };
        var action = GenericVerifyV2;
        var result = WinVerifyTrust(new IntPtr(-1), ref action, ref data);
        data.dwStateAction = 2; // WTD_STATEACTION_CLOSE, always
        WinVerifyTrust(new IntPtr(-1), ref action, ref data);
        return unchecked((uint)result);
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WINTRUST_FILE_INFO
    {
        public uint cbStruct;
        [MarshalAs(UnmanagedType.LPWStr)] public string pcwszFilePath;
        public IntPtr hFile;
        public IntPtr pgKnownSubject;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WINTRUST_CATALOG_INFO
    {
        public uint cbStruct;
        public uint dwCatalogVersion;
        [MarshalAs(UnmanagedType.LPWStr)] public string pcwszCatalogFilePath;
        [MarshalAs(UnmanagedType.LPWStr)] public string pcwszMemberTag;
        [MarshalAs(UnmanagedType.LPWStr)] public string pcwszMemberFilePath;
        public IntPtr hMemberFile;
        public IntPtr pbCalculatedFileHash;
        public uint cbCalculatedFileHash;
        public IntPtr pcCatalogContext;
        public IntPtr hCatAdmin;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct WINTRUST_DATA
    {
        public uint cbStruct;
        public IntPtr pPolicyCallbackData;
        public IntPtr pSIPClientData;
        public uint dwUIChoice;
        public uint fdwRevocationChecks;
        public uint dwUnionChoice;
        public IntPtr pUnion;
        public uint dwStateAction;
        public IntPtr hWVTStateData;
        public IntPtr pwszURLReference;
        public uint dwProvFlags;
        public uint dwUIContext;
        public IntPtr pSignatureSettings;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct CATALOG_INFO
    {
        public uint cbStruct;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string wszCatalogFile;
    }

    [DllImport("wintrust.dll", CharSet = CharSet.Unicode)]
    private static extern int WinVerifyTrust(IntPtr hwnd, ref Guid action, ref WINTRUST_DATA data);

    [DllImport("wintrust.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CryptCATAdminAcquireContext2(out IntPtr admin, IntPtr subsystem, string hashAlgorithm, IntPtr strongHashPolicy, uint flags);

    [DllImport("wintrust.dll", SetLastError = true)]
    private static extern bool CryptCATAdminCalcHashFromFileHandle2(IntPtr admin, SafeFileHandle file, ref uint hashSize, byte[]? hash, uint flags);

    [DllImport("wintrust.dll", SetLastError = true)]
    private static extern IntPtr CryptCATAdminEnumCatalogFromHash(IntPtr admin, byte[] hash, uint hashSize, uint flags, ref IntPtr prevCatInfo);

    [DllImport("wintrust.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CryptCATCatalogInfoFromContext(IntPtr catInfo, ref CATALOG_INFO info, uint flags);

    [DllImport("wintrust.dll")]
    private static extern bool CryptCATAdminReleaseCatalogContext(IntPtr admin, IntPtr catInfo, uint flags);

    [DllImport("wintrust.dll")]
    private static extern bool CryptCATAdminReleaseContext(IntPtr admin, uint flags);
}
