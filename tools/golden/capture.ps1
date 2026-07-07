$ErrorActionPreference = "Stop"
$rootDir = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
Set-Location $rootDir

$output = & lovec . validate golden
$inBlock = $false
$log = @()
foreach ($line in $output) {
    if ($line -match "GOLDEN BEGIN") {
        $inBlock = $true
    } elseif ($line -match "GOLDEN END") {
        $inBlock = $false
    } elseif ($inBlock) {
        $log += $line
    }
}
$log | Out-File -FilePath tools/golden/battle.log -Encoding utf8
