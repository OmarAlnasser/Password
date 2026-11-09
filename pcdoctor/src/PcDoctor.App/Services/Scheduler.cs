using System.Runtime.InteropServices;
using System.IO;
using System.Security;

namespace PcDoctor.App.Services;

public enum ScheduleFrequency { Off, Daily, Weekly }

/// <summary>
/// A per-user scheduled Health Check through the Task Scheduler COM API (no schtasks.exe). It runs
/// read-only, on AC power, and only shows anything when there are new High or Critical findings.
/// </summary>
public static class Scheduler
{
    private const string Folder = @"\PC Doctor";
    private const string TaskName = "Scheduled Health Check";

    public static void Apply(ScheduleFrequency frequency, TimeSpan at)
    {
        dynamic service = Connect();
        dynamic root = service.GetFolder("\\");
        dynamic folder;
        try
        {
            folder = service.GetFolder(Folder);
        }
        catch (Exception ex) when (ex is COMException or FileNotFoundException)
        {
            folder = root.CreateFolder(Folder, Type.Missing);
        }
        if (frequency == ScheduleFrequency.Off)
        {
            try
            {
                folder.DeleteTask(TaskName, 0);
            }
            catch (Exception ex) when (ex is COMException or FileNotFoundException)
            {
            }
            return;
        }
        var exe = Environment.ProcessPath ?? Path.Combine(AppContext.BaseDirectory, "PcDoctor.App.exe");
        // TASK_CREATE_OR_UPDATE = 6, TASK_LOGON_INTERACTIVE_TOKEN = 3: runs as this user, never elevated.
        folder.RegisterTask(TaskName, PcDoctor.Core.Reporting.ScheduleXml.Build(frequency == ScheduleFrequency.Daily, at, exe), 6, Type.Missing, Type.Missing, 3, Type.Missing);
    }

    private static dynamic Connect()
    {
        var type = Type.GetTypeFromProgID("Schedule.Service") ?? throw new InvalidOperationException("Task Scheduler is not available.");
        dynamic service = Activator.CreateInstance(type)!;
        service.Connect();
        return service;
    }
}
