# Rebuild Go backend (linux/amd64) and redeploy to OCI.
# Example:
#   .\oci\scripts\deploy-backend.ps1
#   .\oci\scripts\deploy-backend.ps1 -HostIp 80.225.255.191 -User opc
param(
    [string]$HostIp = "80.225.255.191",
    [string]$User = "opc",
    [string]$KeyPath = "",
    [string]$GoArch = "amd64",
    [string]$RemoteBinDir = "/opt/financetracker",
    [string]$RemoteUploadDir = "/tmp/ft-upload",
    [string]$ServiceName = "financetracker"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$OciDir = Split-Path -Parent $ScriptDir
$ProjectDir = Split-Path -Parent $OciDir
$BackendDir = Join-Path $ProjectDir "backend"
$BuildDir = Join-Path $OciDir "build"
$LocalBinary = Join-Path $BuildDir "financetracker"

if (-not $KeyPath) {
    $KeyPath = Join-Path $OciDir "secrets\ssh-key-2026-07-30.key"
}

$goBin = "C:\Program Files\Go\bin"
$env:Path = "$goBin;" +
    [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
    [System.Environment]::GetEnvironmentVariable("Path", "User")

if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
    Write-Error "Go not found. Install Go or add it to PATH."
}
if (-not (Test-Path $KeyPath)) {
    Write-Error "SSH key not found: $KeyPath"
}
if (-not (Test-Path $BackendDir)) {
    Write-Error "Backend directory not found: $BackendDir"
}

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
$Remote = "${User}@${HostIp}"
$SshArgs = @("-i", $KeyPath, "-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=20")

Write-Host "Building backend (linux/$GoArch)..."
$prevGoos = $env:GOOS
$prevGoarch = $env:GOARCH
$prevCgo = $env:CGO_ENABLED
$env:GOOS = "linux"
$env:GOARCH = $GoArch
$env:CGO_ENABLED = "0"
Push-Location $BackendDir
try {
    & go build -ldflags="-s -w" -o $LocalBinary .
    if ($LASTEXITCODE -ne 0) { throw "go build failed" }
} finally {
    Pop-Location
    if ($null -eq $prevGoos) { Remove-Item Env:GOOS -ErrorAction SilentlyContinue } else { $env:GOOS = $prevGoos }
    if ($null -eq $prevGoarch) { Remove-Item Env:GOARCH -ErrorAction SilentlyContinue } else { $env:GOARCH = $prevGoarch }
    if ($null -eq $prevCgo) { Remove-Item Env:CGO_ENABLED -ErrorAction SilentlyContinue } else { $env:CGO_ENABLED = $prevCgo }
}
$size = (Get-Item $LocalBinary).Length
Write-Host ("Built {0} ({1:N0} bytes)" -f $LocalBinary, $size)

Write-Host "Checking SSH to $Remote..."
& ssh @SshArgs $Remote "echo SSH_OK"
if ($LASTEXITCODE -ne 0) { throw "SSH failed. Is port 22 open?" }

Write-Host "Uploading binary..."
& ssh @SshArgs $Remote "mkdir -p $RemoteUploadDir"
& scp @SshArgs $LocalBinary "${Remote}:${RemoteUploadDir}/financetracker"
if ($LASTEXITCODE -ne 0) { throw "scp failed" }

Write-Host "Installing and restarting $ServiceName..."
# Use a single remote command line (avoid CRLF breaking bash/systemd on Linux).
$remoteCmd = @(
    "set -e",
    "sudo mkdir -p $RemoteBinDir",
    "sudo systemctl stop $ServiceName",
    "sudo cp $RemoteUploadDir/financetracker $RemoteBinDir/financetracker",
    "sudo chmod +x $RemoteBinDir/financetracker",
    "sudo chown ${User}:${User} $RemoteBinDir/financetracker",
    "sudo systemctl start $ServiceName",
    "sleep 2",
    "sudo systemctl is-active $ServiceName",
    "sudo journalctl -u $ServiceName -n 12 --no-pager",
    "echo BACKEND_DEPLOY_OK"
) -join "; "
& ssh @SshArgs $Remote $remoteCmd
if ($LASTEXITCODE -ne 0) { throw "remote install failed" }

Write-Host "Backend redeployed to $HostIp"
