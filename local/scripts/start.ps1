# Start Finance Tracker Application (Windows)
# Defaults to RELEASE mode. Use -Debug for hot-reloadable Flutter debug builds.
# -Release is accepted for backwards compatibility (release is already the default).
param(
    [switch]$Debug,
    [switch]$Release
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LocalDir = Split-Path -Parent $ScriptDir
$ProjectDir = Split-Path -Parent $LocalDir
$BackendDir = Join-Path $ProjectDir "backend"
$FrontendDir = Join-Path $ProjectDir "frontend"
$LogsDir = Join-Path $LocalDir "logs"
$BuildDir = Join-Path $LocalDir "build"
$EnvFile = Join-Path $LocalDir "env\backend.env"
$PidFile = Join-Path $LogsDir ".app.pids"
$BackendExe = Join-Path $BuildDir "financetracker.exe"
if ($Debug -and $Release) {
    Write-Error "Use either -Debug or -Release, not both."
}
$Release = -not $Debug

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
$ErrorActionPreference = "Stop"

New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null
New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null

# The backend reads .env from its own working directory, so the local environment
# file is copied in on every start. This keeps OCI values from ever reaching a
# local run, even if backend\.env was edited by hand.
if (Test-Path $EnvFile) {
    Copy-Item -Path $EnvFile -Destination (Join-Path $BackendDir ".env") -Force
    Write-Host "Using local environment from $EnvFile"
} else {
    Write-Warning "No local env file at $EnvFile. Copy local\env\backend.env.example and fill it in."
}

$backendOut = Join-Path $LogsDir "backend.out.log"
$backendErr = Join-Path $LogsDir "backend.err.log"
$frontendOut = Join-Path $LogsDir "frontend.out.log"
$frontendErr = Join-Path $LogsDir "frontend.err.log"

Write-Host "Building Go backend..."
Push-Location $BackendDir
try {
    if ($Release) {
        & go build -ldflags="-s -w" -o $BackendExe .
    } else {
        & go build -o $BackendExe .
    }
    if ($LASTEXITCODE -ne 0) { throw "Backend build failed" }
} finally {
    Pop-Location
}

if ($Release) {
    $env:GIN_MODE = "release"
    Write-Host "Starting Go backend on port 8080 (GIN_MODE=release)..."
} else {
    Remove-Item Env:GIN_MODE -ErrorAction SilentlyContinue
    Write-Host "Starting Go backend on port 8080..."
}
$backend = Start-Process -FilePath $BackendExe `
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

$modeLabel = if ($Release) { "release" } else { "debug" }
Write-Host "Starting Flutter frontend on Chrome (port 3000, $modeLabel)..."
# Runner keeps stdin open so .\local\scripts\hot-reload.ps1 can send 'r' / 'R' (debug only)
$frontendCmdFile = Join-Path $LogsDir "frontend.cmd"
$flutterPidFile = Join-Path $LogsDir "flutter.pid"
"" | Set-Content -Path $frontendOut -Encoding utf8
"" | Set-Content -Path $frontendErr -Encoding utf8
"" | Set-Content -Path $frontendCmdFile -Encoding ascii

$runner = Join-Path $ScriptDir "flutter-runner.ps1"
$runnerArgs = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $runner,
    "-FrontendDir", $FrontendDir,
    "-OutLog", $frontendOut,
    "-ErrLog", $frontendErr,
    "-CmdFile", $frontendCmdFile,
    "-FlutterPidFile", $flutterPidFile
)
if ($Release) { $runnerArgs += "-Release" }

$frontend = Start-Process -FilePath "powershell.exe" `
    -ArgumentList $runnerArgs `
    -PassThru `
    -WindowStyle Hidden

@($backend.Id, $frontend.Id) | Set-Content -Path $PidFile

Write-Host ""
Write-Host "=========================================="
Write-Host "Finance Tracker Application Started ($modeLabel)"
Write-Host "=========================================="
Write-Host "Backend:  http://localhost:8080"
Write-Host "Frontend: http://localhost:3000"
Write-Host "Mode:     $modeLabel"
Write-Host "Logs:     $LogsDir"
Write-Host "PIDs:     backend=$($backend.Id) frontend=$($frontend.Id)"
if ($Debug) {
    Write-Host "Reload:   .\local\scripts\hot-reload.ps1"
    Write-Host "Restart:  .\local\scripts\hot-reload.ps1 -Restart"
} else {
    Write-Host "Restart:  .\local\scripts\stop.ps1 -Restart"
}
Write-Host "Stop with: .\local\scripts\stop.ps1"
Write-Host "=========================================="
