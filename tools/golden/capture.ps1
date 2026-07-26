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

# Split by fixture key: first line of each block is "battle|<key>|name|<name>"
$currentKey = ""
$currentLog = @()
$fixtureLogs = @{}
foreach ($line in $log) {
    if ($line -match "^battle\|(.+?)\|name\|") {
        if ($currentKey -ne "" -and $currentLog.Count -gt 0) {
            $fixtureLogs[$currentKey] = $currentLog
        }
        $currentKey = $matches[1]
        $currentLog = @($line)
    } else {
        $currentLog += $line
    }
}
if ($currentKey -ne "" -and $currentLog.Count -gt 0) {
    $fixtureLogs[$currentKey] = $currentLog
}

foreach ($key in $fixtureLogs.Keys) {
    $path = "tools/golden/battle_$key.log"
    $refContent = @("GOLDEN BEGIN") + $fixtureLogs[$key] + @("GOLDEN END")
    [System.IO.File]::WriteAllLines((Join-Path $rootDir $path), $refContent)
    Write-Host "Captured golden battle log for fixture '$key' -> $path"
}
