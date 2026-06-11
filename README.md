# timesheet-recorder
Lightweight PowerShell tooling to record the first logon/unlock and last lock/logoff/shutdown for the current user each day.

### How it works
The installer registers three scheduled tasks for the current user, all driving the same recorder script:
- **Session Unlock** — runs at logon and on workstation unlock; starts today's entry if it's the first activity of the day.
- **Session Lock** — runs on workstation lock; stamps the end time and pauses the heartbeat.
- **Heartbeat** — runs every minute (default, configurable) while the session is unlocked; keeps the end time current so a shutdown, hibernate, or power loss costs at most one interval of accuracy.

One line per day is written to `Documents\Timesheet Recorder\<Month> <Year>.txt`:
```
11 June: 08:30:15 -> 17:02:11  (8 hours 31 minutes)
```
Time spent locked (e.g. overnight on an always-on machine) is not counted.

### Requirements
- Windows 10 1809+ or Windows 11 (the tasks use `conhost.exe --headless` to run without a console window)
- Windows PowerShell 5.1 (preinstalled on Windows) or PowerShell 7+
- No elevated privileges required

### Install
```powershell
.\Install-TimesheetRecorder.ps1                       # 1-minute heartbeat (default)
.\Install-TimesheetRecorder.ps1 -HeartbeatMinutes 5   # coarser, fewer wake-ups
```
The installer copies the recorder to `%LOCALAPPDATA%\TimesheetRecorder\bin` (outside OneDrive-synced `Documents`) and locks that folder's permissions so only you, SYSTEM, and Administrators can write to it. Re-run the installer after editing the script to deploy your changes.

### Uninstall
```powershell
.\Install-TimesheetRecorder.ps1 -Uninstall
```

### Example Output
![Example Output](assets/example-output.png)
