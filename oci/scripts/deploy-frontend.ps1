# Rebuild Flutter web frontend and redeploy to OCI (Nginx static root).
# Builds into oci\build\web so a production bundle never lands in frontend\build\web,
# which is the directory the local `flutter run` dev server serves from.
# Example:
#   .\oci\scripts\deploy-frontend.ps1
#   .\oci\scripts\deploy-frontend.ps1 -ApiBaseUrl https://www.dhanshanti.com/api/v1
param(
    [string]$HostIp = "80.225.255.191",
    [string]$User = "opc",
    [string]$KeyPath = "",
    [string]$ApiBaseUrl = "https://www.dhanshanti.com/api/v1",
    [string]$RemoteWebRoot = "/var/www/financetracker",
    [string]$RemoteUploadDir = "/tmp/ft-upload"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$OciDir = Split-Path -Parent $ScriptDir
$ProjectDir = Split-Path -Parent $OciDir
$FrontendDir = Join-Path $ProjectDir "frontend"
$BuildDir = Join-Path $OciDir "build"
$WebTar = Join-Path $BuildDir "web.tar"
$WebBuildDir = Join-Path $BuildDir "web"

if (-not $KeyPath) {
    $KeyPath = Join-Path $OciDir "secrets\ssh-key-2026-07-30.key"
}
$flutterBin = "C:\src\flutter\bin"
$env:Path = "$flutterBin;" +
    [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
    [System.Environment]::GetEnvironmentVariable("Path", "User")

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Error "Flutter not found. Install Flutter or add it to PATH (expected at C:\src\flutter\bin)."
}
if (-not (Test-Path $KeyPath)) {
    Write-Error "SSH key not found: $KeyPath"
}
if (-not (Test-Path $FrontendDir)) {
    Write-Error "Frontend directory not found: $FrontendDir"
}

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
$Remote = "${User}@${HostIp}"
$SshArgs = @("-i", $KeyPath, "-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=20")

Write-Host "Building Flutter web into $WebBuildDir (API_BASE_URL=$ApiBaseUrl)..."
Remove-Item -Recurse -Force $WebBuildDir -ErrorAction SilentlyContinue
Push-Location $FrontendDir
try {
    & flutter build web --release --output $WebBuildDir "--dart-define=API_BASE_URL=$ApiBaseUrl"
    if ($LASTEXITCODE -ne 0) { throw "flutter build web failed" }
} finally {
    Pop-Location
}
if (-not (Test-Path (Join-Path $WebBuildDir "index.html"))) {
    throw "Web build missing index.html at $WebBuildDir"
}

Write-Host "Packaging web build..."
Remove-Item $WebTar -ErrorAction SilentlyContinue
& tar -cf $WebTar -C $WebBuildDir .
if ($LASTEXITCODE -ne 0) { throw "tar failed" }

Write-Host "Checking SSH to $Remote..."
& ssh @SshArgs $Remote "echo SSH_OK"
if ($LASTEXITCODE -ne 0) { throw "SSH failed. Is port 22 open?" }

Write-Host "Uploading web.tar..."
& ssh @SshArgs $Remote "mkdir -p $RemoteUploadDir"
& scp @SshArgs $WebTar "${Remote}:${RemoteUploadDir}/web.tar"
if ($LASTEXITCODE -ne 0) { throw "scp failed" }

Write-Host "Installing into $RemoteWebRoot..."
# Use a single remote command line (avoid CRLF breaking bash on Linux).
$remoteCmd = @(
    "set -e",
    "sudo mkdir -p $RemoteWebRoot",
    "sudo rm -rf $RemoteWebRoot/*",
    "sudo tar -xf $RemoteUploadDir/web.tar -C $RemoteWebRoot",
    "sudo chown -R nginx:nginx $RemoteWebRoot",
    "sudo restorecon -R $RemoteWebRoot 2>/dev/null || true",
    "ls $RemoteWebRoot | head",
    "echo FRONTEND_DEPLOY_OK"
) -join "; "
& ssh @SshArgs $Remote $remoteCmd
if ($LASTEXITCODE -ne 0) { throw "remote install failed" }

Write-Host "Frontend redeployed to https://$HostIp/ (hard-refresh if needed)"
