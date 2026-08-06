param()
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$out = Join-Path $root 'tools\asset-gen\out\first-stratum-overnight'
$pidPath = Join-Path $out 'run.pid'
$statusPath = Join-Path $out 'status.json'
if (Test-Path -LiteralPath $pidPath) {
    $id = [int](Get-Content -LiteralPath $pidPath -Raw).Trim()
    $process = Get-Process -Id $id -ErrorAction SilentlyContinue
    if ($process) { Write-Output "ACTIVE PID $id" } else { Write-Output "NOT RUNNING (stale PID $id)" }
} else { Write-Output 'NOT RUNNING (no PID file)' }
if (Test-Path -LiteralPath $statusPath) {
    $s = Get-Content -Raw -LiteralPath $statusPath | ConvertFrom-Json
    $counts = @{}
    foreach ($j in $s.jobs) { $key = [string]$j.status; if (-not $counts.ContainsKey($key)) { $counts[$key] = 0 }; $counts[$key]++ }
    Write-Output ("Updated {0}; jobs: {1}" -f $s.updatedAt, (($counts.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ', '))
    Write-Output ("Selected candidates: {0}; report: {1}" -f $s.summary.candidates, (Join-Path $out 'first-stratum-material-family-report.html'))
}
Write-Output ("Log: {0}" -f (Join-Path $out 'run.log'))
Write-Output ("Forge: python tools/asset-gen/forge.py status")
