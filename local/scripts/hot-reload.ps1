# Hot-reload the running Flutter frontend (Windows)
# Requires the app to have been started with .\local\scripts\start.ps1 (command channel).
# Usage: .\local\scripts\hot-reload.ps1
#        .\local\scripts\hot-reload.ps1 -Restart

param(
    [switch]$Restart
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LocalDir = Split-Path -Parent $ScriptDir
$LogsDir = Join-Path $LocalDir "logs"
$CmdFile = Join-Path $LogsDir "frontend.cmd"
$OutLog = Join-Path $LogsDir "frontend.out.log"

$command = if ($Restart) { "R" } else { "r" }
$actionName = if ($Restart) { "Hot restart" } else { "Hot reload" }

function Test-FrontendRunning {
    return [bool](netstat -ano | Select-String ':3000\s+.*LISTENING')
}

function Test-CommandChannelReady {
    if (-not (Test-Path $CmdFile)) { return $false }
    if (-not (Test-FrontendRunning)) { return $false }
    $runners = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -and $_.CommandLine -match 'flutter-runner\.ps1'
    }
    return [bool]$runners
}

if (-not (Test-FrontendRunning)) {
    Write-Error "Frontend is not running on port 3000. Start it with .\local\scripts\start.ps1 first."
}

if (-not (Test-CommandChannelReady)) {
    Write-Error @"
Hot reload command channel is not available.

The current Flutter session was started without stdin control.
Restart once with:
  .\local\scripts\start.ps1

Then use:
  .\local\scripts\hot-reload.ps1
"@
}

Write-Host "$actionName..."

$beforeLen = if (Test-Path $OutLog) { (Get-Item $OutLog).Length } else { 0 }
Add-Content -Path $CmdFile -Value $command -Encoding ascii

$deadline = (Get-Date).AddSeconds(60)
$confirmed = $null
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 400
    if (-not (Test-Path $OutLog)) { continue }
    $fs = [System.IO.File]::Open($OutLog, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        if ($fs.Length -le $beforeLen) { continue }
        $fs.Seek($beforeLen, [System.IO.SeekOrigin]::Begin) | Out-Null
        $reader = New-Object System.IO.StreamReader($fs)
        $chunk = $reader.ReadToEnd()
        $reader.Dispose()
    } finally {
        $fs.Dispose()
    }
    if ($chunk -match 'Reloaded .+ libraries|Reloaded application|Restarted application') {
        $confirmed = ($chunk -split "`r?`n" | Where-Object {
            $_ -match 'Reloaded .+ libraries|Reloaded application|Restarted application'
        } | Select-Object -Last 1)
        break
    }
}

if ($confirmed) {
    Write-Host "Success: $confirmed"
    exit 0
}

Write-Host "Command '$command' sent to Flutter. Confirmation not seen in log within 60s;"
Write-Host "check $OutLog and the Chrome window."
exit 0
