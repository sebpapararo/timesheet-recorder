<#
.SYNOPSIS
    Installs or uninstalls the TimesheetRecorder scheduled task.

.DESCRIPTION
    Creates a Windows scheduled task that runs TimesheetRecorder.ps1 at user logon
    and before system shutdown/logoff to capture daily work hours.

.PARAMETER Uninstall
    Removes the scheduled task instead of installing it.

.PARAMETER Username
    The username to track. Defaults to the current user.

.PARAMETER TaskName
    The name of the scheduled task. Defaults to "TimesheetRecorder".

.EXAMPLE
    .\InstallScheduledTask.ps1
    Installs the scheduled task for the current user.

.EXAMPLE
    .\InstallScheduledTask.ps1 -Uninstall
    Removes the scheduled task.

.EXAMPLE
    .\InstallScheduledTask.ps1 -Username "john.doe"
    Installs the scheduled task for a specific user.

.NOTES
    Requires elevated (Administrator) privileges.
#>

[CmdletBinding()]
param (
    [switch]$Uninstall,
    [string]$Username = $env:USERNAME,
    [string]$TaskName = "TimesheetRecorder"
)

# Check for administrator privileges
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "This script requires Administrator privileges. Please run PowerShell as Administrator."
}

# Get the path to the main script
$scriptPath = Join-Path -Path $PSScriptRoot -ChildPath "TimesheetRecorder.ps1"

if (-not (Test-Path -Path $scriptPath)) {
    throw "TimesheetRecorder.ps1 not found at $scriptPath"
}

if ($Uninstall) {
    # Remove the scheduled task
    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Scheduled task '$TaskName' has been removed." -ForegroundColor Green
    } else {
        Write-Warning "Scheduled task '$TaskName' does not exist."
    }
} else {
    # Check if task already exists
    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

    if ($existingTask) {
        Write-Warning "Scheduled task '$TaskName' already exists. Use -Uninstall to remove it first."
        exit 1
    }

    # Create the action to run the PowerShell script
    $action = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`" -username `"$Username`""

    # Create triggers:
    # 1. At user logon (to capture start time on next run)
    # 2. Daily at 11:55 PM (to capture end of day before midnight)
    # 3. On workstation lock (common end-of-day action)
    $triggerLogon = New-ScheduledTaskTrigger -AtLogOn -User $Username
    $triggerDaily = New-ScheduledTaskTrigger -Daily -At "11:55PM"

    # Task settings
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable:$false

    # Create the principal (run as the specified user)
    $principal = New-ScheduledTaskPrincipal -UserId $Username -LogonType Interactive -RunLevel Highest

    # Register the scheduled task
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggerLogon, $triggerDaily -Settings $settings -Principal $principal -Description "Records daily logon and logoff times for timesheet tracking."

    Write-Host "Scheduled task '$TaskName' has been created successfully." -ForegroundColor Green
    Write-Host ""
    Write-Host "The task will run:" -ForegroundColor Cyan
    Write-Host "  - At logon for user '$Username'" -ForegroundColor Cyan
    Write-Host "  - Daily at 11:55 PM" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Output will be saved to: C:\Users\$Username\Documents\Timesheet Recorder\" -ForegroundColor Cyan
}
