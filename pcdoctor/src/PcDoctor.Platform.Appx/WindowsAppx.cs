using Windows.Management.Deployment;
using PcDoctor.Core.Journal;
using PcDoctor.Tweaks;

namespace PcDoctor.Platform.Appx;

/// <summary>
/// Exact package name only. A prefix match would also hit other apps ("Microsoft.Copilot" must never match
/// "Microsoft.CopilotSomethingElse"), and removing the wrong app cannot be undone by PC Doctor.
/// </summary>
internal static class AppxMatch
{
    public static bool Is(Windows.ApplicationModel.PackageId id, string name) => string.Equals(id.Name, name, StringComparison.OrdinalIgnoreCase);
}

/// <summary>Is a package present for this user (no admin) or, from the Broker, for any user or provisioned?</summary>
public sealed class WindowsAppxAccess(bool allUsers) : IAppxAccess
{
    public bool IsPresent(string packageFamilyPrefix)
    {
        var pm = new PackageManager();
        var installed = allUsers ? pm.FindPackages() : pm.FindPackagesForUser(string.Empty);
        if (installed.Any(p => AppxMatch.Is(p.Id, packageFamilyPrefix)))
        {
            return true;
        }
        if (!allUsers)
        {
            return false;
        }
        try
        {
            return pm.FindProvisionedPackages().Any(p => AppxMatch.Is(p.Id, packageFamilyPrefix));
        }
        catch (Exception ex) when (ex is NotImplementedException or System.Runtime.InteropServices.COMException or UnauthorizedAccessException)
        {
            return false;
        }
    }
}

/// <summary>
/// Removes an app for all users and deprovisions it so feature updates do not reinstall it. PC Doctor
/// cannot put an app back by itself: undo says how to reinstall it from the Store with its ID.
/// </summary>
public sealed class AppxApplier : IChangeApplier
{
    public bool CanHandle(JournalChange change) => change is AppxChange;

    public JournalChange? TryCapture(PlannedChange planned)
    {
        if (planned is not PlannedAppxRemove r)
        {
            return null;
        }
        var pm = new PackageManager();
        var pkg = pm.FindPackages().FirstOrDefault(p => AppxMatch.Is(p.Id, r.PackageFamilyPrefix));
        var provisioned = false;
        try
        {
            provisioned = pm.FindProvisionedPackages().Any(p => AppxMatch.Is(p.Id, r.PackageFamilyPrefix));
        }
        catch (Exception ex) when (ex is NotImplementedException or System.Runtime.InteropServices.COMException)
        {
        }
        return new AppxChange(pkg?.Id.FullName ?? r.PackageFamilyPrefix, provisioned, r.StoreId);
    }

    public void Apply(JournalChange change)
    {
        var c = (AppxChange)change;
        var pm = new PackageManager();
        foreach (var p in pm.FindPackages().Where(p => p.Id.FullName == c.PackageFullName || AppxMatch.Is(p.Id, Family(c))).ToList())
        {
            var result = pm.RemovePackageAsync(p.Id.FullName, RemovalOptions.RemoveForAllUsers).AsTask().GetAwaiter().GetResult();
            if (result.ExtendedErrorCode is not null)
            {
                throw new InvalidOperationException(result.ErrorText);
            }
        }
        if (c.WasProvisioned)
        {
            var familyName = pm.FindProvisionedPackages().FirstOrDefault(p => AppxMatch.Is(p.Id, Family(c)))?.Id.FamilyName;
            if (familyName is not null)
            {
                pm.DeprovisionPackageForAllUsersAsync(familyName).AsTask().GetAwaiter().GetResult();
            }
        }
    }

    public bool IsStillApplied(JournalChange change) => !new WindowsAppxAccess(true).IsPresent(Family((AppxChange)change));

    public void Revert(JournalChange change) =>
        throw new InvalidOperationException($"Reinstall from the Microsoft Store: winget install --id {((AppxChange)change).WingetOrStoreId} -s msstore");

    private static string Family(AppxChange c) => c.PackageFullName.Split('_')[0];
}
