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
$tempLog = New-TemporaryFile
$log | Out-File -FilePath $tempLog.FullName -Encoding utf8

$referenceLog = (Get-Content tools/golden/battle.log -Raw).Replace("`r`n", "`n")
$newLog = (Get-Content $tempLog.FullName -Raw).Replace("`r`n", "`n")

if ($referenceLog -eq $newLog) {
    Write-Host "Golden log matches."
    Remove-Item $tempLog.FullName
} else {
    Write-Host "Golden log MISMATCH!"
    Remove-Item $tempLog.FullName
    throw "Mismatch"
}
