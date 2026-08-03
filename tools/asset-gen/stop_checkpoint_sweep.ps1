$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$out = Join-Path $root 'tools\asset-gen\out'
$processIdPath = Join-Path $out 'overnight-wall-checkpoint-sweep.pid'

if (-not (Test-Path -LiteralPath $processIdPath)) {
    Write-Output 'No checkpoint sweep PID file found; nothing to stop.'
    exit 0
}

$rootId = [int](Get-Content -LiteralPath $processIdPath -Raw).Trim()
$processes = @(Get-CimInstance Win32_Process)

function Get-DescendantIds([int]$parentId) {
    $children = @($processes | Where-Object { $_.ParentProcessId -eq $parentId })
    foreach ($child in $children) {
        Write-Output $child.ProcessId
        Get-DescendantIds ([int]$child.ProcessId)
    }
}

$ids = @($rootId) + @(Get-DescendantIds $rootId)
foreach ($id in ($ids | Sort-Object -Descending)) {
    Stop-Process -Id ([int]$id) -Force -ErrorAction SilentlyContinue
}
Remove-Item -LiteralPath $processIdPath -Force -ErrorAction SilentlyContinue
Write-Output "Stopped checkpoint sweep process tree rooted at PID $rootId."
