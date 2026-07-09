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
    if ($line -match "^scene\|(.+?)\|") {
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

$allMatch = $true
foreach ($key in $sceneLogs.Keys) {
    $refPath = "tools/golden/scene_$key.log"
    if (-not (Test-Path $refPath)) {
        Write-Host "WARNING: No reference log for scene '$key' at $refPath"
        $allMatch = $false
        continue
    }

    $tempLog = New-TemporaryFile
    # Re-wrap with markers for comparison
    $refContent = @("UI GOLDEN BEGIN") + $sceneLogs[$key] + @("UI GOLDEN END")
    $refContent | Out-File -FilePath $tempLog.FullName -Encoding utf8

    $referenceLog = (Get-Content $refPath -Raw).Replace("`r`n", "`n")
    $newLog = (Get-Content $tempLog.FullName -Raw).Replace("`r`n", "`n")

    if ($referenceLog -eq $newLog) {
        Write-Host "Golden UI log matches for scene '$key'."
    } else {
        Write-Host "Golden UI log MISMATCH for scene '$key'!"
        $allMatch = $false
    }
    Remove-Item $tempLog.FullName
}

if (-not $allMatch) {
    throw "Golden UI log mismatch detected"
}
