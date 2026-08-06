param()
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$pidPath = Join-Path $root 'tools\asset-gen\out\first-stratum-overnight\run.pid'
if (-not (Test-Path -LiteralPath $pidPath)) { Write-Output 'No First Stratum overnight PID file; nothing stopped.'; exit 0 }
$id = [int](Get-Content -LiteralPath $pidPath -Raw).Trim()
$process = Get-Process -Id $id -ErrorAction SilentlyContinue
if ($process) {
    Write-Output "Stopping First Stratum overnight worker tree PID $id (Forge is left running)."
    & taskkill.exe /PID $id /T /F | Out-Null
} else { Write-Output "Worker PID $id is no longer running." }
Remove-Item -LiteralPath $pidPath -Force
Write-Output 'Staged outputs and status are preserved; rerun the start command to resume.'
