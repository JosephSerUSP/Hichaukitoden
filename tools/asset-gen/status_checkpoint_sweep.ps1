$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$out = Join-Path $root 'tools\asset-gen\out'
$processIdPath = Join-Path $out 'overnight-wall-checkpoint-sweep.pid'
$logPath = Join-Path $out 'overnight-wall-checkpoint-sweep.log'
$errorLogPath = Join-Path $out 'overnight-wall-checkpoint-sweep.err.log'

if (Test-Path -LiteralPath $processIdPath) {
    $processId = [int](Get-Content -LiteralPath $processIdPath -Raw).Trim()
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if ($process) {
        Write-Output "running PID $processId; CPU $($process.CPU); started $($process.StartTime)"
    } else {
        Write-Output "stale PID file for $processId; the sweep is not running."
    }
} else {
    Write-Output 'not running (no PID file).'
}

if (Test-Path -LiteralPath $logPath) {
    Write-Output "`n--- log tail ---"
    Get-Content -LiteralPath $logPath -Tail 25
}
if (Test-Path -LiteralPath $errorLogPath) {
    $errors = Get-Content -LiteralPath $errorLogPath -Tail 25
    if ($errors) {
        Write-Output "`n--- error log tail ---"
        $errors
    }
}
