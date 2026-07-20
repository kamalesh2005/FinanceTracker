# Stop Finance Tracker Application (Windows)

$ErrorActionPreference = "SilentlyContinue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir
$PidFile = Join-Path $ScriptDir ".app.pids"

Write-Host "Stopping Finance Tracker application..."

function Stop-PortListeners([int]$Port) {
    $conns = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if (-not $conns) { return }
    $conns | Select-Object -ExpandProperty OwningProcess -Unique | ForEach-Object {
        Write-Host "  Stopping PID $_ on port $Port"
        Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue
    }
}

# Stop processes recorded by start.ps1
if (Test-Path $PidFile) {
    Get-Content $PidFile | ForEach-Object {
        $procId = $_.Trim()
        if ($procId -match '^\d+$' -and (Get-Process -Id $procId -ErrorAction SilentlyContinue)) {
            Write-Host "  Stopping recorded PID $procId"
            Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
        }
    }
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
}

# Free app ports
Stop-PortListeners 8080
Stop-PortListeners 3000

# Catch remaining project-related go/flutter processes
Get-CimInstance Win32_Process | Where-Object {
    $_.CommandLine -and (
        ($_.CommandLine -match 'financetracker\.exe') -or
        ($_.CommandLine -match 'flutter-runner\.ps1') -or
        ($_.CommandLine -match 'flutter_tools\.snapshot".*run') -or
        ($_.CommandLine -match 'flutter run' -and $_.CommandLine -match 'FinanceTracker') -or
        ($_.CommandLine -match 'go run' -and $_.CommandLine -match 'FinanceTracker\\backend')
    )
} | ForEach-Object {
    Write-Host "  Stopping $($_.Name) PID $($_.ProcessId)"
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}

Start-Sleep -Seconds 1
Write-Host "All processes stopped."
