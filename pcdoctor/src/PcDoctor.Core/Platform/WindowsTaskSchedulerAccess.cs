using System.Runtime.InteropServices;
using System.Runtime.Versioning;

namespace PcDoctor.Core.Platform;

/// <summary>Task Scheduler 2.0 through its COM API (Schedule.Service). No schtasks.exe and no PowerShell.</summary>
[SupportedOSPlatform("windows")]
public sealed class WindowsTaskSchedulerAccess : ITaskSchedulerAccess
{
    public bool? IsEnabled(string taskPath)
    {
        dynamic? task = Find(taskPath);
        return task is null ? null : (bool)task.Enabled;
    }

    public void SetEnabled(string taskPath, bool enabled)
    {
        dynamic task = Find(taskPath) ?? throw new InvalidOperationException($"Task {taskPath} does not exist.");
        task.Enabled = enabled;
    }

    private static dynamic? Find(string taskPath)
    {
        var type = Type.GetTypeFromProgID("Schedule.Service") ?? throw new InvalidOperationException("Task Scheduler is not available.");
        dynamic service = Activator.CreateInstance(type)!;
        service.Connect();
        var slash = taskPath.LastIndexOf('\\');
        var folderPath = slash <= 0 ? "\\" : taskPath[..slash];
        try
        {
            dynamic folder = service.GetFolder(folderPath);
            return folder.GetTask(taskPath[(slash + 1)..]);
        }
        catch (COMException)
        {
            return null;
        }
        catch (FileNotFoundException)
        {
            return null;
        }
    }
}
