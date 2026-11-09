using System.Management;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using Microsoft.Win32;
using PcDoctor.Core.Journal;
using PcDoctor.Core.Platform;

namespace PcDoctor.Modules.Persistence;

/// <summary>Reads every persistence location. Each location is read on its own so one failure never hides the rest.</summary>
[SupportedOSPlatform("windows")]
public static class PersistenceReader
{
    private static readonly string[] RunKeys =
    [
        @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        @"SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
        @"SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run",
        @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run",
        @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce",
    ];

    private static readonly string[] AccessibilityBinaries = ["sethc.exe", "utilman.exe", "osk.exe", "Magnify.exe", "Narrator.exe", "DisplaySwitch.exe", "AtBroker.exe"];

    public static PersistenceSnapshot Read(bool verifySignatures = true)
    {
        var entries = new List<AutorunEntry>();
        var unread = new Dictionary<AutorunCategory, string>();
        void Try(AutorunCategory cat, Action read)
        {
            try
            {
                read();
            }
            catch (Exception ex) when (ex is UnauthorizedAccessException or System.Security.SecurityException or ManagementException or COMException or IOException)
            {
                unread[cat] = ex is UnauthorizedAccessException or System.Security.SecurityException ||
                              ex is ManagementException { ErrorCode: ManagementStatus.AccessDenied }
                    ? "check.needsDeepScan"
                    : "m3.unread.error";
            }
        }

        Try(AutorunCategory.RunKey, () => ReadRunKeys(entries));
        Try(AutorunCategory.StartupFolder, () => ReadStartupFolders(entries));
        Try(AutorunCategory.Service, () => ReadServices(entries));
        Try(AutorunCategory.ScheduledTask, () => ReadTasks(entries));
        Try(AutorunCategory.WmiSubscription, () => ReadWmi(entries));
        Try(AutorunCategory.Winlogon, () => ReadWinlogon(entries));
        Try(AutorunCategory.AppInit, () => ReadAppInit(entries));
        Try(AutorunCategory.ImageFileExecution, () => ReadIfeo(entries));
        Try(AutorunCategory.Accessibility, () => ReadAccessibility(entries));
        Try(AutorunCategory.BootExecute, () => ReadBootExecute(entries));
        Try(AutorunCategory.Lsa, () => ReadLsa(entries));
        Try(AutorunCategory.PrintMonitor, () => ReadPrintMonitors(entries));
        Try(AutorunCategory.WinsockProvider, () => ReadWinsock(entries));
        Try(AutorunCategory.ComHijack, () => ReadComHijacks(entries));
        Try(AutorunCategory.OfficeAddin, () => ReadOffice(entries));
        Try(AutorunCategory.BrowserExtension, () => ReadBrowsers(entries));
        Try(AutorunCategory.PowerShellProfile, () => ReadPowerShellProfiles(entries));
        Try(AutorunCategory.ScreenSaver, () => ReadScreenSaver(entries));

        var verified = verifySignatures ? entries.Select(Enrich).ToList() : entries;
        return new PersistenceSnapshot { Entries = verified, Unread = unread };
    }

    // ---------- helpers ----------

    private static string? Env(string name) => Environment.GetEnvironmentVariable(name);

    private static string? Resolve(string command) => CommandLines.ResolveImage(command, File.Exists, Env);

    /// <summary>Loaded user hives: S-1-5-21-* without the _Classes suffix.</summary>
    private static IEnumerable<string> UserSids()
    {
        using var users = RegistryKey.OpenBaseKey(RegistryHive.Users, RegistryView.Registry64);
        return users.GetSubKeyNames().Where(n => n.StartsWith("S-1-5-21-", StringComparison.Ordinal) && !n.EndsWith("_Classes", StringComparison.Ordinal)).ToList();
    }

    private static RegistryKey Lm => RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);

    private static IEnumerable<(string Location, RegistryKey Root, string Key)> HklmAndUsers(string key)
    {
        yield return (@"HKLM\" + key, Lm, key);
        foreach (var sid in UserSids())
        {
            using var users = RegistryKey.OpenBaseKey(RegistryHive.Users, RegistryView.Registry64);
            var root = users.OpenSubKey(sid);
            if (root is not null)
            {
                yield return ($@"HKU\{sid}\{key}", root, key);
            }
        }
    }

    private static AutorunEntry Enrich(AutorunEntry e)
    {
        if (e.Image is null || e.Category is AutorunCategory.BrowserExtension or AutorunCategory.OfficeAddin)
        {
            return e;
        }
        var sig = SignatureVerifier.Verify(e.Image);
        string? hash = null;
        if (sig.Status is not SignatureStatus.MicrosoftSigned and not SignatureStatus.NotFound)
        {
            try
            {
                hash = SignatureVerifier.Sha256(e.Image);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Locked or denied: the hash stays empty and the evidence says so.
            }
        }
        return e with { Signature = sig, Sha256 = hash, ImageUserWritable = sig.Status != SignatureStatus.NotFound && IsUserWritable(e.Image) };
    }

    /// <summary>True when BUILTIN\Users, Authenticated Users, Everyone or INTERACTIVE may write the file or replace it in its folder.</summary>
    public static bool IsUserWritable(string path)
    {
        var broad = new[]
        {
            new SecurityIdentifier(WellKnownSidType.BuiltinUsersSid, null),
            new SecurityIdentifier(WellKnownSidType.AuthenticatedUserSid, null),
            new SecurityIdentifier(WellKnownSidType.WorldSid, null),
            new SecurityIdentifier(WellKnownSidType.InteractiveSid, null),
        };
        bool Writable(FileSystemSecurity acl, FileSystemRights rights)
        {
            foreach (FileSystemAccessRule rule in acl.GetAccessRules(true, true, typeof(SecurityIdentifier)))
            {
                if (rule.AccessControlType == AccessControlType.Allow && broad.Contains(rule.IdentityReference) && (rule.FileSystemRights & rights) != 0)
                {
                    return true;
                }
            }
            return false;
        }
        try
        {
            var file = new FileInfo(path);
            if (Writable(file.GetAccessControl(), FileSystemRights.WriteData | FileSystemRights.ChangePermissions | FileSystemRights.TakeOwnership))
            {
                return true;
            }
            return file.Directory is { } dir && Writable(dir.GetAccessControl(), FileSystemRights.CreateFiles | FileSystemRights.ChangePermissions);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidOperationException)
        {
            return false;
        }
    }

    private static RegistryData? ValueOf(RegistryKey key, string name) =>
        key.GetValue(name, null, RegistryValueOptions.DoNotExpandEnvironmentNames) is { } v
            ? WindowsRegistryAccess.Encode(key.GetValueKind(name), v)
            : null;

    // ---------- locations ----------

    private static void ReadRunKeys(List<AutorunEntry> entries)
    {
        foreach (var runKey in RunKeys)
        {
            foreach (var (location, root, key) in HklmAndUsers(runKey))
            {
                using var k = root.OpenSubKey(key);
                if (k is null)
                {
                    continue;
                }
                foreach (var name in k.GetValueNames().Where(n => n.Length > 0))
                {
                    var command = k.GetValue(name)?.ToString() ?? "";
                    entries.Add(new AutorunEntry
                    {
                        Category = AutorunCategory.RunKey, Location = location, Name = name, Command = command,
                        Image = Resolve(command), Value = ValueOf(k, name),
                    });
                }
            }
        }
    }

    private static void ReadStartupFolders(List<AutorunEntry> entries)
    {
        foreach (var folder in new[] { Environment.GetFolderPath(Environment.SpecialFolder.CommonStartup), Environment.GetFolderPath(Environment.SpecialFolder.Startup) })
        {
            if (folder.Length == 0 || !Directory.Exists(folder))
            {
                continue;
            }
            foreach (var file in Directory.EnumerateFiles(folder).Where(f => !Path.GetFileName(f).Equals("desktop.ini", StringComparison.OrdinalIgnoreCase)))
            {
                var target = file.EndsWith(".lnk", StringComparison.OrdinalIgnoreCase) ? ShellLink.Target(file) : file;
                entries.Add(new AutorunEntry
                {
                    Category = AutorunCategory.StartupFolder, Location = file, Name = Path.GetFileNameWithoutExtension(file),
                    Command = target ?? file, Image = target ?? file,
                });
            }
        }
    }

    private static void ReadServices(List<AutorunEntry> entries)
    {
        using var services = Lm.OpenSubKey(@"SYSTEM\CurrentControlSet\Services");
        if (services is null)
        {
            return;
        }
        foreach (var name in services.GetSubKeyNames())
        {
            using var s = services.OpenSubKey(name);
            if (s?.GetValue("Start") is not int start || start > 2 || s.GetValue("ImagePath") is not string imagePath)
            {
                continue;
            }
            var type = s.GetValue("Type") is int t ? t : 0;
            var driver = (type & 0x3) != 0; // SERVICE_KERNEL_DRIVER | SERVICE_FILE_SYSTEM_DRIVER
            var image = Resolve(imagePath);
            using (var p = s.OpenSubKey("Parameters"))
            {
                if (p?.GetValue("ServiceDll") is string dll)
                {
                    image = CommandLines.Expand(dll, Env);
                }
            }
            entries.Add(new AutorunEntry
            {
                Category = driver ? AutorunCategory.Driver : AutorunCategory.Service,
                Location = $@"HKLM\SYSTEM\CurrentControlSet\Services\{name}", Name = name, Command = imagePath, Image = image,
                Detail = start switch { 0 => "Boot", 1 => "System", _ => s.GetValue("DelayedAutostart") is int d && d != 0 ? "Automatic" : "Automatic" },
            });
        }
    }

    private static void ReadTasks(List<AutorunEntry> entries)
    {
        var type = Type.GetTypeFromProgID("Schedule.Service") ?? throw new IOException("Task Scheduler unavailable");
        dynamic service = Activator.CreateInstance(type)!;
        service.Connect();
        void Walk(dynamic folder, int depth)
        {
            foreach (dynamic task in folder.GetTasks(1 /* TASK_ENUM_HIDDEN */))
            {
                string path = task.Path;
                bool enabled = task.Enabled;
                bool hidden = task.Definition.Settings.Hidden;
                foreach (dynamic action in task.Definition.Actions)
                {
                    int actionType = action.Type;
                    if (actionType == 0)
                    {
                        string exe = action.Path ?? "";
                        string args = action.Arguments ?? "";
                        var command = (exe.Contains(' ') && !exe.StartsWith('"') ? $"\"{exe}\"" : exe) + (args.Length > 0 ? " " + args : "");
                        entries.Add(new AutorunEntry
                        {
                            Category = AutorunCategory.ScheduledTask, Location = path, Name = path, Command = command,
                            Image = Resolve(command), Enabled = enabled, Detail = hidden ? "hidden" : null,
                        });
                    }
                    else if (actionType == 5)
                    {
                        string clsid = action.ClassId ?? "";
                        entries.Add(new AutorunEntry
                        {
                            Category = AutorunCategory.ScheduledTask, Location = path, Name = path, Command = "COM " + clsid,
                            Image = ComServer(clsid), Enabled = enabled, Detail = hidden ? "hidden" : null,
                        });
                    }
                }
            }
            if (depth < 12)
            {
                foreach (dynamic sub in folder.GetFolders(0))
                {
                    Walk(sub, depth + 1);
                }
            }
        }
        Walk(service.GetFolder("\\"), 0);
    }

    private static string? ComServer(string clsid)
    {
        using var k = Lm.OpenSubKey($@"SOFTWARE\Classes\CLSID\{clsid}\InprocServer32") ?? Lm.OpenSubKey($@"SOFTWARE\Classes\CLSID\{clsid}\LocalServer32");
        return k?.GetValue(null) is string s ? Resolve(s) : null;
    }

    private static void ReadWmi(List<AutorunEntry> entries)
    {
        var bindings = Wmi.Query(@"root\subscription", "SELECT Consumer, Filter FROM __FilterToConsumerBinding")
            .Select(r => r.Str("Consumer") ?? "").ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var r in Wmi.TryQuery(@"root\subscription", "SELECT Name, CommandLineTemplate, ExecutablePath FROM CommandLineEventConsumer") ?? [])
        {
            var name = r.Str("Name") ?? "?";
            var command = r.Str("CommandLineTemplate") ?? r.Str("ExecutablePath") ?? "";
            entries.Add(new AutorunEntry
            {
                Category = AutorunCategory.WmiSubscription, Location = @"root\subscription CommandLineEventConsumer", Name = name, Command = command,
                Image = Resolve(command), Detail = bindings.Any(b => b.Contains(name, StringComparison.OrdinalIgnoreCase)) ? "bound" : "unbound",
            });
        }
        foreach (var r in Wmi.TryQuery(@"root\subscription", "SELECT Name, ScriptText, ScriptFileName, ScriptingEngine FROM ActiveScriptEventConsumer") ?? [])
        {
            entries.Add(new AutorunEntry
            {
                Category = AutorunCategory.WmiSubscription, Location = @"root\subscription ActiveScriptEventConsumer", Name = r.Str("Name") ?? "?",
                Command = $"{r.Str("ScriptingEngine")} {r.Str("ScriptFileName")}".Trim(), ScriptText = r.Str("ScriptText"),
            });
        }
    }

    private static void ReadWinlogon(List<AutorunEntry> entries)
    {
        foreach (var (location, root, key) in HklmAndUsers(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"))
        {
            using var k = root.OpenSubKey(key);
            if (k is null)
            {
                continue;
            }
            foreach (var (name, expected) in new[] { ("Shell", "explorer.exe"), ("Userinit", @"C:\Windows\system32\userinit.exe,") })
            {
                if (k.GetValue(name) is string v && v.Length > 0 && !v.Trim().Equals(expected, StringComparison.OrdinalIgnoreCase) &&
                    !(name == "Userinit" && v.Trim().TrimEnd(',').Equals(@"C:\Windows\system32\userinit.exe", StringComparison.OrdinalIgnoreCase)))
                {
                    entries.Add(new AutorunEntry { Category = AutorunCategory.Winlogon, Location = location, Name = name, Command = v, Image = Resolve(v.Split(',')[0]), Value = ValueOf(k, name) });
                }
            }
            using var notify = k.OpenSubKey("Notify");
            foreach (var n in notify?.GetSubKeyNames() ?? [])
            {
                using var nk = notify!.OpenSubKey(n);
                if (nk?.GetValue("DLLName") is string dll)
                {
                    entries.Add(new AutorunEntry { Category = AutorunCategory.Winlogon, Location = location + @"\Notify", Name = n, Command = dll, Image = Resolve(dll) });
                }
            }
        }
    }

    private static void ReadAppInit(List<AutorunEntry> entries)
    {
        foreach (var key in new[] { @"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows", @"SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows" })
        {
            using var k = Lm.OpenSubKey(key);
            if (k?.GetValue("AppInit_DLLs") is string dlls && dlls.Trim().Length > 0 && k.GetValue("LoadAppInit_DLLs") is int load && load != 0)
            {
                foreach (var dll in dlls.Split([',', ' '], StringSplitOptions.RemoveEmptyEntries))
                {
                    entries.Add(new AutorunEntry { Category = AutorunCategory.AppInit, Location = @"HKLM\" + key, Name = "AppInit_DLLs", Command = dll, Image = Resolve(dll) });
                }
            }
        }
    }

    private static void ReadIfeo(List<AutorunEntry> entries)
    {
        foreach (var key in new[] { @"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options", @"SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Image File Execution Options" })
        {
            using var k = Lm.OpenSubKey(key);
            foreach (var exe in k?.GetSubKeyNames() ?? [])
            {
                using var sub = k!.OpenSubKey(exe);
                if (sub?.GetValue("Debugger") is string debugger && debugger.Trim().Length > 0)
                {
                    var accessibility = AccessibilityBinaries.Contains(exe, StringComparer.OrdinalIgnoreCase);
                    entries.Add(new AutorunEntry
                    {
                        Category = accessibility ? AutorunCategory.Accessibility : AutorunCategory.ImageFileExecution,
                        Location = $@"HKLM\{key}\{exe}", Name = exe, Command = debugger, Image = Resolve(debugger), Detail = "debugger",
                    });
                }
            }
        }
        using var spe = Lm.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion\SilentProcessExit");
        foreach (var exe in spe?.GetSubKeyNames() ?? [])
        {
            using var sub = spe!.OpenSubKey(exe);
            if (sub?.GetValue("MonitorProcess") is string monitor && monitor.Length > 0)
            {
                entries.Add(new AutorunEntry
                {
                    Category = AutorunCategory.ImageFileExecution, Location = $@"HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SilentProcessExit\{exe}",
                    Name = exe, Command = monitor, Image = Resolve(monitor), Detail = "silentProcessExit",
                });
            }
        }
    }

    /// <summary>The accessibility tools reachable from the sign-in screen; a replaced binary is a classic backdoor.</summary>
    private static void ReadAccessibility(List<AutorunEntry> entries)
    {
        var system32 = Environment.GetFolderPath(Environment.SpecialFolder.System);
        foreach (var exe in AccessibilityBinaries)
        {
            var path = Path.Combine(system32, exe);
            if (File.Exists(path))
            {
                entries.Add(new AutorunEntry { Category = AutorunCategory.Accessibility, Location = path, Name = exe, Command = "", Image = path });
            }
        }
    }

    private static void ReadBootExecute(List<AutorunEntry> entries)
    {
        using var k = Lm.OpenSubKey(@"SYSTEM\CurrentControlSet\Control\Session Manager");
        foreach (var v in k?.GetValue("BootExecute") as string[] ?? [])
        {
            if (v.Trim().Length > 0)
            {
                entries.Add(new AutorunEntry { Category = AutorunCategory.BootExecute, Location = @"HKLM\SYSTEM\CurrentControlSet\Control\Session Manager", Name = "BootExecute", Command = v });
            }
        }
    }

    private static void ReadLsa(List<AutorunEntry> entries)
    {
        using var k = Lm.OpenSubKey(@"SYSTEM\CurrentControlSet\Control\Lsa");
        foreach (var value in new[] { "Security Packages", "Authentication Packages", "Notification Packages" })
        {
            foreach (var pkg in k?.GetValue(value) as string[] ?? [])
            {
                if (pkg.Trim().Length == 0)
                {
                    continue;
                }
                var dll = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), pkg.Trim('"') + ".dll");
                entries.Add(new AutorunEntry { Category = AutorunCategory.Lsa, Location = @"HKLM\SYSTEM\CurrentControlSet\Control\Lsa", Name = value, Command = pkg, Image = dll });
            }
        }
    }

    private static void ReadPrintMonitors(List<AutorunEntry> entries)
    {
        using var k = Lm.OpenSubKey(@"SYSTEM\CurrentControlSet\Control\Print\Monitors");
        foreach (var m in k?.GetSubKeyNames() ?? [])
        {
            using var sub = k!.OpenSubKey(m);
            if (sub?.GetValue("Driver") is string dll)
            {
                entries.Add(new AutorunEntry
                {
                    Category = AutorunCategory.PrintMonitor, Location = $@"HKLM\SYSTEM\CurrentControlSet\Control\Print\Monitors\{m}", Name = m, Command = dll,
                    Image = dll.Contains('\\') ? dll : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), dll),
                });
            }
        }
    }

    /// <summary>Winsock catalog entries: PackedCatalogItem starts with the provider DLL path as a NUL-terminated ANSI string. VERIFY.</summary>
    private static void ReadWinsock(List<AutorunEntry> entries)
    {
        foreach (var catalog in new[] { "Protocol_Catalog9", "NameSpace_Catalog5" })
        {
            using var k = Lm.OpenSubKey($@"SYSTEM\CurrentControlSet\Services\WinSock2\Parameters\{catalog}\Catalog_Entries64")
                          ?? Lm.OpenSubKey($@"SYSTEM\CurrentControlSet\Services\WinSock2\Parameters\{catalog}\Catalog_Entries");
            foreach (var n in k?.GetSubKeyNames() ?? [])
            {
                using var sub = k!.OpenSubKey(n);
                string? dll = sub?.GetValue("PackedCatalogItem") is byte[] packed
                    ? Encoding.ASCII.GetString(packed, 0, Math.Max(0, Array.IndexOf(packed, (byte)0) is var z and >= 0 ? z : Math.Min(packed.Length, 260)))
                    : sub?.GetValue("LibraryPath") as string;
                if (!string.IsNullOrWhiteSpace(dll))
                {
                    entries.Add(new AutorunEntry
                    {
                        Category = AutorunCategory.WinsockProvider, Location = $@"HKLM\...\WinSock2\Parameters\{catalog}\{n}", Name = n, Command = dll,
                        Image = CommandLines.Expand(dll, Env),
                    });
                }
            }
        }
    }

    /// <summary>Per-user COM registrations that override a machine-wide CLSID: a common user-level hijack.</summary>
    private static void ReadComHijacks(List<AutorunEntry> entries)
    {
        foreach (var sid in UserSids())
        {
            using var users = RegistryKey.OpenBaseKey(RegistryHive.Users, RegistryView.Registry64);
            using var clsids = users.OpenSubKey($@"{sid}\Software\Classes\CLSID");
            foreach (var clsid in clsids?.GetSubKeyNames() ?? [])
            {
                using var inproc = clsids!.OpenSubKey($@"{clsid}\InprocServer32");
                if (inproc?.GetValue(null) is not string dll || dll.Length == 0)
                {
                    continue;
                }
                using var machine = Lm.OpenSubKey($@"SOFTWARE\Classes\CLSID\{clsid}");
                if (machine is null)
                {
                    continue; // A per-user-only registration is a normal per-user install, not an override.
                }
                entries.Add(new AutorunEntry
                {
                    Category = AutorunCategory.ComHijack, Location = $@"HKU\{sid}\Software\Classes\CLSID\{clsid}\InprocServer32", Name = clsid,
                    Command = dll, Image = CommandLines.Expand(dll, Env),
                });
            }
        }
    }

    private static void ReadOffice(List<AutorunEntry> entries)
    {
        foreach (var app in new[] { "Word", "Excel", "Outlook", "PowerPoint" })
        {
            foreach (var (location, root, key) in HklmAndUsers($@"SOFTWARE\Microsoft\Office\{app}\Addins"))
            {
                using var k = root.OpenSubKey(key);
                foreach (var addin in k?.GetSubKeyNames() ?? [])
                {
                    using var a = k!.OpenSubKey(addin);
                    var load = a?.GetValue("LoadBehavior") is int lb ? lb : 0;
                    entries.Add(new AutorunEntry
                    {
                        Category = AutorunCategory.OfficeAddin, Location = $@"{location}\{addin}", Name = $"{app}: {a?.GetValue("FriendlyName") ?? addin}",
                        Command = addin, Enabled = (load & 1) != 0,
                    });
                }
            }
        }
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        foreach (var folder in new[] { Path.Combine(appData, "Microsoft", "Word", "STARTUP"), Path.Combine(appData, "Microsoft", "Excel", "XLSTART") })
        {
            if (Directory.Exists(folder))
            {
                foreach (var f in Directory.EnumerateFiles(folder))
                {
                    entries.Add(new AutorunEntry { Category = AutorunCategory.OfficeAddin, Location = f, Name = Path.GetFileName(f), Command = f, Image = f });
                }
            }
        }
    }

    private static void ReadBrowsers(List<AutorunEntry> entries)
    {
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        foreach (var (browser, root) in new[] { ("Chrome", Path.Combine(local, "Google", "Chrome", "User Data")), ("Edge", Path.Combine(local, "Microsoft", "Edge", "User Data")) })
        {
            if (!Directory.Exists(root))
            {
                continue;
            }
            foreach (var profile in Directory.EnumerateDirectories(root).Where(d => Directory.Exists(Path.Combine(d, "Extensions"))))
            {
                foreach (var ext in Directory.EnumerateDirectories(Path.Combine(profile, "Extensions")))
                {
                    var manifest = Directory.EnumerateDirectories(ext).Select(v => Path.Combine(v, "manifest.json")).FirstOrDefault(File.Exists);
                    var name = Path.GetFileName(ext);
                    if (manifest is not null)
                    {
                        try
                        {
                            using var doc = JsonDocument.Parse(File.ReadAllText(manifest));
                            if (doc.RootElement.TryGetProperty("name", out var n) && n.GetString() is { } s && !s.StartsWith("__MSG_", StringComparison.Ordinal))
                            {
                                name = s;
                            }
                        }
                        catch (JsonException)
                        {
                        }
                    }
                    entries.Add(new AutorunEntry
                    {
                        Category = AutorunCategory.BrowserExtension, Location = ext, Name = $"{browser} ({Path.GetFileName(profile)}): {name}",
                        Command = Path.GetFileName(ext),
                    });
                }
            }
        }
        foreach (var (browser, key) in new[] { ("Chrome", @"SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist"), ("Edge", @"SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallForcelist") })
        {
            foreach (var (location, root, k) in HklmAndUsers(key))
            {
                using var forced = root.OpenSubKey(k);
                foreach (var v in forced?.GetValueNames() ?? [])
                {
                    entries.Add(new AutorunEntry
                    {
                        Category = AutorunCategory.BrowserExtension, Location = location, Name = $"{browser} (policy): {forced!.GetValue(v)}",
                        Command = forced.GetValue(v)?.ToString() ?? "", Detail = "policy",
                    });
                }
            }
        }
        var firefox = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Mozilla", "Firefox", "Profiles");
        if (Directory.Exists(firefox))
        {
            foreach (var json in Directory.EnumerateDirectories(firefox).Select(p => Path.Combine(p, "extensions.json")).Where(File.Exists))
            {
                try
                {
                    using var doc = JsonDocument.Parse(File.ReadAllText(json));
                    foreach (var addon in doc.RootElement.GetProperty("addons").EnumerateArray())
                    {
                        if (addon.TryGetProperty("location", out var loc) && loc.GetString() is "app-builtin" or "app-system-defaults")
                        {
                            continue;
                        }
                        var name = addon.TryGetProperty("defaultLocale", out var dl) && dl.TryGetProperty("name", out var nm) ? nm.GetString() : null;
                        entries.Add(new AutorunEntry
                        {
                            Category = AutorunCategory.BrowserExtension, Location = json, Name = $"Firefox: {name ?? addon.GetProperty("id").GetString()}",
                            Command = addon.GetProperty("id").GetString() ?? "", Enabled = addon.TryGetProperty("active", out var a) && a.GetBoolean(),
                        });
                    }
                }
                catch (Exception ex) when (ex is JsonException or KeyNotFoundException or InvalidOperationException)
                {
                }
            }
        }
    }

    private static void ReadPowerShellProfiles(List<AutorunEntry> entries)
    {
        var docs = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
        var system = Environment.GetFolderPath(Environment.SpecialFolder.System);
        var candidates = new[]
        {
            Path.Combine(docs, "WindowsPowerShell", "profile.ps1"),
            Path.Combine(docs, "WindowsPowerShell", "Microsoft.PowerShell_profile.ps1"),
            Path.Combine(docs, "PowerShell", "profile.ps1"),
            Path.Combine(docs, "PowerShell", "Microsoft.PowerShell_profile.ps1"),
            Path.Combine(system, "WindowsPowerShell", "v1.0", "profile.ps1"),
            Path.Combine(system, "WindowsPowerShell", "v1.0", "Microsoft.PowerShell_profile.ps1"),
        };
        foreach (var path in candidates.Where(File.Exists))
        {
            string? text = null;
            try
            {
                text = File.ReadAllText(path);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
            }
            entries.Add(new AutorunEntry { Category = AutorunCategory.PowerShellProfile, Location = path, Name = Path.GetFileName(path), Command = path, ScriptText = text });
        }
    }

    private static void ReadScreenSaver(List<AutorunEntry> entries)
    {
        foreach (var sid in UserSids())
        {
            using var users = RegistryKey.OpenBaseKey(RegistryHive.Users, RegistryView.Registry64);
            using var k = users.OpenSubKey($@"{sid}\Control Panel\Desktop");
            if (k?.GetValue("SCRNSAVE.EXE") is string saver && saver.Length > 0)
            {
                entries.Add(new AutorunEntry
                {
                    Category = AutorunCategory.ScreenSaver, Location = $@"HKU\{sid}\Control Panel\Desktop", Name = "SCRNSAVE.EXE", Command = saver,
                    Image = Resolve(saver), Value = ValueOf(k, "SCRNSAVE.EXE"),
                });
            }
        }
    }
}

/// <summary>Resolves a .lnk target through IShellLinkW (no scripting host).</summary>
[SupportedOSPlatform("windows")]
internal static class ShellLink
{
    [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
    private class CShellLink;

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("000214F9-0000-0000-C000-000000000046")]
    private interface IShellLinkW
    {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszFile, int cch, IntPtr pfd, uint fFlags);
        void GetIDList(out IntPtr ppidl);
        void SetIDList(IntPtr pidl);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszName, int cch);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string pszName);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszDir, int cch);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string pszDir);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszArgs, int cch);
    }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("0000010b-0000-0000-C000-000000000046")]
    private interface IPersistFile
    {
        void GetClassID(out Guid pClassID);
        [PreserveSig] int IsDirty();
        void Load([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, uint dwMode);
    }

    public static string? Target(string lnk)
    {
        try
        {
            var link = (IShellLinkW)new CShellLink();
            ((IPersistFile)link).Load(lnk, 0);
            var sb = new StringBuilder(1024);
            link.GetPath(sb, sb.Capacity, IntPtr.Zero, 0x4 /* SLGP_RAWPATH */);
            var args = new StringBuilder(2048);
            link.GetArguments(args, args.Capacity);
            var target = Environment.ExpandEnvironmentVariables(sb.ToString());
            return target.Length == 0 ? null : target;
        }
        catch (COMException)
        {
            return null;
        }
    }
}
