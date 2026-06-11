[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [ValidateSet('Unlock','Lock','Heartbeat')]
    [string]$Action,

    [string]$OutputDirectory = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Timesheet Recorder')
)

# Non-terminating cmdlet errors (e.g. New-Item, Set-Content) must become terminating
# so the try/catch below can log them; otherwise they'd be silently swallowed.
$ErrorActionPreference = 'Stop'

# The lock flag gates the heartbeat so locked time is not counted as worked time
$stateDirectory = Join-Path $env:LOCALAPPDATA 'TimesheetRecorder'
$lockFlagPath = Join-Path $stateDirectory 'session.locked'
$errorLogPath = Join-Path $stateDirectory 'error.log'
if (-not (Test-Path -Path $stateDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $stateDirectory | Out-Null
}

try {
    switch ($Action) {
        'Lock'      { New-Item -ItemType File -Path $lockFlagPath -Force | Out-Null }
        'Unlock'    { if (Test-Path -Path $lockFlagPath) { Remove-Item -Path $lockFlagPath -Force } }
        'Heartbeat' { if (Test-Path -Path $lockFlagPath) { return } }
    }

    $now = Get-Date
    $currentDay   = $now.ToString('dd')
    $currentMonth = $now.ToString('MMMM')
    $currentYear  = $now.ToString('yyyy')
    $fullOutputPath = Join-Path $OutputDirectory "$currentMonth $currentYear.txt"

    if (-not (Test-Path -Path $OutputDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
    }

    # Today's start time is recovered from the existing line, keeping the script stateless
    $currentContents = @()
    if (Test-Path -Path $fullOutputPath -PathType Leaf) {
        $currentContents = @(Get-Content -Path $fullOutputPath)
    }
    $existingLine = $currentContents |
        Select-String -Pattern "^$currentDay $([regex]::Escape($currentMonth)): (\d{2}:\d{2}:\d{2})" |
        Select-Object -First 1

    if ($existingLine) {
        # A corrupted/hand-edited start time (e.g. 25:99:99) must not crash every later stamp;
        # fall back to treating now as the start and rewriting the line.
        try {
            $startTimeOfDay = [DateTime]::ParseExact($existingLine.Matches[0].Groups[1].Value, 'HH:mm:ss', [CultureInfo]::InvariantCulture).TimeOfDay
            $start = $now.Date.Add($startTimeOfDay)
        }
        catch {
            $start = $now
        }
    }
    else {
        $start = $now
    }

    $duration = New-TimeSpan -Start $start -End $now
    $newLine = "$currentDay ${currentMonth}: $($start.ToString('HH:mm:ss')) -> $($now.ToString('HH:mm:ss'))  ($($duration.Hours) hours $($duration.Minutes) minutes)"

    if ($existingLine) {
        # Overwrite the existing line
        $currentContents[$existingLine.LineNumber - 1] = $newLine
    }
    else {
        # Append the new line
        $currentContents += $newLine
    }

    # Write via a temp file + rename so a kill mid-write can't corrupt the whole file
    $tempPath = "$fullOutputPath.tmp"
    Set-Content -Path $tempPath -Value $currentContents -Encoding UTF8
    Move-Item -Path $tempPath -Destination $fullOutputPath -Force
}
catch {
    $logEntry = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Action, $_.Exception.Message
    Add-Content -Path $errorLogPath -Value $logEntry -Encoding UTF8
}
