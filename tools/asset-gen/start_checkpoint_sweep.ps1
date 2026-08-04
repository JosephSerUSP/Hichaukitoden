param(
    [int]$Variants = 2,
    [ValidateSet('checkpoint', 'style-depth', 'surface-kit')]
    [string]$Experiment = 'checkpoint'
)

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$out = Join-Path $root 'tools\asset-gen\out'
$processIdPath = Join-Path $out 'overnight-wall-checkpoint-sweep.pid'
$logPath = Join-Path $out 'overnight-wall-checkpoint-sweep.log'
$errorLogPath = Join-Path $out 'overnight-wall-checkpoint-sweep.err.log'
$python = 'C:\Users\josep\AppData\Local\Programs\Python\Python310\python.exe'

if ($Variants -lt 1) {
    throw 'Variants must be positive.'
}

if (Test-Path -LiteralPath $processIdPath) {
    $existingId = [int](Get-Content -LiteralPath $processIdPath -Raw).Trim()
    if (Get-Process -Id $existingId -ErrorAction SilentlyContinue) {
        Write-Output "Checkpoint sweep already running (PID $existingId)."
        exit 0
    }
    Remove-Item -LiteralPath $processIdPath -Force
}

$process = Start-Process -FilePath $python `
    -ArgumentList @('tools/asset-gen/run_checkpoint_sweep.py', '--experiment', $Experiment, '--variants', $Variants) `
    -WorkingDirectory $root -WindowStyle Hidden `
    -RedirectStandardOutput $logPath -RedirectStandardError $errorLogPath -PassThru

Set-Content -LiteralPath $processIdPath -Value $process.Id -Encoding ascii
Write-Output "Started $Experiment asset sweep (PID $($process.Id))."
Write-Output "Log: $logPath"
Write-Output "Stop: powershell -NoProfile -ExecutionPolicy Bypass -File tools\asset-gen\stop_checkpoint_sweep.ps1"
