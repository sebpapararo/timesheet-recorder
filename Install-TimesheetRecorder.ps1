param (
    [int]$HeartbeatMinutes = 1,
    [switch]$Uninstall
)

$taskNames = @(
    'Timesheet Recorder - Session Unlock',
    'Timesheet Recorder - Session Lock',
    'Timesheet Recorder - Heartbeat'
)

# Scripts are executed from here, not from the (OneDrive-syncable, user-writable) source folder
$installRoot = Join-Path $env:LOCALAPPDATA 'TimesheetRecorder'
$binDir      = Join-Path $installRoot 'bin'

if ($Uninstall) {
    foreach ($name in $taskNames) {
        Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
    }
    if (Test-Path -Path $binDir) { Remove-Item -Path $binDir -Recurse -Force }
    Write-Host 'Timesheet Recorder scheduled tasks removed and installed scripts deleted.'
    return
}

$sourceRecorderPath = Join-Path $PSScriptRoot 'TimesheetRecorder.ps1'
if (-not (Test-Path -Path $sourceRecorderPath -PathType Leaf)) { throw "Required file not found: $sourceRecorderPath" }

# Full paths so neither binary is resolved via a user-writable PATH
$conhostPath    = Join-Path $env:SystemRoot 'System32\conhost.exe'
$powershellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

$currentUserSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
$userId = $currentUserSid.Translate([System.Security.Principal.NTAccount]).Value

function Set-ExecutableDirAcl ([string]$path) {
    # Lock the directory holding the auto-run scripts so no lower-privileged principal can
    # write to it: a writable script path that a scheduled task executes is the classic
    # privilege-escalation vector. Only the owning user (modify), SYSTEM and the local
    # Administrators group (full) get access.
    #
    # icacls is used rather than Set-Acl because it only ever touches the DACL. Set-Acl, given
    # a security-descriptor object, attempts to persist the SACL (audit) section too, which
    # requires SeSecurityPrivilege -- a right a non-elevated user does not hold -- and fails.
    #   /inheritance:r  removes inherited ACEs and does not copy them (so no broad "Users" grant)
    #   /grant:r        replaces any existing grant for each identity (idempotent on reinstall)
    #   (OI)(CI)        object-inherit + container-inherit, so files/subfolders inherit the ACE
    #   F / M           Full control / Modify; "*SID" applies the entry by well-known SID
    $output = & icacls $path /inheritance:r /grant:r `
        '*S-1-5-18:(OI)(CI)F' `
        '*S-1-5-32-544:(OI)(CI)F' `
        ("*{0}:(OI)(CI)M" -f $currentUserSid.Value) 2>&1
    if ($LASTEXITCODE -ne 0) { throw "icacls failed to harden ${path}: $output" }
}

New-Item -ItemType Directory -Path $binDir -Force | Out-Null
Copy-Item -Path $sourceRecorderPath -Destination $binDir -Force
$recorderPath = Join-Path $binDir 'TimesheetRecorder.ps1'
Set-ExecutableDirAcl $binDir

function New-RecorderAction ([string]$recorderAction) {
    # conhost --headless runs powershell with no console window, so nothing flashes on each run
    $argument = "--headless `"$powershellPath`" -NoProfile -NonInteractive -ExecutionPolicy Bypass " +
                "-File `"$recorderPath`" -Action $recorderAction"
    New-ScheduledTaskAction -Execute $conhostPath -Argument $argument
}

# New-ScheduledTaskTrigger cannot create lock/unlock triggers, so build them from the CIM class directly
$stateChangeClass = Get-CimClass -Namespace Root/Microsoft/Windows/TaskScheduler -ClassName MSFT_TaskSessionStateChangeTrigger
$unlockTrigger = New-CimInstance -CimClass $stateChangeClass -ClientOnly -Property @{ StateChange = 8; UserId = $userId; Enabled = $true }
$lockTrigger   = New-CimInstance -CimClass $stateChangeClass -ClientOnly -Property @{ StateChange = 7; UserId = $userId; Enabled = $true }
$logonTrigger  = New-ScheduledTaskTrigger -AtLogOn -User $userId

# Repeats indefinitely; only fires while the user is logged on (Interactive principal),
# and the recorder itself skips heartbeats while the session is locked
$heartbeatTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Minutes $HeartbeatMinutes)

$principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -StartWhenAvailable

$tasks = @(
    @{ Name = $taskNames[0]; Triggers = @($logonTrigger, $unlockTrigger); RecorderAction = 'Unlock' }
    @{ Name = $taskNames[1]; Triggers = @($lockTrigger);                  RecorderAction = 'Lock' }
    @{ Name = $taskNames[2]; Triggers = @($heartbeatTrigger);             RecorderAction = 'Heartbeat' }
)

foreach ($task in $tasks) {
    Register-ScheduledTask -TaskName $task.Name -Action (New-RecorderAction $task.RecorderAction) `
        -Trigger $task.Triggers -Principal $principal -Settings $settings -Force | Out-Null
    Write-Host "Registered scheduled task: $($task.Name)"
}

Write-Host "Scripts installed to $binDir (restricted ACL applied)."
Write-Host "Done. Entries will be written to $(Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Timesheet Recorder')."
