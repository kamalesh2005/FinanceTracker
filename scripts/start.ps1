# Start Finance Tracker Application (Windows)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir
$BackendDir = Join-Path $ProjectDir "backend"
$FrontendDir = Join-Path $ProjectDir "frontend"
$PidFile = Join-Path $ScriptDir ".app.pids"
$LogsDir = Join-Path $ScriptDir "logs"

# Ensure tools are on PATH
$goBin = "C:\Program Files\Go\bin"
$flutterBin = "C:\src\flutter\bin"
$env:Path = "$flutterBin;$goBin;" +
    [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
    [System.Environment]::GetEnvironmentVariable("Path", "User")

if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
    Write-Error "Go not found. Install Go or add it to PATH."
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Error "Flutter not found. Install Flutter or add it to PATH (expected at C:\src\flutter\bin)."
}

# Stop any existing instance first
& (Join-Path $ScriptDir "stop.ps1")

New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null
$backendOut = Join-Path $LogsDir "backend.out.log"
$backendErr = Join-Path $LogsDir "backend.err.log"
$frontendOut = Join-Path $LogsDir "frontend.out.log"
$frontendErr = Join-Path $LogsDir "frontend.err.log"

Write-Host "Building Go backend..."
Push-Location $BackendDir
try {
    & go build -o financetracker.exe .
    if ($LASTEXITCODE -ne 0) { throw "Backend build failed" }
} finally {
    Pop-Location
}

Write-Host "Starting Go backend on port 8080..."
$backend = Start-Process -FilePath (Join-Path $BackendDir "financetracker.exe") `
    -WorkingDirectory $BackendDir `
    -RedirectStandardOutput $backendOut `
    -RedirectStandardError $backendErr `
    -PassThru `
    -WindowStyle Hidden

Write-Host "Waiting for backend..."
$ready = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 500
    $conn = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue
    if ($conn) { $ready = $true; break }
}
if (-not $ready) {
    Write-Error "Backend did not start on port 8080. See $backendErr"
}

Write-Host "Starting Flutter frontend on Chrome (port 3000)..."
# Runner keeps stdin open so .\scripts\hot-reload.ps1 can send 'r' / 'R'
$frontendCmdFile = Join-Path $LogsDir "frontend.cmd"
$flutterPidFile = Join-Path $LogsDir "flutter.pid"
"" | Set-Content -Path $frontendOut -Encoding utf8
"" | Set-Content -Path $frontendErr -Encoding utf8
"" | Set-Content -Path $frontendCmdFile -Encoding ascii

$runner = Join-Path $ScriptDir "flutter-runner.ps1"
$frontend = Start-Process -FilePath "powershell.exe" `
    -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $runner,
        "-FrontendDir", $FrontendDir,
        "-OutLog", $frontendOut,
        "-ErrLog", $frontendErr,
        "-CmdFile", $frontendCmdFile,
        "-FlutterPidFile", $flutterPidFile
    ) `
    -PassThru `
    -WindowStyle Hidden

@($backend.Id, $frontend.Id) | Set-Content -Path $PidFile

Write-Host ""
Write-Host "=========================================="
Write-Host "Finance Tracker Application Started"
Write-Host "=========================================="
Write-Host "Backend:  http://localhost:8080"
Write-Host "Frontend: http://localhost:3000"
Write-Host "Logs:     $LogsDir"
Write-Host "PIDs:     backend=$($backend.Id) frontend=$($frontend.Id)"
Write-Host "Reload:   .\scripts\hot-reload.ps1"
Write-Host "Restart:  .\scripts\hot-reload.ps1 -Restart"
Write-Host "Stop with: .\scripts\stop.ps1"
Write-Host "=========================================="
