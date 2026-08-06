param()

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$out = Join-Path $root 'tools\asset-gen\out\first-stratum-overnight'
$pidPath = Join-Path $out 'run.pid'
$logPath = Join-Path $out 'run.log'
$errPath = Join-Path $out 'run.err.log'
$python = 'C:\Users\josep\AppData\Local\Programs\Python\Python310\python.exe'
if (-not (Test-Path -LiteralPath $python)) { $python = (Get-Command python -ErrorAction Stop).Source }
New-Item -ItemType Directory -Force -Path $out | Out-Null

if (Test-Path -LiteralPath $pidPath) {
    $existing = 0
    [int]::TryParse((Get-Content -LiteralPath $pidPath -Raw).Trim(), [ref]$existing) | Out-Null
    if ($existing -gt 0 -and (Get-Process -Id $existing -ErrorAction SilentlyContinue)) {
        Write-Output "First Stratum overnight already running (PID $existing)."
        Write-Output "Log: $logPath"
        exit 0
    }
    Remove-Item -LiteralPath $pidPath -Force
}

$drive = Get-PSDrive -Name D -ErrorAction SilentlyContinue
if ($drive -and $drive.Free -lt 20GB) { throw "Less than 20 GB free on D:; refusing to launch." }
$cdrive = Get-PSDrive -Name C -ErrorAction SilentlyContinue
if ($cdrive -and $cdrive.Free -lt 10GB) { throw "Less than 10 GB free on C:; refusing to launch." }

Push-Location $root
try {
    & $python tools/asset-gen/forge.py status *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Output 'Forge is down; starting the existing local Forge installation...'
        & $python tools/asset-gen/forge.py start
        if ($LASTEXITCODE -ne 0) { throw 'Forge failed to start; inspect tools/asset-gen/out/forge.log.' }
    }
    & $python -m py_compile tools/asset-gen/run_first_stratum_overnight.py
    if ($LASTEXITCODE -ne 0) { throw 'Overnight worker Python syntax validation failed.' }
    $process = Start-Process -FilePath $python -ArgumentList @('-u', 'tools/asset-gen/run_first_stratum_overnight.py', '--run') -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput $logPath -RedirectStandardError $errPath -PassThru
    Set-Content -LiteralPath $pidPath -Value $process.Id -Encoding ascii
    Write-Output "Started First Stratum overnight run (PID $($process.Id))."
    Write-Output "Log: $logPath"
    Write-Output "Status: powershell -NoProfile -ExecutionPolicy Bypass -File tools\asset-gen\status_first_stratum_overnight.ps1"
    Write-Output "Stop: powershell -NoProfile -ExecutionPolicy Bypass -File tools\asset-gen\stop_first_stratum_overnight.ps1"
    Write-Output "Report: $out\first-stratum-material-family-report.html"
} finally {
    Pop-Location
}
