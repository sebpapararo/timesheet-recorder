# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An event-driven timesheet recorder: scheduled tasks stamp the current user's first logon/unlock and last lock/logoff time for each day into a monthly text file. There is no build, lint, or test tooling — plain scripts.

## Files

- `TimesheetRecorder.ps1` — the recorder. Takes a mandatory `-Action` of `Unlock`, `Lock`, or `Heartbeat`, plus an optional `-OutputDirectory` (defaults to `Documents\Timesheet Recorder`; mainly useful for testing against a temp directory).
- `Install-TimesheetRecorder.ps1` — copies the recorder to `%LOCALAPPDATA%\TimesheetRecorder\bin` and registers/unregisters three scheduled tasks pointing there (`-Uninstall` removes tasks and the bin copy; `-HeartbeatMinutes` tunes the interval, default 1). Task actions run via `conhost.exe --headless powershell.exe ...` so no console window flashes on each run (Windows 10 1809+/11; full paths to `conhost.exe` and `powershell.exe` avoid user-writable PATH resolution). `Set-ExecutableDirAcl` hardens the bin dir (inheritance off; SYSTEM + Administrators FullControl, owning user Modify, no broad Users ACE) so no lower-privileged principal can tamper with the auto-run scripts.

## Architecture

The recorder is stateless apart from a lock-flag file at `%LOCALAPPDATA%\TimesheetRecorder\session.locked`:

1. **Every invocation stamps the timesheet**: if no line exists for today, start = end = now; otherwise the start time is parsed back out of the existing line and only the end time (and duration) is rewritten in place.
2. **Action semantics**: `Lock` creates the flag file then stamps; `Unlock` deletes it then stamps; `Heartbeat` exits without stamping if the flag exists. This gates the heartbeat so locked time (e.g. overnight on an always-on machine) is never counted.
3. **Scheduled tasks** (registered by the installer, run as the current user, Interactive logon type, no elevation):
   - *Session Unlock*: at-logon trigger + session-unlock trigger → `-Action Unlock`
   - *Session Lock*: session-lock trigger → `-Action Lock`
   - *Heartbeat*: once-trigger at midnight repeating every N minutes indefinitely → `-Action Heartbeat`

Design rationale: the heartbeat is insurance for endings that produce no event (hard power loss, shutdown killing the task), bounding the end-time error to one heartbeat interval. Lock/unlock triggers give exact boundaries on the common path and also handle hibernate-resume, where no fresh logon event ever occurs.

Output format (one line per day, in `<Month> <Year>.txt`): `DD Month: HH:mm:ss -> HH:mm:ss  (X hours Y minutes)`. The day-line regex and the start-time parsing in `TimesheetRecorder.ps1` both depend on this exact format — change them together.

## Implementation notes

- Lock/unlock session-state triggers cannot be created with `New-ScheduledTaskTrigger`; the installer builds them via `New-CimInstance` on `MSFT_TaskSessionStateChangeTrigger` (StateChange 7 = lock, 8 = unlock).
- `Set-ExecutableDirAcl` deliberately uses `icacls`, not `Set-Acl`. `Set-Acl` on a security-descriptor object tries to persist the SACL (audit) section, which requires `SeSecurityPrivilege` — a right a non-elevated user lacks — so it fails with "does not possess the 'SeSecurityPrivilege' privilege". `icacls` only ever touches the DACL. Do not switch this back to `Set-Acl`.
- Tasks must keep `-AllowStartIfOnBatteries` / `-DontStopIfGoingOnBatteries` or the heartbeat silently stops on laptops on battery.
- Month names come from the current culture (`'MMMM'`), so timesheet files are locale-dependent but internally consistent.
- Scripts target Windows PowerShell 5.1 (the task actions invoke `powershell.exe`) — avoid PowerShell 7-only syntax in `TimesheetRecorder.ps1`.

## Testing the recorder manually

```powershell
.\TimesheetRecorder.ps1 -Action Heartbeat -OutputDirectory "$env:TEMP\tsr-test"
```

Use a temp `-OutputDirectory` — the default writes to the user's real timesheet. Note the lock-flag file is always the real one in `%LOCALAPPDATA%`; clean it up after testing `Lock`.
