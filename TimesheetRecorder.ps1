param (
    [Parameter(Mandatory=$true)]
    [string]$username
)

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

# Access results
$logonEvents    = $results['Logon']
$logoffEvents   = $results['Logoff']
$shutdownEvents   = $results['Shutdown']

# Create the output directory if it does not exist
if (-Not (Test-Path -Path $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory
}

# Create the output file if it does not exist
if (-Not (Test-Path -Path $fullOutputPath -PathType Leaf)) {
    New-Item -ItemType File -Path $fullOutputPath
}


# Get the first logon and last logoff and calculate duration
$firstLogon = ($logonEvents | Sort-Object TimeCreated -Top 1).TimeCreated
$firstLogonTime = $firstLogon.ToString("HH:mm:ss")
$lastLogoffOrShutdown = (@($logoffEvents) + @($shutdownEvents) | Sort-Object TimeCreated -Descending -Top 1).TimeCreated
$lastLogoffTime = $lastLogoffOrShutdown.ToString("HH:mm:ss")

$duration = New-TimeSpan -Start $firstLogon -End $lastLogoffOrShutdown

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
