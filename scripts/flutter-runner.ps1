# Keeps Flutter run alive with stdin so hot-reload.ps1 can send commands.
param(
    [Parameter(Mandatory = $true)][string]$FrontendDir,
    [Parameter(Mandatory = $true)][string]$OutLog,
    [Parameter(Mandatory = $true)][string]$ErrLog,
    [Parameter(Mandatory = $true)][string]$CmdFile,
    [Parameter(Mandatory = $true)][string]$FlutterPidFile
)

$ErrorActionPreference = "Continue"

$flutterRoot = "C:\src\flutter"
$dartExe = Join-Path $flutterRoot "bin\cache\dart-sdk\bin\dart.exe"
$snapshot = Join-Path $flutterRoot "bin\cache\flutter_tools.snapshot"
$packages = Join-Path $flutterRoot "packages\flutter_tools\.dart_tool\package_config.json"

if (-not (Test-Path $dartExe)) { throw "Dart not found at $dartExe" }
if (-not (Test-Path $snapshot)) { throw "flutter_tools snapshot not found at $snapshot" }

$env:Path = "$(Join-Path $flutterRoot 'bin');" +
    [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
    [System.Environment]::GetEnvironmentVariable("Path", "User")

"" | Set-Content -Path $CmdFile -Encoding ascii
Remove-Item -Path $FlutterPidFile -Force -ErrorAction SilentlyContinue

# Invoke flutter_tools directly so stdin stays connected (flutter.bat drops it).
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $dartExe
$psi.Arguments = "--packages=`"$packages`" `"$snapshot`" run -d chrome --web-port=3000 --pid-file `"$FlutterPidFile`""
$psi.WorkingDirectory = $FrontendDir
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$psi.Environment["FLUTTER_ROOT"] = $flutterRoot

$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi

$sync = [hashtable]::Synchronized(@{ out = $OutLog; err = $ErrLog })

$outputHandler = {
    if ($EventArgs.Data -ne $null) {
        Add-Content -LiteralPath $Event.MessageData.out -Value $EventArgs.Data -Encoding utf8
    }
}
$errorHandler = {
    if ($EventArgs.Data -ne $null) {
        Add-Content -LiteralPath $Event.MessageData.err -Value $EventArgs.Data -Encoding utf8
    }
}

$outEvent = Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action $outputHandler -MessageData $sync
$errEvent = Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -Action $errorHandler -MessageData $sync

[void]$proc.Start()
$proc.BeginOutputReadLine()
$proc.BeginErrorReadLine()

Add-Content -LiteralPath $OutLog -Value "[flutter-runner] started pid=$($proc.Id)" -Encoding utf8

try {
    while (-not $proc.HasExited) {
        if (Test-Path $CmdFile) {
            $lines = @(Get-Content -Path $CmdFile -ErrorAction SilentlyContinue |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ })
            if ($lines.Count -gt 0) {
                Clear-Content -Path $CmdFile -ErrorAction SilentlyContinue
                foreach ($line in $lines) {
                    $proc.StandardInput.WriteLine($line)
                    $proc.StandardInput.Flush()
                    Add-Content -LiteralPath $OutLog -Value "[flutter-runner] sent command: $line" -Encoding utf8
                }
            }
        }
        Start-Sleep -Milliseconds 250
    }
    Add-Content -LiteralPath $OutLog -Value "[flutter-runner] exited code=$($proc.ExitCode)" -Encoding utf8
} finally {
    Unregister-Event -SourceIdentifier $outEvent.Name -ErrorAction SilentlyContinue
    Unregister-Event -SourceIdentifier $errEvent.Name -ErrorAction SilentlyContinue
    if (-not $proc.HasExited) {
        try { $proc.StandardInput.WriteLine("q") } catch {}
        try { $proc.Kill() } catch {}
    }
    $proc.Dispose()
}
