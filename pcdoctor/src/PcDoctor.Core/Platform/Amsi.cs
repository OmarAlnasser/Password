using System.Runtime.InteropServices;
using System.Runtime.Versioning;

namespace PcDoctor.Core.Platform;

/// <summary>
/// The Antimalware Scan Interface: hands script text to the installed antivirus (Defender or a
/// third-party AMSI provider). A result of 32768 or more means the provider called it malware;
/// anything lower is "no verdict", never "safe".
/// </summary>
[SupportedOSPlatform("windows")]
public sealed partial class Amsi : IDisposable
{
    public const int AMSI_RESULT_DETECTED = 32768;
    private readonly IntPtr _context;
    private readonly IntPtr _session;

    private Amsi(IntPtr context, IntPtr session)
    {
        _context = context;
        _session = session;
    }

    public static Amsi? TryOpen()
    {
        try
        {
            if (AmsiInitialize("PC Doctor", out var ctx) != 0)
            {
                return null;
            }
            if (AmsiOpenSession(ctx, out var session) != 0)
            {
                AmsiUninitialize(ctx);
                return null;
            }
            return new Amsi(ctx, session);
        }
        catch (DllNotFoundException)
        {
            return null;
        }
        catch (EntryPointNotFoundException)
        {
            return null;
        }
    }

    public static bool IsMalware(int result) => result >= AMSI_RESULT_DETECTED;

    public int Scan(string content, string name)
    {
        var bytes = System.Text.Encoding.Unicode.GetBytes(content);
        return AmsiScanBuffer(_context, bytes, (uint)bytes.Length, name, _session, out var result) == 0 ? result : 0;
    }

    public void Dispose()
    {
        AmsiCloseSession(_context, _session);
        AmsiUninitialize(_context);
    }

    [LibraryImport("amsi.dll", StringMarshalling = StringMarshalling.Utf16)]
    private static partial int AmsiInitialize(string appName, out IntPtr context);

    [LibraryImport("amsi.dll")]
    private static partial int AmsiOpenSession(IntPtr context, out IntPtr session);

    [LibraryImport("amsi.dll", StringMarshalling = StringMarshalling.Utf16)]
    private static partial int AmsiScanBuffer(IntPtr context, byte[] buffer, uint length, string contentName, IntPtr session, out int result);

    [LibraryImport("amsi.dll")]
    private static partial void AmsiCloseSession(IntPtr context, IntPtr session);

    [LibraryImport("amsi.dll")]
    private static partial void AmsiUninitialize(IntPtr context);
}
