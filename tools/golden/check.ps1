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

if ($fixtureLogs.Count -eq 0) {
    throw "No golden battle fixtures produced any output"
}

$allMatch = $true
foreach ($key in $fixtureLogs.Keys) {
    $refPath = "tools/golden/battle_$key.log"
    if (-not (Test-Path $refPath)) {
        Write-Host "WARNING: No reference log for fixture '$key' at $refPath"
        $allMatch = $false
        continue
    }

    $tempLog = New-TemporaryFile
    $refContent = @("GOLDEN BEGIN") + $fixtureLogs[$key] + @("GOLDEN END")
    $refContent | Out-File -FilePath $tempLog.FullName -Encoding utf8

    $referenceLog = (Get-Content $refPath -Raw).Replace("`r`n", "`n")
    $newLog = (Get-Content $tempLog.FullName -Raw).Replace("`r`n", "`n")

    if ($referenceLog -eq $newLog) {
        Write-Host "Golden log matches for fixture '$key'."
    } else {
        Write-Host "Golden log MISMATCH for fixture '$key'!"
        $allMatch = $false
    }
    Remove-Item $tempLog.FullName
}

# A captured log with no matching fixture means a fixture was deleted or
# renamed. Silently passing would quietly shrink battle coverage.
foreach ($refFile in Get-ChildItem "tools/golden/battle_*.log") {
    $key = $refFile.BaseName -replace "^battle_", ""
    if (-not $fixtureLogs.ContainsKey($key)) {
        Write-Host "WARNING: $($refFile.Name) has no matching fixture in data/goldenBattles.json"
        $allMatch = $false
    }
}

if (-not $allMatch) {
    throw "Golden log mismatch detected"
}
