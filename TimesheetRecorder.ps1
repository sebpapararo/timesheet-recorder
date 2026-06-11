param (
    [Parameter(Mandatory=$true)]
    [ValidateSet('Unlock','Lock','Heartbeat')]
    [string]$Action,

    [string]$OutputDirectory = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Timesheet Recorder')
)

# The lock flag gates the heartbeat so locked time is not counted as worked time
$stateDirectory = Join-Path $env:LOCALAPPDATA 'TimesheetRecorder'
$lockFlagPath = Join-Path $stateDirectory 'session.locked'
if (-not (Test-Path -Path $stateDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $stateDirectory | Out-Null
}

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
if (-not (Test-Path -Path $fullOutputPath -PathType Leaf)) {
    New-Item -ItemType File -Path $fullOutputPath | Out-Null
}

# Today's start time is recovered from the existing line, keeping the script stateless
$currentContents = @(Get-Content -Path $fullOutputPath)
$existingLine = $currentContents |
    Select-String -Pattern "^$currentDay ${currentMonth}: (\d{2}:\d{2}:\d{2})" |
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
    Set-Content -Path $fullOutputPath -Value $currentContents
}
else {
    # Append the new line
    Add-Content -Path $fullOutputPath -Value $newLine
}
