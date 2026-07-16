$ErrorActionPreference = "Stop"
$rootDir = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
Set-Location $rootDir

$output = & lovec . validate golden-ui
$inBlock = $false
$log = @()
foreach ($line in $output) {
    if ($line -match "UI GOLDEN BEGIN") {
        $inBlock = $true
    } elseif ($line -match "UI GOLDEN END") {
        $inBlock = $false
    } elseif ($inBlock) {
        $log += $line
    }
}

# Split by scene key: first line of each block is "scene|<key>|name|<name>"
$currentScene = ""
$currentLog = @()
$sceneLogs = @{}
foreach ($line in $log) {
    if ($line -match "^scene\|(.+?)\|name\|") {
        if ($currentScene -ne "" -and $currentLog.Count -gt 0) {
            $sceneLogs[$currentScene] = $currentLog
        }
        $currentScene = $matches[1]
        $currentLog = @($line)
    } else {
        $currentLog += $line
    }
}
if ($currentScene -ne "" -and $currentLog.Count -gt 0) {
    $sceneLogs[$currentScene] = $currentLog
}

foreach ($key in $sceneLogs.Keys) {
    $path = "tools/golden/scene_$key.log"
    # Prepend UI GOLDEN BEGIN/END markers for the reference file
    $refContent = @("UI GOLDEN BEGIN") + $sceneLogs[$key] + @("UI GOLDEN END")
    [System.IO.File]::WriteAllLines((Join-Path $rootDir $path), $refContent)
    Write-Host "Captured golden UI log for scene '$key' -> $path"
}
