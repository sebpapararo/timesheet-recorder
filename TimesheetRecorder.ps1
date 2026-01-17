[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$username = $env:USERNAME
)

# Validate username exists
$userProfile = "C:\Users\$username"
if (-Not (Test-Path -Path $userProfile -PathType Container)) {
    throw "User profile for '$username' not found at $userProfile"
}

$outputDirectory = "C:\Users\$username\Documents\Timesheet Recorder"
$now = Get-Date
$currentDay   = $now.ToString('dd')
$currentMonth = $now.ToString('MMMM')
$currentYear  = $now.ToString('yyyy')
$outputFileName = "$currentMonth $currentYear.txt"
$fullOutputPath = "$outputDirectory\$outputFileName"
$startOfDay = ($now).Date
$endOfDay = $startOfDay.AddDays(1)

# Build queries for logon, logoff, and shutdown events
$queries = @{
    Logon = @{ Filter = @{ LogName='Security'; ID=4624; StartTime=$startOfDay; EndTime=$endOfDay }; ErrorAction = 'Stop' }
    Logoff = @{ Filter = @{ LogName='Security'; ID=4634; StartTime=$startOfDay; EndTime=$endOfDay }; ErrorAction = 'SilentlyContinue' }
    Shutdown = @{ Filter = @{ LogName='System'; ID=42,1074,6008; StartTime=$startOfDay; EndTime=$endOfDay }; ErrorAction = 'SilentlyContinue' }
}

$results = @{}
# Process each query in parallel (requires PowerShell 7+)
$queries.GetEnumerator() | ForEach-Object -Parallel {
    $name = $_.Key
    $q = $_.Value
    $events = Get-WinEvent -FilterHashtable $q.Filter -ErrorAction $q.ErrorAction
    [PSCustomObject]@{ Name = $name; Events = $events }
} -ThrottleLimit 3 | ForEach-Object {
    $results[$_.Name] = $_.Events
}

# Access results and filter by username and logon type
# Logon types: 2=Interactive, 7=Unlock, 10=RemoteInteractive, 11=CachedInteractive
$logonEvents = $results['Logon'] | Where-Object {
    $_.Properties[5].Value -eq $username -and
    $_.Properties[8].Value -in @(2, 7, 10, 11)
}

$logoffEvents = $results['Logoff'] | Where-Object {
    $_.Properties[1].Value -eq $username
}

$shutdownEvents = $results['Shutdown']

# Validate that we have logon events
if (-not $logonEvents) {
    Write-Warning "No logon events found for user '$username' today"
    exit 1
}

# Create the output directory if it does not exist
if (-Not (Test-Path -Path $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

# Create the output file if it does not exist
if (-Not (Test-Path -Path $fullOutputPath -PathType Leaf)) {
    New-Item -ItemType File -Path $fullOutputPath | Out-Null
}

# Get the first logon and last logoff and calculate duration
$firstLogon = ($logonEvents | Sort-Object TimeCreated -Top 1).TimeCreated
$firstLogonTime = $firstLogon.ToString("HH:mm:ss")

# Handle missing logoff/shutdown events by using current time
$combinedEndEvents = @($logoffEvents) + @($shutdownEvents) | Where-Object { $_ }
if ($combinedEndEvents) {
    $lastLogoffOrShutdown = ($combinedEndEvents | Sort-Object TimeCreated -Descending -Top 1).TimeCreated
} else {
    Write-Verbose "No logoff or shutdown events found, using current time"
    $lastLogoffOrShutdown = $now
}
$lastLogoffTime = $lastLogoffOrShutdown.ToString("HH:mm:ss")

$duration = New-TimeSpan -Start $firstLogon -End $lastLogoffOrShutdown

# Validate duration is positive
if ($duration.TotalMinutes -lt 0) {
    Write-Warning "Calculated negative duration - check event ordering. Using absolute value."
    $duration = New-TimeSpan -Minutes ([Math]::Abs($duration.TotalMinutes))
}

# Construct line to be written
$newLine = "$currentDay $currentMonth`: $firstLogonTime -> $lastLogoffTime  ($($duration.Hours) hours $($duration.Minutes) minutes)"

# Get the current file contents and check if there is already an entry for today's date
$currentContents = @(Get-Content "$fullOutputPath")
$existingLineNumber = ($currentContents | Select-String -Pattern "^$currentDay $currentMonth`:").LineNumber

if ($existingLineNumber) {
   # Overwrite the existing line
    $currentContents[$existingLineNumber - 1] = $newLine
    Set-Content -Path $fullOutputPath -Value $currentContents
}
else {
    # Append the new line
    Add-Content -Path $fullOutputPath -Value $newLine
}
