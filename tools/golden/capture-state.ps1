$ErrorActionPreference = "Stop"
$rootDir = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
Set-Location $rootDir

# Regenerates docs/ENGINE-STATE.md from the live engine + data. Run this after
# any change G4 flags: the report is generated, so a G4 failure means the doc is
# stale, not that the engine is wrong.
$output = & lovec . engine-state
$inBlock = $false
$report = @()
foreach ($line in $output) {
    if ($line -match "ENGINE STATE BEGIN") {
        $inBlock = $true
    } elseif ($line -match "ENGINE STATE END") {
        $inBlock = $false
    } elseif ($inBlock) {
        $report += $line
    }
}

if ($report.Count -eq 0) {
    Write-Host "ENGINE STATE capture produced no output — is the engine erroring?"
    exit 1
}

$path = "docs/ENGINE-STATE.md"
[System.IO.File]::WriteAllLines((Join-Path $rootDir $path), $report)
Write-Host "Captured engine state -> $path ($($report.Count) lines)"
