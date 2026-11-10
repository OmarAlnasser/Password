using System.Security;

namespace PcDoctor.Core.Reporting;

/// <summary>Task Scheduler XML for the scheduled Health Check: this user, least privilege, AC power only, one fixed argument.</summary>
public static class ScheduleXml
{
    /// <summary>Runs two minutes after this user signs in, so it does not compete with Windows starting up.</summary>
    public static string BuildAtSignIn(string exePath) => Build(
        "<LogonTrigger><Enabled>true</Enabled><Delay>PT2M</Delay></LogonTrigger>", exePath);

    public static string Build(bool daily, TimeSpan at, string exePath)
    {
        var start = DateTime.Today.Add(at).ToString("yyyy-MM-ddTHH:mm:ss", System.Globalization.CultureInfo.InvariantCulture);
        var schedule = daily
            ? "<ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay>"
            : "<ScheduleByWeek><WeeksInterval>1</WeeksInterval><DaysOfWeek><Sunday /></DaysOfWeek></ScheduleByWeek>";
        return Build($"<CalendarTrigger><StartBoundary>{start}</StartBoundary><Enabled>true</Enabled>{schedule}</CalendarTrigger>", exePath);
    }

    private static string Build(string trigger, string exePath)
    {
        return $"""
            <?xml version="1.0" encoding="UTF-16"?>
            <Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
              <RegistrationInfo><Description>PC Doctor read-only Health Check. Notifies only about new important findings.</Description></RegistrationInfo>
              <Triggers>{trigger}</Triggers>
              <Principals><Principal id="Author"><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>
              <Settings>
                <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
                <DisallowStartIfOnBatteries>true</DisallowStartIfOnBatteries>
                <StopIfGoingOnBatteries>true</StopIfGoingOnBatteries>
                <StartWhenAvailable>true</StartWhenAvailable>
                <RunOnlyIfIdle>false</RunOnlyIfIdle>
                <ExecutionTimeLimit>PT1H</ExecutionTimeLimit>
                <Priority>7</Priority>
              </Settings>
              <Actions Context="Author"><Exec><Command>{SecurityElement.Escape(exePath)}</Command><Arguments>--scheduled-scan</Arguments></Exec></Actions>
            </Task>
            """;
    }
}
